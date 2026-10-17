/* =============================================================================
 * CFG — Configuration Clinique
 * -----------------------------------------------------------------------------
 * draf1 §19 « NASSIERA CONFIGURATION CENTER » — organisation et organigramme,
 * identité et papier à en-tête, référentiel tarifaire, règles métier versionnées,
 * paramètres fiscaux, notifications, compte utilisateur et paramètres système.
 *
 * Principe directeur (draf1 §1) : rien n'est codé en dur ; tout provient des
 * documents de cadrage devenus référentiels administrables.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      N = global.SIGH.nav, P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = new Date(2026, 7, 16);

  /* ==========================================================================
   * ORGANISATION & ORGANIGRAMME
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * Deux référentiels d'organisation, tous deux administrables :
   *   — les SECTEURS de la note de service NS 145, maille réelle des
   *     habilitations et base d'évaluation de l'activité des services ;
   *   — les POSTES de l'organigramme, dont dérive la matrice RBAC.
   * Ni l'un ni l'autre n'est figé dans le code : la clinique crée, réaffecte et
   * archive. Une note de service ultérieure se traduit ici, pas dans le code.
   * ----------------------------------------------------------------------- */
  function colSecteurs() { return S.collection('secteurs', { module: 'CFG', entite: 'secteur', prefix: 'SEC' }); }
  function colPostes() { return S.collection('postes', { module: 'CFG', entite: 'poste', prefix: 'PST' }); }

  /* L'organigramme du document est un arbre ; la collection est plate, chaque
     poste désignant son rattachement. C'est ce qui permet d'en créer, d'en
     déplacer et d'en archiver sans toucher au code. */
  function amorcerPostes() {
    var db = S.raw();
    if (db.postes && db.postes.length) return;
    var out = [], n = 0;
    (function aplatir(noeud, parentId) {
      n++;
      var id = 'PST' + C.pad(n, 3);
      out.push({
        id: id, statut: 'actif', parentId: parentId,
        poste: noeud.poste, effectif: noeud.effectif || 0,
        titulaire: noeud.titulaire || null, chef: !!noeud.chef, role: noeud.role,
        source: 'Organigramme de la Clinique NASSIERA TOO',
      });
      (noeud.enfants || []).forEach(function (e) { aplatir(e, id); });
    })(D.ORGANIGRAMME.racine, null);
    db.postes = out;
    S.save();
  }

  function arbreDepuisCollection() {
    var plats = colPostes().active();
    var parId = {};
    plats.forEach(function (p) { parId[p.id] = Object.assign({}, p, { enfants: [] }); });
    var racines = [];
    plats.forEach(function (p) {
      var n = parId[p.id];
      if (p.parentId && parId[p.parentId]) parId[p.parentId].enfants.push(n);
      else racines.push(n);
    });
    return racines;
  }

  function effectifTotal(noeuds) {
    return noeuds.reduce(function (s, n) { return s + (n.effectif || 0) + effectifTotal(n.enfants || []); }, 0);
  }

  global.SIGH.screen('cfg-organisation', {
    title: 'Organisation & organigramme',
    description: 'Secteurs de la clinique, structure hiérarchique et rôles qui en découlent.',
    regle: 'Deux référentiels administrables. Les <strong>secteurs (NS 145/08/DA/CNT/2026)</strong> donnent la maille '
      + 'réelle des habilitations et de l’évaluation des services. L’<strong>organigramme</strong> pilote la matrice RBAC : '
      + 'chaque poste porte un rôle qui détermine son périmètre d’accès. '
      + '<strong>RG-14</strong> — retirer un secteur ou un poste l’archive : rien n’est supprimé, tout se restaure.',
    actions: function () {
      return [
        K.btn('Personnel', { icon: 'users', onclick: function () { global.SIGH.app.go('m10-personnel'); } }),
        K.btn('Rôles & permissions', { icon: 'key-round', onclick: function () { global.SIGH.app.go('m14-roles'); } }),
      ];
    },
    render: function (root) {
      amorcerPostes();
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Secteurs de la clinique', value: C.num(colSecteurs().active().length), icon: 'layers', tone: 'navy', hint: 'NS 145 du 06/08/2026' },
        { label: 'Postes de l’organigramme', value: C.num(colPostes().active().length), icon: 'network', tone: 'info' },
        { label: 'Effectif porté', value: C.num(effectifTotal(arbreDepuisCollection())), icon: 'users-round', tone: 'success' },
        { label: 'Rôles RBAC', value: C.num(Object.keys(N.ROLES).length), icon: 'shield', tone: 'neutral' },
      ]));

      host.appendChild(U.tabs([
        { id: 'secteurs', label: 'Secteurs (NS 145)', badge: colSecteurs().active().length, render: ongletSecteurs },
        { id: 'organigramme', label: 'Organigramme', badge: colPostes().active().length, render: ongletOrganigramme },
        { id: 'roles', label: 'Poste → rôle → accès', render: ongletRoles },
      ]));

      root.appendChild(host);
      return null;
    },
  });

  /* --- Onglet « Secteurs » ------------------------------------------------- */
  function champsSecteur() {
    return [
      { name: 'libelle', label: 'Secteur', required: true, col: 'full' },
      { name: 'code', label: 'Code', help: 'Trois lettres, laisser vide pour une attribution automatique.' },
      {
        name: 'role', label: 'Rôle RBAC rattaché', type: 'select', required: true,
        options: Object.keys(N.ROLES).map(function (r) { return { value: r, label: N.ROLES[r].label }; }),
        help: 'Détermine ce que les agents de ce secteur peuvent voir et faire.',
      },
      { name: 'responsable', label: 'Responsable', col: 'full' },
      { name: 'adjoint', label: 'Responsable adjoint', col: 'full' },
      { name: 'qualification', label: 'Qualification' },
      { name: 'source', label: 'Note de service d’origine', col: 'full' },
    ];
  }

  function ongletSecteurs(panneau) {
    dessiner();
    return null;

    function dessiner() {
      C.clear(panneau);
      var rows = C.sortBy(colSecteurs().active(), 'ordre');
      var host = el('div.space-y-3');

      host.appendChild(K.note('<strong>' + D.NS145.reference + '</strong> — ' + D.NS145.objet
        + ', signée le ' + C.dateFR(D.NS145.dateSignature) + ' par ' + D.NS145.signataire
        + ', avec effet au <strong>' + C.dateFR(D.NS145.dateEffet) + '</strong>. '
        + 'Une note ultérieure se saisit ici : le référentiel est versionné par sa source, pas par le code.',
      { tone: 'info', icon: 'file-check-2' }));

      host.appendChild(U.dataTable({
        rows: rows, exportName: 'secteurs', pageSize: 20, searchable: true, defaultSort: 'ordre',
        columns: [
          { key: 'code', label: 'Code', nowrap: true, render: function (s) { return el('span.font-mono.text-xs', { text: s.code }); } },
          { key: 'libelle', label: 'Secteur', render: function (s) { return el('span.font-medium.text-slate-800', { text: s.libelle }); } },
          {
            key: 'responsable', label: 'Responsable',
            render: function (s) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.text-slate-700', { text: s.responsable || '—' }),
                el('p.truncate.text-xs.text-slate-400', { text: s.qualification || '' }),
              ]);
            },
          },
          {
            key: 'adjoint', label: 'Adjoint',
            render: function (s) {
              return s.adjoint
                ? el('span.text-sm.text-slate-700', { text: s.adjoint })
                : el('span.text-xs.text-slate-300', { text: 'non désigné' });
            },
          },
          {
            key: 'role', label: 'Rôle RBAC',
            text: function (s) { return N.ROLES[s.role] ? N.ROLES[s.role].label : s.role; },
            render: function (s) { return U.badge(N.ROLES[s.role] ? N.ROLES[s.role].label : s.role, 'navy'); },
          },
        ],
        rowActions: K.actionsLigne(colSecteurs(), champsSecteur, { entite: 'secteur' }),
        actions: [
          K.creer(colSecteurs(), champsSecteur, {
            titre: 'Nouveau secteur', entite: 'Secteur',
            defauts: function () { return { role: 'agentadmin', source: 'Décision de la Direction' }; },
            transform: function (v) {
              if (!v.code) v.code = (v.libelle || 'SEC').slice(0, 3).toUpperCase();
              v.ordre = colSecteurs().all().length + 1;
              return v;
            },
            apres: dessiner,
          }),
          K.btn('Imprimer la répartition', {
            size: 'sm', icon: 'printer',
            onclick: function () {
              P.etat({
                titre: 'Répartition des secteurs de la clinique',
                sousTitre: D.NS145.reference,
                cartouche: [['Objet', D.NS145.objet], ['Secteurs', C.num(rows.length)],
                  ['Date d’effet', C.dateFR(D.NS145.dateEffet)], ['Date d’édition', C.dateFR(AUJ)]],
                contenu: P.tableau([
                  { label: 'N°', align: 'right', key: 'ordre' },
                  { label: 'Secteur', key: 'libelle' },
                  { label: 'Responsable', value: function (s) { return s.responsable || '—'; } },
                  { label: 'Responsable adjoint', value: function (s) { return s.adjoint || '—'; } },
                  { label: 'Qualification', value: function (s) { return s.qualification || '—'; } },
                ], rows),
                signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou épse BASSONGUI' }],
              });
            },
          }),
        ],
      }));

      host.appendChild(K.source(D.NS145.source));
      panneau.appendChild(host);
      U.icons(panneau);
    }
  }

  /* --- Onglet « Organigramme » --------------------------------------------- */
  function champsPoste(record) {
    var autres = colPostes().active().filter(function (p) { return !record || p.id !== record.id; });
    return [
      { name: 'poste', label: 'Intitulé du poste', required: true, col: 'full' },
      {
        name: 'parentId', label: 'Rattaché à', type: 'select',
        options: [{ value: '', label: '— Sommet de l’organigramme —' }].concat(
          C.sortBy(autres, 'poste').map(function (p) { return { value: p.id, label: p.poste }; })),
        help: 'Déplacer un poste ici le réaffecte, lui et les postes qu’il porte.',
      },
      { name: 'effectif', label: 'Effectif', type: 'number', min: 0, required: true },
      { name: 'titulaire', label: 'Titulaire / chef de service', col: 'full' },
      {
        name: 'role', label: 'Rôle RBAC', type: 'select', required: true,
        options: Object.keys(N.ROLES).map(function (r) { return { value: r, label: N.ROLES[r].label }; }),
      },
      { name: 'chef', label: 'Chef de service', type: 'checkbox' },
    ];
  }

  function ongletOrganigramme(panneau) {
    dessiner();
    return null;

    function dessiner() {
      C.clear(panneau);
      var racines = arbreDepuisCollection();
      var plats = colPostes().active();
      var host = el('div.space-y-3');

      var carte = el('div');
      racines.forEach(function (r) { carte.appendChild(arbre(r, 0)); });
      host.appendChild(U.card('Organigramme de la Clinique NASSIERA TOO', carte, [
        K.btn('Imprimer l’organigramme', { size: 'sm', icon: 'printer', onclick: imprimer }),
      ]));

      host.appendChild(U.dataTable({
        title: 'Postes — création, réaffectation et archivage',
        rows: plats, exportName: 'postes', pageSize: 20, searchable: true,
        columns: [
          { key: 'poste', label: 'Poste', render: function (p) { return el('span.font-medium.text-slate-800', { text: p.poste }); } },
          {
            key: 'parentId', label: 'Rattaché à',
            text: function (p) { return nomDe(p.parentId); },
            render: function (p) {
              return p.parentId
                ? el('span.text-sm.text-slate-600', { text: nomDe(p.parentId) })
                : U.badge('Sommet', 'navy');
            },
          },
          { key: 'effectif', label: 'Effectif', align: 'right' },
          {
            key: 'titulaire', label: 'Titulaire',
            render: function (p) {
              return p.titulaire
                ? el('span.text-sm.text-slate-700', { text: p.titulaire + (p.chef ? ' — chef de service' : '') })
                : el('span.text-xs.text-slate-300', { text: 'vacant' });
            },
          },
          {
            key: 'role', label: 'Rôle RBAC',
            text: function (p) { return N.ROLES[p.role] ? N.ROLES[p.role].label : p.role; },
            render: function (p) { return U.badge(N.ROLES[p.role] ? N.ROLES[p.role].label : p.role, 'navy'); },
          },
        ],
        rowActions: K.actionsLigne(colPostes(), champsPoste, { entite: 'poste' }),
        actions: [K.creer(colPostes(), champsPoste, {
          titre: 'Nouveau poste ou département', entite: 'Poste',
          defauts: function () { return { effectif: 1, role: 'agentadmin' }; },
          transform: function (v) { if (!v.parentId) v.parentId = null; return v; },
          apres: dessiner,
        })],
      }));

      host.appendChild(K.source('Organigramme de la Clinique NASSIERA TOO — document de cadrage, désormais administrable.'));
      panneau.appendChild(host);
      U.icons(panneau);

      function nomDe(id) {
        var p = plats.filter(function (x) { return x.id === id; })[0];
        return p ? p.poste : '—';
      }

      function arbre(noeud, niveau) {
        var wrap = el('div', { class: niveau ? 'ml-6 border-l border-slate-200 pl-4' : '' });
        var carteN = el('div.mb-2.flex.flex-wrap.items-center.gap-2.rounded-lg.border.px-3.py-2', {
          class: niveau === 0 ? 'border-navy-300 bg-navy-50' : 'border-slate-200 bg-white',
        });
        carteN.appendChild(el('span.grid.h-7.w-7.shrink-0.place-items-center.rounded-lg', {
          class: niveau === 0 ? 'bg-navy-900 text-white' : 'bg-slate-100 text-slate-500',
        }, C.icon(niveau === 0 ? 'crown' : 'user', 'h-3.5 w-3.5')));
        carteN.appendChild(el('span.text-sm.font-semibold.text-slate-800', { text: noeud.poste }));
        carteN.appendChild(U.badge('(' + C.pad(noeud.effectif, 2) + ')', 'neutral'));
        if (noeud.titulaire) {
          carteN.appendChild(el('span.text-xs.text-slate-500', { text: noeud.titulaire + (noeud.chef ? ' — chef de service' : '') }));
        }
        if (noeud.role && N.ROLES[noeud.role]) {
          carteN.appendChild(el('span.ml-auto', null, U.badge(N.ROLES[noeud.role].label, 'navy')));
        }
        wrap.appendChild(carteN);
        (noeud.enfants || []).forEach(function (e) { wrap.appendChild(arbre(e, niveau + 1)); });
        return wrap;
      }

      function imprimer() {
        P.etat({
          titre: 'Organigramme de la Clinique NASSIERA TOO',
          sousTitre: 'Structure organisationnelle et correspondance des rôles',
          cartouche: [['Effectif total', C.num(effectifTotal(racines)) + ' agents'],
            ['Postes distincts', C.num(plats.length)],
            ['Rôles définis', C.num(Object.keys(N.ROLES).length)],
            ['Date d’édition', C.dateFR(AUJ)]],
          contenu: P.tableau([
            { label: 'Poste', key: 'poste' },
            { label: 'Rattaché à', value: function (p) { return nomDe(p.parentId); } },
            { label: 'Effectif', key: 'effectif', align: 'right' },
            { label: 'Titulaire / chef de service', value: function (p) { return p.titulaire || '—'; } },
            { label: 'Rôle dans le système', value: function (p) { return N.ROLES[p.role] ? N.ROLES[p.role].label : p.role; } },
          ], plats),
          signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
            { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
        });
      }
    }
  }

  /* --- Onglet « Poste → rôle → accès » ------------------------------------- */
  function ongletRoles(panneau) {
    var plats = colPostes().active();
    var lignes = plats.map(function (p) {
      return {
        poste: p.poste, effectif: p.effectif, titulaire: p.titulaire || '—',
        role: p.role, modules: modulesRole(p.role).join(', '),
      };
    });
    panneau.appendChild(el('div.space-y-3', null, [
      K.lectureSeule('Cette correspondance est <strong>calculée</strong> depuis l’organigramme et la matrice RBAC. '
        + 'Pour la modifier, changer le rôle du poste dans l’onglet Organigramme, ou la matrice dans Rôles & permissions.'),
      U.dataTable({
        rows: lignes, exportName: 'organigramme-rbac', pageSize: 20, searchable: true,
        columns: [
          { key: 'poste', label: 'Poste' },
          { key: 'effectif', label: 'Effectif', align: 'right' },
          { key: 'titulaire', label: 'Titulaire / chef de service' },
          {
            key: 'role', label: 'Rôle RBAC',
            text: function (l) { return N.ROLES[l.role] ? N.ROLES[l.role].label : l.role; },
            render: function (l) { return U.badge(N.ROLES[l.role] ? N.ROLES[l.role].label : l.role, 'navy'); },
          },
          {
            key: 'modules', label: 'Modules accessibles',
            render: function (l) {
              return el('div.flex.flex-wrap.gap-1', null, modulesRole(l.role).map(function (m) {
                return U.badge(m, 'neutral');
              }));
            },
          },
        ],
      }),
    ]));
    U.icons(panneau);
    return null;
  }

  function modulesRole(roleId) {
    var out = [];
    N.NAV.forEach(function (dom) {
      dom.modules.forEach(function (mod) {
        var ok = mod.items.some(function (it) {
          /* L’identifiant compte : il porte les drapeaux de l’écran. */
          return N.can(roleId, { id: it.id, roles: it.roles || mod.roles || N.ALL, module: mod.code });
        });
        if (ok) out.push(mod.code);
      });
    });
    return out;
  }

  /* ==========================================================================
   * IDENTITÉ & PAPIER À EN-TÊTE
   * ======================================================================== */
  global.SIGH.screen('cfg-branding', {
    title: 'Identité & papier à en-tête',
    description: 'Paramétrage de l’identité visuelle et des mentions légales reprises sur tous les documents édités.',
    regle: 'Ces paramètres alimentent <strong>automatiquement tous les états imprimables</strong> : facture, ordonnance, bulletin de paie, bon de sortie, état comptable. Aucune mention légale n’est saisie document par document.',
    render: function (root) {
      var host = el('div.grid.gap-4.lg\\:grid-cols-2');

      var f = U.form([
        { type: 'section', label: 'Dénomination' },
        { name: 'nom', label: 'Dénomination sociale', required: true, col: 'full', value: C.BRAND.nom },
        { name: 'sigle', label: 'Sigle', value: C.BRAND.sigle },
        { name: 'forme', label: 'Forme juridique', value: C.BRAND.forme },
        { name: 'slogan', label: 'Devise ou slogan', col: 'full', value: C.BRAND.slogan },

        { type: 'section', label: 'Coordonnées' },
        { name: 'adresse', label: 'Adresse géographique', col: 'full', value: C.BRAND.adresse },
        { name: 'bp', label: 'Adresse postale', col: 'full', value: C.BRAND.bp },
        { name: 'telephones', label: 'Téléphones', value: C.BRAND.telephones.join(' / ') },
        { name: 'email', label: 'Adresse électronique', type: 'email', value: C.BRAND.email },

        { type: 'section', label: 'Mentions légales' },
        { name: 'ifu', label: 'IFU', required: true, value: C.BRAND.ifu },
        { name: 'rccm', label: 'RCCM', required: true, value: C.BRAND.rccm },
        { name: 'autorisation', label: 'N° d’autorisation d’ouverture', col: 'full', value: C.BRAND.autorisation },

        { type: 'section', label: 'Options d’impression' },
        { name: 'doubleLogo', label: 'Logo de part et d’autre de la dénomination', type: 'checkbox', value: true },
        { name: 'piedPage', label: 'Pied de page normalisé (utilisateur, date, identifiant)', type: 'checkbox', value: true },
        { name: 'filigrane', label: 'Filigrane par défaut', type: 'select', options: ['', 'Document officiel', 'Confidentiel'] },
      ], {});

      var gauche = el('div');
      gauche.appendChild(U.card('Paramètres de l’identité', el('div', null, [
        f,
        el('div.mt-4.flex.flex-wrap.gap-2', null, [
          K.btn('Enregistrer', {
            variant: 'primary', icon: 'save',
            onclick: function () {
              var v = f.collect();
              if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
              S.log('Modification', 'CFG', 'BrandConfiguration', 'BRAND', null, v);
              U.toast('Identité enregistrée.', {
                type: 'success',
                detail: 'Tous les états édités reprendront désormais ces mentions.',
              });
            },
          }),
          K.btn('Prévisualiser un état', {
            icon: 'eye',
            onclick: function () {
              P.etat({
                titre: 'Aperçu du papier à en-tête',
                sousTitre: 'Modèle appliqué à tous les documents édités',
                contenu: el('div.space-y-3', null, [
                  el('p', { text: 'Ce document illustre le gabarit officiel appliqué automatiquement à l’ensemble des états produits par le système : factures normalisées, ordonnances, bulletins de paie, bons de commande et de sortie, résultats de laboratoire, états comptables et rapports de direction.' }),
                  P.tableau([{ label: 'Mention', key: 'k' }, { label: 'Valeur', key: 'v' }], [
                    { k: 'Dénomination', v: C.BRAND.nom },
                    { k: 'Adresse postale', v: C.BRAND.bp },
                    { k: 'Téléphones', v: C.BRAND.telephones.join(' / ') },
                    { k: 'Adresse électronique', v: C.BRAND.email },
                    { k: 'Autorisation d’ouverture', v: C.BRAND.autorisation },
                    { k: 'IFU', v: C.BRAND.ifu },
                    { k: 'RCCM', v: C.BRAND.rccm },
                  ]),
                ]),
                signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
              });
            },
          }),
        ]),
      ])));
      host.appendChild(gauche);

      var droite = el('div.space-y-4');

      /* Aperçu visuel de l'entête */
      var apercu = el('div.rounded-lg.border.border-slate-300.bg-white.p-4');
      var top = el('div.flex.items-center.justify-center.gap-4');
      [1, 2].forEach(function () {
        top.appendChild(el('img.h-12.w-12.object-contain', {
          src: global.SIGH.app.base() + C.BRAND.logo, alt: 'CNT',
          onerror: function () { this.style.visibility = 'hidden'; },
        }));
      });
      var mid = el('div.text-center');
      mid.appendChild(el('p.text-base.font-bold.text-navy-950', { text: 'CLINIQUE NASSIERA TOO' }));
      mid.appendChild(el('p.text-\\[9px\\].text-slate-700', { text: C.BRAND.bp + ' TÉL. : ' + C.BRAND.telephones.join(' / ') }));
      mid.appendChild(el('p.text-\\[8px\\].text-slate-700', { text: 'AUTORISATION D’OUVERTURE ' + C.BRAND.autorisation }));
      mid.appendChild(el('p.text-\\[8px\\].font-semibold.text-slate-800', { text: 'IFU : ' + C.BRAND.ifu + '   RCCM : ' + C.BRAND.rccm }));
      mid.appendChild(el('p.text-\\[8px\\].text-slate-700', { text: 'E-mail : ' + C.BRAND.email }));
      top.insertBefore(mid, top.childNodes[1]);
      apercu.appendChild(top);
      apercu.appendChild(el('div.mt-2.border-b-2.border-navy-900'));
      apercu.appendChild(el('p.mt-4.text-center.text-xs.italic.text-slate-400', { text: '— corps du document —' }));
      apercu.appendChild(el('div.mt-4.border-t.border-slate-300.pt-2', null,
        el('p.text-\\[8px\\].text-slate-500', {
          text: C.BRAND.nom + ' — ' + C.BRAND.rccm + ' — IFU ' + C.BRAND.ifu
            + ' · Document généré par ' + S.currentUser() + ' le ' + C.dateHeure(AUJ) + ' · Réf. CNT-XXXXXXXX-0001',
        })));
      droite.appendChild(U.card('Aperçu du papier à en-tête', apercu));

      var carteRessources = el('div');
      droite.appendChild(carteRessources);
      dessinerRessources(carteRessources);

      droite.appendChild(K.note('Les états produits par le prototype reprennent déjà fidèlement l’entête réelle relevée sur les documents de la clinique.', { tone: 'success', icon: 'check-circle-2' }));

      host.appendChild(droite);
      root.appendChild(host);
      return null;
    },
  });

  /* --------------------------------------------------------------------------
   * RESSOURCES GRAPHIQUES — déposées, conservées, diffusées
   * --------------------------------------------------------------------------
   * L'écran se contentait d'annoncer ce qui manquait. La clinique dépose
   * désormais ses fichiers : ils sont conservés dans le magasin et alimentent
   * les états imprimables. Le dépôt reste local — aucune requête réseau.
   * ----------------------------------------------------------------------- */
  function colRessources() { return S.collection('ressources', { module: 'CFG', entite: 'ressource graphique', prefix: 'RES' }); }

  var RESSOURCES_ATTENDUES = [
    ['logo', 'Logo principal', 'Utilisé sur tous les états et dans l’application'],
    ['logo_mono', 'Logo monochrome', 'Pour les impressions en noir et blanc'],
    ['cachet', 'Cachet de l’établissement', 'Apposé sur les documents officiels'],
    ['signature_dm', 'Signature numérisée du Directeur', 'Documents médicaux et administratifs'],
    ['photos', 'Photographies du site', 'Supports de communication'],
  ];

  function dessinerRessources(hote) {
    C.clear(hote);
    var deposees = colRessources().active();

    var liste = el('div.space-y-2');
    RESSOURCES_ATTENDUES.forEach(function (r) {
      var d = deposees.filter(function (x) { return x.type === r[0]; });
      liste.appendChild(ligneRessource(r[0], r[1], r[2], d));
    });

    /* Une ressource hors catalogue reste possible : filigrane, en-tête d'un
       service, papier spécifique à un état. */
    var libres = deposees.filter(function (x) {
      return !RESSOURCES_ATTENDUES.some(function (r) { return r[0] === x.type; });
    });
    libres.forEach(function (x) {
      liste.appendChild(ligneRessource(x.type, x.libelle, 'Ressource ajoutée par la clinique', [x]));
    });

    hote.appendChild(U.card('Ressources graphiques', liste, [
      K.btn('Déposer une ressource', { size: 'sm', variant: 'primary', icon: 'upload', onclick: function () { deposer(null); } }),
    ]));
    U.icons(hote);

    function ligneRessource(type, nom, usage, fichiers) {
      var fourni = fichiers.length > 0;
      var f = fichiers[0];
      var vignette = fourni && f.donnees
        ? el('img.h-9.w-9.shrink-0.rounded-lg.border.border-slate-200.object-cover', { src: f.donnees, alt: nom })
        : el('span.grid.h-9.w-9.shrink-0.place-items-center.rounded-lg', {
          class: fourni ? 'bg-success-50 text-success-600' : 'bg-slate-100 text-slate-400',
        }, C.icon(fourni ? 'image' : 'image-off', 'h-4 w-4'));

      var actions = el('div.flex.shrink-0.items-center.gap-1');
      if (fourni) {
        if (fichiers.length > 1) actions.appendChild(U.badge(fichiers.length + ' fichiers', 'info'));
        actions.appendChild(U.badge('Déposé', 'success'));
        actions.appendChild(K.iconBtn('replace', 'Remplacer', function () { deposer(type, f); }));
        actions.appendChild(K.iconBtn('trash-2', 'Retirer', function () { retirer(f); }));
      } else {
        actions.appendChild(U.badge('À fournir', 'warning'));
        actions.appendChild(K.iconBtn('upload', 'Déposer', function () { deposer(type); }));
      }

      return el('div.flex.items-center.gap-3.rounded-lg.border.border-slate-200.px-3.py-2', null, [
        vignette,
        el('div.min-w-0.flex-1', null, [
          el('p.text-sm.font-medium.text-slate-800', { text: nom }),
          el('p.truncate.text-xs.text-slate-400', {
            text: fourni ? (f.fichier + ' · ' + poids(f.taille) + ' · déposé le ' + C.dateFR(f._creeLe)) : usage,
          }),
        ]),
        actions,
      ]);
    }

    function poids(o) {
      if (!o) return '—';
      return o > 1024 * 1024 ? (o / 1024 / 1024).toFixed(1) + ' Mo' : Math.round(o / 1024) + ' ko';
    }

    function retirer(f) {
      U.confirm({
        title: 'Retirer « ' + f.libelle + ' » ?',
        message: 'La ressource est archivée, non supprimée (RG-14) : elle reste restaurable depuis la corbeille. '
          + 'Les états édités après ce retrait ne la reprendront plus.',
        confirmLabel: 'Retirer', danger: true,
      }).then(function (ok) {
        if (!ok) return;
        var res = colRessources().archive(f.id, 'Retirée du papier à en-tête');
        dessinerRessources(hote);
        U.toast('Ressource retirée.', {
          type: 'success',
          undo: function () { res.undo(); dessinerRessources(hote); },
        });
      });
    }

    function deposer(type, remplace) {
      var attendue = RESSOURCES_ATTENDUES.filter(function (r) { return r[0] === type; })[0];
      var input = el('input.input', {
        type: 'file', accept: 'image/png,image/jpeg,image/webp,image/svg+xml',
        'aria-label': 'Fichier image',
      });
      var apercu = el('div');
      var meta = { donnees: null, fichier: null, taille: 0 };

      input.addEventListener('change', function () {
        var file = input.files && input.files[0];
        C.clear(apercu);
        if (!file) return;
        if (file.size > 1024 * 1024) {
          apercu.appendChild(K.note('Fichier de ' + poids(file.size) + ' — au-delà d’un mégaoctet, '
            + 'le stockage local du navigateur sature vite. Préférer une image allégée.', { tone: 'warning', icon: 'alert-triangle' }));
        }
        var lecteur = new FileReader();
        lecteur.onload = function () {
          meta.donnees = lecteur.result;
          meta.fichier = file.name;
          meta.taille = file.size;
          apercu.appendChild(el('img.mt-2.max-h-32.rounded-lg.border.border-slate-200.object-contain', { src: meta.donnees, alt: 'Aperçu' }));
        };
        lecteur.readAsDataURL(file);
      });

      var f = U.form([
        { name: 'libelle', label: 'Intitulé', required: true, col: 'full', value: attendue ? attendue[1] : '' },
        {
          name: 'type', label: 'Emploi', type: 'select', required: true,
          options: RESSOURCES_ATTENDUES.map(function (r) { return { value: r[0], label: r[1] }; })
            .concat([{ value: 'autre', label: 'Autre usage' }]),
          value: type || 'autre',
        },
        { name: 'usage', label: 'Où elle apparaît', col: 'full', value: attendue ? attendue[2] : '' },
      ], {});

      var corps = el('div.space-y-3', null, [
        f,
        el('div', null, [el('label.label', { text: 'Fichier image *' }), input, apercu]),
        K.note('Le fichier est conservé <strong>dans le poste</strong>, avec le reste des données : '
          + 'aucune requête réseau, conformément à la contrainte hors ligne de la clinique.', { tone: 'info' }),
      ]);

      var m = U.modal({
        title: remplace ? 'Remplacer la ressource' : 'Déposer une ressource graphique',
        subtitle: attendue ? attendue[1] : null, size: 'md', body: corps,
        footer: [
          K.btn('Annuler', { onclick: function () { m.close(); } }),
          K.btn(remplace ? 'Remplacer' : 'Déposer', {
            variant: 'primary', icon: 'upload',
            onclick: function () {
              var v = f.collect();
              if (!v) return;
              if (!meta.donnees) { U.toast('Choisir un fichier image.', { type: 'warning' }); return; }
              v.donnees = meta.donnees; v.fichier = meta.fichier; v.taille = meta.taille;
              if (remplace) colRessources().archive(remplace.id, 'Remplacée par une version plus récente');
              colRessources().insert(v);
              m.close();
              dessinerRessources(hote);
              U.toast('Ressource « ' + v.libelle + ' » enregistrée.', {
                type: 'success', detail: 'Elle alimentera les états imprimables.',
              });
            },
          }),
        ],
      });
    }
  }

  /* ==========================================================================
   * RÉFÉRENTIEL TARIFAIRE
   * ======================================================================== */
  global.SIGH.screen('cfg-tarifs', {
    title: 'Référentiel tarifaire',
    description: 'Tarif unique consommé par la pharmacie, la facturation, les assurances, les rapports et la comptabilité.',
    regle: 'Règle d’or (draf1 §22) : <strong>une seule source de vérité tarifaire</strong>. '
      + 'Les prix ne sont jamais dupliqués entre modules — la pharmacie, la facturation et la comptabilité lisent le même référentiel.',
    render: function (root) {
      var host = el('div.space-y-4');
      var produits = S.collection('produits').active();
      var analyses = S.collection('analyses').active();

      host.appendChild(U.kpiGrid([
        { label: 'Produits tarifés', value: C.num(produits.length), icon: 'pill', tone: 'navy' },
        { label: 'Analyses tarifées', value: C.num(analyses.length), icon: 'flask-conical', tone: 'info' },
        { label: 'Actes et prestations', value: C.num(actes().length), icon: 'stethoscope', tone: 'success', hint: D.SECTEURS_ACTIVITE.length + ' secteurs' },
        {
          label: 'Tarifs à confirmer',
          value: C.num(analyses.filter(function (a) { return a.tarifProvisoire; }).length + actes().filter(function (a) { return a.prix == null; }).length),
          icon: 'help-circle', tone: 'warning', hint: 'Colonnes de prix vierges aux sources',
        },
      ]));

      /* Schéma de propagation du tarif */
      var flux = el('div.flex.flex-wrap.items-center.justify-center.gap-2');
      flux.appendChild(el('span.rounded-lg.border-2.border-navy-400.bg-navy-50.px-4.py-2\\.5.text-sm.font-semibold.text-navy-900', { text: 'TARIF MASTER' }));
      flux.appendChild(C.icon('arrow-right', 'h-4 w-4 text-slate-300'));
      var cible = el('div.flex.flex-wrap.gap-2');
      [['Pharmacie', 'pill'], ['Facturation', 'receipt'], ['Assurances', 'shield-check'], ['Rapports', 'bar-chart-3'], ['Comptabilité', 'book-open-check']].forEach(function (x) {
        cible.appendChild(el('span.inline-flex.items-center.gap-1\\.5.rounded-lg.border.border-slate-200.bg-white.px-3.py-2.text-xs.font-medium.text-slate-700', null, [
          C.icon(x[1], 'h-3.5 w-3.5'), x[0],
        ]));
      });
      flux.appendChild(cible);
      host.appendChild(U.card('Propagation du tarif', flux));

      host.appendChild(U.tabs([
        {
          id: 'produits', label: 'Produits & médicaments', badge: produits.length,
          render: function () {
            return el('div.space-y-3', null, [
              K.note('<strong>RG-02</strong> — pour les médicaments, le prix de vente est strictement égal au prix d’achat : aucune marge n’est appliquée.', { tone: 'info' }),
              U.dataTable({
                rows: produits, exportName: 'tarifs-produits', pageSize: 15,
                actions: [K.creer(S.collection('produits', { module: 'M6', entite: 'Produit' }), CHAMPS_PRODUIT, {
                  titre: 'Nouveau produit tarifé', entite: 'Produit',
                  defauts: function () { return { categorie: 'medicament' }; },
                  transform: function (v) {
                    /* RG-02 : sur un médicament, le prix de vente suit le prix d achat. */
                    if (v.categorie === 'medicament') v.prixVente = v.prixAchat;
                    if (!v.code) v.code = 'PRD-' + C.pad(S.collection('produits').all().length + 1, 4);
                    v.stock = v.stock || 0; v.stockGros = v.stockGros || 0; v.stockDetail = v.stockDetail || 0;
                    return v;
                  },
                  apres: function () { global.location.reload(); },
                })],
                rowActions: K.actionsLigne(S.collection('produits', { module: 'M6', entite: 'Produit' }), [
                  { name: 'designation', label: 'Désignation', required: true, col: 'full' },
                  { name: 'prixAchat', label: 'Prix d’achat (FCFA)', type: 'number', min: 0, required: true },
                  {
                    name: 'prixVente', label: 'Prix de vente (FCFA)', type: 'number', min: 0, required: true,
                    help: 'RG-02 — pour un médicament, le prix de vente doit rester égal au prix d’achat.',
                  },
                  { name: 'unite', label: 'Unité' },
                ], {
                  archivable: false,
                }),
                defaultSort: 'designation',
                filters: [{ name: 'categorie', label: 'Catégorie', options: D.CATEGORIES_PRODUIT.map(function (c) { return { value: c.id, label: c.label }; }) }],
                columns: [
                  { key: 'code', label: 'Code', nowrap: true, render: function (p) { return el('span.font-mono.text-xs', { text: p.code }); } },
                  { key: 'designation', label: 'Désignation' },
                  {
                    key: 'categorie', label: 'Catégorie',
                    text: function (p) { var c = D.CATEGORIES_PRODUIT.filter(function (x) { return x.id === p.categorie; })[0]; return c ? c.label : p.categorie; },
                    render: function (p) {
                      var c = D.CATEGORIES_PRODUIT.filter(function (x) { return x.id === p.categorie; })[0];
                      return U.badge(c ? c.label : p.categorie, 'navy');
                    },
                  },
                  { key: 'unite', label: 'Unité' },
                  { key: 'prixAchat', label: 'Prix d’achat', align: 'right', text: function (p) { return C.money(p.prixAchat, false); }, render: function (p) { return C.money(p.prixAchat, false); } },
                  { key: 'prixVente', label: 'Prix de vente', align: 'right', text: function (p) { return C.money(p.prixVente, false); }, render: function (p) { return el('span.font-semibold', { text: C.money(p.prixVente, false) }); } },
                  {
                    key: 'marge', label: 'Marge', align: 'right',
                    value: function (p) { return p.prixVente - p.prixAchat; },
                    render: function (p) {
                      var m = p.prixVente - p.prixAchat;
                      return m === 0 ? U.badge('Sans marge', 'success') : el('span.font-semibold.text-warning-600', { text: C.money(m, false) });
                    },
                  },
                ],
              }),
            ]);
          },
        },
        {
          id: 'analyses', label: 'Analyses de laboratoire', badge: analyses.length,
          render: function () {
            return el('div.space-y-3', null, [
              K.note('Les 48 désignations proviennent du document « Tarifs des analyses de laboratoire » de la clinique. '
                + 'Le document source ne renseignant pas la colonne des prix, les tarifs portés ici sont des <strong>valeurs d’attente à confirmer</strong>.', { tone: 'warning', icon: 'help-circle' }),
              U.dataTable({
                rows: analyses, exportName: 'tarifs-analyses', pageSize: 15, defaultSort: 'n',
                actions: [K.creer(S.collection('analyses', { module: 'M5', entite: 'Analyse' }), CHAMPS_ANALYSE, {
                  titre: 'Nouvelle analyse au catalogue', entite: 'Analyse',
                  transform: function (v) {
                    var n = S.collection('analyses').all().length + 1;
                    v.n = n; v.code = v.code || 'L' + C.pad(n, 2);
                    v.tarifProvisoire = true;
                    return v;
                  },
                  apres: function () { global.location.reload(); },
                })],
                rowActions: K.actionsLigne(S.collection('analyses', { module: 'M5', entite: 'Analyse' }), [
                  { name: 'designation', label: 'Désignation', required: true, col: 'full' },
                  { name: 'categorie', label: 'Catégorie' },
                  {
                    name: 'prix', label: 'Tarif (FCFA)', type: 'number', min: 0, required: true,
                    help: 'Valeur d’attente : le document source ne renseigne pas la colonne des prix.',
                  },
                  { name: 'delai', label: 'Délai de rendu' },
                ], { entite: 'analyse' }),
                filters: [{ name: 'categorie', label: 'Catégorie', options: Object.keys(C.groupBy(analyses, 'categorie')).sort() }],
                columns: [
                  { key: 'n', label: 'N°', align: 'right', nowrap: true },
                  { key: 'code', label: 'Code', nowrap: true, render: function (a) { return el('span.font-mono.text-xs', { text: a.code }); } },
                  { key: 'designation', label: 'Désignation' },
                  { key: 'categorie', label: 'Catégorie', render: function (a) { return U.badge(a.categorie, 'navy'); } },
                  { key: 'prix', label: 'Tarif', align: 'right', text: function (a) { return C.money(a.prix, false); }, render: function (a) { return el('span.font-semibold', { text: C.money(a.prix, false) }); } },
                  {
                    key: 'tarifProvisoire', label: 'Statut',
                    text: function (a) { return a.tarifProvisoire ? 'À confirmer' : 'Confirmé'; },
                    render: function (a) { return a.tarifProvisoire ? U.badge('À confirmer', 'warning') : U.badge('Confirmé', 'success'); },
                  },
                ],
              }),
            ]);
          },
        },
        {
          id: 'actes', label: 'Actes & hospitalisation', badge: actes().length,
          render: function (panneau) {
            dessinerActes(panneau);
            return null;
          },
        },
        {
          /* QUATRIÈME ONGLET (Bug 12 des Instructions) : les certificats et
             attestations, LUS depuis le catalogue tarifaire et les types de
             pièces — une seule vérité, la modification se fait à sa source. */
          id: 'certificats', label: 'Certificats et Attestations',
          badge: (D.tarifParFamille ? D.tarifParFamille('CERTIFICAT') : []).length,
          render: function () {
            var tarifes = D.tarifParFamille ? D.tarifParFamille('CERTIFICAT') : [];
            var types = S.collection('typesPiece').active();
            var sansTarif = types.filter(function (t) { return !t.tarifCode; });
            return el('div.space-y-3', null, [
              K.note('Les certificats ne sont couverts par <strong>aucune assurance à l’exception de '
                + 'SOS</strong> — mention manuscrite de la grille tarifaire. Les tarifs se corrigent au '
                + '<strong>catalogue tarifaire</strong>, les pièces dans « Types de pièces certifiantes » : '
                + 'cet onglet les lit, il ne les duplique pas.', { tone: 'info', icon: 'file-badge' }),
              U.dataTable({
                rows: tarifes, exportName: 'tarifs-certificats', pageSize: 15,
                defaultSort: 'libelle',
                emptyMessage: 'Aucun certificat tarifé au catalogue.',
                columns: [
                  { key: 'code', label: 'Code', nowrap: true, render: function (t) { return el('span.font-mono.text-xs', { text: t.code }); } },
                  { key: 'libelle', label: 'Pièce' },
                  {
                    key: 'prixNonAssure', label: 'Prix non assuré', align: 'right',
                    text: function (t) { return C.money(t.prixNonAssure, false); },
                    render: function (t) { return C.money(t.prixNonAssure, false); },
                  },
                  {
                    key: 'prixAssure', label: 'Prix assuré', align: 'right',
                    text: function (t) { return t.assurable === 'sos' ? C.money(t.prixAssure, false) + ' (SOS)' : 'NON COUVERT'; },
                    render: function (t) {
                      return t.assurable === 'sos'
                        ? el('span', null, [el('span', { text: C.money(t.prixAssure, false) + ' ' }), U.badge('SOS seule', 'info')])
                        : U.badge('NON COUVERT', 'warning');
                    },
                  },
                ],
              }),
              sansTarif.length
                ? K.note('<strong>' + C.num(sansTarif.length) + ' type(s) de pièce sans tarif au '
                  + 'catalogue</strong> : ' + sansTarif.map(function (t) { return t.libelle; }).join(', ')
                  + '. Une pièce non tarifée se délivre, elle ne se facture pas — rattacher son acte '
                  + 'depuis « Types de pièces certifiantes ».', { tone: 'warning', icon: 'triangle-alert' })
                : null,
            ]);
          },
        },
      ]));
      root.appendChild(host);
      return null;
    },
  });

  /* --------------------------------------------------------------------------
   * CATALOGUE DES ACTES — administrable, et non plus écrit en dur
   * --------------------------------------------------------------------------
   * L'onglet présentait auparavant quatorze tarifs inscrits dans le code, dont
   * aucun ne figurait dans un document de la clinique. Il lit désormais la
   * collection `actes`, amorcée depuis le document « Répartition des activités
   * permettant l'évaluation des différents secteurs » : la Direction y crée,
   * corrige et archive ses prestations elle-même (draf1 §1 — rien en dur).
   * ----------------------------------------------------------------------- */
  /* Champs de saisie des deux autres onglets du référentiel — définis ici pour
     que la création et la modification partagent exactement le même formulaire. */
  var CHAMPS_PRODUIT = [
    { name: 'designation', label: 'Désignation', required: true, col: 'full' },
    {
      name: 'categorie', label: 'Catégorie', type: 'select', required: true,
      options: [{ value: 'medicament', label: 'Médicament' }, { value: 'conso_medical', label: 'Consommable médical' },
        { value: 'reactif', label: 'Réactif de laboratoire' }, { value: 'conso_labo', label: 'Consommable de laboratoire' },
        { value: 'divers', label: 'Divers' }],
    },
    { name: 'code', label: 'Code article', help: 'Laisser vide pour une attribution automatique.' },
    { name: 'unite', label: 'Unité' },
    { name: 'prixAchat', label: 'Prix d’achat (FCFA)', type: 'money', min: 0, required: true },
    {
      name: 'prixVente', label: 'Prix de vente (FCFA)', type: 'money', min: 0,
      help: 'RG-02 — pour un médicament, il est aligné d’office sur le prix d’achat : aucune marge.',
    },
    { name: 'seuilAlerte', label: 'Seuil d’alerte', type: 'number', min: 0 },
  ];

  var CHAMPS_ANALYSE = [
    { name: 'designation', label: 'Désignation', required: true, col: 'full' },
    { name: 'categorie', label: 'Catégorie', required: true },
    { name: 'code', label: 'Code', help: 'Laisser vide pour une attribution automatique.' },
    {
      name: 'prix', label: 'Tarif (FCFA)', type: 'money', min: 0, required: true,
      help: 'Le document source ne renseigne pas les prix : toute valeur saisie ici reste à confirmer.',
    },
    { name: 'echantillon', label: 'Échantillon' },
    { name: 'delai', label: 'Délai de rendu' },
  ];

  function colActes() { return S.collection('actes', { module: 'CFG', entite: 'acte', prefix: 'ACT' }); }
  function actes() { return colActes().active(); }
  /* L'amorçage du catalogue vit dans store.seed() — les actes sont lus par la
     consultation, l'hospitalisation, la facturation, la recherche globale et le
     moteur de parcours : un référentiel multi-lecteurs ne s'amorce jamais ici. */

  function champsActe() {
    return [
      { name: 'libelle', label: 'Libellé de la prestation', required: true, col: 'full' },
      {
        name: 'secteur', label: 'Secteur', type: 'select', required: true,
        options: D.SECTEURS_ACTIVITE.concat(['Hospitalisation']),
        help: 'Secteur qui exécute l’acte — sert aussi à l’évaluation de son activité.',
      },
      { name: 'code', label: 'Code', help: 'Laisser vide pour une attribution automatique.' },
      {
        name: 'prix', label: 'Tarif (FCFA)', type: 'money', min: 0,
        help: 'Laisser vide tant que la Direction n’a pas validé le tarif : l’acte est alors signalé « à valider ».',
      },
      { name: 'source', label: 'Document d’origine', col: 'full',
        help: 'Traçabilité : d’où vient ce tarif (facture, note de service, décision).' },
    ];
  }

  function dessinerActes(panneau) {
    C.clear(panneau);
    var rows = actes();
    var aValider = rows.filter(function (a) { return a.prix == null || a.tarifProvisoire; });
    var host = el('div.space-y-3');

    /* Trois populations, et il faut les distinguer : un tarif repris d'une
       grille imprimée, une valeur d'attente, et un acte que la grille décline
       en variantes — ce dernier n'est pas « sans prix », il attend qu'on dise
       DE QUEL acte il s'agit. Les confondre ferait chercher un prix là où
       c'est une question de nomenclature. */
    var repris = rows.filter(function (a) { return a.codeTarif; });
    var declines = rows.filter(function (a) { return a.variantesGrille && a.variantesGrille.length; });

    if (repris.length) {
      host.appendChild(K.note('<strong>' + repris.length + ' prestation(s) reprennent leur tarif des grilles '
        + 'imprimées de la clinique</strong>, avec leurs <strong>deux colonnes</strong> — assuré et non assuré. '
        + 'Le rapprochement est fait sur <strong>libellé identique</strong> ou par une '
        + '<strong>correspondance nommée</strong>, jamais par approximation : apparier « Consultation '
        + 'généraliste à domicile » avec « Consultation généraliste » ferait perdre le déplacement.',
        { tone: 'success', icon: 'check-circle' }));
    }
    if (aValider.length) {
      host.appendChild(K.note('<strong>' + aValider.length + ' prestation(s) portent encore un tarif '
        + 'd’attente.</strong> Elles ne figurent sur aucune des six grilles : la valeur permet d’exercer la '
        + 'facturation, elle reste signalée tant que la Direction ne l’a pas validée.',
        { tone: 'warning', icon: 'help-circle' }));
    }
    if (declines.length) {
      host.appendChild(K.note('<strong>' + declines.length + ' prestation(s) sont déclinées par la grille en '
        + 'plusieurs variantes</strong> — sept accouchements, quatre paliers d’oxygénothérapie, trois '
        + 'épisiotomies, deux ponctions lombaires. Ce n’est pas un prix manquant : c’est à la clinique de dire '
        + '<strong>quelle variante</strong> son acte désigne. Choisir à sa place facturerait le mauvais tarif.',
        { tone: 'info', icon: 'git-branch' }));
    }

    host.appendChild(U.dataTable({
      rows: rows, exportName: 'tarifs-actes', pageSize: 20, defaultSort: 'secteur', searchable: true,
      filters: [{
        name: 'secteur', label: 'Secteur',
        options: Object.keys(C.groupBy(rows, 'secteur')).sort(),
      }, {
        name: 'tarife', label: 'Tarif',
        options: [{ value: 'grille', label: 'Repris d’une grille' },
          { value: 'valide', label: 'Validé sur pièce' },
          { value: 'attente', label: 'Valeur d’attente' },
          { value: 'decline', label: 'Décliné par la grille' },
          { value: 'absent', label: 'Sans tarif' }],
        match: function (r, v) {
          if (v === 'grille') return !!r.codeTarif;
          if (v === 'valide') return r.prix != null && !r.tarifProvisoire;
          if (v === 'attente') return !!r.tarifProvisoire;
          if (v === 'decline') return !!(r.variantesGrille && r.variantesGrille.length);
          return r.prix == null;
        },
      }],
      columns: [
        { key: 'code', label: 'Code', nowrap: true, render: function (a) { return el('span.font-mono.text-xs', { text: a.code || '—' }); } },
        { key: 'libelle', label: 'Prestation' },
        { key: 'secteur', label: 'Secteur', render: function (a) { return U.badge(a.secteur, 'navy'); } },
        {
          key: 'prix', label: 'Tarif non assuré', align: 'right',
          text: function (a) { return a.prix == null ? 'à valider' : C.money(a.prix, false); },
          sortValue: function (a) { return a.prix == null ? -1 : a.prix; },
          render: function (a) {
            if (a.prix == null) return U.badge('à valider', 'warning');
            return el('div', null, [
              el('span.font-semibold', {
                class: a.tarifProvisoire ? 'text-warning-700' : 'text-slate-800',
                text: C.money(a.prix, false),
              }),
              a.tarifProvisoire ? el('p.text-[10px].text-warning-600', { text: 'valeur d’attente' }) : null,
            ]);
          },
        },
        {
          /* La colonne assurée n'est pas un doublon : c'est la règle de la
             Direction rendue vérifiable d'un coup d'œil. « NON COUVERT » y est
             une VALEUR, pas une absence — les actes de planification familiale
             et l'hydrotubation sont exclus délibérément. */
          key: 'prixAssure', label: 'Tarif assuré', align: 'right',
          text: function (a) {
            if (a.nonCouvert) return 'non couvert';
            return a.prixAssure == null ? '—' : C.money(a.prixAssure, false);
          },
          sortValue: function (a) { return a.prixAssure == null ? -1 : a.prixAssure; },
          render: function (a) {
            if (a.nonCouvert) return U.badge('non couvert', 'neutral');
            if (a.prixAssure == null) {
              return el('span.text-xs.text-slate-300', { text: '—' });
            }
            var ecart = a.prix != null ? a.prix - a.prixAssure : null;
            return el('div', null, [
              el('span.font-semibold.text-success-700', { text: C.money(a.prixAssure, false) }),
              ecart ? el('p.text-[10px].text-slate-400', { text: '− ' + C.money(ecart, false) }) : null,
            ].filter(Boolean));
          },
        },
        {
          key: 'source', label: 'Origine du tarif',
          render: function (a) {
            var lignes = [];
            lignes.push(a.source
              ? el('span.text-xs.text-slate-500', { text: a.source })
              : el('span.text-xs.text-slate-300', { text: '—' }));
            /* Par quelle voie le rapprochement s'est fait : une correspondance
               nommée est une DÉCISION, elle doit pouvoir se relire. */
            if (a.rapprochement) {
              lignes.push(el('p.text-[10px].text-slate-400', { text: 'rapproché par ' + a.rapprochement }));
            }
            if (a.motifPrix) {
              lignes.push(el('p.text-[10px].text-info-600', { text: a.motifPrix }));
            }
            return el('div', null, lignes);
          },
        },
      ],
      rowActions: K.actionsLigne(colActes(), champsActe, { entite: 'acte' }),
      actions: [
        K.creer(colActes(), champsActe, {
          titre: 'Nouvelle prestation', entite: 'Acte',
          defauts: function () { return { secteur: D.SECTEURS_ACTIVITE[0] }; },
          transform: function (v) {
            if (!v.code) v.code = 'ACT-' + C.pad(colActes().all().length + 1, 3);
            if (v.prix === '' || v.prix == null) v.prix = null;
            return v;
          },
          apres: function () { dessinerActes(panneau); },
        }),
        K.btn('Imprimer la grille tarifaire', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Grille tarifaire des actes et prestations',
              sousTitre: 'Catalogue par secteur — ' + C.dateFR(AUJ),
              cartouche: [['Prestations au catalogue', C.num(rows.length)],
                ['Tarifs validés', C.num(rows.length - aValider.length)],
                ['Tarifs à valider', C.num(aValider.length)],
                ['Date d’édition', C.dateFR(AUJ)]],
              contenu: P.tableau([
                { label: 'Code', key: 'code' },
                { label: 'Prestation', key: 'libelle' },
                { label: 'Secteur', key: 'secteur' },
                { label: 'Tarif', align: 'right', value: function (a) { return a.prix == null ? 'à valider' : C.money(a.prix, false); } },
              ], C.sortBy(rows, 'secteur')),
              signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
                { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
            });
          },
        }),
      ],
    }));

    host.appendChild(K.source('Répartition des activités permettant l’évaluation des différents secteurs de la clinique '
      + '— complétée des types de chambre du CDCT.'));
    panneau.appendChild(host);
    U.icons(panneau);
  }

  /* ==========================================================================
   * NATURES DE FACTURE
   * --------------------------------------------------------------------------
   * L'écran de facturation proposait cinq natures écrites dans son code, sans
   * Maternité ni Mise en observation — deux activités pourtant facturées tous
   * les jours. La liste devient un référentiel : la caisse en ajoute une sans
   * attendre une livraison logicielle.
   * ======================================================================== */
  function colNatures() { return S.collection('naturesFacture', { module: 'CFG', entite: 'nature de facture', prefix: 'NAT' }); }

  function champsNature() {
    return [
      { name: 'libelle', label: 'Nature de la facture', required: true, col: 'full' },
      { name: 'code', label: 'Code', help: 'Quatre lettres, laisser vide pour une attribution automatique.' },
      {
        name: 'secteur', label: 'Secteur émetteur', type: 'select', required: true,
        options: D.SECTEURS_ACTIVITE,
      },
      { name: 'source', label: 'Origine', col: 'full' },
    ];
  }

  global.SIGH.screen('cfg-natures-facture', {
    title: 'Natures de facture',
    description: 'Liste des natures proposées à l’émission d’une facture, administrable par la clinique.',
    regle: 'La caisse choisit la nature d’une facture dans cette liste. En ajouter une ici la rend '
      + '<strong>immédiatement disponible à l’émission</strong>, sans intervention sur le logiciel — '
      + 'c’est l’option « Ajouter » demandée par la Direction.',
    actions: function () {
      return [
        K.btn('Émettre une facture', { variant: 'primary', icon: 'receipt', onclick: function () { global.SIGH.app.go('m8-facturation'); } }),
        K.btn('Référentiel tarifaire', { icon: 'tag', onclick: function () { global.SIGH.app.go('cfg-tarifs'); } }),
      ];
    },
    render: function (root) {
      dessiner();
      return null;

      function dessiner() {
        C.clear(root);
        var rows = C.sortBy(colNatures().active(), 'ordre');
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          { label: 'Natures disponibles', value: C.num(rows.length), icon: 'receipt-text', tone: 'navy' },
          { label: 'Secteurs couverts', value: C.num(Object.keys(C.groupBy(rows, 'secteur')).length), icon: 'layers', tone: 'info' },
          { label: 'Natures archivées', value: C.num(colNatures().archived().length), icon: 'archive', tone: 'neutral', hint: 'Restaurables depuis la corbeille' },
        ]));

        host.appendChild(U.dataTable({
          title: 'Natures proposées à l’émission', rows: rows, exportName: 'natures-facture',
          pageSize: 20, searchable: true, defaultSort: 'ordre',
          filters: [{ name: 'secteur', label: 'Secteur', options: Object.keys(C.groupBy(rows, 'secteur')).sort() }],
          columns: [
            { key: 'code', label: 'Code', nowrap: true, render: function (n) { return el('span.font-mono.text-xs', { text: n.code }); } },
            { key: 'libelle', label: 'Nature', render: function (n) { return el('span.font-medium.text-slate-800', { text: n.libelle }); } },
            { key: 'secteur', label: 'Secteur émetteur', render: function (n) { return U.badge(n.secteur, 'navy'); } },
            {
              key: 'source', label: 'Origine',
              render: function (n) { return el('span.text-xs.text-slate-500', { text: n.source || '—' }); },
            },
          ],
          rowActions: K.actionsLigne(colNatures(), champsNature, { entite: 'nature de facture' }),
          actions: [K.creer(colNatures(), champsNature, {
            titre: 'Nouvelle nature de facture', entite: 'Nature',
            defauts: function () { return { secteur: D.SECTEURS_ACTIVITE[0], source: 'Décision de la Direction' }; },
            transform: function (v) {
              if (!v.code) v.code = (v.libelle || 'NAT').slice(0, 4).toUpperCase();
              v.ordre = colNatures().all().length + 1;
              return v;
            },
            apres: dessiner,
          })],
        }));

        root.appendChild(host);
        U.icons(root);
      }
    },
  });

  /* ==========================================================================
   * CENTRES DE COÛTS
   * ======================================================================== */
  function colCentres() { return S.collection('centresCouts', { module: 'M12', entite: 'centre de coûts', prefix: 'CC' }); }

  function champsCentre() {
    return [
      { name: 'libelle', label: 'Intitulé du centre', required: true, col: 'full' },
      { name: 'code', label: 'Code', help: 'Laisser vide pour une attribution automatique.' },
      {
        name: 'type', label: 'Type', type: 'select', required: true,
        options: [{ value: 'exploitation', label: 'Centre d’exploitation' },
          { value: 'support', label: 'Centre de support' }],
      },
      { name: 'responsable', label: 'Responsable', col: 'full' },
      { name: 'source', label: 'Origine', col: 'full' },
    ];
  }

  global.SIGH.screen('cfg-centres-couts', {
    title: 'Centres de coûts',
    description: 'Axes d’imputation analytique des écritures comptables, administrables par la clinique.',
    regle: 'Chaque écriture peut être imputée à un centre de coûts : c’est ce qui permet de mesurer '
      + 'ce que coûte et ce que rapporte chaque service. La liste se complète ici — ou directement '
      + 'depuis la saisie des écritures, sans quitter l’écran.',
    actions: function () {
      return [
        K.btn('Saisie des écritures', { variant: 'primary', icon: 'pencil-line', onclick: function () { global.SIGH.app.go('m12-ecritures'); } }),
        K.btn('Comptabilité analytique', { icon: 'pie-chart', onclick: function () { global.SIGH.app.go('m12-analytique'); } }),
      ];
    },
    render: function (root) {
      dessiner();
      return null;

      function dessiner() {
        C.clear(root);
        var rows = colCentres().active();
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          { label: 'Centres de coûts', value: C.num(rows.length), icon: 'target', tone: 'navy' },
          { label: 'Centres d’exploitation', value: C.num(rows.filter(function (c) { return c.type === 'exploitation'; }).length), icon: 'activity', tone: 'success' },
          { label: 'Centres de support', value: C.num(rows.filter(function (c) { return c.type === 'support'; }).length), icon: 'life-buoy', tone: 'info' },
          { label: 'Sans responsable', value: C.num(rows.filter(function (c) { return !c.responsable; }).length), icon: 'user-x', tone: 'warning' },
        ]));

        host.appendChild(U.dataTable({
          title: 'Axes analytiques', rows: rows, exportName: 'centres-couts',
          pageSize: 20, searchable: true, defaultSort: 'code',
          filters: [{
            name: 'type', label: 'Type',
            options: [{ value: 'exploitation', label: 'Exploitation' }, { value: 'support', label: 'Support' }],
          }],
          columns: [
            { key: 'code', label: 'Code', nowrap: true, render: function (c) { return el('span.font-mono.text-xs', { text: c.code }); } },
            { key: 'libelle', label: 'Centre', render: function (c) { return el('span.font-medium.text-slate-800', { text: c.libelle }); } },
            {
              key: 'type', label: 'Type',
              text: function (c) { return c.type === 'support' ? 'Support' : 'Exploitation'; },
              render: function (c) {
                return c.type === 'support' ? U.badge('Support', 'info') : U.badge('Exploitation', 'success');
              },
            },
            {
              key: 'responsable', label: 'Responsable',
              render: function (c) {
                return c.responsable
                  ? el('span.text-sm.text-slate-700', { text: c.responsable })
                  : el('span.text-xs.text-slate-300', { text: 'non désigné' });
              },
            },
          ],
          rowActions: K.actionsLigne(colCentres(), champsCentre, { entite: 'centre de coûts' }),
          actions: [K.creer(colCentres(), champsCentre, {
            titre: 'Nouveau centre de coûts', entite: 'Centre',
            defauts: function () { return { type: 'exploitation', source: 'Décision de la Direction' }; },
            transform: function (v) {
              if (!v.code) v.code = 'CC' + C.pad(colCentres().all().length + 1, 2);
              return v;
            },
            apres: dessiner,
          })],
        }));

        root.appendChild(host);
        U.icons(root);
      }
    },
  });

  /* ==========================================================================
   * RÈGLES MÉTIER VERSIONNÉES
   * ======================================================================== */
  global.SIGH.screen('cfg-regles', {
    title: 'Règles métier versionnées',
    description: 'Matrice de traçabilité : chaque règle du système est rattachée au document de cadrage qui la fonde.',
    regle: 'Chaque donnée issue d’un document de cadrage est <strong>reliée à sa source</strong> (draf1 §23). '
      + 'Une nouvelle note de service crée une nouvelle version : l’historique antérieur demeure intact.',
    render: function (root) {
      var host = el('div.space-y-4');

      /* --------------------------------------------------------------------
       * Valorisation des sorties de stock — le paramètre demandé par la
       * Direction, avec la mesure de ce qu'il change réellement.
       * ------------------------------------------------------------------ */
      /* La bascule vit au SOCLE : le moteur de stock, les états de la Direction
         et les points du gestionnaire la lisent depuis des pages qui ne
         chargent pas cet écran. */
      function methodeCourante() { return S.valorisationSortie(); }

      var carteValo = el('div');
      host.appendChild(carteValo);
      dessinerValorisation();

      function dessinerValorisation() {
        C.clear(carteValo);
        var methode = methodeCourante();
        var produits = S.collection('produits').active();

        /* L'écart réel sur le stock détenu, calculé et non supposé. */
        var ecart = 0, divergents = 0;
        produits.forEach(function (p) {
          var pv = (p.prixVente != null ? p.prixVente : p.prixAchat) || 0;
          var cump = p.cump != null ? p.cump : pv;
          var q = p.stock || 0;
          var d = (pv - cump) * q;
          if (Math.abs(pv - cump) > 0.0001) divergents++;
          ecart += d;
        });

        var choix = el('div.space-y-2');
        D.PARAM_STOCK.options.forEach(function (o) {
          var actif = o.id === methode;
          var ligne = el('button.flex.w-full.items-start.gap-3.rounded-lg.border.p-3.text-left.transition-colors', {
            type: 'button',
            class: actif ? 'border-navy-400 bg-navy-50' : 'border-slate-200 bg-white hover:border-navy-300',
            onclick: function () { basculer(o); },
          });
          ligne.appendChild(el('span.mt-0\\.5.grid.h-5.w-5.shrink-0.place-items-center.rounded-full.border-2', {
            class: actif ? 'border-navy-700 bg-navy-700 text-white' : 'border-slate-300',
          }, actif ? C.icon('check', 'h-3 w-3') : null));
          ligne.appendChild(el('div.min-w-0.flex-1', null, [
            el('p.text-sm.font-semibold.text-slate-800', { text: o.label }),
            el('p.mt-0\\.5.text-xs.text-slate-500', { text: o.note }),
          ]));
          if (actif) ligne.appendChild(U.badge('En vigueur', 'success'));
          choix.appendChild(ligne);
        });

        carteValo.appendChild(U.card('Valorisation des sorties de stock', el('div.space-y-3', null, [
          K.note('Annotation manuscrite de la réunion du 30/12/2024 : <em>« Paramétrer pour que les produits '
            + 'sortent au Prix de Vente et non au CUMP »</em>. La Direction demandait un paramètre — le voici, '
            + 'avec la mesure de ce qu’il change.', { tone: 'info', icon: 'file-check-2' }),
          choix,
          el('div.rounded-lg.border.border-slate-200.bg-slate-50.p-3', null, [
            el('p.text-xs.font-semibold.uppercase.tracking-wide.text-slate-500', { text: 'Effet mesuré sur le stock détenu' }),
            el('p.mt-1.text-sm.text-slate-700', {
              text: Math.abs(ecart) < 5000
                ? 'Écart entre les deux méthodes : ' + C.money(Math.abs(Math.round(ecart)))
                  + ' sur l’ensemble du stock — un effet d’arrondi, non une différence de méthode.'
                : 'Écart entre les deux méthodes : ' + C.money(Math.abs(Math.round(ecart))) + ' sur l’ensemble du stock.',
            }),
            el('p.mt-1.text-xs.text-slate-500', {
              text: divergents + ' article(s) sur ' + produits.length + ' présentent un prix de vente différent du CUMP. '
                + 'Tant que RG-02 s’applique — médicaments au prix d’achat, sans marge — les deux valorisations coïncident. '
                + 'Elles divergeront le jour où une marge sera appliquée à un article hors médicament.',
            }),
          ]),
        ])));
        U.icons(carteValo);
      }

      function basculer(o) {
        if (o.id === methodeCourante()) return;
        U.confirm({
          title: 'Valoriser les sorties au ' + o.label.toLowerCase() + ' ?',
          message: o.note + ' Le changement s’applique aux sorties à venir ; les mouvements déjà enregistrés '
            + 'conservent la valeur retenue au moment de leur saisie, ainsi que les deux valorisations, '
            + 'de sorte que l’historique reste comparable.',
          confirmLabel: 'Appliquer',
        }).then(function (ok) {
          if (!ok) return;
          var avant = methodeCourante();
          S.storage.set(CLE_VALO, o.id);
          S.setValorisationSortie(o.id);
          S.log('Paramétrage', 'M6', 'Valorisation des sorties', o.id, { methode: avant }, { methode: o.id });
          dessinerValorisation();
          U.toast('Sorties valorisées au ' + o.label.toLowerCase() + '.', {
            type: 'success', detail: 'Applicable aux prochaines sorties de stock.',
          });
        });
      }

      /* --------------------------------------------------------------------
       * Groupes et familles d'articles.
       * ------------------------------------------------------------------ */
      var produitsTous = S.collection('produits').active();
      var parFamille = D.FAMILLES_ARTICLES.map(function (f) {
        var lot = produitsTous.filter(function (p) { return p.categorie === f.id; });
        var g = D.GROUPES_ARTICLES.filter(function (x) { return x.id === f.groupe; })[0];
        return {
          famille: f.label, groupe: g ? g.label : '—',
          articles: lot.length,
          quantite: C.sum(lot, function (p) { return p.stock || 0; }),
          valeur: C.sum(lot, function (p) { return (p.prixAchat || 0) * (p.stock || 0); }),
        };
      });

      host.appendChild(U.card('Groupes et familles d’articles', el('div.space-y-3', null, [
        K.note('Les <strong>familles</strong> viennent du document : l’inventaire SAGE « Grand Stock » classe '
          + 'ses articles en sept catégories. Les <strong>groupes</strong>, eux, ne figurent dans aucun document — '
          + 'ce regroupement en quatre ensembles est une <strong>proposition</strong> soumise à la Direction, '
          + 'et non une donnée reprise d’une source.', { tone: 'warning', icon: 'help-circle' }),
        K.miniTable([
          { label: 'Groupe', key: 'groupe' },
          { label: 'Famille', key: 'famille' },
          { label: 'Articles', align: 'right', render: function (r) { return C.num(r.articles); } },
          { label: 'Quantité en stock', align: 'right', render: function (r) { return C.num(r.quantite); } },
          { label: 'Valeur', align: 'right', render: function (r) { return C.money(r.valeur, false); } },
        ], C.sortBy(parFamille, 'groupe')),
      ])));


      host.appendChild(U.kpiGrid([
        { label: 'Documents sources', value: C.num(D.SOURCES_VERITE.length), icon: 'file-check-2', tone: 'navy' },
        { label: 'Intégrés au système', value: C.num(D.SOURCES_VERITE.filter(function (s) { return s.statut.indexOf('Intégré') === 0; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'À importer', value: C.num(D.SOURCES_VERITE.filter(function (s) { return s.statut.indexOf('À') === 0; }).length), icon: 'upload', tone: 'warning' },
        { label: 'Règles de gestion', value: '14', icon: 'scale', tone: 'info', hint: 'RG-01 à RG-14' },
      ]));

      /* Matrice document → système */
      host.appendChild(U.dataTable({
        title: 'Matrice « document collecté → rôle dans le logiciel »',
        rows: D.SOURCES_VERITE, exportName: 'sources-verite', pageSize: 20, searchable: true,
        columns: [
          { key: 'document', label: 'Document collecté' },
          { key: 'devient', label: 'Devient dans le logiciel' },
          { key: 'module', label: 'Module', render: function (s) { return U.badge(s.module, 'navy'); } },
          {
            key: 'ecran', label: 'Écran',
            render: function (s) {
              return s.ecran
                ? el('a.btn.btn-secondary.btn-sm', { href: global.SIGH.app.href(s.ecran) }, 'Ouvrir')
                : el('span.text-xs.text-slate-400', { text: '—' });
            },
          },
          {
            key: 'statut', label: 'Statut',
            render: function (s) {
              if (s.statut.indexOf('Intégré') === 0) {
                return U.badge(s.statut, s.statut.indexOf('partiel') > 0 || s.statut.indexOf('confirmer') > 0 ? 'warning' : 'success');
              }
              return U.badge(s.statut, 'warning');
            },
          },
        ],
      }));

      /* Règles de gestion RG-01 à RG-14 */
      var RG = [
        ['RG-01', 'Identifiant patient CNT/[n°]/[année] généré automatiquement, unique et non modifiable', 'M1', 'm1-patients'],
        ['RG-02', 'Médicaments facturés au prix d’achat, sans marge bénéficiaire', 'M6 / M8', 'm6-produits'],
        ['RG-03', 'Toute sortie de stock rattachée à un justificatif ; stock jamais négatif', 'M6', 'm6-mouvements'],
        ['RG-04', 'Commande de stock gros validée par la Directrice Administrative', 'M7', 'm7-commandes'],
        ['RG-05', 'Rangement FEFO et alertes de péremption automatiques', 'M6', 'm6-lots'],
        ['RG-06', 'Sortie d’hospitalisation conditionnée à l’apurement du solde', 'M3', 'm3-sorties'],
        ['RG-07', 'Sortie requérant signature patient, signature infirmier et constat du gardien', 'M3', 'm3-sorties'],
        ['RG-08', 'Sortie contre avis médical motivée ; avis du Procureur si nécessaire', 'M3', 'm3-sortie-avis-medical'],
        ['RG-09', 'Prise en charge assurance appliquée uniquement si la carte est valide', 'M9', 'm9-assures'],
        ['RG-10', 'Toute écriture comptable équilibrée avant validation', 'M12', 'm12-ecritures'],
        ['RG-11', 'Primes de garde et de permanence calculées depuis le planning validé', 'M10 / M11', 'm10-primes'],
        ['RG-12', 'Journalisation de toute action ; aucune action anonyme', 'M14', 'm14-audit'],
        ['RG-13', 'Cloisonnement des données médicales, financières et RH', 'M14', 'm14-roles'],
        ['RG-14', 'Suppression logique uniquement, jamais de suppression physique', 'Transverse', 'm14-audit'],
      ].map(function (r) { return { code: r[0], regle: r[1], module: r[2], ecran: r[3] }; });

      host.appendChild(U.dataTable({
        title: 'Règles de gestion transversales',
        rows: RG, exportName: 'regles-gestion', pageSize: 20, searchable: true,
        columns: [
          { key: 'code', label: 'Code', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: r.code }); } },
          { key: 'regle', label: 'Règle appliquée' },
          { key: 'module', label: 'Module', render: function (r) { return U.badge(r.module, 'navy'); } },
          {
            key: 'ecran', label: 'Écran d’application',
            render: function (r) { return el('a.btn.btn-secondary.btn-sm', { href: global.SIGH.app.href(r.ecran) }, 'Voir'); },
          },
        ],
        actions: [K.btn('Imprimer la matrice', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'Matrice de traçabilité des règles métier',
              sousTitre: 'Documents de cadrage et règles de gestion appliquées',
              cartouche: [['Documents sources', C.num(D.SOURCES_VERITE.length)],
                ['Règles de gestion', C.num(RG.length)],
                ['Date d’édition', C.dateFR(AUJ)], ['Établi par', S.currentUser()]],
              contenu: el('div.space-y-4', null, [
                el('p.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Documents collectés et leur rôle dans le logiciel' }),
                P.tableau([
                  { label: 'Document collecté', key: 'document' },
                  { label: 'Devient dans le logiciel', key: 'devient' },
                  { label: 'Module', key: 'module' },
                  { label: 'Statut', key: 'statut' },
                ], D.SOURCES_VERITE),
                el('p.mt-4.text-\\[11px\\].font-bold.uppercase.text-navy-900', { text: 'Règles de gestion transversales' }),
                P.tableau([
                  { label: 'Code', key: 'code' },
                  { label: 'Règle appliquée', key: 'regle' },
                  { label: 'Module', key: 'module' },
                ], RG),
              ]),
              signatures: [{ role: 'La Directrice Administrative', nom: 'TAKI Alimatou' },
                { role: 'Le Directeur Médical', nom: 'BASSONGUI Chabi Séko' }],
            });
          },
        })],
      }));

      /* Versions des règles */
      host.appendChild(U.card('Règles métier versionnées', K.miniTable([
        { label: 'Référence', render: function (n) { return el('span.font-mono.text-xs.font-semibold', { text: n.reference }); } },
        { label: 'Objet', key: 'objet' },
        { label: 'Version', render: function (n) { return U.badge('v' + n.version, 'navy'); } },
        { label: 'Date d’effet', render: function (n) { return C.dateFR(n.dateEffet); } },
        { label: 'Statut', render: function (n) { return U.badge(n.statut, 'success'); } },
        { label: 'Moteur piloté', render: function (n) { return n === D.NS131 ? 'Évaluation et sanctions' : 'Primes diverses'; } },
      ], [D.NS131, D.NS132]), [K.lien('m13-notes-service', 'Consulter les notes', { size: 'sm', icon: 'arrow-right' })]));

      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * PARAMÈTRES FISCAUX
   * ======================================================================== */
  global.SIGH.screen('cfg-fiscalite', {
    title: 'Paramètres fiscaux (IFU / RCCM)',
    description: 'Identifiants fiscaux, numérotation des documents et paramètres de la facturation normalisée.',
    render: function (root) {
      var host = el('div.space-y-4');
      host.appendChild(K.note('Ces paramètres sont partagés avec le module <strong>MECeF</strong>. Toute modification s’applique immédiatement aux prochains documents émis.', { tone: 'info' }));
      host.appendChild(U.card('Identification fiscale de l’établissement', U.descList([
        ['Dénomination sociale', C.BRAND.nom],
        ['Forme juridique', C.BRAND.forme],
        ['IFU', el('span.font-mono.text-base.font-semibold.text-navy-900', { text: C.BRAND.ifu })],
        ['RCCM', el('span.font-mono.text-base.font-semibold.text-navy-900', { text: C.BRAND.rccm })],
        ['Autorisation d’ouverture', C.BRAND.autorisation],
        ['Adresse fiscale', C.BRAND.bp],
        ['Devise', C.BRAND.devise + ' (' + C.BRAND.codeDevise + ')'],
        ['Régime de TVA', 'Taux normal 18 %'],
      ], 'grid-cols-1 sm:grid-cols-2'), [K.lien('mecef-config', 'Configuration MECeF', { size: 'sm', icon: 'arrow-right' })]));

      host.appendChild(U.card('Numérotation des documents', K.miniTable([
        { label: 'Type de document', key: 'type' },
        { label: 'Préfixe', render: function (x) { return el('span.font-mono.text-xs.font-semibold', { text: x.prefixe }); } },
        { label: 'Format', key: 'format' },
        { label: 'Séquence', key: 'sequence' },
      ], [
        { type: 'Facture normalisée', prefixe: 'FN-2026-', format: 'FN-AAAA-NNNNN', sequence: 'Strictement séquentielle' },
        { type: 'Facture pro-forma', prefixe: 'PRO-2026-', format: 'PRO-AAAA-NNNNN', sequence: 'Indépendante' },
        { type: 'Avoir', prefixe: 'AV-2026-', format: 'AV-AAAA-NNNN', sequence: 'Strictement séquentielle' },
        { type: 'Dossier patient', prefixe: 'CNT', format: 'CNT/[n°]/[AA]', sequence: 'Par année civile (RG-01)' },
        { type: 'Bon de commande', prefixe: 'BC-2026-', format: 'BC-AAAA-NNNN', sequence: 'Par exercice' },
        { type: 'Bon d’expression de besoins', prefixe: 'BEB-2026-', format: 'BEB-AAAA-NNNN', sequence: 'Par exercice' },
        { type: 'Bulletin de paie', prefixe: 'BP-', format: 'BP-NNNNN', sequence: 'Par période de paie' },
        { type: 'Écriture comptable', prefixe: '[JOURNAL]-2026-', format: 'JJJ-AAAA-NNNNN', sequence: 'Par journal' },
      ])));

      host.appendChild(U.card('Obligations déclaratives', K.miniTable([
        { label: 'Déclaration', key: 'd' },
        { label: 'Périodicité', key: 'p' },
        { label: 'Échéance', key: 'e' },
        { label: 'Écran producteur', render: function (x) { return el('a.btn.btn-secondary.btn-sm', { href: global.SIGH.app.href(x.ecran) }, 'Éditer'); } },
      ], [
        { d: 'Cotisations CNSS', p: 'Mensuelle', e: '15 du mois suivant', ecran: 'm11-cotisations' },
        { d: 'Impôt sur les traitements et salaires (ITS)', p: 'Mensuelle', e: '10 du mois suivant', ecran: 'm11-cotisations' },
        { d: 'Versement patronal de solidarité (VPS)', p: 'Mensuelle', e: '10 du mois suivant', ecran: 'm11-cotisations' },
        { d: 'Transmission des factures normalisées', p: 'Continue', e: 'À l’émission', ecran: 'mecef-transmission' },
        { d: 'États financiers de synthèse', p: 'Annuelle', e: 'Clôture de l’exercice', ecran: 'm12-etats-financiers' },
      ])));

      /* --------------------------------------------------------------------
       * Calendrier fiscal et social — les échéances dictées par le comptable.
       * Une échéance qui tombe un week-end se reporte au jour ouvrable suivant.
       * ------------------------------------------------------------------ */
      var AN = AUJ.getFullYear();

      function jourOuvrable(d) {
        var x = new Date(d.getTime());
        while (x.getDay() === 0 || x.getDay() === 6) x = C.addDays(x, 1);
        return x;
      }

      function prochaineEcheance(e) {
        if (e.periodicite === 'mensuelle') {
          var m = AUJ.getMonth();
          var d = new Date(AN, m, e.jour);
          if (d < AUJ) d = new Date(AN, m + 1, e.jour);
          return jourOuvrable(d);
        }
        var a = new Date(AN, e.mois, e.jour);
        if (a < AUJ) a = new Date(AN + 1, e.mois, e.jour);
        return jourOuvrable(a);
      }

      var echeances = D.CALENDRIER_FISCAL.map(function (e) {
        var d = prochaineEcheance(e);
        var reporte = C.iso(d) !== C.iso(new Date(d.getFullYear(),
          e.periodicite === 'mensuelle' ? d.getMonth() : e.mois, e.jour));
        return Object.assign({}, e, {
          echeance: C.iso(d),
          jours: C.daysBetween(AUJ, d),
          reporte: reporte,
        });
      });
      var proches = echeances.filter(function (e) { return e.jours >= 0 && e.jours <= 30; });

      host.appendChild(U.kpiGrid([
        { label: 'Échéances suivies', value: C.num(echeances.length), icon: 'landmark', tone: 'navy' },
        { label: 'Mensuelles', value: C.num(echeances.filter(function (e) { return e.periodicite === 'mensuelle'; }).length), icon: 'calendar-days', tone: 'info', hint: 'ITS, AIB, VPS, CNSS' },
        {
          label: 'Dans les 30 jours', value: C.num(proches.length), icon: 'alarm-clock',
          tone: proches.length ? 'warning' : 'success',
        },
        { label: 'CCIB annuelle', value: C.money(D.MONTANTS_FISCAUX.ccib.total), icon: 'coins', tone: 'neutral', hint: 'Deux tranches de 150 000 F' },
      ], 'grid-cols-2 lg:grid-cols-4'));

      if (proches.length) {
        host.appendChild(K.note('<strong>' + proches.length + ' échéance(s) dans les trente jours</strong> : '
          + proches.slice(0, 4).map(function (e) { return e.code + ' le ' + C.dateFR(e.echeance); }).join(' · ')
          + (proches.length > 4 ? ' …' : '') + '. Une déclaration précède généralement le paiement.',
        { tone: 'warning', icon: 'alarm-clock' }));
      }

      host.appendChild(U.dataTable({
        title: 'Calendrier fiscal et social',
        rows: echeances, exportName: 'calendrier-fiscal', pageSize: 20, searchable: true,
        defaultSort: 'jours',
        filters: [
          {
            name: 'periodicite', label: 'Périodicité',
            options: [{ value: 'mensuelle', label: 'Mensuelle' }, { value: 'annuelle', label: 'Annuelle' }],
          },
        ],
        columns: [
          { key: 'code', label: 'Code', nowrap: true, render: function (e) { return el('span.font-mono.text-xs.font-semibold', { text: e.code }); } },
          { key: 'libelle', label: 'Obligation' },
          {
            key: 'periodicite', label: 'Périodicité',
            render: function (e) { return U.badge(e.periodicite === 'mensuelle' ? 'Mensuelle' : 'Annuelle', e.periodicite === 'mensuelle' ? 'info' : 'navy'); },
          },
          {
            key: 'echeance', label: 'Prochaine échéance', nowrap: true,
            text: function (e) { return C.dateFR(e.echeance); },
            render: function (e) {
              return el('div', null, [
                el('p.text-sm.text-slate-700', { text: C.dateFR(e.echeance) }),
                e.reporte ? el('p.text-\[10px\].text-warning-600', { text: 'reportée — jour ouvrable' }) : null,
              ]);
            },
          },
          {
            key: 'jours', label: 'Dans', align: 'right',
            render: function (e) {
              if (e.jours < 0) return el('span.text-xs.text-slate-400', { text: 'passée' });
              return el('span.num', {
                class: e.jours <= 10 ? 'font-semibold text-danger-600' : (e.jours <= 30 ? 'text-warning-600' : 'text-slate-600'),
                text: e.jours + ' j',
              });
            },
          },
          { key: 'note', label: 'Règle appliquée', render: function (e) { return el('span.text-xs.text-slate-500', { text: e.note }); } },
        ],
      }));

      host.appendChild(K.note('<strong>Impôt sur les sociétés.</strong> L’impôt de l’exercice se paie par '
        + 'anticipation : l’impôt de l’année précédente est divisé en quatre acomptes, versés les 10 mars, '
        + '10 juin, 10 septembre et 10 décembre. Le <strong>30 avril de l’année suivante</strong>, la '
        + 'liquidation du solde ajuste à la hausse ou à la baisse, en même temps que le dépôt des états '
        + 'financiers.', { tone: 'info', icon: 'landmark' }));

      host.appendChild(K.source(D.CALENDRIER_FISCAL[0].source
        + ' — le calendrier de la CCIB et des acomptes d’impôt sur les sociétés a été '
          + '<strong>confirmé par la Direction le 25/08/2026</strong> : déclaration prévisionnelle de fin de '
          + 'mois, puis deux tranches de 50 % aux 10 mars et 10 juin pour la CCIB ; quatre acomptes aux '
          + '10 mars, 10 juin, 10 septembre et 10 décembre pour l’impôt sur les sociétés, liquidation du '
          + 'solde et dépôt des états financiers au 30 avril de l’année suivante.'));

      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * NOTIFICATIONS
   * ======================================================================== */
  /**
   * Le bloc « Notifications & son ». Il pilote le CANAL sonore ; les règles
   * métier — quels événements, pour qui, avec quelle priorité — restent
   * définies ailleurs et ne sont pas touchées ici.
   */
  function blocSon() {
    var NT = global.SIGH.notifications;
    var carte = el('div.card');
    var corps = el('div.card-body.space-y-4');

    if (!NT) {
      corps.appendChild(K.note('Moteur de notification indisponible sur ce poste.',
        { tone: 'warning', icon: 'bell-off' }));
      carte.appendChild(corps);
      return carte;
    }

    function peindre() {
      C.clear(corps);
      var p = NT.params();
      var dispo = NT.audioDisponible();

      corps.appendChild(el('div.flex.items-center.justify-between.gap-3', null, [
        el('div', null, [
          el('p.text-sm.font-semibold.text-slate-800', { text: 'Notifications & son' }),
          el('p.text-xs.text-slate-500', {
            text: 'Ces réglages gouvernent la façon dont une alerte se manifeste sur CE poste. '
              + 'Ils ne modifient ni les seuils, ni les destinataires, ni les priorités.' }),
        ]),
        dispo
          ? U.badge('Sonorisation disponible', 'success')
          : U.badge('Sonorisation indisponible', 'warning'),
      ]));

      if (!dispo) {
        corps.appendChild(K.note('Aucun périphérique audio n’a répondu. '
          + '<strong>L’application continue normalement</strong> : la cloche, le badge, les '
          + 'messages et l’historique fonctionnent. La sonorisation est un canal secondaire, '
          + 'jamais un point de défaillance.', { tone: 'info', icon: 'volume-x' }));
      }

      function bascule(cle, libelle, aide) {
        var id = 'ntf_' + cle;
        var input = el('input.checkbox', { type: 'checkbox', id: id });
        input.checked = !!p[cle];
        input.addEventListener('change', function () {
          var o = {}; o[cle] = input.checked;
          NT.setParams(o);
          peindre();
        });
        return el('div.flex.items-start.gap-2', null, [
          input,
          el('label.min-w-0', { for: id }, [
            el('p.text-sm.text-slate-800', { text: libelle }),
            el('p.text-xs.text-slate-500', { text: aide }),
          ]),
        ]);
      }

      corps.appendChild(el('div.grid.gap-3.md\\:grid-cols-2', null, [
        bascule('visuel', 'Notifications visuelles',
          'Message à l’écran lorsqu’une alerte nouvelle apparaît. La cloche et le badge '
          + 'restent actifs même sans cette option.'),
        bascule('son', 'Sons d’alerte',
          'DÉSACTIVER LE SON NE DÉSACTIVE PAS L’ALERTE : cloche, badge, message et '
          + 'historique continuent de fonctionner.'),
      ]));

      /* Le profil sonore : volume, durée, répétition. Il ne crée aucune
         catégorie métier — il applique une politique aux priorités qui
         existent déjà. */
      var selProfil = el('select.select');
      NT.PROFILS_AUDIO.forEach(function (x) {
        selProfil.appendChild(el('option', { value: x.id }, x.label));
      });
      selProfil.value = p.profil;
      selProfil.disabled = !p.son;
      selProfil.addEventListener('change', function () {
        NT.setParams({ profil: selProfil.value });
        peindre();
      });

      var selTempo = el('select.select');
      [[5, '5 minutes'], [15, '15 minutes'], [30, '30 minutes'],
        [60, '1 heure'], [240, '4 heures']].forEach(function (t) {
        selTempo.appendChild(el('option', { value: String(t[0]) }, t[1]));
      });
      selTempo.value = String(p.temporisation);
      selTempo.disabled = !p.son;
      selTempo.addEventListener('change', function () {
        NT.setParams({ temporisation: Number(selTempo.value) });
        peindre();
      });

      corps.appendChild(el('div.grid.gap-3.md\\:grid-cols-2', null, [
        el('div', null, [
          el('label.label', { text: 'Profil sonore' }), selProfil,
          el('p.mt-1.text-xs.text-slate-500', { text: NT.profilAudio().note }),
        ]),
        el('div', null, [
          el('label.label', { text: 'Ne pas resonner la même alerte avant' }), selTempo,
          el('p.mt-1.text-xs.text-slate-500', {
            text: 'Une alerte persistante — un stock sous son seuil le reste des jours — ne doit '
              + 'pas sonner à chaque passage. L’alerte, elle, demeure entière.' }),
        ]),
      ]));

      /* Tester SANS créer de fausse alerte : aucun enregistrement, aucun
         workflow, aucune donnée touchée. Un test qui laisserait une trace
         serait pire qu'aucun test — il faudrait la nettoyer ensuite. */
      corps.appendChild(el('div.flex.flex-wrap.items-center.gap-2', null, [
        K.btn('Tester la sonorisation', {
          icon: 'volume-2', variant: 'secondary',
          onclick: function () {
            var r = NT.tester();
            U.toast(r.joue ? 'Son de test émis.' : 'Son de test non émis.', {
              type: r.joue ? 'success' : 'warning',
              detail: r.joue
                ? 'Aucune alerte n’a été créée : ce test ne touche ni les données ni les workflows.'
                : r.motif,
              silencieux: true,
            });
          },
        }),
        el('span.text-xs.text-slate-500', {
          text: 'Ce test ne crée aucune notification métier et ne modifie aucune donnée.' }),
      ]));

      var att = NT.enAttente().length;
      corps.appendChild(K.note('<strong>' + att + ' alerte(s) en attente</strong> pour votre poste. '
        + 'Le moteur route chaque alerte selon les <strong>rôles et les droits déjà définis</strong> : '
        + 'une alerte qui renverrait vers un écran interdit à votre profil ne vous est pas présentée.',
      { tone: att ? 'warning' : 'success', icon: 'bell' }));

      U.icons(corps);
    }

    peindre();
    carte.appendChild(corps);
    return carte;
  }

  global.SIGH.screen('cfg-notifications', {
    title: 'Notifications',
    description: 'Paramétrage des alertes adressées au personnel, par événement et par canal.',
    render: function (root) {
      var host = el('div.space-y-4');

      /* ------------------------------------------------------------------
       * NOTIFICATIONS & SON — le canal, jamais la règle
       * ------------------------------------------------------------------
       * Ces réglages ne touchent AUCUN paramètre métier : ni seuil, ni
       * destinataire, ni priorité. Ils décident seulement si, et comment, une
       * alerte déjà déterminée se fait entendre.
       *
       * COUPER LE SON NE COUPE PAS L'ALERTE. C'est ce qui rend le mode
       * silencieux utilisable en salle : le poste se tait sans rien perdre.
       * ---------------------------------------------------------------- */
      host.appendChild(blocSon());

      var NOTIFS = [
        { id: 'admission', libelle: 'Nouvelle admission', detail: 'Alerte à l’admission d’un patient', dest: 'Infirmiers, Direction médicale', app: true, sms: false, mail: false },
        { id: 'sortie', libelle: 'Sortie d’hospitalisation', detail: 'Alerte à la caisse pour vérification du solde (RG-06)', dest: 'Caisse, Infirmiers', app: true, sms: false, mail: false },
        { id: 'rupture', libelle: 'Rupture de stock', detail: 'Produit passant sous le seuil d’alerte', dest: 'Gestionnaire de stock, Pharmacie', app: true, sms: true, mail: false },
        { id: 'peremption', libelle: 'Péremption proche', detail: 'Lot arrivant à échéance sous 90 jours (RG-05)', dest: 'Pharmacie, Gestionnaire de stock', app: true, sms: false, mail: false },
        { id: 'resultat', libelle: 'Résultat de laboratoire disponible', detail: 'Notification au médecin prescripteur', dest: 'Médecins', app: true, sms: true, mail: false },
        { id: 'facture', libelle: 'Facture générée', detail: 'Notification à la caisse et à la comptabilité', dest: 'Caisse, Comptabilité', app: true, sms: false, mail: false },
        { id: 'commande', libelle: 'Commande à valider', detail: 'Demande de validation (RG-04)', dest: 'Directrice Administrative', app: true, sms: false, mail: true },
        { id: 'paie', libelle: 'Paie à valider', detail: 'Soumission des bulletins à la Direction', dest: 'Direction', app: true, sms: false, mail: true },
        { id: 'carte', libelle: 'Carte d’assurance expirée', detail: 'Alerte à la facturation (RG-09)', dest: 'Caisse', app: true, sms: false, mail: false },
        { id: 'mecef', libelle: 'Facture MECeF rejetée', detail: 'Anomalie fiscale à corriger', dest: 'Caisse, Comptabilité', app: true, sms: false, mail: true },
        { id: 'securite', libelle: 'Tentative de connexion infructueuse', detail: 'Alerte de sécurité (RG-12)', dest: 'Administrateur système', app: true, sms: false, mail: true },
        { id: 'sauvegarde', libelle: 'Échec de sauvegarde', detail: 'Alerte technique', dest: 'Administrateur système', app: true, sms: true, mail: true },
      ];

      var etats = {};
      var liste = el('div.overflow-x-auto');
      var t = el('table.tbl');
      t.appendChild(el('thead', null, el('tr', null, [
        el('th', { text: 'Événement déclencheur' }),
        el('th', { text: 'Destinataires' }),
        el('th.text-center', { text: 'Dans l’application' }),
        el('th.text-center', { text: 'SMS' }),
        el('th.text-center', { text: 'Courriel' }),
      ])));
      var tb = el('tbody');
      NOTIFS.forEach(function (n) {
        var tr = el('tr');
        tr.appendChild(el('td', null, el('div.min-w-0', null, [
          el('p.text-sm.font-medium.text-slate-800', { text: n.libelle }),
          el('p.text-xs.text-slate-400', { text: n.detail }),
        ])));
        tr.appendChild(el('td.text-xs.text-slate-600', { text: n.dest }));
        etats[n.id] = {};
        ['app', 'sms', 'mail'].forEach(function (canal) {
          var cb = el('input.checkbox', { type: 'checkbox' });
          cb.checked = n[canal];
          etats[n.id][canal] = cb;
          tr.appendChild(el('td.text-center', null, cb));
        });
        tb.appendChild(tr);
      });
      t.appendChild(tb);
      liste.appendChild(t);

      host.appendChild(U.kpiGrid([
        { label: 'Événements paramétrés', value: C.num(NOTIFS.length), icon: 'bell', tone: 'navy' },
        { label: 'Notifications dans l’application', value: C.num(NOTIFS.filter(function (n) { return n.app; }).length), icon: 'monitor', tone: 'success' },
        { label: 'Notifications par SMS', value: C.num(NOTIFS.filter(function (n) { return n.sms; }).length), icon: 'smartphone', tone: 'info' },
        { label: 'Notifications par courriel', value: C.num(NOTIFS.filter(function (n) { return n.mail; }).length), icon: 'mail', tone: 'warning' },
      ]));

      host.appendChild(U.card('Matrice des notifications', liste, [
        K.btn('Enregistrer le paramétrage', {
          size: 'sm', variant: 'primary', icon: 'save',
          onclick: function () {
            var actifs = 0;
            Object.keys(etats).forEach(function (id) {
              ['app', 'sms', 'mail'].forEach(function (c) { if (etats[id][c].checked) actifs++; });
            });
            S.log('Modification', 'CFG', 'ParametrageNotifications', 'NOTIF', null, { canauxActifs: actifs });
            U.toast('Paramétrage enregistré.', { type: 'success', detail: actifs + ' canal(aux) actif(s).' });
          },
        }),
      ]));

      host.appendChild(K.note('Les envois par SMS et par courriel nécessitent une connexion Internet. En son absence, les notifications restent disponibles dans l’application et sont transmises dès le rétablissement de la liaison.', { tone: 'warning', icon: 'wifi-off' }));

      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * MON COMPTE
   * ======================================================================== */
  global.SIGH.screen('cfg-compte', {
    title: 'Mon compte',
    description: 'Informations personnelles, sécurité du compte et préférences d’affichage.',
    render: function (root) {
      var s = S.session() || { nom: 'Utilisateur', role: 'admin' };
      var host = el('div.grid.gap-4.lg\\:grid-cols-3');

      var principal = el('div.space-y-4.lg\\:col-span-2');

      var profil = U.form([
        { name: 'nom', label: 'Nom et prénoms', required: true, col: 'full', value: s.nom },
        { name: 'identifiant', label: 'Identifiant de connexion', readonly: true, value: s.identifiant || 'admin.systeme' },
        { name: 'poste', label: 'Poste', readonly: true, value: N.ROLES[s.role] ? N.ROLES[s.role].label : '' },
        { name: 'telephone', label: 'Téléphone', type: 'tel' },
        { name: 'email', label: 'Adresse électronique', type: 'email' },
      ], {});
      principal.appendChild(U.card('Informations personnelles', el('div', null, [
        profil,
        el('div.mt-4', null, K.btn('Enregistrer', {
          variant: 'primary', icon: 'save',
          onclick: function () {
            var v = profil.collect();
            if (!v) return;
            S.setSession(Object.assign({}, s, { nom: v.nom }));
            U.toast('Informations enregistrées.', { type: 'success' });
          },
        })),
      ])));

      var securite = U.form([
        { name: 'actuel', label: 'Mot de passe actuel', type: 'password', required: true },
        { name: 'nouveau', label: 'Nouveau mot de passe', type: 'password', required: true },
        { name: 'confirmation', label: 'Confirmer le nouveau mot de passe', type: 'password', required: true },
        { name: 'mfa', label: 'Activer l’authentification à deux facteurs', type: 'checkbox', col: 'full', value: ['admin', 'direction', 'dm', 'da'].indexOf(s.role) !== -1 },
      ], {});
      principal.appendChild(U.card('Sécurité du compte', el('div', null, [
        securite,
        el('div.mt-3', null, K.note('Politique en vigueur : 12 caractères minimum, majuscules, minuscules, chiffre et caractère spécial, renouvellement tous les 90 jours, verrouillage après trois tentatives infructueuses.', { tone: 'info' })),
        el('div.mt-4', null, K.btn('Modifier le mot de passe', {
          variant: 'primary', icon: 'key-round',
          onclick: function () {
            var v = securite.collect();
            if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
            if (v.nouveau !== v.confirmation) { U.toast('Les deux mots de passe ne correspondent pas.', { type: 'error' }); return; }
            if (String(v.nouveau).length < 12) { U.toast('Le mot de passe doit comporter au moins 12 caractères.', { type: 'error' }); return; }
            S.log('Modification', 'M14', 'Utilisateur', s.identifiant || s.nom, null, { motDePasse: 'modifié' });
            U.toast('Mot de passe modifié.', { type: 'success' });
          },
        })),
      ])));

      host.appendChild(principal);

      var lateral = el('div.space-y-4');
      var carte = el('div.card');
      var b = el('div.card-body.text-center');
      b.appendChild(el('span.mx-auto.grid.h-16.w-16.place-items-center.rounded-full.bg-navy-900.text-lg.font-semibold.text-white', { text: C.initials(s.nom) }));
      b.appendChild(el('p.mt-3.text-sm.font-semibold.text-slate-900', { text: s.nom }));
      b.appendChild(el('p.text-xs.text-slate-500', { text: N.ROLES[s.role] ? N.ROLES[s.role].label : '' }));
      b.appendChild(el('div.mt-3.flex.justify-center', null, U.badge('Compte actif', 'success')));
      carte.appendChild(b);
      lateral.appendChild(carte);

      lateral.appendChild(U.card('Périmètre d’accès', el('div.flex.flex-wrap.gap-1', null,
        (function () {
          var out = [];
          N.NAV.forEach(function (dom) {
            dom.modules.forEach(function (mod) {
              var ok = mod.items.some(function (it) { return N.can(s.role, { roles: it.roles || mod.roles || N.ALL, module: mod.code }); });
              if (ok) out.push(U.badge(mod.code, 'navy'));
            });
          });
          return out;
        })()
      ), [K.lien('m14-roles', 'Matrice RBAC', { size: 'sm', icon: 'arrow-right' })]));

      lateral.appendChild(U.card('Activité récente', U.timeline(
        (S.raw().audit || []).filter(function (a) { return a.utilisateur === s.nom; }).slice(0, 6).map(function (a) {
          return { title: a.action + ' — ' + a.entite, detail: 'Module ' + a.module, date: C.ilYA(a.dateHeure), tone: 'navy' };
        })
      )));

      host.appendChild(lateral);
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * PARAMÈTRES SYSTÈME
   * ======================================================================== */
  /* ==========================================================================
   * ACTIVITÉ DES MODULES
   * --------------------------------------------------------------------------
   * Le logiciel sait tenir des activités que la clinique n'exerce pas. Laisser
   * leurs écrans au méga-menu donne à croire qu'ils attendent d'être remplis —
   * et un utilisateur finit par y saisir quelque chose.
   *
   * Fermer une activité la retire du menu, de la recherche globale ET de ses
   * propres adresses, pour TOUS les rôles, administrateur compris : ce n'est
   * pas une habilitation, c'est une activité qui n'a pas lieu. Rien n'est
   * supprimé : la clinique peut ouvrir l'activité demain, et ses données
   * l'attendent intactes.
   * ======================================================================== */
  global.SIGH.screen('cfg-modules', {
    title: 'Activité des modules',
    description: 'Ouvrir ou fermer les activités que la clinique exerce. Un module fermé disparaît du menu sans rien perdre.',
    regle: 'Fermer une activité la retire du méga-menu, de la recherche et de ses adresses, '
      + '<strong>pour tous les rôles</strong>. Ce n’est pas une habilitation : c’est une activité que '
      + 'l’établissement ne pratique pas. <strong>Rien n’est supprimé</strong> — la réouverture rend '
      + 'l’écran et ses données en l’état. Depuis la vague 50, <strong>chaque module M1…M14 se pilote '
      + 'ici d’une bascule</strong> — un autre établissement active seulement ce qu’il exerce — et '
      + '<strong>fermer un module n’empêche jamais un autre de travailler</strong> : les stocks, la '
      + 'paie ou les RH fonctionnent Accueil et Soins fermés. Seul le NOYAU (Configuration, tableaux '
      + 'de bord) ne se ferme pas : un interrupteur qui se coupe lui-même ne se rallume plus.',
    render: function (root) {
      /* Déclaré AVANT le premier afficher() : une affectation `var` placée
         après le `return` ne s'exécute jamais — le piège déjà payé sur
         CODES_PANSEMENT (phase 7). */
      var NOYAU = {
        CFG: 'porte cet interrupteur — un interrupteur qui se coupe lui-même ne se rallume plus',
        DASH: 'porte la page d’accueil de chaque rôle — la fermer laisserait la connexion sans destination',
      };
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col() {
        return S.collection('modulesActifs', { module: 'CFG', entite: 'activité', prefix: 'MOD' });
      }

      /** Tous les écrans du manifeste, à plat, avec leur module. */
      function tousEcrans() {
        var out = [];
        N.NAV.forEach(function (dom) {
          dom.modules.forEach(function (m) {
            if (m.alias) return;
            m.items.forEach(function (it) {
              if (it.alias) return;
              out.push({ id: it.id, label: it.label, module: m.code, moduleLabel: m.label, domaine: dom.domain });
            });
          });
        });
        return out;
      }

      /* --------------------------------------------------------------------
       * VAGUE 50 — LE PILOTAGE PAR MODULE, dérivé du manifeste
       * --------------------------------------------------------------------
       * Une autre clinique n'active que ce qu'elle exerce : chaque module
       * du ruban se bascule ici. Le NOYAU ne se ferme pas — CFG porte cet
       * interrupteur même, DASH porte la page d'accueil de chaque rôle.
       * Fermer un module ne touche NI ses données NI les autres modules :
       * les files qu'il alimentait cessent de se remplir, la saisie directe
       * des autres postes reste ouverte (c'est déjà la doctrine du
       * laboratoire et de l'accueil externe).
       * ------------------------------------------------------------------ */
      function listeModules() {
        var vus = {}, out = [];
        N.NAV.forEach(function (dom) {
          dom.modules.forEach(function (m) {
            if (m.alias || vus[m.code]) return;
            vus[m.code] = true;
            out.push({ code: m.code, label: m.label, icon: m.icon, domaine: dom.domain,
              nbEcrans: m.items.filter(function (it) { return !it.alias; }).length });
          });
        });
        return out;
      }

      /** La fiche MODULE-niveau (sans liste d'écrans) d'un code, s'il en a une. */
      function ficheModule(code) {
        return col().active().filter(function (x) {
          return x.module === code && !(x.ecrans && x.ecrans.length);
        })[0] || null;
      }

      function basculerModule(m) {
        var fiche = ficheModule(m.code);
        if (!fiche) {
          /* La fiche naît OUVERTE au premier geste : basculer() porte ensuite
             la fermeture, avec son motif obligatoire. */
          fiche = col().insert({
            code: 'MODULE-' + m.code, module: m.code,
            libelle: 'Module — ' + m.label,
            actif: true,
            motif: null,
          }).record;
        }
        basculer(fiche);
      }

      function afficher() {
        var fiches = col().active();
        var fermes = fiches.filter(function (f) { return f.actif === false; });
        var ecrans = tousEcrans();
        var ecransFermes = ecrans.filter(function (e) { return !N.ecranActif(e.id, e.module); });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Écrans au périmètre', value: C.num(ecrans.length), icon: 'layout-grid', tone: 'navy' },
          {
            label: 'Activités fermées', value: C.num(fermes.length), icon: 'toggle-left',
            tone: fermes.length ? 'warning' : 'success',
          },
          {
            label: 'Écrans retirés du menu', value: C.num(ecransFermes.length), icon: 'eye-off',
            tone: ecransFermes.length ? 'warning' : 'neutral',
          },
          {
            label: 'Écrans ouverts', value: C.num(ecrans.length - ecransFermes.length),
            icon: 'eye', tone: 'success',
          },
        ]));

        vue.appendChild(K.note('Une activité fermée n’est <strong>pas supprimée</strong>. Ses écrans, ses données de '
          + 'démonstration et son paramétrage restent en place : rouvrir l’activité les rend en l’état. '
          + 'C’est ce qui distingue cette page d’une suppression, et ce qui permet de fermer sans crainte.',
        { tone: 'info', icon: 'archive-restore' }));

        var rows = fiches.map(function (f) {
          return Object.assign({}, f, {
            nbEcrans: (f.ecrans && f.ecrans.length) || 0,
            portee: f.ecrans && f.ecrans.length
              ? C.num(f.ecrans.length) + ' écran(s)'
              : 'Module ' + f.module + ' entier',
          });
        });

        vue.appendChild(U.dataTable({
          title: 'Activités pilotées', rows: rows, exportName: 'activite-modules', pageSize: 15,
          emptyMessage: 'Aucune activité pilotée — toutes les activités du logiciel sont ouvertes.',
          columns: [
            {
              key: 'libelle', label: 'Activité',
              render: function (f) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.font-medium.text-slate-800', { text: f.libelle }),
                  el('p.text-xs.text-slate-400', { text: f.portee }),
                ]);
              },
            },
            { key: 'module', label: 'Module', nowrap: true, render: function (f) { return U.badge(f.module, 'navy'); } },
            {
              key: 'actif', label: 'État',
              text: function (f) { return f.actif === false ? 'fermée' : 'ouverte'; },
              render: function (f) {
                return f.actif === false ? U.badge('Fermée', 'warning') : U.badge('Ouverte', 'success');
              },
            },
            { key: 'motif', label: 'Motif', render: function (f) { return el('span.text-xs.text-slate-500', { text: f.motif || '—' }); } },
            {
              key: 'fermeLe', label: 'Depuis le', nowrap: true, align: 'right',
              render: function (f) {
                return f.actif === false && f.fermeLe
                  ? el('span.text-xs.text-slate-500', { text: C.dateFR(f.fermeLe) })
                  : el('span.text-xs.text-slate-300', { text: '—' });
              },
            },
          ],
          actions: K.droits('CFG').editer ? [K.btn('Piloter une activité', {
            variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { declarer(); },
          })] : [],
          rowActions: function (f) {
            if (!K.droits('CFG').editer) return [];
            return [K.iconBtn(f.actif === false ? 'toggle-right' : 'toggle-left',
              f.actif === false ? 'Rouvrir cette activité' : 'Fermer cette activité',
              function () { basculer(f); })];
          },
        }));

        /* ------------------------------------------------------------------
         * LES MODULES DU LOGICIEL — une bascule par module, dérivée du
         * manifeste (jamais recopiée : un module ajouté paraît ici seul).
         * ---------------------------------------------------------------- */
        var grilleModules = el('div.grid.gap-3.md:grid-cols-2.xl:grid-cols-3');
        listeModules().forEach(function (m) {
          var fiche = ficheModule(m.code);
          var ferme = !!(fiche && fiche.actif === false);
          var noyau = NOYAU[m.code];
          var carte = el('div.card', { class: ferme ? 'opacity-75' : '' });
          carte.appendChild(el('div.card-body.flex.items-center.gap-3', null, [
            el('span.shrink-0', { class: ferme ? 'text-slate-400' : 'text-navy-600' },
              C.icon(m.icon || 'box', 'h-6 w-6')),
            el('div.min-w-0.flex-1', null, [
              el('p.truncate.text-sm.font-medium.text-slate-800', { text: m.code + ' — ' + m.label }),
              el('p.text-xs.text-slate-400', {
                text: noyau
                  ? 'NOYAU : ' + noyau
                  : C.num(m.nbEcrans) + ' écran(s) · ' + m.domaine
                    + (ferme && fiche.fermeLe ? ' · fermé le ' + C.dateFR(fiche.fermeLe) : ''),
              }),
            ]),
            noyau
              ? U.badge('Toujours ouvert', 'navy')
              : (ferme ? U.badge('Fermé', 'warning') : U.badge('Ouvert', 'success')),
            !noyau && K.droits('CFG').editer
              ? K.iconBtn(ferme ? 'toggle-right' : 'toggle-left',
                ferme ? 'Rouvrir le module ' + m.code : 'Fermer le module ' + m.code,
                function () { basculerModule(m); })
              : null,
          ].filter(Boolean)));
          grilleModules.appendChild(carte);
        });
        vue.appendChild(U.card('Modules du logiciel — activer seulement ce que l’établissement exerce',
          el('div.space-y-3', null, [
            K.note('<strong>Fermer un module n’empêche jamais un autre de travailler.</strong> Les stocks, '
              + 'la paie ou les ressources humaines fonctionnent Accueil et Soins fermés : les files que '
              + 'le module fermé alimentait cessent simplement de se remplir, ses données restent en '
              + 'place, et la saisie directe des autres postes demeure ouverte — c’est la doctrine du '
              + 'laboratoire (saisie manuelle) et de l’accueil externe, appliquée partout.',
            { tone: 'info', icon: 'unplug' }),
            grilleModules,
          ])));

        /* Les écrans effectivement retirés, pour que la conséquence se voie. */
        if (ecransFermes.length) {
          vue.appendChild(U.card('Écrans actuellement retirés du méga-menu',
            K.miniTable([
              { label: 'Écran', key: 'label' },
              { label: 'Module', render: function (e) { return e.moduleLabel; } },
              { label: 'Domaine', key: 'domaine' },
              {
                label: 'Motif', render: function (e) {
                  var f = N.fermeturePour(e.id, e.module);
                  return el('span.text-xs.text-slate-500', { text: f ? f.motif : '—' });
                },
              },
            ], ecransFermes)));
        }
        U.icons(vue);
      }

      function declarer() {
        var ecrans = tousEcrans();
        var f = U.form([
          { name: 'libelle', label: 'Intitulé de l’activité', type: 'text', required: true, col: 'full' },
          {
            name: 'module', label: 'Module concerné', type: 'select', required: true,
            options: Object.keys(C.groupBy(ecrans, 'module')).map(function (c) {
              var m = N.module(c);
              return { value: c, label: c + ' — ' + (m ? m.label : c) };
            }),
          },
          {
            name: 'ecrans', label: 'Écrans concernés', type: 'multiselect', col: 'full',
            options: ecrans.map(function (e) { return { value: e.id, label: e.moduleLabel + ' · ' + e.label }; }),
            hint: 'Laisser vide pour piloter le module entier.',
          },
          { name: 'motif', label: 'Motif', type: 'textarea', rows: 2, required: true, col: 'full',
            hint: 'Pourquoi la clinique n’exerce pas cette activité — le motif s’affiche à l’écran.' },
        ], {});

        var m = U.modal({
          title: 'Piloter une activité', size: 'lg',
          body: el('div.space-y-3', null, [
            K.note('Déclarer une activité permet de l’<strong>ouvrir ou la fermer</strong> par la suite. '
              + 'Elle est créée <strong>ouverte</strong> : la fermeture est un second geste, délibéré.',
            { tone: 'info' }),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Déclarer', {
              variant: 'primary', icon: 'plus',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                v.code = v.module + '-' + String(v.libelle).toUpperCase().replace(/[^A-Z0-9]+/g, '').slice(0, 8);
                v.actif = true;
                col().insert(v);
                N.invaliderModules();
                m.close(); afficher();
                U.toast('Activité déclarée.', { type: 'success', detail: v.libelle + ' — ouverte.' });
              },
            }),
          ],
        });
      }

      function basculer(f) {
        var fermer = f.actif !== false;
        var nb = (f.ecrans && f.ecrans.length) || 0;
        /* Le NOYAU ne se ferme pas, quelle que soit la porte : refuser EN LE
           DISANT vaut mieux qu'un interrupteur qui se coupe lui-même. */
        if (fermer && !nb && NOYAU[f.module]) {
          U.toast('Le module ' + f.module + ' ne se ferme pas.', {
            type: 'error', detail: 'Il ' + NOYAU[f.module] + '.',
          });
          return;
        }
        U.confirm({
          title: fermer ? 'Fermer « ' + f.libelle + ' » ?' : 'Rouvrir « ' + f.libelle + ' » ?',
          message: fermer
            ? (nb ? '<strong>' + C.num(nb) + ' écran(s)</strong> disparaîtront du méga-menu, de la recherche '
              + 'globale et de leurs propres adresses'
              : 'Le <strong>module ' + f.module + ' entier</strong> disparaîtra du méga-menu, de la recherche '
              + 'globale et de ses adresses')
              + ', <strong>pour tous les rôles</strong>, administrateur compris.<br><br>'
              + 'Aucune donnée n’est supprimée : la réouverture rend les écrans en l’état.'
            : (nb ? C.num(nb) + ' écran(s) réapparaîtront' : 'Le module ' + f.module + ' réapparaîtra')
              + ' au méga-menu, avec leurs données inchangées.',
          confirmLabel: fermer ? 'Fermer l’activité' : 'Rouvrir l’activité',
          danger: fermer, requireMotif: fermer,
        }).then(function (rep) {
          if (!rep) return;
          col().update(f.id, {
            actif: !fermer,
            motif: fermer ? (rep.motif || f.motif) : f.motif,
            fermeLe: fermer ? C.iso(AUJ) : null,
            fermePar: fermer ? S.currentUser() : null,
            rouvertLe: fermer ? null : C.iso(AUJ),
            rouvertPar: fermer ? null : S.currentUser(),
          });
          N.invaliderModules();
          S.log(fermer ? 'Fermeture d’une activité' : 'Réouverture d’une activité',
            'CFG', 'Activité', f.code, { actif: f.actif }, { actif: !fermer });
          afficher();
          U.toast(fermer ? 'Activité fermée.' : 'Activité rouverte.', {
            type: 'success',
            detail: fermer
              ? 'Les écrans concernés quittent le menu ; leurs données restent intactes.'
              : 'Les écrans réapparaissent au menu avec leurs données.',
          });
        });
      }
    },
  });

  global.SIGH.screen('cfg-systeme', {
    title: 'Paramètres système',
    description: 'Configuration technique, environnement d’exécution et outils de maintenance du prototype.',
    regle: 'Les paramètres décrivent l’<strong>installation technique</strong> et ne se saisissent pas ici. '
      + 'L’onglet <strong>Corbeille</strong>, lui, agit : <strong>RG-14</strong> — rien n’est jamais supprimé, '
      + 'tout ce qui a été archivé dans n’importe quel module s’y retrouve et s’y restaure.',
    render: function (root) {
      root.appendChild(U.tabs([
        { id: 'installation', label: 'Installation et données', render: ongletInstallation },
        { id: 'corbeille', label: 'Corbeille', badge: S.corbeille().length, render: ongletCorbeille },
        { id: 'bareme', label: 'Barème NS 131', render: ongletBaremeNS131 },
        { id: 'reinitialisation', label: 'Jeux de test', render: ongletReinitialisation },
      ]));
      return null;
    },
  });

  /* --- Onglet « Installation et données » --------------------------------- */
  /* ==========================================================================
   * LA PORTE DU BARÈME NS 131
   * --------------------------------------------------------------------------
   * Condition posée par la Direction : « on doit autoriser le CRUD depuis
   * paramètres de setting ». Un barème de sanctions ne se retouche pas au
   * détour d'un écran d'évaluation.
   *
   * Fermée, la modification est ABSENTE à l'écran des évaluations et non
   * grisée : un bouton grisé invite à chercher pourquoi, un bouton absent dit
   * que ce n'est pas ici que cela se règle.
   * ======================================================================== */
  function ongletBaremeNS131() {
    var hote = el('div.space-y-3');
    dessiner();
    return hote;

    function dessiner() {
      var ouverte = global.SIGH.baremeModifiable();
      C.clear(hote);
      hote.appendChild(K.note('Le <strong>barème d’évaluation ' + D.NS131.reference + '</strong> fixe les '
        + 'retenues appliquées au salaire brut. Sa modification est <strong>fermée par défaut</strong>. '
        + 'L’ouvrir ici rend le barème modifiable à l’écran « Évaluations » — et l’ouverture est journalisée. '
        + 'Chaque modification demandera ensuite sa <strong>portée</strong> : évaluations à venir seulement, '
        + 'ou évaluations déjà prononcées comprises.',
      { tone: ouverte ? 'warning' : 'info', icon: ouverte ? 'unlock' : 'lock' }));

      hote.appendChild(U.card('Modification du barème', el('div.space-y-3', null, [
        U.descList([
          ['État', ouverte ? U.badge('Ouverte', 'warning') : U.badge('Fermée', 'success')],
          ['Référence', D.NS131.reference],
          ['En vigueur depuis', C.dateFR(D.NS131.dateEffet)],
          ['Critères au barème', C.num(S.collection('baremeNS131').active().length)],
          ['Versions antérieures', C.num(S.collection('historiqueBareme').active().length)],
        ], 'grid-cols-2'),
        K.btn(ouverte ? 'Refermer la modification' : 'Autoriser la modification', {
          variant: ouverte ? 'secondary' : 'danger',
          icon: ouverte ? 'lock' : 'unlock',
          onclick: function () { basculer(ouverte); },
        }),
      ])));
      U.icons(hote);
    }

    function basculer(ouverte) {
      if (ouverte) {
        global.SIGH.setBaremeModifiable(false);
        S.log('Fermeture de la modification du barème', 'M10', 'Barème', D.NS131.reference, null, {});
        dessiner();
        U.toast('Modification du barème refermée.', {
          type: 'success', detail: 'Le barème redevient consultable seulement.',
        });
        return;
      }
      U.confirm({
        title: 'Autoriser la modification du barème NS 131 ?',
        message: 'Le barème fixe les <strong>retenues sur salaire</strong>. L’ouvrir rend ses critères et ses '
          + 'taux modifiables depuis l’écran « Évaluations ».<br><br>'
          + 'Chaque modification demandera sa <strong>portée</strong> — évaluations à venir seulement, ou '
          + 'évaluations déjà prononcées comprises. <strong>Refermer la porte après usage</strong> évite '
          + 'qu’elle reste ouverte des mois durant.',
        confirmLabel: 'Autoriser la modification', danger: true, requireMotif: true,
      }).then(function (rep) {
        if (!rep) return;
        global.SIGH.setBaremeModifiable(true);
        S.log('Ouverture de la modification du barème', 'M10', 'Barème', D.NS131.reference,
          null, { motif: rep.motif });
        dessiner();
        U.toast('Modification du barème autorisée.', {
          type: 'warning', duration: 8000,
          detail: 'Le CRUD est ouvert à l’écran « Évaluations ». Penser à refermer après usage.',
        });
      });
    }
  }

  function ongletInstallation(panel) {
      var host = el('div.space-y-4');
      var db = S.raw();
      var collections = Object.keys(db).filter(function (k) { return k[0] !== '_' && Array.isArray(db[k]); });
      var total = collections.reduce(function (s, k) { return s + db[k].length; }, 0);

      host.appendChild(U.kpiGrid([
        { label: 'Collections de données', value: C.num(collections.length), icon: 'database', tone: 'navy' },
        { label: 'Enregistrements', value: C.num(total), icon: 'layers', tone: 'info' },
        { label: 'Persistance', value: S.storage.disponible ? 'Navigateur' : 'Mémoire', icon: 'hard-drive', tone: S.storage.disponible ? 'success' : 'warning', hint: S.storage.disponible ? 'Stockage local actif' : 'Stockage local indisponible' },
        { label: 'Version du prototype', value: 'v1.0', icon: 'tag', tone: 'neutral' },
      ]));

      if (!S.storage.disponible) {
        host.appendChild(K.note('Le stockage local du navigateur est indisponible — le prototype fonctionne <strong>en mémoire</strong>. '
          + 'Les modifications restent pleinement opérationnelles mais ne survivent pas au rechargement de la page. '
          + 'Servir le dossier via un petit serveur local rétablit la persistance.', { tone: 'warning', icon: 'hard-drive' }));
      }

      /* ARCHITECTURE CIBLE — PROPOSITION, ET L'ÉCRAN LE DIT.
       * La cible desktop en réseau local a été abandonnée au profit d'une
       * application web hébergée. Tant que la Direction n'a pas arrêté la
       * pile par écrit, cette fiche est une PROPOSITION : l'afficher comme
       * un fait engagerait un choix que personne n'a signé. */
      host.appendChild(U.card('Architecture cible — proposition', U.descList([
        ['Application', 'Web — Laravel 12 (PHP 8.3) avec Vue 3 via Inertia'],
        ['Postes de travail', 'Navigateur ; application installable (PWA) sur chaque poste'],
        ['Base de données', 'PostgreSQL, hébergée avec l’application'],
        ['Hébergement', 'Serveur mutualisé cPanel — déploiement Git, SSL automatique'],
        ['Poste caisse', 'Enveloppe Tauri si l’imprimante ticket ou la MECeF l’exigent'],
        ['Reporting', 'Gabarits d’impression du navigateur ; PDF archivés côté serveur'],
        ['Sauvegarde', 'Export chiffré planifié HORS de l’hébergeur — jamais un seul dépositaire'],
        ['Continuité électrique', 'Onduleurs aux postes critiques, box sur onduleur, secours 4G, mode dégradé papier'],
        ['Ce prototype', 'HTML, CSS et JavaScript — sans dépendance réseau'],
      ], 'grid-cols-1 sm:grid-cols-2')));

      host.appendChild(K.note('Cette architecture est une <strong>proposition technique</strong>, pas une décision : '
        + 'elle attend l’arbitrage écrit de la Direction. Deux conséquences y sont attachées et doivent être '
        + 'assumées avec elle — l’exploitation dépend désormais de la connexion Internet de la clinique et de la '
        + 'disponibilité de l’hébergeur, d’où les onduleurs, la liaison de secours et le mode dégradé papier ; '
        + 'et les sauvegardes doivent sortir de chez l’hébergeur, des données de santé ne pouvant reposer sur un '
        + 'seul prestataire.', { tone: 'warning', icon: 'flag' }));

      host.appendChild(U.card('Contenu du jeu de données', U.dataTable({
        rows: collections.map(function (k) {
          return {
            id: k, collection: k, nb: db[k].length,
            actifs: db[k].filter(function (r) { return r && r.statut !== 'archive'; }).length,
            archives: db[k].filter(function (r) { return r && r.statut === 'archive'; }).length,
          };
        }),
        exportName: 'collections', pageSize: 30, searchable: true,
        defaultSort: 'nb', defaultDir: 'desc',
        columns: [
          { key: 'collection', label: 'Collection', render: function (r) { return el('span.font-mono.text-xs', { text: r.collection }); } },
          { key: 'nb', label: 'Enregistrements', align: 'right' },
          { key: 'actifs', label: 'Actifs', align: 'right' },
          {
            key: 'archives', label: 'Archivés', align: 'right',
            render: function (r) { return r.archives ? el('span.text-warning-600', { text: String(r.archives) }) : '—'; },
          },
        ],
      })));

      host.appendChild(U.card('Maintenance du prototype', el('div.flex.flex-wrap.gap-2', null, [
        K.btn('Réinitialiser le jeu de données', {
          variant: 'danger', icon: 'rotate-ccw',
          onclick: function () {
            U.confirm({
              title: 'Réinitialiser toutes les données de démonstration ?',
              message: 'Toutes les créations, modifications et archivages réalisés dans le prototype seront perdus '
                + 'et le jeu de démonstration initial sera rétabli. Cette action est irréversible.',
              confirmLabel: 'Réinitialiser', danger: true,
            }).then(function (ok) {
              if (!ok) return;
              S.reset();
              U.toast('Jeu de données réinitialisé.', { type: 'success' });
              setTimeout(function () { global.location.reload(); }, 900);
            });
          },
        }),
        K.btn('Exporter les données', {
          icon: 'download',
          onclick: function () {
            try {
              var blob = new Blob([JSON.stringify(S.raw(), null, 2)], { type: 'application/json' });
              var url = URL.createObjectURL(blob);
              var a = el('a', { href: url, download: 'sigh-cnt-donnees-' + C.iso(AUJ) + '.json' });
              document.body.appendChild(a); a.click(); a.remove();
              setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
              U.toast('Export JSON généré.', { type: 'success' });
            } catch (e) {
              U.toast('Export impossible : ' + e.message, { type: 'error' });
            }
          },
        }),
        K.lien('plan-du-site', 'Plan du site', { icon: 'map' }),
        K.lien('m14-sauvegardes', 'Sauvegardes', { icon: 'database-backup' }),
      ])));

      host.appendChild(K.note('Ce prototype fonctionne intégralement <strong>hors ligne</strong> : la feuille de style, les polices, '
        + 'la bibliothèque de graphiques et les icônes sont hébergées dans le dossier du projet. Aucune requête réseau n’est émise.', { tone: 'success', icon: 'wifi-off' }));

      panel.appendChild(host);
      return null;
  }


  /* --- Onglet « Jeux de test » ---------------------------------------------
   * Vider les données de démonstration est utile en recette, désastreux en
   * production. D'où la bascule : tant qu'elle est fermée, la réinitialisation
   * n'est pas seulement refusée, elle est indisponible — un bouton grisé se
   * clique quand même, un bouton absent ne s'atteint pas.
   *
   * Ce qui est préservé dans tous les cas : les PARAMÈTRES et les RÉFÉRENTIELS
   * administrés par la clinique (tarifs, secteurs, conventions, certificats,
   * comptes). Seules les données d'activité engendrées pour la démonstration
   * sont effacées.
   * --------------------------------------------------------------------- */
  var CLE_REINIT = 'sigh-cnt:reinit-autorisee';

  /* Collections de PARAMÉTRAGE — jamais touchées par une réinitialisation. */
  var COLLECTIONS_PARAMETRAGE = [
    'actes', 'analyses', 'produits', 'assureurs', 'fournisseurs', 'comptes',
    'naturesFacture', 'centresCouts', 'secteurs', 'postes', 'personnel',
    'utilisateurs', 'ressources', 'banques', 'souscripteurs', 'garanties',
    /* Les objectifs du pilotage sont un PARAMÉTRAGE de la Direction, pas des
       données d'exploitation : une réinitialisation du jeu de test ne doit
       pas effacer des cibles qu'elle a arrêtées. */
    'certificats', 'objectifsPilotage',
  ];

  function ongletReinitialisation(panneau) {
    dessiner();
    return null;

    function autorisee() { return S.storage.get(CLE_REINIT) === 'oui'; }

    function dessiner() {
      C.clear(panneau);
      var db = S.raw();
      var toutes = Object.keys(db).filter(function (k) { return k.charAt(0) !== '_' && Array.isArray(db[k]); });
      var activite = toutes.filter(function (k) { return COLLECTIONS_PARAMETRAGE.indexOf(k) < 0; });
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        {
          label: 'Réinitialisation', value: autorisee() ? 'Autorisée' : 'Verrouillée',
          icon: autorisee() ? 'unlock' : 'lock',
          tone: autorisee() ? 'danger' : 'success',
          hint: autorisee() ? 'Le poste accepte l’effacement des jeux de test' : 'Aucun effacement possible',
        },
        {
          label: 'Tables d’activité', value: C.num(activite.length), icon: 'database', tone: 'info',
          hint: C.num(activite.reduce(function (n, k) { return n + db[k].length; }, 0)) + ' enregistrements',
        },
        {
          label: 'Tables de paramétrage préservées', value: C.num(toutes.length - activite.length),
          icon: 'shield-check', tone: 'success', hint: 'Tarifs, secteurs, conventions, comptes',
        },
      ], 'grid-cols-1 sm:grid-cols-3'));

      /* La bascule */
      var bascule = el('input.checkbox', { type: 'checkbox', id: 'f_reinit', checked: autorisee() });
      bascule.addEventListener('change', function () {
        if (bascule.checked) {
          U.confirm({
            title: 'Autoriser la réinitialisation des jeux de test ?',
            message: 'Une fois autorisée, la réinitialisation devient possible depuis ce poste. '
              + 'Sur un poste en production, la laisser fermée est la seule position raisonnable : '
              + 'elle protège les données réelles de l’établissement.',
            confirmLabel: 'Autoriser', danger: true,
          }).then(function (ok) {
            if (!ok) { bascule.checked = false; return; }
            S.storage.set(CLE_REINIT, 'oui');
            S.log('Déverrouillage', 'CFG', 'Réinitialisation', 'jeux de test', { etat: 'verrouillée' }, { etat: 'autorisée' });
            dessiner();
          });
        } else {
          S.storage.remove(CLE_REINIT);
          S.log('Verrouillage', 'CFG', 'Réinitialisation', 'jeux de test', { etat: 'autorisée' }, { etat: 'verrouillée' });
          dessiner();
        }
      });

      host.appendChild(U.card('Autorisation', el('div.space-y-3', null, [
        el('label.flex.cursor-pointer.items-start.gap-3', { for: 'f_reinit' }, [
          bascule,
          el('div', null, [
            el('p.text-sm.font-medium.text-slate-800', { text: 'Autoriser la réinitialisation des jeux de test sur ce poste' }),
            el('p.mt-0\\.5.text-xs.text-slate-500', {
              text: 'À laisser fermé sur un poste en service. Le déverrouillage et le verrouillage sont journalisés.',
            }),
          ]),
        ]),
      ])));

      host.appendChild(U.card('Ce qui serait effacé, ce qui serait conservé', el('div.grid.gap-3.sm\\:grid-cols-2', null, [
        el('div.rounded-lg.border.border-danger-200.bg-danger-50.p-3', null, [
          el('p.mb-2.text-xs.font-semibold.uppercase.tracking-wide.text-danger-700', { text: 'Effacé — données d’activité' }),
          el('div.flex.flex-wrap.gap-1', null, activite.slice(0, 24).map(function (k) {
            return el('span.rounded.bg-white.px-1\\.5.py-0\\.5.text-\\[10px\\].text-danger-700', {
              text: k + ' (' + db[k].length + ')',
            });
          })),
        ]),
        el('div.rounded-lg.border.border-success-200.bg-success-50.p-3', null, [
          el('p.mb-2.text-xs.font-semibold.uppercase.tracking-wide.text-success-700', { text: 'Conservé — paramétrage et référentiels' }),
          el('div.flex.flex-wrap.gap-1', null, COLLECTIONS_PARAMETRAGE.filter(function (k) { return db[k]; }).map(function (k) {
            return el('span.rounded.bg-white.px-1\\.5.py-0\\.5.text-\\[10px\\].text-success-700', {
              text: k + ' (' + db[k].length + ')',
            });
          })),
        ]),
      ])));

      host.appendChild(K.note('L’administrateur, les réglages et les référentiels administrés par la clinique '
        + '<strong>ne sont jamais effacés</strong>. La réinitialisation ne retire que les données engendrées '
        + 'pour la démonstration — patients, consultations, factures, mouvements.', { tone: 'info' }));

      if (autorisee()) {
        host.appendChild(U.card('Réinitialisation', el('div.flex.flex-wrap.gap-2', null, [
          K.btn('Vider les jeux de test', {
            variant: 'danger', icon: 'trash-2',
            onclick: function () { vider(activite); },
          }),
          K.btn('Régénérer le jeu de démonstration complet', {
            icon: 'rotate-ccw',
            onclick: function () {
              U.confirm({
                title: 'Régénérer entièrement le jeu de démonstration ?',
                message: 'Toute la base est remplacée par le jeu initial, paramétrage compris. '
                  + 'À n’utiliser que sur un poste de démonstration.',
                confirmLabel: 'Régénérer', danger: true, requireMotif: true,
              }).then(function (ok) {
                if (!ok) return;
                S.reset();
                U.toast('Jeu de démonstration régénéré.', { type: 'success' });
                setTimeout(function () { global.location.reload(); }, 900);
              });
            },
          }),
        ])));
      } else {
        host.appendChild(U.card('Réinitialisation',
          U.empty('Réinitialisation verrouillée — activer l’autorisation ci-dessus pour la rendre possible.',
            { icon: 'lock' })));
      }

      panneau.appendChild(host);
      U.icons(panneau);
    }

    function vider(activite) {
      U.confirm({
        title: 'Vider les jeux de test ?',
        message: 'Les ' + activite.length + ' tables d’activité seront vidées : patients, consultations, '
          + 'factures, mouvements, ordonnances. Les paramètres, les référentiels et le compte administrateur '
          + 'sont conservés. L’opération est journalisée et irréversible — générer une sauvegarde d’abord.',
        confirmLabel: 'Vider les jeux de test', danger: true, requireMotif: true,
      }).then(function (r) {
        if (!r) return;
        var db = S.raw();
        var vidées = 0, lignes = 0;
        activite.forEach(function (k) {
          lignes += db[k].length;
          db[k] = [];
          vidées++;
        });
        S.save();
        S.log('Réinitialisation des jeux de test', 'CFG', 'Base', C.iso(AUJ), null,
          { tables: vidées, enregistrements: lignes, motif: r.motif });
        U.toast(vidées + ' table(s) vidée(s) — ' + C.num(lignes) + ' enregistrements retirés.', {
          type: 'success', detail: 'Paramétrage et référentiels conservés.',
        });
        setTimeout(function () { global.location.reload(); }, 1400);
      });
    }
  }

  /* --- Onglet « Corbeille » ------------------------------------------------
   * Le pendant de RG-14 : puisque rien n'est supprimé, il faut un endroit d'où
   * tout se retrouve. La vue balaie les collections du magasin ; l'utilisateur
   * n'a pas à savoir de quel écran venait la fiche pour la remettre en service.
   * --------------------------------------------------------------------- */
  function ongletCorbeille(panel) {
    dessiner();
    return null;

    function dessiner() {
      C.clear(panel);
      var rows = S.corbeille();
      var host = el('div.space-y-4');

      var modules = {};
      rows.forEach(function (r) { modules[r.module] = true; });

      host.appendChild(U.kpiGrid([
        { label: 'Fiches archivées', value: C.num(rows.length), icon: 'trash-2', tone: rows.length ? 'warning' : 'success' },
        { label: 'Modules concernés', value: C.num(Object.keys(modules).length), icon: 'layers', tone: 'info' },
        { label: 'Suppression définitive', value: 'Impossible', icon: 'shield-check', tone: 'success', hint: 'RG-14 — archivage logique' },
      ]));

      host.appendChild(K.note('<strong>RG-14</strong> — aucune donnée n’est jamais supprimée physiquement. '
        + 'Archiver retire la fiche des listes de travail ; la restaurer la remet exactement où elle était, '
        + 'et l’opération est journalisée dans les deux sens.', { tone: 'info' }));

      if (!rows.length) {
        host.appendChild(U.card('Corbeille', U.empty('La corbeille est vide — aucune fiche archivée.', { icon: 'trash-2' })));
        panel.appendChild(host);
        U.icons(panel);
        return;
      }

      host.appendChild(U.card('Fiches archivées', U.dataTable({
        rows: rows, exportName: 'corbeille', pageSize: 15, searchable: true,
        defaultSort: 'archiveLe', defaultDir: 'desc',
        filters: [{
          name: 'module', label: 'Module',
          options: Object.keys(modules).sort().map(function (m) { return { value: m, label: m }; }),
        }],
        columns: [
          { key: 'module', label: 'Module', nowrap: true, render: function (r) { return U.badge(r.module, 'neutral'); } },
          { key: 'entite', label: 'Type de fiche' },
          {
            key: 'libelle', label: 'Élément',
            render: function (r) {
              return el('div.min-w-0', null, [
                el('p.truncate.text-sm.font-medium.text-slate-800', { text: r.libelle }),
                el('p.font-mono.text-xs.text-slate-400', { text: r.refId }),
              ]);
            },
          },
          {
            key: 'archiveLe', label: 'Archivée le', nowrap: true,
            text: function (r) { return r.archiveLe ? C.dateFR(r.archiveLe) : '—'; },
            render: function (r) { return r.archiveLe ? C.dateFR(r.archiveLe) : '—'; },
            sortValue: function (r) { return String(r.archiveLe || ''); },
          },
          { key: 'archivePar', label: 'Par', nowrap: true },
          {
            key: 'motif', label: 'Motif',
            render: function (r) { return r.motif || el('span.text-slate-300', { text: '—' }); },
          },
        ],
        rowActions: function (r) {
          return [K.iconBtn('undo-2', 'Restaurer', function () { restaurer(r); })];
        },
      })));

      panel.appendChild(host);
      U.icons(panel);
    }

    function restaurer(r) {
      U.confirm({
        title: 'Restaurer « ' + r.libelle + ' » ?',
        message: 'La fiche réapparaîtra dans ' + r.entite + ' (' + r.module + ') et redeviendra modifiable. '
          + 'La restauration est journalisée (RG-12).',
        confirmLabel: 'Restaurer',
      }).then(function (ok) {
        if (!ok) return;
        S.collection(r.collection).restore(r.refId);
        U.toast('Fiche restaurée dans ' + r.entite + '.', { type: 'success' });
        dessiner();
      });
    }
  }
  /* ==========================================================================
   * CERTIFICATS MÉDICAUX
   * --------------------------------------------------------------------------
   * « Au lieu d'écrire ça à part, à partir du logiciel on peut déjà générer le
   * certificat médical » — la Direction en a énuméré les types en réunion.
   *
   * Un certificat est un acte engageant : il porte l'en-tête officielle, le nom
   * du praticien signataire, un numéro unique et reste archivé au dossier du
   * patient. Le modèle fournit la trame ; le praticien complète et signe.
   * ======================================================================== */
  var TYPES_CERTIFICAT = [
    {
      id: 'repos', libelle: 'Certificat médical de repos',
      champs: ['duree', 'dateDebut'],
      trame: 'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient}, '
        + 'et atteste que son état de santé nécessite un repos de {duree} jour(s) '
        + 'à compter du {dateDebut}.',
    },
    {
      id: 'grossesse', libelle: 'Certificat médical de grossesse',
      champs: ['termeSemaines', 'datePresumee'],
      trame: 'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient}, '
        + 'et atteste qu’elle présente une grossesse évolutive de {termeSemaines} semaines '
        + 'd’aménorrhée, dont le terme est présumé au {datePresumee}.',
    },
    {
      id: 'accouchement', libelle: 'Attestation d’accouchement',
      champs: ['dateAccouchement', 'sexeEnfant'],
      trame: 'Je soussigné(e), {praticien}, atteste que {patient} a accouché dans notre '
        + 'établissement le {dateAccouchement} d’un enfant de sexe {sexeEnfant}.',
    },
    {
      id: 'coups', libelle: 'Certificat médical de coups et blessures involontaires',
      champs: ['constatations', 'itt'],
      trame: 'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient} '
        + 'et avoir constaté : {constatations}. Ces lésions entraînent une incapacité '
        + 'totale de travail de {itt} jour(s), sauf complications.',
    },
    {
      id: 'initial', libelle: 'Certificat médical initial',
      champs: ['constatations', 'itt'],
      trame: 'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient} '
        + 'et avoir constaté : {constatations}. Incapacité totale de travail estimée '
        + 'à {itt} jour(s), sous réserve de complications ultérieures.',
    },
    {
      id: 'guerison', libelle: 'Certificat médical de guérison',
      champs: ['affection', 'dateGuerison'],
      trame: 'Je soussigné(e), {praticien}, certifie que {patient}, traité(e) pour '
        + '{affection}, est déclaré(e) guéri(e) depuis le {dateGuerison} et peut '
        + 'reprendre ses activités.',
    },
    {
      id: 'prenuptial', libelle: 'Certificat prénuptial',
      champs: ['examens'],
      trame: 'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient} '
        + 'dans le cadre d’un examen prénuptial. Examens pratiqués : {examens}. '
        + 'Aucune contre-indication médicale au mariage n’a été relevée.',
    },
    {
      id: 'aptitude', libelle: 'Certificat d’aptitude physique',
      champs: ['activite'],
      trame: 'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient} '
        + 'et n’avoir constaté aucune contre-indication à la pratique de : {activite}.',
    },
  ];

  var CHAMPS_CERTIFICAT = {
    duree: { label: 'Durée du repos (jours)', type: 'number', min: 1 },
    dateDebut: { label: 'À compter du', type: 'date' },
    termeSemaines: { label: 'Terme (semaines d’aménorrhée)', type: 'number', min: 1, max: 45 },
    datePresumee: { label: 'Terme présumé', type: 'date' },
    dateAccouchement: { label: 'Date d’accouchement', type: 'date' },
    sexeEnfant: { label: 'Sexe de l’enfant', type: 'select', options: ['masculin', 'féminin'] },
    constatations: { label: 'Constatations médicales', type: 'textarea', rows: 3, col: 'full' },
    itt: { label: 'Incapacité totale de travail (jours)', type: 'number', min: 0 },
    affection: { label: 'Affection traitée', col: 'full' },
    dateGuerison: { label: 'Date de guérison', type: 'date' },
    examens: { label: 'Examens pratiqués', type: 'textarea', rows: 2, col: 'full' },
    activite: { label: 'Activité concernée', col: 'full' },
  };

  function colCertificats() { return S.collection('certificats', { module: 'CFG', entite: 'certificat', prefix: 'CERT' }); }

  function typeCertificat(id) {
    return TYPES_CERTIFICAT.filter(function (t) { return t.id === id; })[0] || null;
  }

  /** Remplace les {jetons} de la trame par les valeurs saisies. */
  function composer(trame, valeurs) {
    return String(trame).replace(/\{(\w+)\}/g, function (m, cle) {
      var v = valeurs[cle];
      if (v == null || v === '') return '……………';
      if (/^\d{4}-\d{2}-\d{2}$/.test(String(v))) return C.dateFR(v);
      return String(v);
    });
  }

  global.SIGH.screen('cfg-certificats', {
    title: 'Certificats médicaux',
    description: 'Génération, numérotation et archivage des certificats délivrés par la clinique.',
    regle: 'Un certificat est un <strong>acte engageant</strong> : il porte l’en-tête officielle, le nom du '
      + 'praticien signataire, un numéro unique et reste archivé au dossier du patient. '
      + 'Le modèle fournit la trame — le praticien la complète et la signe. '
      + '<strong>RG-14</strong> — un certificat délivré s’annule par archivage motivé, il ne s’efface pas.',
    render: function (root) {
      dessiner();
      return null;

      function dessiner() {
        C.clear(root);
        var rows = colCertificats().active();
        var host = el('div.space-y-4');

        host.appendChild(U.kpiGrid([
          { label: 'Certificats délivrés', value: C.num(rows.length), icon: 'file-badge', tone: 'navy' },
          { label: 'Types au catalogue', value: C.num(TYPES_CERTIFICAT.length), icon: 'list', tone: 'info' },
          {
            label: 'Délivrés ce mois',
            value: C.num(rows.filter(function (r) { return C.toDate(r.date).getMonth() === AUJ.getMonth(); }).length),
            icon: 'calendar-check', tone: 'success',
          },
          { label: 'Praticiens signataires', value: C.num(Object.keys(C.groupBy(rows, 'praticien')).length), icon: 'stethoscope', tone: 'neutral' },
        ]));

        /* Le catalogue : un clic sur un type ouvre sa rédaction. */
        var grille = el('div.grid.gap-3.sm\\:grid-cols-2.lg\\:grid-cols-4');
        TYPES_CERTIFICAT.forEach(function (t) {
          var n = rows.filter(function (r) { return r.type === t.id; }).length;
          var carte = el('button.rounded-xl.border.border-slate-200.bg-white.p-4.text-left.shadow-card.transition-colors.hover\\:border-navy-300.hover\\:bg-navy-50', {
            type: 'button', onclick: function () { rediger(t); },
          });
          carte.appendChild(el('span.mb-2.grid.h-9.w-9.place-items-center.rounded-lg.bg-navy-50.text-navy-700', null, C.icon('file-badge', 'h-4 w-4')));
          carte.appendChild(el('p.text-sm.font-semibold.text-slate-800', { text: t.libelle }));
          carte.appendChild(el('p.mt-1.text-xs.text-slate-400', { text: n ? C.num(n) + ' délivré(s)' : 'Aucun délivré' }));
          grille.appendChild(carte);
        });
        host.appendChild(U.card('Types de certificats — cliquer pour rédiger', grille));

        host.appendChild(U.dataTable({
          title: 'Registre des certificats délivrés',
          rows: rows, exportName: 'certificats', pageSize: 15, searchable: true,
          defaultSort: 'date', defaultDir: 'desc',
          emptyMessage: 'Aucun certificat délivré.',
          filters: [{ name: 'type', label: 'Type', options: TYPES_CERTIFICAT.map(function (t) { return { value: t.id, label: t.libelle }; }) }],
          columns: [
            { key: 'numero', label: 'N°', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.numero }); } },
            { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
            {
              key: 'patient', label: 'Patient',
              render: function (r) {
                return el('div.min-w-0', null, [
                  el('p.truncate.text-sm.text-slate-800', { text: r.patient }),
                  el('p.font-mono.text-xs.text-slate-400', { text: r.patientCode }),
                ]);
              },
            },
            {
              key: 'type', label: 'Type',
              text: function (r) { var t = typeCertificat(r.type); return t ? t.libelle : r.type; },
              render: function (r) { var t = typeCertificat(r.type); return U.badge(t ? t.libelle : r.type, 'navy'); },
            },
            { key: 'praticien', label: 'Praticien signataire' },
          ],
          rowActions: function (r) {
            return [
              K.iconBtn('printer', 'Rééditer', function () { imprimer(r); }),
              K.iconBtn('archive', 'Annuler le certificat', function () { annuler(r); }),
            ];
          },
        }));

        root.appendChild(host);
        U.icons(root);
      }

      function rediger(t) {
        var champs = [
          {
            name: 'patientCode', label: 'Patient', type: 'select', required: true, col: 'full',
            options: C.sortBy(S.collection('patients').active(), 'code').map(function (p) {
              return { value: p.code, label: p.code + ' — ' + p.nom + ' ' + p.prenom };
            }),
          },
          {
            name: 'praticien', label: 'Praticien signataire', type: 'select', required: true,
            options: S.collection('personnel').active()
              .filter(function (e) { return e.fonction === 'medecin' || e.fonction === 'sage_femme'; })
              .map(function (e) { return { value: e.nomComplet, label: e.nomComplet }; }),
          },
          { name: 'date', label: 'Date de délivrance', type: 'date', required: true, value: C.iso(AUJ) },
        ].concat(t.champs.map(function (c) {
          return Object.assign({ name: c, required: true }, CHAMPS_CERTIFICAT[c]);
        }));

        var f = U.form(champs, {});
        var apercu = el('div.rounded-lg.border.border-slate-200.bg-slate-50.p-3.text-sm.leading-relaxed.text-slate-700');

        function majApercu() {
          var v = {};
          Object.keys(f.controls).forEach(function (k) { v[k] = f.controls[k].value; });
          var p = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
          v.patient = p ? p.nom + ' ' + p.prenom : '……………';
          apercu.textContent = composer(t.trame, v);
        }
        f.addEventListener('input', majApercu);
        f.addEventListener('change', majApercu);
        majApercu();

        var m = U.modal({
          title: t.libelle, subtitle: 'Le texte se compose au fil de la saisie', size: 'lg',
          body: el('div.space-y-3', null, [
            f,
            el('div', null, [
              el('p.mb-1.text-xs.font-semibold.uppercase.tracking-wide.text-slate-500', { text: 'Aperçu du texte' }),
              apercu,
            ]),
            K.note('Le certificat sera numéroté, archivé au dossier du patient et journalisé (RG-12). '
              + 'Il porte l’en-tête officielle et la signature du praticien.', { tone: 'info' }),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Délivrer le certificat', {
              variant: 'primary', icon: 'file-badge',
              onclick: function () {
                var v = f.collect();
                if (!v) return;
                var p = S.collection('patients').active().filter(function (x) { return x.code === v.patientCode; })[0];
                v.type = t.id;
                v.numero = 'CERT-2026-' + C.pad(colCertificats().all().length + 1, 4);
                v.patientId = p ? p.id : null;
                v.patient = p ? p.nom + ' ' + p.prenom : '—';
                v.texte = composer(t.trame, Object.assign({}, v, { patient: v.patient }));
                var res = colCertificats().insert(v);
                S.log('Délivrance de certificat', 'CFG', t.libelle, v.numero, null, { patient: v.patient });
                m.close(); dessiner();
                U.toast('Certificat ' + v.numero + ' délivré.', {
                  type: 'success', detail: t.libelle + ' — ' + v.patient,
                  undo: function () { res.undo(); dessiner(); },
                });
                imprimer(res.record);
              },
            }),
          ],
        });
      }

      function annuler(r) {
        U.confirm({
          title: 'Annuler le certificat ' + r.numero + ' ?',
          message: 'Le certificat est archivé, non supprimé (RG-14) : il reste au registre et restaurable. '
            + 'Un certificat déjà remis au patient garde sa valeur — l’annulation doit être motivée.',
          confirmLabel: 'Annuler le certificat', danger: true, requireMotif: true,
        }).then(function (ok) {
          if (!ok) return;
          var res = colCertificats().archive(r.id, ok.motif);
          dessiner();
          U.toast('Certificat annulé.', { type: 'success', undo: function () { res.undo(); dessiner(); } });
        });
      }

      function imprimer(r) {
        var t = typeCertificat(r.type);
        var p = S.collection('patients').get(r.patientId);
        P.etat({
          titre: t ? t.libelle.toUpperCase() : 'CERTIFICAT MÉDICAL',
          sousTitre: r.numero,
          cartouche: [['Patient', r.patient], ['Dossier', r.patientCode],
            ['Âge', C.ageTexte(p)],
            ['Date de délivrance', C.dateFR(r.date)],
            ['Praticien', r.praticien], ['N° du certificat', r.numero]],
          contenu: el('div.space-y-4', null, [
            el('p.mt-4.text-\\[11px\\].leading-loose.text-slate-800', { text: r.texte || composer(t ? t.trame : '', r) }),
            el('p.mt-6.text-\\[10px\\].italic.text-slate-500', {
              text: 'Certificat établi à la demande de l’intéressé(e) et remis en main propre pour servir '
                + 'et valoir ce que de droit.',
            }),
          ]),
          signatures: [{ role: 'Le praticien', nom: r.praticien, mention: 'Signature et cachet' }],
        });
      }
    },
  });

  /* ==========================================================================
   * PARAMÈTRES COMPTABLES & OBLIGATIONS
   * --------------------------------------------------------------------------
   * Documentation de référence des obligations fiscales et sociales de la
   * clinique, telle que le comptable les a précisées en réunion. Cet écran ne
   * calcule rien : il dit ce qui est dû, quand, sur quelle base et après quelle
   * déclaration. Le suivi des paiements se tient à l'écran « Échéances
   * fiscales & paiements » du module M12.
   *
   * L'écrire ici plutôt que dans un document extérieur a une raison : une règle
   * fiscale qui vit dans un fichier séparé cesse d'être lue.
   * ======================================================================== */
  global.SIGH.screen('cfg-comptabilite', {
    title: 'Paramètres comptables & obligations',
    description: 'Obligations fiscales et sociales de la clinique : périodicités, tranches, déclarations préalables et redevances.',
    regle: 'Cet écran est la <strong>référence documentaire</strong> des obligations. Il ne calcule ni ne paie — '
      + 'le suivi des paiements et leur validation se tiennent à l’écran <strong>Échéances fiscales & paiements</strong>. '
      + 'Toute échéance tombant un week-end est reportée au <strong>jour ouvrable suivant</strong>.',
    render: function (root) {
      var host = el('div.space-y-4');
      var cal = D.CALENDRIER_FISCAL;
      var mensuelles = cal.filter(function (e) { return e.periodicite === 'mensuelle'; });
      var annuelles = cal.filter(function (e) { return e.periodicite === 'annuelle'; });

      host.appendChild(U.kpiGrid([
        { label: 'Obligations suivies', value: C.num(cal.length), icon: 'book-open-check', tone: 'navy' },
        { label: 'Mensuelles', value: C.num(mensuelles.length), icon: 'calendar-days', tone: 'info', hint: 'ITS, AIB, VPS, CNSS' },
        { label: 'Annuelles', value: C.num(annuelles.length), icon: 'calendar-range', tone: 'neutral', hint: 'IS, patente, CCIB, TVM, ORTB' },
        { label: 'Réglées en tranches', value: C.num(cal.filter(function (e) { return e.part && e.part < 100; }).length), icon: 'divide', tone: 'warning' },
      ]));

      /* --- Obligations mensuelles --------------------------------------- */
      host.appendChild(U.card('Obligations mensuelles — le 10 du mois suivant', el('div.space-y-3', null, [
        K.note('<strong>ITS, AIB, VPS et CNSS se paient le 10 de chaque mois</strong>, pour le mois d’exercice '
          + 'précédent. Une <strong>déclaration précède le paiement</strong>. Si le 10 tombe un samedi ou un '
          + 'dimanche, le jour ouvrable qui suit immédiatement fait foi.', { tone: 'info' }),
        K.miniTable([
          { label: 'Code', render: function (e) { return el('span.font-mono.text-xs.font-semibold', { text: e.code }); } },
          { label: 'Obligation', key: 'libelle' },
          { label: 'Échéance', render: function () { return 'le 10 du mois suivant'; } },
          { label: 'Déclaration préalable', render: function (e) { return e.declaration || '—'; } },
        ], mensuelles),
        el('div.rounded-lg.border.border-slate-200.bg-slate-50.p-3', null, [
          el('p.text-xs.font-semibold.uppercase.tracking-wide.text-slate-500', { text: 'Assiettes' }),
          el('p.mt-1.text-sm.text-slate-700', {
            text: 'CNSS — part patronale ' + D.PARAM_PAIE.cnss.patronale + ' %, part ouvrière '
              + D.PARAM_PAIE.cnss.ouvriere + ' %. VPS — ' + D.PARAM_PAIE.vps.taux + ' % du salaire brut. '
              + 'ITS — barème progressif par tranches. AIB — acompte assis sur les bénéfices.',
          }),
        ]),
      ])));

      /* --- Impôt sur les sociétés --------------------------------------- */
      var acomptes = cal.filter(function (e) { return /^IS-\d$/.test(e.code); });
      host.appendChild(U.card('Impôt sur les sociétés — quatre acomptes et une liquidation', el('div.space-y-3', null, [
        K.note('L’impôt se paie <strong>par anticipation</strong> : l’impôt de l’exercice précédent est divisé '
          + 'en quatre acomptes égaux, versés au cours de l’exercice courant. Exemple donné par le comptable — '
          + 'un impôt de 2 000 000 FCFA en 2025 donne quatre acomptes de 500 000 FCFA en 2026.',
        { tone: 'info', icon: 'landmark' }),
        K.miniTable([
          { label: 'Acompte', key: 'libelle' },
          { label: 'Échéance', render: function (e) { return 'le ' + e.jour + ' ' + C.MOIS[e.mois]; } },
          { label: 'Part', render: function (e) { return e.part + ' % de l’impôt de l’exercice précédent'; } },
        ], acomptes),
        el('div.rounded-lg.border.border-navy-200.bg-navy-50.p-3', null, [
          el('p.text-xs.font-semibold.uppercase.tracking-wide.text-navy-700', { text: 'Le 30 avril de l’année suivante' }),
          el('p.mt-1.text-sm.text-slate-700', {
            text: 'Deux opérations, dans cet ordre : la liquidation du solde ajuste ce qui a été versé en acomptes — '
              + 'la clinique complète si l’impôt réel dépasse les acomptes, l’État rembourse dans le cas inverse — '
              + 'puis intervient le dépôt des états financiers de l’exercice clos.',
          }),
        ]),
      ])));

      /* --- Obligations annuelles en tranches ---------------------------- */
      host.appendChild(U.card('Patente, CCIB et TVM — une fois par an', el('div.space-y-3', null, [
        el('div.grid.gap-3.md\\:grid-cols-3', null, [
          bloc('Patente', 'Une fois par an, avec possibilité de régler en deux tranches.', [
            ['31 janvier', 'Date limite de la déclaration prévisionnelle'],
            ['10 février', '1er acompte — 50 %'],
            ['30 avril', 'Solde — 50 %'],
          ]),
          bloc('CCIB', C.money(D.MONTANTS_FISCAUX.ccib.total) + ' par an, en deux tranches égales de '
            + C.money(D.MONTANTS_FISCAUX.ccib.total / 2) + '.', [
            ['Fin de mois', 'Déclaration prévisionnelle, avant le 1er acompte'],
            ['10 mars', '1re tranche — 50 %'],
            ['10 juin', '2e tranche — 50 %'],
          ]),
          bloc('TVM', 'Taxe sur véhicules à moteur. Une fois par an, en une seule fois.', [
            ['30 avril', 'Paiement, au plus tard'],
          ]),
        ]),
      ])));

      /* --- Redevances ORTB ---------------------------------------------- */
      var ortb = D.PARAM_PAIE.ortb;
      host.appendChild(U.card('Redevances ORTB — prélevées sur les salaires', el('div.space-y-3', null, [
        K.note('<strong>Deux redevances distinctes, qui se cumulent</strong> — et non deux tranches '
          + 'exclusives d’un même barème. La <strong>radio est due par tous les salariés sans exception</strong> ; '
          + 'la <strong>télé s’y ajoute</strong> au-delà de ' + C.money(ortb.seuilTele, false) + ' de salaire brut. '
          + 'Un agent au-dessus du seuil acquitte donc ' + C.money(ortb.cumulMaximum, false) + ' sur l’exercice, '
          + 'et non ' + C.money(3000, false) + ' seulement.', { tone: 'warning', icon: 'radio' }),
        K.miniTable([
          { label: 'Redevance', key: 'libelle' },
          { label: 'Catégorie', render: function (t) { return U.badge(t.categorie, t.id === 'radio' ? 'info' : 'navy'); } },
          { label: 'Assiette', key: 'assiette' },
          { label: 'Montant', align: 'right', render: function (t) { return C.money(t.montant, false); } },
          { label: 'Mois de prélèvement', render: function (t) { return t.moisLabel; } },
        ], ortb.redevances),
        el('div.rounded-lg.border.border-slate-200.bg-slate-50.p-3', null, [
          el('p.text-xs.font-semibold.uppercase.tracking-wide.text-slate-500', { text: 'Ce que supporte un agent' }),
          el('p.mt-1.text-sm.text-slate-700', {
            text: 'Salaire brut jusqu’à ' + C.money(ortb.seuilTele, false) + ' — '
              + C.money(1000, false) + ' au titre de la radio, en mars. '
              + 'Salaire brut supérieur à ' + C.money(ortb.seuilTele, false) + ' — '
              + C.money(1000, false) + ' en mars pour la radio, puis ' + C.money(3000, false)
              + ' en juin pour la télé, soit ' + C.money(ortb.cumulMaximum, false) + ' sur l’année.',
          }),
        ]),
        K.note('Le prélèvement est <strong>annuel</strong>, non mensuel : chaque redevance n’apparaît que '
          + 'sur le bulletin de son mois. Les porter chaque mois majorerait les retenues de onze douzièmes. '
          + 'Les deux parts restent distinguées jusqu’au bulletin et à l’état des cotisations.',
        { tone: 'info' }),
      ]), [
        K.btn('Suivi nominatif', { size: 'sm', icon: 'radio', onclick: function () { global.SIGH.app.go('m11-ortb'); } }),
      ]));

      /* --- Principes de tenue ------------------------------------------- */
      host.appendChild(U.card('Principes de tenue', U.descList([
        ['Report d’échéance', 'Une échéance tombant un samedi ou un dimanche est reportée au jour ouvrable suivant.'],
        ['Déclaration préalable', 'Six obligations exigent une déclaration avant paiement — elle est signalée à l’échéance.'],
        ['Équilibre des écritures', 'RG-10 — aucune écriture ne se valide si le débit ne balance pas le crédit.'],
        ['Continuité de l’exercice', 'Le logiciel ne se clôture pas en fin d’année : verrouiller une période empêche d’y saisir, pas d’y lire.'],
        ['Valorisation des sorties', 'Paramétrable — prix de vente par défaut, conformément à l’annotation du 30/12/2024.'],
        ['Journalisation', 'RG-12 — chaque paiement validé porte son auteur, sa date et son montant.'],
      ], 'grid-cols-1')));

      host.appendChild(K.source('Précisions du comptable de la clinique — réunion du 19 août 2026, '
        + 'complétées des arbitrages de la Direction du 20 août 2026.'));

      root.appendChild(host);
      return null;

      function bloc(titre, sousTitre, lignes) {
        var d = el('div.rounded-lg.border.border-slate-200.bg-white.p-3');
        d.appendChild(el('p.text-sm.font-semibold.text-slate-800', { text: titre }));
        d.appendChild(el('p.mt-0\\.5.mb-2.text-xs.text-slate-500', { text: sousTitre }));
        lignes.forEach(function (l) {
          d.appendChild(el('div.flex.items-baseline.gap-2.border-t.border-slate-100.py-1\\.5', null, [
            el('span.shrink-0.font-mono.text-xs.font-semibold.text-navy-700', { text: l[0] }),
            el('span.text-xs.text-slate-600', { text: l[1] }),
          ]));
        });
        return d;
      }
    },
  });


  /* ==========================================================================
   * CATALOGUE TARIFAIRE — DEUX PRIX PAR ACTE
   * --------------------------------------------------------------------------
   * Les six grilles officielles de la clinique portent chacune DEUX colonnes,
   * « PRIX NON ASSURE » et « PRIX ASSURE », et le prix assuré est presque
   * toujours le plus élevé. Ce n'est pas une coquille : le tarif conventionné
   * opposable à une compagnie n'est pas le tarif de guichet. Un modèle à prix
   * unique fausserait à la fois la facture du patient, la créance de
   * l'assureur et la recette comptable.
   *
   * TROIS ÉTATS et non deux dans la colonne assurée — un montant, NON COUVERT,
   * ou un tiret. Le tiret n'est ni un zéro ni une exclusion : c'est une valeur
   * que le document ne donne pas. Trois actes sont dans ce cas et l'écran les
   * compte, les nomme, et refuse de les facturer.
   * ======================================================================== */
  function colCatalogue() {
    return S.collection('catalogueTarifs', { module: 'CFG', entite: 'tarif', prefix: 'TAR' });
  }

  global.SIGH.screen('cfg-catalogue', {
    title: 'Catalogue tarifaire (deux prix)',
    description: 'Les six grilles officielles : consultations, imageries, analyses, AMI, gynéco-obstétrique, certificats.',
    regle: 'Chaque acte porte <strong>deux prix</strong> — non assuré et assuré. C’est la validité de la carte '
      + '<strong>à la date de facturation</strong> qui décide lequel s’applique (RG-09), et non le fait de '
      + 'posséder une carte. Un acte <strong>NON COUVERT</strong> reste facturé au patient au tarif non assuré, '
      + 'motif à l’appui. Un prix <strong>absent</strong> bloque la ligne : il n’est jamais présumé nul.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function champs() {
        return [
          { name: 'code', label: 'Code', type: 'text', required: true },
          { name: 'libelle', label: 'Désignation', type: 'text', required: true },
          { name: 'famille', label: 'Famille', type: 'select', required: true,
            options: (D.FAMILLES_TARIF || []).map(function (f) { return { value: f.code, label: f.label }; }) },
          { name: 'prixNonAssure', label: 'Prix non assuré (FCFA)', type: 'money' },
          { name: 'prixAssure', label: 'Prix assuré (FCFA)', type: 'money',
            hint: 'Laisser vide si le document ne le renseigne pas — un vide n’est pas un zéro.' },
          { name: 'nonCouvert', label: 'NON COUVERT par les assurances', type: 'checkbox',
            hint: 'L’acte existe et il est tarifé, mais aucune compagnie ne le prend en charge.' },
          { name: 'source', label: 'Document d’origine', type: 'text' },
        ];
      }

      function afficher() {
        var rows = colCatalogue().active();
        var sansPrix = rows.filter(function (r) { return r.prixAValider; });
        var nonCouverts = rows.filter(function (r) { return r.nonCouvert; });
        var sosSeul = rows.filter(function (r) { return r.assurable === 'sos'; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Actes au catalogue', value: C.num(rows.length), icon: 'list-ordered', tone: 'navy',
            hint: C.num((D.FAMILLES_TARIF || []).length) + ' familles' },
          { label: 'Non couverts par les assurances', value: C.num(nonCouverts.length), icon: 'shield-off',
            tone: 'warning', hint: 'planification familiale et hydrotubation' },
          { label: 'Couverts par SOS seule', value: C.num(sosSeul.length), icon: 'shield-alert', tone: 'info',
            hint: 'les certificats' },
          { label: 'Prix non renseigné', value: C.num(sansPrix.length), icon: 'triangle-alert',
            tone: sansPrix.length ? 'danger' : 'success', hint: 'ligne non facturable' },
        ]));

        if (sansPrix.length) {
          vue.appendChild(K.note('<strong>' + sansPrix.length + ' acte(s) sans prix au document</strong> : '
            + sansPrix.map(function (r) { return r.libelle; }).join(' · ')
            + '. Un tiret sur la grille n’est ni un zéro ni une exclusion — c’est une valeur manquante. '
            + 'Ces lignes ne peuvent pas être facturées tant que la Direction ne les a pas arrêtées.',
          { tone: 'danger', icon: 'triangle-alert' }));
        }

        var aArbitrer = rows.filter(function (r) { return r.aArbitrer; });
        if (aArbitrer.length) {
          vue.appendChild(K.note('<strong>Divergence à arbitrer</strong> — '
            + aArbitrer.map(function (r) { return r.libelle + ' : ' + r.aArbitrer; }).join(' ; ')
            + ' Le prototype retient le <strong>document</strong> ; écraser une pièce écrite par une phrase, '
            + 'ou l’inverse, serait décider à la place de la clinique.',
          { tone: 'warning', icon: 'scale' }));
        }

        var arbitres = rows.filter(function (r) { return r.arbitrage; });
        if (arbitres.length) {
          vue.appendChild(K.note('<strong>' + arbitres.length + ' acte(s) arbitré(s) par la Direction</strong>, '
            + 'dont le tarif ne suit pas la grille relevée : '
            + arbitres.map(function (r) { return r.code + ' — ' + r.libelle; }).join(' · ')
            + '. Un arbitrage tranché n’est pas une divergence en attente : il est appliqué et daté. '
            + 'Ne pas le « corriger » sans nouvelle décision écrite.',
          { tone: 'info', icon: 'gavel' }));
        }

        vue.appendChild(U.tabs((D.FAMILLES_TARIF || []).map(function (f) {
          var sous = rows.filter(function (r) { return r.famille === f.code; });
          return {
            id: f.code.toLowerCase(), label: f.label, badge: sous.length,
            render: function () { return tableau(sous); },
          };
        })));
        U.icons(vue);
      }

      function tableau(rows) {
        return U.dataTable({
          rows: C.sortBy(rows, 'code'),
          empty: 'Aucun acte dans cette famille.',
          actions: [K.creer(colCatalogue(), champs(), {
            module: 'CFG', label: 'Nouvel acte', titre: 'Ajouter un acte au catalogue',
            entite: 'Acte', apres: afficher,
            transform: function (v) {
              return Object.assign({}, v, {
                assurable: v.nonCouvert ? false : true,
                prixAValider: v.prixNonAssure == null || (v.prixAssure == null && !v.nonCouvert),
                source: v.source || 'Saisi par l’administrateur',
                statut: 'actif',
              });
            },
          })].filter(Boolean),
          columns: [
            { key: 'code', label: 'Code' },
            { key: 'libelle', label: 'Désignation' },
            { key: 'prixNonAssure', label: 'Prix non assuré', align: 'right',
              render: function (r) {
                return r.prixNonAssure == null
                  ? el('span.text-xs.italic.text-rose-600', { text: 'non renseigné' })
                  : C.money(r.prixNonAssure);
              } },
            { key: 'prixAssure', label: 'Prix assuré', align: 'right',
              render: function (r) {
                if (r.nonCouvert) return U.badge('NON COUVERT', 'warning');
                if (r.assurable === 'sos') return U.badge('SOS seule — ' + C.money(r.prixAssure), 'info');
                if (r.prixAssure == null) return el('span.text-xs.italic.text-rose-600', { text: 'non renseigné' });
                /* Un tarif arbitré porte sa marque : sinon un assuré payant
                   moins qu'un non-assuré se lit comme une inversion de saisie. */
                if (r.arbitrage) {
                  return el('span.inline-flex.items-center.gap-1', null, [
                    el('span', { text: C.money(r.prixAssure) }),
                    U.badge('arbitré', 'info'),
                  ]);
                }
                return C.money(r.prixAssure);
              } },
            { key: 'ecart', label: 'Écart', align: 'right',
              render: function (r) {
                if (r.prixNonAssure == null || r.prixAssure == null || r.nonCouvert) return '—';
                var e = r.prixAssure - r.prixNonAssure;
                return el('span', { class: e > 0 ? 'text-emerald-700' : 'text-slate-500',
                  text: (e > 0 ? '+' : '') + C.money(e) });
              } },
            { key: 'source', label: 'Document d’origine',
              render: function (r) { return el('span.text-xs.text-slate-500', { text: r.source || '—' }); } },
          ],
          rowActions: K.actionsLigne(colCatalogue(), champs(), {
            module: 'CFG', refresh: afficher,
            titre: function (r) { return r.code + ' — ' + r.libelle; },
            detail: function (r) {
              return el('div.space-y-4', null,
                K.grid([
                  ['Code', r.code], ['Désignation', r.libelle],
                  ['Famille', r.famille],
                  ['Prix non assuré', r.prixNonAssure == null ? 'non renseigné' : C.money(r.prixNonAssure)],
                  ['Prix assuré', r.nonCouvert ? 'NON COUVERT'
                    : (r.prixAssure == null ? 'non renseigné' : C.money(r.prixAssure))],
                  ['Couverture', r.assurable === 'sos' ? 'SOS seule'
                    : (r.assurable === false || r.nonCouvert ? 'Aucune' : 'Toutes compagnies')],
                  ['Document d’origine', r.source || '—'],
                ]),
                r.motifPrix ? K.note(r.motifPrix, { tone: 'danger', icon: 'triangle-alert' }) : null,
                r.aArbitrer ? K.note(r.aArbitrer, { tone: 'warning', icon: 'scale' }) : null,
                r.arbitrage ? K.note(r.arbitrage, { tone: 'info', icon: 'gavel' }) : null,
                r.nonCouvert ? K.note('Cet acte est <strong>NON COUVERT</strong> : l’assuré le règle au tarif '
                  + 'non assuré, et la facture en porte le motif. Tous les actes de planification familiale '
                  + 'sont dans ce cas.', { tone: 'warning', icon: 'shield-off' }) : null);
            },
          }),
        });
      }
    },
  });

  /* ==========================================================================
   * PAPIER À EN-TÊTE OFFICIEL — UNIFIÉ
   * --------------------------------------------------------------------------
   * Arbitrage de la Direction du 31/08/2026 (Bugs 7/8/13 des Instructions) :
   * les pièces réelles portaient trois IFU, trois RCCM et deux autorisations
   * selon la famille de document ; le logiciel n'imprime plus qu'UN en-tête
   * légal, celui de C.BRAND. Le référentiel des variantes est retiré — les
   * divergences anciennes restent documentées par les scans de docs/.
   * ======================================================================== */
  global.SIGH.screen('cfg-entetes', {
    title: 'Papier à en-tête officiel',
    description: 'L’unique identité légale imprimée sur tous les états de la clinique.',
    regle: 'Depuis l’arbitrage de la Direction du 31/08/2026, <strong>tous les états portent le même '
      + 'en-tête</strong> : IFU <strong>3201642748214</strong>, RCCM <strong>RB/NAT/2016-B-268</strong>. '
      + 'L’identité se corrige en un seul endroit — le Brand Configuration Center — et chaque pièce '
      + 'imprimée la reprend.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      var B = C.BRAND;

      vue.appendChild(U.kpiGrid([
        { label: 'IFU imprimé', value: '1', icon: 'hash', tone: 'success', hint: B.ifu },
        { label: 'RCCM imprimé', value: '1', icon: 'scale', tone: 'success', hint: B.rccm },
        { label: 'Autorisation d’ouverture', value: '1', icon: 'stamp', tone: 'success' },
        { label: 'États alimentés', value: 'Tous', icon: 'printer', tone: 'navy' },
      ]));

      vue.appendChild(U.card('Identité légale imprimée sur chaque état', el('div.space-y-1', null,
        K.grid([
          ['Dénomination', B.nom + (B.forme ? ' — ' + B.forme : '')],
          ['Devise de l’établissement', B.slogan],
          ['Adresse', B.adresse + ' · ' + B.bp],
          ['Téléphones', (B.telephones || []).join(' / ')],
          ['Ligne rendez-vous', B.telephoneRdv || '—'],
          ['Courriel', B.email],
          ['IFU', B.ifu],
          ['RCCM', B.rccm],
          ['Autorisation d’ouverture', B.autorisation],
          ['Autorisation d’exercice', B.autorisationExercice || 'Non imprimée — ' + (B.autorisationExerciceMotif || '')],
        ]))));

      vue.appendChild(K.note('Les pièces émises AVANT l’unification portent d’autres identités — trois IFU, '
        + 'trois RCCM et deux autorisations relevés sur les 37 documents collectés (certificats médico-légaux, '
        + 'rapport médical, comptes rendus de laboratoire et d’imagerie). Ces pièces restent valables et '
        + 'documentées par leurs scans dans docs/ ; elles ne sont simplement plus reproduites. Un document '
        + 'ancien qui diverge du présent en-tête n’est donc pas un faux.', { tone: 'info', icon: 'archive' }));

      U.icons(vue);
      return null;
    },
  });

  /* ==========================================================================
   * TYPES DE PIÈCES CERTIFIANTES
   * --------------------------------------------------------------------------
   * Quatorze gabarits officiels relevés sur les documents réels, chacun avec
   * son sigle de référence, sa direction émettrice et sa variante d'en-tête.
   * La numérotation est « <SIGLE> n°/n°/CNT/<direction>/<année> ».
   *
   * DEUX COLLISIONS DE SIGLES existent dans les sources : CMA désigne à la fois
   * l'accouchement et l'aptitude, CMD le décès et le genre de mort. Elles sont
   * CONSERVÉES et signalées — renuméroter d'office romprait la correspondance
   * avec les registres papier tenus depuis des années.
   * ======================================================================== */
  global.SIGH.screen('cfg-types-piece', {
    title: 'Types de pièces certifiantes',
    description: 'Les quatorze certificats et attestations que la clinique délivre.',
    regle: 'Chaque pièce porte son <strong>sigle de référence</strong> et sa direction émettrice ; toutes '
      + 's’impriment sous l’en-tête officiel unifié. Les certificats ne sont couverts par aucune assurance '
      + '<strong>à l’exception de SOS</strong> — la grille tarifaire le porte en toutes lettres.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function col3() {
        return S.collection('typesPiece', { module: 'CFG', entite: 'type de pièce', prefix: 'TPC' });
      }

      function champs() {
        return [
          { name: 'sigle', label: 'Sigle de référence', type: 'text', required: true },
          { name: 'libelle', label: 'Intitulé de la pièce', type: 'text', required: true },
          { name: 'direction', label: 'Direction émettrice', type: 'text', required: true,
            hint: 'Le segment du numéro de référence : DG/DE, DA, CN, DM/DA…' },
          { name: 'tarifCode', label: 'Acte du catalogue', type: 'select',
            options: [{ value: '', label: '— non tarifé —' }].concat(
              (D.tarifParFamille ? D.tarifParFamille('CERTIFICAT') : []).map(function (t) {
                return { value: t.code, label: t.libelle + ' — ' + C.money(t.prixNonAssure) };
              })) },
        ];
      }

      function afficher() {
        var rows = col3().active();
        var collisions = rows.filter(function (r) { return r.collision; });
        var tarifes = rows.filter(function (r) { return r.tarifCode; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Types de pièces', value: C.num(rows.length), icon: 'stamp', tone: 'navy' },
          { label: 'Tarifés au catalogue', value: C.num(tarifes.length), icon: 'tag', tone: 'info' },
          { label: 'Sigles en collision', value: C.num(collisions.length), icon: 'triangle-alert',
            tone: collisions.length ? 'warning' : 'success' },
          { label: 'Pièces délivrées', value: C.num(S.collection('pieces').active().length),
            icon: 'file-check', tone: 'neutral' },
        ]));

        if (collisions.length) {
          vue.appendChild(K.note('<strong>Deux sigles servent chacun à deux pièces</strong> dans les documents '
            + 'sources : <strong>CMA</strong> pour l’accouchement et pour l’aptitude, <strong>CMD</strong> pour '
            + 'le décès et pour le genre de mort. Les sigles sont <strong>conservés tels quels</strong> — '
            + 'renuméroter d’office romprait la correspondance avec les registres papier tenus depuis des années. '
            + 'Trancher appartient à la Direction.', { tone: 'warning', icon: 'triangle-alert' }));
        }

        vue.appendChild(U.dataTable({
          rows: C.sortBy(rows, 'libelle'),
          empty: 'Aucun type de pièce enregistré.',
          actions: [K.creer(col3(), champs(), {
            module: 'CFG', label: 'Nouveau type de pièce', titre: 'Type de pièce certifiante',
            entite: 'Type de pièce', apres: afficher,
          })].filter(Boolean),
          columns: [
            { key: 'sigle', label: 'Sigle',
              render: function (r) {
                return el('span', null, [
                  el('span.font-mono.text-xs', { text: r.sigle }),
                  r.collision ? el('span.ml-2', null, U.badge('collision', 'warning')) : null,
                ]);
              } },
            { key: 'libelle', label: 'Pièce' },
            { key: 'direction', label: 'Direction' },
            { key: 'tarifCode', label: 'Tarif', align: 'right',
              render: function (r) {
                if (!r.tarifCode || !D.tarif) return '—';
                var t = D.tarif(r.tarifCode);
                return t ? C.money(t.prixNonAssure) : '—';
              } },
          ],
          rowActions: K.actionsLigne(col3(), champs(), {
            module: 'CFG', refresh: afficher,
            titre: function (r) { return r.libelle; },
            detail: function (r) {
              var t = r.tarifCode && D.tarif ? D.tarif(r.tarifCode) : null;
              return el('div.space-y-4', null,
                K.grid([
                  ['Sigle', r.sigle], ['Pièce', r.libelle],
                  ['Direction émettrice', r.direction],
                  ['Numérotation', r.sigle + ' n°/n°/CNT/' + r.direction + '/' + new Date().getFullYear()],
                  ['Tarif', t ? C.money(t.prixNonAssure) : 'non tarifé'],
                  ['Couverture', t ? (t.assurable === 'sos' ? 'SOS seule' : 'aucune') : '—'],
                ]),
                r.collision ? K.note(r.collision + ' Le sigle est conservé tel quel : la correspondance avec '
                  + 'les registres papier prime sur la cohérence apparente.',
                { tone: 'warning', icon: 'triangle-alert' }) : null,
                r.examens ? K.note('Cette pièce se remplit depuis les <strong>résultats validés '
                  + 'biologiquement</strong> du patient — ' + r.examens.length + ' examens : '
                  + r.examens.map(function (c) {
                    var x = D.tarif ? D.tarif(c) : null; return x ? x.libelle : c;
                  }).join(', ') + '. Un examen non validé ne peut pas y être coché.',
                { tone: 'info', icon: 'flask-conical' }) : null);
            },
          }),
        }));
        U.icons(vue);
      }
    },
  });


  /* ==========================================================================
   * RAPPELS ET MESSAGES
   * --------------------------------------------------------------------------
   * Deux objets distincts, et la distinction est ce qui rend le module utile :
   *
   *   - le MODÈLE DE MESSAGE est un gabarit administrable, avec ses variables.
   *     Il s'écrit une fois ;
   *   - le RAPPEL est son envoi à une occasion donnée.
   *
   * Les confondre obligerait à ressaisir le texte à chaque anniversaire — ce
   * qui garantit qu'au bout de trois mois personne ne le fait plus.
   *
   * LE LOGICIEL PRÉPARE, IL N'ENVOIE PAS. Le prototype fonctionne hors ligne,
   * sans passerelle SMS ni serveur de messagerie : il compose le message et le
   * met en file. Prétendre l'envoyer serait mentir sur ce qui se passe.
   * ======================================================================== */
  function colModeles() {
    return S.collection('modelesMessage', { module: 'CFG', entite: 'modèle de message', prefix: 'MSG' });
  }
  function colRappels() {
    return S.collection('rappels', { module: 'CFG', entite: 'rappel', prefix: 'RPL' });
  }

  global.SIGH.screen('cfg-rappels', {
    title: 'Rappels & messages',
    description: 'Modèles de message administrables et rappels à échéance : anniversaires, nouvel an, fêtes, rendez-vous.',
    regle: 'Le <strong>modèle</strong> s’écrit une fois, le <strong>rappel</strong> est son envoi. Les '
      + 'confondre obligerait à ressaisir le texte à chaque occasion. Le logiciel <strong>prépare</strong> le '
      + 'message et le met en file : il ne l’envoie pas — le prototype fonctionne hors ligne, sans passerelle.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      var OCCASIONS = [
        { code: 'anniversaire', label: 'Anniversaire du patient', icone: 'cake' },
        { code: 'nouvel_an', label: 'Nouvel an', icone: 'party-popper' },
        { code: 'fete', label: 'Fête ou jour férié', icone: 'calendar-heart' },
        { code: 'rdv', label: 'Rappel de rendez-vous', icone: 'calendar-clock' },
        { code: 'resultat', label: 'Résultat disponible', icone: 'file-check-2' },
        { code: 'echeance', label: 'Échéance de règlement', icone: 'wallet' },
      ];

      /* Les variables reconnues dans un modèle. Les nommer évite qu'un agent
         invente « {{nom_du_patient}} » là où le logiciel attend « {{nom}} ». */
      var VARIABLES = [
        { jeton: '{{nom}}', description: 'Nom et prénoms du patient' },
        { jeton: '{{clinique}}', description: 'Dénomination de la clinique' },
        { jeton: '{{date}}', description: 'Date de l’occasion' },
        { jeton: '{{telephone}}', description: 'Ligne téléphonique de la clinique' },
        { jeton: '{{rdv}}', description: 'Date et heure du rendez-vous' },
      ];

      /* Les deux listes ci-dessus doivent être INITIALISÉES avant le premier
         rendu : var les hisse, il ne les remplit pas. */
      amorcer();
      afficher();
      return null;

      function amorcer() {
        var col = colModeles();
        if (col.all().length) return;
        [
          ['anniversaire', 'Anniversaire',
            'Bonjour {{nom}}, toute l’équipe de {{clinique}} vous souhaite un très joyeux anniversaire '
            + 'et une excellente santé. Votre santé, notre raison de vivre.'],
          ['nouvel_an', 'Vœux de nouvel an',
            'Bonjour {{nom}}, {{clinique}} vous présente ses meilleurs vœux pour la nouvelle année : '
            + 'santé, paix et prospérité à vous et à toute votre famille.'],
          ['fete', 'Vœux de fête',
            'Bonjour {{nom}}, {{clinique}} vous souhaite une excellente fête, entouré des vôtres.'],
          ['rdv', 'Rappel de rendez-vous',
            'Bonjour {{nom}}, nous vous rappelons votre rendez-vous à {{clinique}} le {{rdv}}. '
            + 'Pour toute modification, appelez le {{telephone}}.'],
          ['resultat', 'Résultat disponible',
            'Bonjour {{nom}}, votre résultat est disponible à {{clinique}}. '
            + 'Vous pouvez le retirer aux heures d’ouverture.'],
          ['echeance', 'Rappel de règlement',
            'Bonjour {{nom}}, un reliquat reste dû sur votre dossier à {{clinique}}. '
            + 'Nous vous remercions de bien vouloir passer à la caisse.'],
        ].forEach(function (m) {
          col.insert({ occasion: m[0], libelle: m[1], texte: m[2], actif: true,
            source: 'Modèle proposé — à valider par la Direction' });
        });
        S.save();
      }

      function champsModele() {
        return [
          { name: 'occasion', label: 'Occasion', type: 'select', required: true,
            options: OCCASIONS.map(function (x) { return { value: x.code, label: x.label }; }) },
          { name: 'libelle', label: 'Intitulé du modèle', type: 'text', required: true },
          { name: 'texte', label: 'Texte du message', type: 'textarea', rows: 5, required: true,
            hint: 'Variables reconnues : ' + VARIABLES.map(function (v) { return v.jeton; }).join(' · ') },
          { name: 'actif', label: 'Modèle actif', type: 'checkbox' },
        ];
      }

      /* L'aperçu remplace les variables par des valeurs d'exemple : un modèle
         qu'on ne peut pas relire en clair se relit mal. */
      function apercu(texte) {
        return String(texte || '')
          .replace(/\{\{nom\}\}/g, 'OROU YO Marguerite')
          .replace(/\{\{clinique\}\}/g, C.BRAND.nom)
          .replace(/\{\{date\}\}/g, C.dateFR(C.iso(new Date())))
          .replace(/\{\{telephone\}\}/g, C.BRAND.telephoneRdv || C.BRAND.telephones[0])
          .replace(/\{\{rdv\}\}/g, C.dateFR(C.iso(new Date())) + ' à 09h00');
      }

      function afficher() {
        var modeles = colModeles().active();
        var rappels = colRappels().active();
        var enFile = rappels.filter(function (r) { return r.etat === 'en_file'; });

        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Modèles de message', value: C.num(modeles.length), icon: 'message-square', tone: 'navy' },
          { label: 'Modèles actifs', value: C.num(modeles.filter(function (m) { return m.actif; }).length),
            icon: 'check-check', tone: 'success' },
          { label: 'Rappels préparés', value: C.num(rappels.length), icon: 'bell-ring', tone: 'info' },
          { label: 'En file d’envoi', value: C.num(enFile.length), icon: 'send',
            tone: enFile.length ? 'warning' : 'neutral', hint: 'le logiciel prépare, il n’envoie pas' },
        ]));

        vue.appendChild(K.note('Le prototype <strong>compose</strong> les messages et les met en file. '
          + 'Il ne les envoie pas : la solution fonctionne <strong>hors ligne</strong>, sans passerelle SMS ni '
          + 'serveur de messagerie. Prétendre l’envoi serait mentir sur ce qui se passe — et la clinique '
          + 'croirait ses patients prévenus.', { tone: 'warning', icon: 'wifi-off' }));

        vue.appendChild(U.tabs([
          { id: 'modeles', label: 'Modèles de message', badge: modeles.length, render: ongletModeles },
          { id: 'rappels', label: 'Rappels préparés', badge: rappels.length, render: ongletRappels },
          { id: 'variables', label: 'Variables', badge: VARIABLES.length, render: ongletVariables },
        ]));
        U.icons(vue);
      }

      function ongletModeles() {
        return U.dataTable({
          rows: colModeles().active(),
          empty: 'Aucun modèle de message.',
          actions: [K.creer(colModeles(), champsModele(), {
            module: 'CFG', label: 'Nouveau modèle', titre: 'Modèle de message',
            entite: 'Modèle', apres: afficher,
            transform: function (v) {
              return Object.assign({ source: 'Rédigé par l’administrateur' }, v);
            },
          })].filter(Boolean),
          columns: [
            { key: 'libelle', label: 'Modèle' },
            { key: 'occasion', label: 'Occasion', render: function (r) {
              var o = OCCASIONS.filter(function (x) { return x.code === r.occasion; })[0];
              return o ? o.label : r.occasion;
            } },
            { key: 'texte', label: 'Texte',
              render: function (r) {
                return el('span.text-xs.text-slate-500', {
                  text: r.texte.length > 90 ? r.texte.slice(0, 90) + '…' : r.texte,
                });
              } },
            { key: 'actif', label: 'Actif', align: 'center',
              render: function (r) { return r.actif ? U.badge('Oui', 'success') : U.badge('Non', 'neutral'); } },
          ],
          rowActions: K.actionsLigne(colModeles(), champsModele(), {
            module: 'CFG', refresh: afficher,
            titre: function (r) { return r.libelle; },
            detail: function (r) {
              return el('div.space-y-4', null,
                K.grid([
                  ['Intitulé', r.libelle],
                  ['Occasion', (OCCASIONS.filter(function (x) { return x.code === r.occasion; })[0] || {}).label || r.occasion],
                  ['Actif', r.actif ? 'Oui' : 'Non'],
                  ['Origine', r.source || '—'],
                ]),
                K.section('Texte du modèle',
                  el('p.whitespace-pre-line.text-sm.text-slate-600', { text: r.texte })),
                K.section('Aperçu, variables remplacées',
                  el('p.whitespace-pre-line.rounded-lg.bg-slate-50.p-3.text-sm.text-slate-700',
                    { text: apercu(r.texte) })));
            },
          }),
        });
      }

      function ongletRappels() {
        return U.dataTable({
          rows: C.sortBy(colRappels().active(), 'dateEcheance').reverse(),
          empty: 'Aucun rappel préparé.',
          actions: K.droits('CFG').editer ? [K.btn('Préparer les anniversaires du jour', {
            variant: 'primary', size: 'sm', icon: 'cake', onclick: preparerAnniversaires,
          })] : [],
          columns: [
            { key: 'reference', label: 'Référence' },
            { key: 'occasion', label: 'Occasion' },
            { key: 'destinataire', label: 'Destinataire' },
            { key: 'telephone', label: 'Téléphone' },
            { key: 'dateEcheance', label: 'Échéance',
              render: function (r) { return C.dateFR(r.dateEcheance); } },
            { key: 'etat', label: 'État', render: function (r) {
              return r.etat === 'en_file' ? U.badge('En file', 'warning') : U.badge(r.etat, 'neutral');
            } },
          ],
          rowActions: K.actionsLigne(colRappels(), null, {
            module: 'CFG', refresh: afficher,
            titre: function (r) { return r.reference; },
            detail: function (r) {
              return el('div.space-y-4', null,
                K.grid([
                  ['Référence', r.reference], ['Occasion', r.occasion],
                  ['Destinataire', r.destinataire], ['Téléphone', r.telephone || '—'],
                  ['Échéance', C.dateFR(r.dateEcheance)], ['État', r.etat],
                ]),
                K.section('Message composé',
                  el('p.whitespace-pre-line.rounded-lg.bg-slate-50.p-3.text-sm.text-slate-700',
                    { text: r.message })));
            },
          }),
        });
      }

      function ongletVariables() {
        return el('div.space-y-3', null,
          K.note('Ces jetons sont remplacés au moment de composer le message. Un jeton inconnu reste tel quel '
            + 'dans le texte — visible, donc corrigeable, plutôt que remplacé par du vide.',
          { tone: 'info', icon: 'braces' }),
          K.miniTable(['Jeton', 'Remplacé par'],
            VARIABLES.map(function (v) { return [v.jeton, v.description]; })));
      }

      function preparerAnniversaires() {
        var modele = colModeles().active().filter(function (m) {
          return m.occasion === 'anniversaire' && m.actif;
        })[0];
        if (!modele) { U.toast('Aucun modèle d’anniversaire actif.', { type: 'error' }); return; }
        var auj = new Date();
        var jour = C.pad(auj.getMonth() + 1, 2) + '-' + C.pad(auj.getDate(), 2);
        var concernes = S.collection('patients').active().filter(function (p2) {
          return p2.dateNaissance && String(p2.dateNaissance).slice(5, 10) === jour;
        });
        if (!concernes.length) {
          U.toast('Aucun patient ne fête son anniversaire aujourd’hui.', { type: 'info' });
          return;
        }
        var col = colRappels();
        var faits = 0;
        concernes.forEach(function (p2) {
          var nom = p2.nom + ' ' + p2.prenom;
          /* Un rappel déjà préparé pour ce patient et cette date ne se
             redouble pas : le patient recevrait deux fois le même message. */
          var deja = col.all().some(function (r) {
            return r.patientId === p2.id && r.dateEcheance === C.iso(auj) && r.occasion === 'Anniversaire';
          });
          if (deja) return;
          col.insert({
            reference: C.nextRef('RPL-', 5), occasion: 'Anniversaire',
            patientId: p2.id, destinataire: nom, telephone: p2.telephone,
            dateEcheance: C.iso(auj), etat: 'en_file',
            message: apercu(modele.texte).replace('OROU YO Marguerite', nom),
          });
          faits++;
        });
        afficher();
        U.toast(faits + ' rappel(s) préparé(s) — ' + concernes.length + ' anniversaire(s) aujourd’hui.', {
          type: faits ? 'success' : 'info',
          detail: 'Les messages sont EN FILE : le logiciel ne les envoie pas.',
        });
      }
    },
  });


  /* ==========================================================================
   * CATALOGUE DE L'IMAGERIE (phase 8)
   * --------------------------------------------------------------------------
   * Les examens et leurs variables quittent le code pour le magasin — la
   * doctrine du laboratoire, appliquée à l'imagerie. Les listes de choix
   * viennent du BROUILLON MANUSCRIT de l'échographiste et des cinq comptes
   * rendus réels ; les modifier ici, c'est faire évoluer le formulaire de
   * saisie sans toucher au code. D.IMAGERIE n'est que la semence.
   * ======================================================================== */
  global.SIGH.screen('cfg-imagerie-catalogue', {
    title: 'Catalogue de l\u2019imagerie',
    description: 'Examens d\u2019imagerie et variables de leurs comptes rendus : listes de choix, mesures, rubriques.',
    regle: 'Les listes pr\u00e9-ins\u00e9r\u00e9es viennent du <strong>brouillon manuscrit de l\u2019\u00e9chographiste</strong> '
      + 'et des cinq comptes rendus r\u00e9els. Une variable se <strong>ferme</strong> sans se supprimer : les '
      + 'comptes rendus d\u00e9j\u00e0 rendus la conservent. \u00ab Annexes \u00bb et \u00ab Conclusion \u00bb ne se '
      + 'param\u00e8trent pas : elles restent en texte libre \u2014 \u00ab \u00e0 remplir par moi-m\u00eame \u00bb, '
      + '\u00e9crit de sa main.',
    render: function (root) {
      var vue = el('div.space-y-4');
      root.appendChild(vue);
      afficher();
      return null;

      function colExamensIm() {
        return S.collection('examensImagerie', { module: 'CFG', entite: 'examen d\u2019imagerie', prefix: 'EXI' });
      }
      function colVariablesIm() {
        return S.collection('variablesImagerie', { module: 'CFG', entite: 'variable d\u2019imagerie', prefix: 'VIM' });
      }
      function types() { return (D.IMAGERIE && D.IMAGERIE.TYPES) || []; }

      function champsExamen() {
        return [
          { name: 'code', label: 'Code', type: 'text', required: true,
            hint: 'Align\u00e9 sur le code du r\u00e9f\u00e9rentiel tarifaire : un examen est un acte facturable.' },
          { name: 'label', label: 'Intitul\u00e9', type: 'text', required: true, col: 'full' },
          /* Vague 61 \u2014 la modalit\u00e9 range l'examen dans SON tableau (\u00e9chographie,
             radiographie, mammographie, scanner, IRM) : c'est le catalogue qui en
             d\u00e9cide, jamais le compte rendu. */
          { name: 'modalite', label: 'Modalit\u00e9', type: 'select', required: true,
            options: ((D.IMAGERIE && D.IMAGERIE.MODALITES) || []).map(function (m) { return { value: m.code, label: m.label }; }) },
          { name: 'voie', label: 'Voie d\u2019abord', type: 'text', hint: 'sus-pubienne, transpari\u00e9tale\u2026' },
          { name: 'tarifCode', label: 'Code tarifaire (si diff\u00e9rent)', type: 'text',
            hint: 'L\u2019obst\u00e9tricale du 1er trimestre se facture comme l\u2019obst\u00e9tricale.' },
        ];
      }

      function champsVariable(v) {
        /* À l'édition, les choix se relisent dans le champ texte — le
           formulaire est prérempli depuis la fiche. */
        if (v && v.optionsTexte == null) v.optionsTexte = (v.options || []).join('|');
        return [
          { name: 'examen', label: 'Examen', type: 'select', required: true, col: 'full',
            options: colExamensIm().active().map(function (x) { return { value: x.code, label: x.label }; }) },
          { name: 'code', label: 'Code de la variable', type: 'text', required: true },
          { name: 'libelle', label: 'Intitul\u00e9', type: 'text', required: true, col: 'full' },
          { name: 'type', label: 'Type', type: 'select', required: true,
            options: types().map(function (x) { return { value: x.code, label: x.label }; }) },
          { name: 'optionsTexte', label: 'Choix propos\u00e9s (s\u00e9par\u00e9s par |)', type: 'text', col: 'full',
            hint: 'Pour une liste ou un binaire \u2014 par exemple \u00ab homog\u00e8ne|h\u00e9t\u00e9rog\u00e8ne \u00bb.' },
          { name: 'unite', label: 'Unit\u00e9', type: 'text', hint: 'mm, g, ml\u2026 pour une mesure.' },
          { name: 'rubrique', label: 'Rubrique du compte rendu', type: 'text', required: true },
          { name: 'normal', label: 'Valeur normale attendue', type: 'text',
            hint: 'Ce qui s\u2019en \u00e9carte est mis en gras sur la pi\u00e8ce.' },
          { name: 'ordre', label: 'Rang de rendu', type: 'number', min: 1, required: true },
        ];
      }

      function transformVariable(v) {
        v.options = v.optionsTexte
          ? String(v.optionsTexte).split('|').map(function (x) { return x.trim(); }).filter(Boolean)
          : null;
        delete v.optionsTexte;
        if (v.ordre != null) v.ordre = Number(v.ordre);
        return v;
      }

      function afficher() {
        var exams = colExamensIm().active();
        var vars = colVariablesIm().active();
        C.clear(vue);
        vue.appendChild(U.kpiGrid([
          { label: 'Examens au catalogue', value: C.num(exams.length), icon: 'scan-line', tone: 'navy' },
          { label: 'Variables de compte rendu', value: C.num(vars.length), icon: 'list-checks', tone: 'info' },
          { label: 'Variables ferm\u00e9es', value: C.num(colVariablesIm().active().filter(function (v) { return v.actif === false; }).length),
            icon: 'eye-off', tone: 'neutral' },
          { label: 'Listes de choix', value: C.num(vars.filter(function (v) { return v.type === 'liste' || v.type === 'binaire'; }).length),
            icon: 'chevrons-up-down', tone: 'neutral', hint: 'La demande du brouillon manuscrit' },
        ]));

        vue.appendChild(U.tabs([
          {
            id: 'examens', label: 'Examens', badge: exams.length,
            render: function () {
              return U.dataTable({
                rows: function () { return colExamensIm().active(); },
                exportName: 'imagerie-examens', pageSize: 10,
                emptyMessage: 'Aucun examen au catalogue.',
                actions: [K.creer(colExamensIm(), champsExamen(), {
                  module: 'CFG', label: 'Nouvel examen', titre: 'Examen d\u2019imagerie',
                  entite: 'Examen', apres: afficher,
                })].filter(Boolean),
                columns: [
                  { key: 'code', label: 'Code', render: function (x) { return el('span.font-mono.text-xs', { text: x.code }); } },
                  { key: 'label', label: 'Intitul\u00e9' },
                  {
                    key: 'modalite', label: 'Modalit\u00e9',
                    value: function (x) {
                      var m = D.IMAGERIE && D.IMAGERIE.modalite ? D.IMAGERIE.modalite(x.modalite || 'echographie') : null;
                      return m ? m.label : (x.modalite || '\u2014');
                    },
                  },
                  {
                    key: 'aValider', label: 'Origine',
                    value: function (x) { return x.aValider ? 'Proposition \u00e0 valider' : 'Document\u00e9e'; },
                    render: function (x) {
                      return x.aValider ? U.badge('Proposition \u00e0 valider', 'warning') : U.badge('Document\u00e9e', 'success');
                    },
                  },
                  { key: 'voie', label: 'Voie d\u2019abord', render: function (x) { return x.voie || '\u2014'; } },
                  {
                    key: 'variables', label: 'Variables', align: 'right',
                    value: function (x) {
                      return colVariablesIm().active().filter(function (v) { return v.examen === x.code; }).length;
                    },
                  },
                ],
                rowActions: K.actionsLigne(colExamensIm(), champsExamen(), {
                  module: 'CFG', refresh: afficher,
                  titre: function (x) { return x.label; },
                }),
              });
            },
          },
          {
            id: 'variables', label: 'Variables', badge: vars.length,
            render: function () {
              return U.dataTable({
                rows: function () { return colVariablesIm().active(); },
                exportName: 'imagerie-variables', pageSize: 15, searchable: true,
                emptyMessage: 'Aucune variable param\u00e9tr\u00e9e.',
                actions: [K.creer(colVariablesIm(), champsVariable, {
                  module: 'CFG', label: 'Nouvelle variable', titre: 'Variable de compte rendu',
                  entite: 'Variable', size: 'lg', apres: afficher, transform: transformVariable,
                })].filter(Boolean),
                columns: [
                  {
                    key: 'examen', label: 'Examen',
                    render: function (v) {
                      var ex = colExamensIm().active().filter(function (x) { return x.code === v.examen; })[0];
                      return el('div.min-w-0', null, [
                        el('p.truncate.text-sm.text-slate-700', { text: ex ? ex.label : v.examen }),
                        el('p.text-xs.text-slate-400', { text: v.rubrique }),
                      ]);
                    },
                  },
                  { key: 'libelle', label: 'Variable' },
                  {
                    key: 'type', label: 'Type',
                    render: function (v) {
                      var ty = types().filter(function (x) { return x.code === v.type; })[0];
                      return U.badge(ty ? ty.label : v.type, 'info');
                    },
                  },
                  {
                    key: 'options', label: 'Choix / unit\u00e9',
                    render: function (v) {
                      if (v.options && v.options.length) {
                        return el('span.text-xs.text-slate-600', { text: v.options.join(' \u00b7 ') });
                      }
                      return el('span.font-mono.text-xs.text-slate-500', { text: v.unite || '\u2014' });
                    },
                  },
                  {
                    key: 'actif', label: '\u00c9tat', align: 'right',
                    render: function (v) {
                      return v.actif === false ? U.badge('Ferm\u00e9e', 'neutral') : U.badge('Active', 'success');
                    },
                  },
                ],
                rowActions: function (v) {
                  var actes = K.actionsLigne(colVariablesIm(), champsVariable, {
                    module: 'CFG', refresh: afficher, transform: transformVariable,
                    titre: function (x) { return x.libelle; },
                  })(v);
                  if (K.droits('CFG').editer) {
                    actes.push(K.iconBtn(v.actif === false ? 'eye' : 'eye-off',
                      v.actif === false ? 'Rouvrir la variable' : 'Fermer la variable',
                      function () {
                        colVariablesIm().update(v.id, { actif: v.actif === false });
                        afficher();
                        U.toast(v.actif === false ? 'Variable rouverte.' : 'Variable ferm\u00e9e.', {
                          type: 'success',
                          detail: v.actif === false ? null : 'Les comptes rendus d\u00e9j\u00e0 rendus la conservent.',
                        });
                      }));
                  }
                  return actes;
                },
              });
            },
          },
        ]));
        U.icons(vue);
      }
    },
  });

})(window);
