/* =============================================================================
 * M7 — Achats & Fournisseurs
 * -----------------------------------------------------------------------------
 * CDCT §10.1 — cycle complet : quantification → validation par la Directrice
 * Administrative → commande → réception → vérification par 2 à 3 personnes →
 * approvisionnement → enregistrement au stock gros.
 * Le bon d'expression de besoins distingue la QUANTITÉ DEMANDÉE de la
 * QUANTITÉ ACCORDÉE, conformément au processus réel de la clinique.
 * RG-04 — toute commande de stock gros est validée par la DA avant transmission.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data,
      P = global.SIGH.print, G = global.SIGH.charts, K = global.SIGH.kit,
      PR = global.SIGH.parcours;
  var el = C.el;
  var AUJ = new Date(2026, 7, 16);

  var SERVICES_DEMANDEURS = ['Pharmacie d’urgence', 'Laboratoire', 'Hospitalisation', 'Maternité',
    'Bloc opératoire', 'Accueil', 'Administration', 'Entretien'];

  /* Étapes du workflow d'expression de besoins (draf1 §11). */
  var ETAPES_BESOIN = [
    { id: 'brouillon', label: 'Brouillon', tone: 'neutral' },
    { id: 'soumis', label: 'Soumis', tone: 'info' },
    { id: 'controle_stock', label: 'Contrôle stock', tone: 'info' },
    { id: 'validation_da', label: 'Validation DA', tone: 'warning' },
    { id: 'accorde', label: 'Quantité accordée', tone: 'navy' },
    { id: 'prepare', label: 'Préparation', tone: 'navy' },
    { id: 'livre', label: 'Livré', tone: 'success' },
    { id: 'cloture', label: 'Clôturé', tone: 'neutral' },
  ];
  /* ==========================================================================
   * DEUX ISSUES QUI NE SONT PAS DES ÉTAPES (NEINSTRUCTION2, 24/09/2026)
   * --------------------------------------------------------------------------
   * La DAF arbitre : elle VALIDE, elle REJETTE, ou elle DEMANDE UN COMPLÉMENT.
   * Les deux dernières ne sont pas des étapes du circuit — elles en sortent —
   * et les ranger dans la file linéaire ferait croire qu'un bon rejeté avance.
   * Elles vivent donc à part, et le ruban du circuit n'affiche que le chemin.
   *
   * UN BON REJETÉ N'EST PAS ARCHIVÉ : le service doit pouvoir lire le motif,
   * et la DAF pouvoir montrer ce qu'elle a refusé. C'est RG-14 appliqué au
   * bon sens — on n'efface pas une décision.
   * ======================================================================== */
  var ISSUES_BESOIN = [
    { id: 'rejete', label: 'Rejeté', tone: 'danger' },
    { id: 'complement', label: 'Complément demandé', tone: 'warning' },
    { id: 'distribue', label: 'Distribué au service', tone: 'success' },
  ];

  /* Les quatre familles nommées par la Direction. Un besoin qui n'entre dans
     aucune se dit « Autre » et se décrit — inventer une cinquième famille à
     chaque demande rendrait le classement inutilisable. */
  var CATEGORIES_BESOIN = [
    'Produits d’entretien (nettoyage, désinfection)',
    'Produits administratifs (stylos, cahiers, classeurs, cartouches, papier RAM)',
    'Matériel technique léger',
    'Consommables médicaux',
    'Autre — à préciser',
  ];

  function etatBesoin(id) {
    return ETAPES_BESOIN.concat(ISSUES_BESOIN).filter(function (x) { return x.id === id; })[0]
      || { id: id, label: id, tone: 'neutral' };
  }

  function etapeLabel(id) { return etatBesoin(id).label; }
  function etapeTone(id) { return etatBesoin(id).tone; }

  function produits() { return S.collection('produits').active(); }
  function fournisseurs() { return S.collection('fournisseurs').active(); }
  function optionsProduits() {
    return C.sortBy(produits(), 'designation').map(function (p) {
      return { value: p.id, label: p.designation + ' (' + p.unite + ')' };
    });
  }
  function optionsFournisseurs() {
    return fournisseurs().map(function (f) { return { value: f.code, label: f.nom }; });
  }

  /* ==========================================================================
   * AMORÇAGE
   * ======================================================================== */
  /* L’AMORÇAGE A QUITTÉ CET ÉCRAN (22/09/2026) pour le socle : le BFR lit
     les dettes fournisseurs depuis la comptabilité, le pilotage et le
     moteur d’alertes, et un poste qui n’avait jamais ouvert M7 les voyait
     à zéro. La graine est la même (911) : le jeu ne change pas d’un franc.
     Une COPIE locale aurait divergé au premier correctif — on appelle. */
  function amorcer() {
    /* `true` : M7 veut AUSSI ses bons de besoins, que le socle ne sème pas
       — le magasin du navigateur est à sa marge, et le BFR ne les lit pas. */
    if (global.SIGH.semerAchats) { global.SIGH.semerAchats(true); S.save(); }
  }

  /* ==========================================================================
   * BONS D'EXPRESSION DE BESOINS
   * ======================================================================== */
  global.SIGH.screen('m7-besoins', {
    title: 'Bons d’expression de besoins',
    description: 'Demandes internes des services : désignation, date, secteur demandeur, quantité voulue et quantité accordée.',
    regle: '<strong>Tout agent exprime un besoin</strong> — papier, produits d’entretien, fournitures, '
      + 'petit matériel : l’écran est ouvert à tous les postes, chacun sur SA vue. '
      + 'La <strong>DAF arbitre</strong> (valider, rejeter avec motif, demander un complément) ; sa '
      + 'validation <strong>informe le comptable et le gestionnaire de stock</strong>, qui transforment '
      + 'le besoin en commande puis en distribution. Le bon distingue la <strong>quantité demandée</strong> '
      + 'de la <strong>quantité accordée</strong>, et le circuit reste : brouillon → soumis → contrôle '
      + 'stock → validation DA → accordé → préparation → livraison → clôture. '
      + 'Un bon <strong>rejeté n’est pas archivé</strong> : le service doit pouvoir en lire le motif.',
    render: function (root) {
      amorcer();
      var col = S.collection('besoins', { module: 'M7', entite: 'BonExpressionBesoin' });
      var host = el('div.space-y-4');
      var table;

      /* ====================================================================
       * QUATRE VUES SUR UNE SEULE COLLECTION
       * --------------------------------------------------------------------
       * Le même bon est regardé par quatre postes qui n'en attendent pas la
       * même chose : celui qui demande veut savoir OÙ EN EST sa demande, la
       * DAF veut ARBITRER, l'achat veut ce qui est VALIDÉ, la logistique veut
       * le tableau entier. Quatre écrans auraient donné quatre vérités sur la
       * même pièce — c'est la leçon des visites et des certificats, payée
       * deux fois. Ce sont donc des VUES, filtrées, jamais des collections.
       *
       * CHAQUE VUE EST GARDÉE PAR CE QU'ELLE PERMET, et non par un module :
       * « Mes demandes » est ouvert à tous (l'écran est universel), mais
       * l'arbitrage n'apparaît qu'à qui arbitre. Un onglet visible sans le
       * droit d'agir promettrait une porte fermée.
       * ================================================================== */
      var session = S.session() || {};
      var moi = S.currentUser();
      var dr = K.droits('M7');
      var estArbitre = ['da', 'direction', 'admin'].indexOf(session.role) !== -1;
      var estAchat = ['comptable', 'stock', 'da', 'direction', 'admin', 'aide_comptable']
        .indexOf(session.role) !== -1;

      /* « Mes demandes » : ce que CE poste a exprimé. On reconnaît l'agent par
         son nom — le bon porte le demandeur, pas un identifiant de compte. */
      function miennes() {
        return col.active().filter(function (b) { return b.demandeur === moi; });
      }
      function aArbitrer() {
        return col.active().filter(function (b) {
          return ['soumis', 'controle_stock', 'validation_da'].indexOf(b.etape) !== -1;
        });
      }
      function pourAchat() {
        return col.active().filter(function (b) {
          return ['accorde', 'prepare', 'livre'].indexOf(b.etape) !== -1;
        });
      }

      host.appendChild(U.kpiGrid([
        { label: 'Mes demandes', value: C.num(miennes().length), icon: 'user-round-pen', tone: 'navy',
          hint: C.num(col.active().length) + ' bon(s) au registre' },
        { label: 'En attente d’arbitrage DAF', value: C.num(aArbitrer().length), icon: 'hourglass', tone: 'warning' },
        { label: 'Livrés', value: C.num(col.active().filter(function (b) { return ['livre', 'cloture'].indexOf(b.etape) !== -1; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Montant estimé cumulé', value: C.money(C.sum(col.active(), 'montantEstime')), icon: 'wallet', tone: 'info' },
      ]));

      /* Vue du circuit */
      var circuit = el('div.flex.flex-wrap.items-center.gap-1\\.5');
      ETAPES_BESOIN.forEach(function (e, i) {
        var n = col.active().filter(function (b) { return b.etape === e.id; }).length;
        circuit.appendChild(el('span.inline-flex.items-center.gap-1\\.5.rounded-lg.border.px-2\\.5.py-1\\.5', {
          class: 'border-' + e.tone + '-200 bg-' + e.tone + '-50',
        }, [
          el('span.text-xs.font-medium', { class: 'text-' + e.tone + '-900', text: e.label }),
          el('span.rounded-full.bg-white.px-1\\.5.text-\\[10px\\].font-semibold.num', { class: 'text-' + e.tone + '-700', text: String(n) }),
        ]));
        if (i < ETAPES_BESOIN.length - 1) circuit.appendChild(C.icon('chevron-right', 'h-3.5 w-3.5 text-slate-300'));
      });
      host.appendChild(U.card('Circuit de traitement', circuit));

      table = tableauBesoins('Bons d’expression de besoins', function () { return col.active(); }, 'tous');

      root.appendChild(host);
      host.appendChild(U.tabs([
        { id: 'miennes', label: 'Mes demandes', badge: miennes().length,
          render: function () {
            return el('div.space-y-4', null, [
              K.note('Exprimez ici vos besoins de fournitures — papier, produits d’entretien, '
                + 'stylos, petit matériel. La <strong>DAF arbitre</strong>, puis l’achat et la '
                + 'distribution suivent : vous voyez l’avancement sans avoir à le demander.',
              { tone: 'info', icon: 'clipboard-pen' }),
              tableauBesoins('Mes demandes', miennes, 'miennes'),
            ]);
          } },
        estArbitre ? { id: 'arbitrage', label: 'Arbitrage & validation DAF', badge: aArbitrer().length,
          render: function () {
            return el('div.space-y-4', null, [
              K.note('<strong>Valider</strong> accorde le besoin et informe le comptable et le '
                + 'gestionnaire de stock. <strong>Rejeter</strong> et <strong>demander un '
                + 'complément</strong> exigent leur motif — un refus sans motif se represente '
                + 'la semaine suivante à l’identique.', { tone: 'warning', icon: 'gavel' }),
              tableauBesoins('Demandes à arbitrer', aArbitrer, 'arbitrage'),
            ]);
          } } : null,
        estAchat ? { id: 'achats', label: 'Besoins validés — achats & logistique', badge: pourAchat().length,
          render: function () {
            return el('div.space-y-4', null, [
              K.note('Ces besoins sont <strong>accordés par la DAF</strong>. Ils deviennent un bon de '
                + 'commande fournisseur (RG-04) ou une distribution directe si l’article est déjà au '
                + 'magasin.', { tone: 'success', icon: 'package-check' }),
              tableauBesoins('Besoins accordés', pourAchat, 'achats'),
            ]);
          } } : null,
        dr.voir && estAchat ? { id: 'tous', label: 'Tous les bons', badge: col.active().length,
          render: function () { return table; } } : null,
      ].filter(Boolean)));
      U.icons(host);
      return null;

      /**
       * La fabrique de tableau — une seule, pour les quatre vues.
       * @param {string}   titre
       * @param {Function} lignes  la population à montrer
       * @param {string}   vue     'miennes' | 'arbitrage' | 'achats' | 'tous'
       */
      function tableauBesoins(titre, lignes, vue) {
        return U.dataTable({
        title: titre,
        rows: lignes,
        exportName: 'bons-expression-besoins', pageSize: 12, searchable: true,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'etape', label: 'Étape', options: ETAPES_BESOIN.map(function (e) { return { value: e.id, label: e.label }; }) },
          { name: 'service', label: 'Service demandeur', options: SERVICES_DEMANDEURS },
        ],
        actions: [K.commande('Nouveau bon', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(null); } })],
        columns: [
          { key: 'reference', label: 'N° bon', nowrap: true, render: function (b) { return el('span.font-mono.text-xs.font-semibold', { text: b.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (b) { return C.dateFR(b.date); }, render: function (b) { return C.dateFR(b.date); } },
          { key: 'service', label: 'Service demandeur' },
          { key: 'demandeur', label: 'Demandeur' },
          { key: 'nbLignes', label: 'Articles', align: 'right', value: function (b) { return (b.lignes || []).length; }, render: function (b) { return String((b.lignes || []).length); } },
          {
            key: 'quantites', label: 'Demandé / Accordé', align: 'right', sortable: false,
            text: function (b) {
              return C.sum(b.lignes || [], 'quantiteDemandee') + ' / ' + C.sum((b.lignes || []).filter(function (l) { return l.quantiteAccordee != null; }), 'quantiteAccordee');
            },
            render: function (b) {
              var dem = C.sum(b.lignes || [], 'quantiteDemandee');
              var acc = C.sum((b.lignes || []).filter(function (l) { return l.quantiteAccordee != null; }), 'quantiteAccordee');
              var complet = acc === dem;
              return el('span.num', null, [
                el('span.font-medium.text-slate-700', { text: C.num(dem) }),
                el('span.text-slate-400', { text: ' / ' }),
                el('span', { class: acc === 0 ? 'text-slate-400' : (complet ? 'font-semibold text-success-600' : 'font-semibold text-warning-600'), text: acc ? C.num(acc) : '—' }),
              ]);
            },
          },
          {
            key: 'montantEstime', label: 'Montant estimé', align: 'right',
            text: function (b) { return C.money(b.montantEstime, false); },
            render: function (b) { return C.money(b.montantEstime, false); },
          },
          { key: 'etape', label: 'Étape', render: function (b) { return U.badge(etapeLabel(b.etape), etapeTone(b.etape)); } },
        ],
        onRowClick: function (b) { consulter(b); },
        rowActions: function (b) {
          var actes = [
            K.iconBtn('eye', 'Consulter', function () { consulter(b); }),
            K.iconBtn('printer', 'Imprimer le bon', function () { etat(b); }),
          ];
          /* L'ARBITRAGE N'APPARAÎT QU'À SA VUE, et seulement sur un bon qui
             l'attend : proposer « Valider » sur un bon déjà accordé ferait
             douter de ce qui a été décidé. */
          if (vue === 'arbitrage') {
            actes.push(K.iconBtn('check', 'Valider le besoin', function () { arbitrer(b, 'valider'); }));
            actes.push(K.iconBtn('x', 'Rejeter avec motif', function () { arbitrer(b, 'rejeter'); }));
            actes.push(K.iconBtn('help-circle', 'Demander un complément', function () { arbitrer(b, 'complement'); }));
          }
          if (vue === 'achats') {
            actes.push(K.iconBtn('shopping-cart', 'Transformer en bon de commande', function () { versCommande(b); }));
            actes.push(K.iconBtn('package-check', 'Marquer distribué au service', function () { distribuer(b); }));
          }
          if (vue !== 'arbitrage' && vue !== 'achats') {
            actes.push(K.commandeIcone('pencil', 'Modifier', function () { ouvrir(b); }));
            actes.push(K.commandeIcone('archive', 'Archiver', function () {
              var res = col.archive(b.id);
              rafraichir();
              U.toast('Bon archivé.', { type: 'success', undo: function () { res.undo(); rafraichir(); } });
            }, { droit: 'annuler', variant: 'ghost' }));
          }
          return actes;
        },
        });
      }

      /** Repeint l'écran : les quatre vues comptent la même collection. */
      function rafraichir() { global.SIGH.app.go('m7-besoins'); }

      /* ====================================================================
       * L'ARBITRAGE DE LA DAF
       * --------------------------------------------------------------------
       * Trois réponses, et les deux dernières EXIGENT leur motif. Un refus
       * sans motif se represente la semaine suivante à l'identique — le
       * service n'a rien appris, et la DAF rearbitre la même chose.
       *
       * LA VALIDATION INFORME DEUX POSTES, et c'est tout l'objet du module :
       * le comptable pour l'engagement, le gestionnaire de stock pour l'achat
       * ou la distribution. On ne leur envoie pas un message à écrire à la
       * main — la notification naît du geste, comme l'encaissement fait naître
       * l'écriture comptable.
       * ================================================================== */
      function arbitrer(b, quoi) {
        var titres = {
          valider: 'Valider ce besoin ?',
          rejeter: 'Rejeter ce besoin ?',
          complement: 'Demander un complément d’information ?',
        };
        var f = U.form([
          {
            name: 'motif',
            label: quoi === 'valider' ? 'Observation (facultative)' : 'Motif — obligatoire',
            type: 'textarea', rows: 3, required: quoi !== 'valider', col: 'full',
            help: quoi === 'valider'
              ? 'Ce que la DAF souhaite porter à la connaissance de l’achat.'
              : 'Le service doit pouvoir lire POURQUOI : sans motif, la même demande revient à l’identique.',
          },
        ], {});
        var m = U.modal({
          title: titres[quoi],
          subtitle: b.reference + ' — ' + b.service + ' · ' + C.money(b.montantEstime, false),
          size: 'md',
          body: el('div.space-y-3', null, [
            K.miniTable([
              { label: 'Article', key: 'produit' },
              { label: 'Demandé', align: 'right', key: 'quantiteDemandee' },
              { label: 'Accordé', align: 'right', render: function (l) {
                return l.quantiteAccordee == null ? '—' : C.num(l.quantiteAccordee);
              } },
            ], b.lignes || []),
            f,
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(quoi === 'valider' ? 'Valider et informer' : (quoi === 'rejeter' ? 'Rejeter' : 'Demander'), {
              variant: 'primary', icon: quoi === 'valider' ? 'check' : 'send',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le motif est obligatoire.', { type: 'error' }); return; }
                var etape = quoi === 'valider' ? 'accorde' : (quoi === 'rejeter' ? 'rejete' : 'complement');
                col.update(b.id, {
                  etape: etape,
                  arbitreLe: new Date().toISOString(),
                  arbitrePar: S.currentUser(),
                  motifArbitrage: v.motif || null,
                  valideePar: quoi === 'valider' ? S.currentUser() : null,
                });
                if (quoi === 'valider') informerAchat(b, v.motif);
                m.close();
                U.toast(quoi === 'valider'
                  ? 'Besoin ' + b.reference + ' accordé — le comptable et le gestionnaire de stock sont informés.'
                  : 'Besoin ' + b.reference + ' — ' + etatBesoin(etape).label.toLowerCase() + '.',
                { type: quoi === 'valider' ? 'success' : 'warning', duration: 8000 });
                rafraichir();
              },
            }),
          ],
        });
      }

      /** Le comptable et le stock sont saisis — par une TÂCHE, pas par un mot. */
      function informerAchat(b, motif) {
        if (!PR || !PR.notifier) return;
        var detail = b.service + ' — ' + C.num((b.lignes || []).length) + ' article(s), '
          + C.money(b.montantEstime, false) + (motif ? ' · ' + motif : '');
        ['comptable', 'stock'].forEach(function (poste) {
          try {
            /* `libelle` et non `titre`, `reference` et non `lien` : c'est
               l'API du moteur, lue et non supposée. */
            PR.notifier({
              type: 'besoin_accorde', poste: poste,
              libelle: 'Besoin accordé — ' + b.reference,
              detail: detail + (poste === 'comptable'
                ? ' · engagement budgétaire et décaissement à préparer'
                : ' · achat à lancer ou distribution à planifier'),
              reference: b.reference,
              priorite: 'important',
            });
          } catch (e) { /* le module de notification n'est pas chargé ici */ }
        });
      }

      /* Le besoin accordé devient une COMMANDE : on mène au bon écran plutôt
         que de fabriquer la commande à l'aveugle — RG-04 veut la validation
         de la Direction sur la commande elle-même. */
      function versCommande(b) {
        U.confirm({
          title: 'Transformer en bon de commande ?',
          message: 'Le besoin <strong>' + b.reference + '</strong> passe en <strong>préparation</strong> '
            + 'et l’écran des commandes s’ouvre. <strong>RG-04</strong> : la commande devra être '
            + 'validée par la Directrice Administrative avant transmission au fournisseur.',
          confirmLabel: 'Ouvrir les commandes',
        }).then(function (ok) {
          if (!ok) return;
          col.update(b.id, { etape: 'prepare', prepareLe: new Date().toISOString(),
            preparePar: S.currentUser() });
          global.SIGH.app.go('m7-commandes');
        });
      }

      function distribuer(b) {
        U.confirm({
          title: 'Marquer le besoin distribué ?',
          message: 'Le service <strong>' + b.service + '</strong> a reçu les articles du bon '
            + '<strong>' + b.reference + '</strong>. Le bon sort du circuit d’achat.',
          confirmLabel: 'Distribuer',
        }).then(function (ok) {
          if (!ok) return;
          col.update(b.id, { etape: 'distribue', distribueLe: new Date().toISOString(),
            distribuePar: S.currentUser() });
          U.toast('Besoin ' + b.reference + ' distribué à ' + b.service + '.', { type: 'success' });
          rafraichir();
        });
      }

      /* Code du prochain article créé ici. La suite se lit dans la collection
         et non dans un compteur de session : deux onglets ouverts, ou un
         rechargement, réécriraient NOUV-0001 par-dessus un article existant. */
      function codeArticleSuivant() {
        var dernier = 0;
        produits().forEach(function (p) {
          var m = /^NOUV-(\d+)$/.exec(p.code || '');
          if (m) dernier = Math.max(dernier, Number(m[1]));
        });
        return 'NOUV-' + C.pad(dernier + 1, 4);
      }

      /* Saisie minimale : ce qu'il faut pour qu'un article soit commandable et
         valorisable. Le stock, le CUMP, le rangement et le fournisseur se
         règlent au référentiel M6 — les demander ici à un agent qui exprime un
         besoin lui ferait saisir des chiffres qu'il n'a pas. */
      function ouvrirArticle(apres) {
        var f = U.form([
          { name: 'designation', label: 'Désignation', required: true, col: 'full' },
          { name: 'categorie', label: 'Catégorie', type: 'select', required: true,
            options: D.CATEGORIES_PRODUIT.map(function (c) { return { value: c.id, label: c.label }; }) },
          { name: 'unite', label: 'Unité', required: true, placeholder: 'Boîte, Ramette, Flacon…' },
          { name: 'prixAchat', label: 'Prix d’achat (FCFA)', type: 'money', required: true, min: 0 },
          { name: 'seuilAlerte', label: 'Seuil d’alerte', type: 'number', min: 0, required: true },
        ], { categorie: 'fourniture', unite: 'Unité', seuilAlerte: 10 });
        var ma = U.modal({
          title: 'Nouvel article au référentiel',
          subtitle: 'L’article rejoint le référentiel produits (M6) et devient commandable immédiatement.',
          size: 'md',
          body: el('div.space-y-3', null, [
            f,
            K.note('Le stock part à zéro : il s’alimente par une entrée de stock, jamais par cette saisie. '
              + 'Rangement, CUMP et fournisseur habituel se complètent au référentiel produits.'),
          ]),
          footer: [
            K.btn('Annuler', { onclick: function () { ma.close(); } }),
            K.btn('Créer l’article', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var doublon = produits().filter(function (p) {
                  return C.slug(p.designation) === C.slug(v.designation);
                })[0];
                if (doublon) {
                  U.toast('« ' + doublon.designation + ' » (' + doublon.code + ') existe déjà au référentiel.',
                    { type: 'error' });
                  return;
                }
                v.code = codeArticleSuivant();
                v.prixAchat = Number(v.prixAchat) || 0;
                v.seuilAlerte = Number(v.seuilAlerte) || 0;
                /* RG-02 : pas de marge. Le prix de vente suit le prix d'achat,
                   et le CUMP part de là en attendant la première entrée. */
                v.prixVente = v.prixAchat;
                v.cump = v.prixAchat;
                v.stockGros = 0; v.stockDetail = 0; v.stock = 0;
                /* insert() retourne { record, undo } — et NON l'enregistrement.
                   Lire l'API plutôt que la supposer : p.id valait undefined, et
                   le combo retombait silencieusement sur « Choisir un article ». */
                var p = S.collection('produits').insert(v).record;
                ma.close();
                U.toast('Article ' + p.code + ' créé au référentiel.', { type: 'success' });
                if (apres) apres(p);
              },
            }),
          ],
        });
      }

      function ouvrir(record) {
        var lignes = record ? (record.lignes || []).slice() : [];
        var body = el('div.space-y-4');
        /* ================================================================
         * LE FORMULAIRE S'ADAPTE À QUI L'OUVRE
         * ----------------------------------------------------------------
         * Un agent qui exprime un besoin n'a pas à choisir son « étape du
         * circuit » : il demande, et le bon part SOUMIS. Lui présenter la
         * file complète l'inviterait à se placer lui-même en « validation
         * DA » — c'est-à-dire à s'accorder ce qu'il demande.
         *
         * La logistique, elle, garde la main sur l'étape : c'est elle qui
         * tient le circuit et qui doit pouvoir rattraper un bon mal placé.
         * ============================================================== */
        var piloteCircuit = K.droits('M7').editer && estAchat;
        var f = U.form([
          { name: 'date', label: 'Date', type: 'date', required: true },
          { name: 'service', label: 'Service demandeur', type: 'select', required: true, options: SERVICES_DEMANDEURS },
          { name: 'demandeur', label: 'Demandeur', required: true },
          {
            name: 'categorie', label: 'Catégorie du besoin', type: 'select', required: true,
            options: CATEGORIES_BESOIN,
          },
          { name: 'urgent', label: 'Besoin urgent', type: 'checkbox' },
          piloteCircuit
            ? { name: 'etape', label: 'Étape du circuit', type: 'select', required: true,
              options: ETAPES_BESOIN.map(function (e) { return { value: e.id, label: e.label }; }) }
            : null,
          { name: 'motif', label: 'Motif de la demande', type: 'textarea', rows: 2, col: 'full',
            help: 'À quoi cela va servir : c’est ce que la DAF lit pour arbitrer.' },
        ].filter(Boolean), record || {
          date: C.iso(AUJ),
          /* Un bon exprimé par un service part SOUMIS : laissé en brouillon,
             il attendrait indéfiniment que son auteur pense à l'envoyer. */
          etape: piloteCircuit ? 'brouillon' : 'soumis',
          demandeur: S.currentUser(),
        });
        body.appendChild(f);

        /* Lignes de la demande */
        var ajout = el('div.flex.flex-wrap.items-end.gap-2.rounded-lg.border.border-slate-200.bg-slate-50.p-3');
        var optsBesoin = optionsProduits();
        var selP = U.combo(optsBesoin, {
          value: optsBesoin.length ? optsBesoin[0].value : '',
          searchPlaceholder: 'Désignation ou code article…',
          placeholder: 'Choisir un article',
        });
        var qD = el('input.input.w-24', { type: 'number', min: 1, value: 10 });
        var qA = el('input.input.w-24', { type: 'number', min: 0, placeholder: '—' });
        ajout.appendChild(el('div.min-w-\\[14rem\\].flex-1', null, [el('label.label', { text: 'Article' }), selP]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Qté demandée' }), qD]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Qté accordée' }), qA]));
        /* L'article n'est pas au catalogue : on l'y met, sans perdre le bon
           en cours de saisie. */
        var creerArticle = K.commande('Nouvel article', {
          moduleCode: 'M6', icon: 'package-plus', variant: 'ghost',
          onclick: function () {
            ouvrirArticle(function (p) {
              selP.setOptions(optionsProduits(), true);
              selP.value = p.id;
            });
          },
        });
        if (creerArticle) ajout.appendChild(creerArticle);
        ajout.appendChild(K.btn('Ajouter', {
          variant: 'primary', icon: 'plus',
          onclick: function () {
            var p = produits().filter(function (x) { return x.id === selP.value; })[0];
            var d = Number(qD.value) || 0;
            if (!p || d <= 0) { U.toast('Sélectionner un article et une quantité.', { type: 'error' }); return; }
            var a = qA.value === '' ? null : Number(qA.value);
            if (a != null && a > d) { U.toast('La quantité accordée ne peut excéder la quantité demandée.', { type: 'error' }); return; }
            lignes.push({ produitId: p.id, produit: p.designation, unite: p.unite, quantiteDemandee: d, quantiteAccordee: a, quantiteLivree: null, prixAchat: p.prixAchat });
            qD.value = 10; qA.value = '';
            maj();
          },
        }));
        body.appendChild(ajout);

        var lignesHost = el('div');
        body.appendChild(lignesHost);

        function maj() {
          C.clear(lignesHost);
          if (!lignes.length) { lignesHost.appendChild(U.empty('Aucun article dans la demande.', { icon: 'clipboard-list' })); U.icons(lignesHost); return; }
          var t = el('table.tbl');
          t.appendChild(el('thead', null, el('tr', null, [
            el('th', { text: 'Article' }), el('th.text-right', { text: 'Demandée' }),
            el('th.text-right', { text: 'Accordée' }), el('th.text-right', { text: 'Montant estimé' }), el('th'),
          ])));
          var tb = el('tbody');
          lignes.forEach(function (l, i) {
            tb.appendChild(el('tr', null, [
              el('td', null, el('div', null, [
                el('p.text-sm.text-slate-700', { text: l.produit }),
                el('p.text-xs.text-slate-400', { text: l.unite }),
              ])),
              el('td.text-right.num', { text: C.num(l.quantiteDemandee) }),
              el('td.text-right.num', null, l.quantiteAccordee != null
                ? el('span.font-semibold', { class: l.quantiteAccordee < l.quantiteDemandee ? 'text-warning-600' : 'text-success-600', text: C.num(l.quantiteAccordee) })
                : el('span.text-slate-400', { text: '—' })),
              el('td.text-right.num', { text: C.money(l.quantiteDemandee * l.prixAchat, false) }),
              el('td.text-right', null, K.iconBtn('x', 'Retirer', function () { lignes.splice(i, 1); maj(); }, 'ghost')),
            ]));
          });
          t.appendChild(tb);
          t.appendChild(el('tfoot', null, el('tr', null, [
            el('td.font-semibold', { colspan: 3, text: 'TOTAL ESTIMÉ' }),
            el('td.text-right.num.font-bold.text-navy-900', { text: C.money(C.sum(lignes, function (l) { return l.quantiteDemandee * l.prixAchat; }), false) }),
            el('td'),
          ])));
          lignesHost.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, t));
          U.icons(lignesHost);
        }
        maj();

        var m = U.modal({
          title: record ? 'Modifier le bon ' + record.reference : 'Nouveau bon d’expression de besoins',
          subtitle: 'La quantité accordée est renseignée après validation de la Directrice Administrative (RG-04).',
          size: 'xl', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(record ? 'Enregistrer' : 'Créer le bon', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (!lignes.length) { U.toast('Ajouter au moins un article.', { type: 'error' }); return; }
                v.lignes = lignes;
                v.montantEstime = C.sum(lignes, function (l) { return l.quantiteDemandee * l.prixAchat; });
                if (!v.reference) v.reference = C.nextRef('BEB-2026-', 4);
                if (['validation_da', 'accorde', 'prepare', 'livre', 'cloture'].indexOf(v.etape) !== -1 && !v.valideePar) {
                  v.valideePar = 'TAKI Alimatou';
                }
                var res = record ? col.update(record.id, v) : col.insert(v);
                m.close(); table.refresh();
                U.toast(record ? 'Bon mis à jour.' : 'Bon créé — ' + res.record.reference, { type: 'success', undo: res.undo });
              },
            }),
          ],
        });
      }

      function consulter(b) {
        var idx = ETAPES_BESOIN.map(function (e) { return e.id; }).indexOf(b.etape);
        U.drawer({
          title: 'Bon ' + b.reference, subtitle: b.service + ' — ' + C.dateFR(b.date), width: 'max-w-3xl',
          body: el('div.space-y-4', null, [
            U.descList([['Référence', b.reference], ['Date', C.dateFR(b.date)],
              ['Service demandeur', b.service], ['Demandeur', b.demandeur],
              ['Motif', b.motif], ['Étape', U.badge(etapeLabel(b.etape), etapeTone(b.etape))],
              ['Validé par', b.valideePar || 'En attente'], ['Montant estimé', C.money(b.montantEstime)]]),
            U.card('Avancement du circuit', U.timeline(ETAPES_BESOIN.map(function (e, i) {
              return {
                title: e.label,
                detail: i === idx ? 'Étape courante' : (i < idx ? 'Franchie' : 'À venir'),
                date: i <= idx ? '✓' : '—',
                tone: i < idx ? 'success' : (i === idx ? 'navy' : 'neutral'),
              };
            }))),
            U.card('Articles demandés', K.miniTable([
              { label: 'Article', key: 'produit' },
              { label: 'Unité', key: 'unite' },
              { label: 'Demandée', align: 'right', key: 'quantiteDemandee' },
              { label: 'Accordée', align: 'right', render: function (l) { return l.quantiteAccordee != null ? String(l.quantiteAccordee) : '—'; } },
              { label: 'Livrée', align: 'right', render: function (l) { return l.quantiteLivree != null ? String(l.quantiteLivree) : '—'; } },
            ], b.lignes || [])),
          ]),
          footer: [
            K.btn('Imprimer', { icon: 'printer', onclick: function () { etat(b); } }),
            K.btn('Modifier', { variant: 'primary', icon: 'pencil', onclick: function () { ouvrir(b); } }),
          ],
        });
      }

      function etat(b) {
        P.etat({
          titre: 'Bon d’expression de besoins',
          sousTitre: b.reference,
          cartouche: [['Référence', b.reference], ['Date', C.dateFR(b.date)],
            ['Service demandeur', b.service], ['Demandeur', b.demandeur],
            ['Motif', b.motif || '—'], ['Étape', etapeLabel(b.etape)]],
          contenu: P.tableau([
            { label: 'Désignation', key: 'produit' },
            { label: 'Unité', key: 'unite' },
            { label: 'Quantité voulue', key: 'quantiteDemandee', align: 'right' },
            { label: 'Quantité accordée', align: 'right', value: function (l) { return l.quantiteAccordee != null ? l.quantiteAccordee : ''; } },
            { label: 'Quantité livrée', align: 'right', value: function (l) { return l.quantiteLivree != null ? l.quantiteLivree : ''; } },
          ], b.lignes || []),
          signatures: [
            { role: 'Le Demandeur', nom: b.demandeur },
            { role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri', mention: 'Contrôle de disponibilité' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou', mention: 'Validation (RG-04)' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * BONS DE COMMANDE
   * ======================================================================== */
  global.SIGH.screen('m7-commandes', {
    title: 'Bons de commande',
    description: 'Commandes fournisseurs, validation par la Directrice Administrative et transmission.',
    regle: '<strong>RG-04</strong> — toute commande d’achat de stock gros doit être <strong>validée par la Directrice Administrative</strong> avant transmission au fournisseur.',
    render: function (root) {
      amorcer();
      var col = S.collection('commandes', { module: 'M7', entite: 'BonCommande' });
      var host = el('div.space-y-4');
      var table;

      var STATUTS_CMD = [
        { value: 'brouillon', label: 'Brouillon' },
        { value: 'attente_validation', label: 'En attente de validation DA' },
        { value: 'validee', label: 'Validée' },
        { value: 'transmise', label: 'Transmise au fournisseur' },
        { value: 'livree', label: 'Livrée' },
        { value: 'soldee', label: 'Soldée' },
      ];
      function toneCmd(s) {
        return { brouillon: 'neutral', attente_validation: 'warning', validee: 'info', transmise: 'navy', livree: 'success', soldee: 'success' }[s] || 'neutral';
      }
      function labelCmd(s) {
        var x = STATUTS_CMD.filter(function (o) { return o.value === s; })[0];
        return x ? x.label : s;
      }

      var enAttente = col.active().filter(function (c) { return c.statutCommande === 'attente_validation'; });
      if (enAttente.length) {
        host.appendChild(K.note('<strong>' + enAttente.length + ' commande(s)</strong> en attente de validation par la Directrice Administrative. '
          + 'Aucune transmission au fournisseur n’est possible avant cette validation (RG-04).', { tone: 'warning', icon: 'shield-alert' }));
      }

      host.appendChild(U.kpiGrid([
        { label: 'Commandes enregistrées', value: C.num(col.active().length), icon: 'truck', tone: 'navy' },
        { label: 'En attente de validation', value: C.num(enAttente.length), icon: 'hourglass', tone: 'warning' },
        { label: 'Montant commandé', value: C.money(C.sum(col.active(), 'montant')), icon: 'wallet', tone: 'info' },
        { label: 'Livrées', value: C.num(col.active().filter(function (c) { return ['livree', 'soldee'].indexOf(c.statutCommande) !== -1; }).length), icon: 'check-circle-2', tone: 'success' },
      ]));

      table = U.dataTable({
        title: 'Bons de commande',
        rows: function () { return col.active(); },
        exportName: 'bons-commande', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'statutCommande', label: 'Statut', options: STATUTS_CMD },
          { name: 'fournisseur', label: 'Fournisseur', options: optionsFournisseurs() },
        ],
        actions: [K.commande('Nouvelle commande', { variant: 'primary', size: 'sm', icon: 'plus', onclick: function () { ouvrir(null); } })],
        columns: [
          { key: 'reference', label: 'N° commande', nowrap: true, render: function (c) { return el('span.font-mono.text-xs.font-semibold', { text: c.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (c) { return C.dateFR(c.date); }, render: function (c) { return C.dateFR(c.date); } },
          { key: 'fournisseurNom', label: 'Fournisseur' },
          { key: 'nbLignes', label: 'Articles', align: 'right', value: function (c) { return (c.lignes || []).length; }, render: function (c) { return String((c.lignes || []).length); } },
          {
            key: 'montant', label: 'Montant', align: 'right',
            text: function (c) { return C.money(c.montant, false); },
            render: function (c) { return el('span.font-semibold', { text: C.money(c.montant, false) }); },
          },
          { key: 'delaiLivraison', label: 'Délai', align: 'right', render: function (c) { return (c.delaiLivraison || '—') + ' j'; } },
          { key: 'statutCommande', label: 'Statut', render: function (c) { return U.badge(labelCmd(c.statutCommande), toneCmd(c.statutCommande)); } },
          { key: 'valideePar', label: 'Validée par (RG-04)', render: function (c) { return c.valideePar || el('span.text-xs.text-slate-400', { text: 'En attente' }); } },
        ],
        onRowClick: function (c) { consulter(c); },
        rowActions: function (c) {
          /* C.append attend un NŒUD ; ici on empile dans un tableau. Une
             commande refusée vaut null et ne s'empile pas. */
          function pousser(liste, cmd) { if (cmd) liste.push(cmd); }
          var acts = [K.iconBtn('eye', 'Consulter', function () { consulter(c); })];
          if (c.statutCommande === 'attente_validation') {
            /* LA VALIDATION RG-04 EST L'ACTE DE LA DIRECTRICE
               ADMINISTRATIVE. L'offrir à qui lit les commandes ferait croire
               que la commande peut partir sans elle. */
            pousser(acts, K.commandeIcone('shield-check', 'Valider (DA)', function () { valider(c); }, 'ghost'));
          }
          acts.push(K.iconBtn('printer', 'Imprimer', function () { etat(c); }));
          pousser(acts, K.commandeIcone('pencil', 'Modifier', function () { ouvrir(c); }));
          return acts;
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function valider(c) {
        U.confirm({
          title: 'Valider la commande ' + c.reference + ' ?',
          message: 'En application de la règle RG-04, cette validation autorise la transmission au fournisseur '
            + c.fournisseurNom + ' pour un montant de ' + C.money(c.montant) + '. L’opération est journalisée.',
          confirmLabel: 'Valider la commande',
        }).then(function (ok) {
          if (!ok) return;
          var res = col.update(c.id, { statutCommande: 'validee', valideePar: 'TAKI Alimatou', dateValidation: C.iso(AUJ) });
          table.refresh();
          U.toast('Commande validée par la Directrice Administrative.', { type: 'success', undo: function () { res.undo(); table.refresh(); } });
        });
      }

      function ouvrir(record) {
        var lignes = record ? (record.lignes || []).slice() : [];
        var body = el('div.space-y-4');
        var f = U.form([
          { name: 'date', label: 'Date de la commande', type: 'date', required: true },
          { name: 'fournisseur', label: 'Fournisseur', type: 'select', required: true, options: optionsFournisseurs() },
          { name: 'statutCommande', label: 'Statut', type: 'select', required: true, options: STATUTS_CMD },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ], record || { date: C.iso(AUJ), statutCommande: 'brouillon' });
        body.appendChild(f);

        var ajout = el('div.flex.flex-wrap.items-end.gap-2.rounded-lg.border.border-slate-200.bg-slate-50.p-3');
        var optsCmd = optionsProduits();
        var selP = U.combo(optsCmd, {
          value: optsCmd.length ? optsCmd[0].value : '',
          searchPlaceholder: 'Désignation ou code article…',
          placeholder: 'Choisir un article',
        });
        var qte = el('input.input.w-24', { type: 'number', min: 1, value: 10 });
        var pu = el('input.input.w-28', { type: 'number', min: 0 });
        selP.addEventListener('change', function () {
          var p = produits().filter(function (x) { return x.id === selP.value; })[0];
          if (p) pu.value = p.prixAchat;
        });
        var p0 = produits().filter(function (x) { return x.id === selP.value; })[0];
        if (p0) pu.value = p0.prixAchat;

        ajout.appendChild(el('div.min-w-\\[14rem\\].flex-1', null, [el('label.label', { text: 'Article' }), selP]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Quantité' }), qte]));
        ajout.appendChild(el('div', null, [el('label.label', { text: 'Prix unitaire' }), pu]));
        ajout.appendChild(K.btn('Ajouter', {
          variant: 'primary', icon: 'plus',
          onclick: function () {
            var p = produits().filter(function (x) { return x.id === selP.value; })[0];
            var q = Number(qte.value) || 0, prix = Number(pu.value) || 0;
            if (!p || q <= 0) { U.toast('Sélectionner un article et une quantité.', { type: 'error' }); return; }
            lignes.push({ produitId: p.id, produit: p.designation, unite: p.unite, quantite: q, prixUnitaire: prix, montant: q * prix });
            qte.value = 10; maj();
          },
        }));
        body.appendChild(ajout);

        var lignesHost = el('div');
        body.appendChild(lignesHost);
        function maj() {
          C.clear(lignesHost);
          if (!lignes.length) { lignesHost.appendChild(U.empty('Aucun article dans la commande.', { icon: 'truck' })); U.icons(lignesHost); return; }
          var t = el('table.tbl');
          t.appendChild(el('thead', null, el('tr', null, [
            el('th', { text: 'Article' }), el('th.text-right', { text: 'Quantité' }),
            el('th.text-right', { text: 'P.U.' }), el('th.text-right', { text: 'Montant' }), el('th'),
          ])));
          var tb = el('tbody');
          lignes.forEach(function (l, i) {
            tb.appendChild(el('tr', null, [
              el('td', { text: l.produit }),
              el('td.text-right.num', { text: C.num(l.quantite) + ' ' + l.unite }),
              el('td.text-right.num', { text: C.money(l.prixUnitaire, false) }),
              el('td.text-right.num.font-semibold', { text: C.money(l.montant, false) }),
              el('td.text-right', null, K.iconBtn('x', 'Retirer', function () { lignes.splice(i, 1); maj(); }, 'ghost')),
            ]));
          });
          t.appendChild(tb);
          t.appendChild(el('tfoot', null, el('tr', null, [
            el('td.font-semibold', { colspan: 3, text: 'TOTAL' }),
            el('td.text-right.num.font-bold.text-navy-900', { text: C.money(C.sum(lignes, 'montant'), false) }),
            el('td'),
          ])));
          lignesHost.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, t));
          U.icons(lignesHost);
        }
        maj();

        var m = U.modal({
          title: record ? 'Modifier la commande ' + record.reference : 'Nouveau bon de commande',
          size: 'xl', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn(record ? 'Enregistrer' : 'Créer la commande', {
              variant: 'primary', icon: 'save',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                if (!lignes.length) { U.toast('Ajouter au moins un article.', { type: 'error' }); return; }
                var four = D.FOURNISSEURS.filter(function (x) { return x.code === v.fournisseur; })[0];
                v.fournisseurNom = four ? four.nom : v.fournisseur;
                v.delaiLivraison = four ? four.delai : null;
                v.lignes = lignes; v.montant = C.sum(lignes, 'montant');
                if (!v.reference) v.reference = C.nextRef('BC-2026-', 4);
                if (['validee', 'transmise', 'livree', 'soldee'].indexOf(v.statutCommande) !== -1 && !v.valideePar) {
                  v.valideePar = 'TAKI Alimatou'; v.dateValidation = C.iso(AUJ);
                }
                var res = record ? col.update(record.id, v) : col.insert(v);
                m.close(); table.refresh();
                U.toast(record ? 'Commande mise à jour.' : 'Commande créée — ' + res.record.reference, { type: 'success', undo: res.undo });
              },
            }),
          ],
        });
      }

      function consulter(c) {
        U.drawer({
          title: 'Commande ' + c.reference, subtitle: c.fournisseurNom + ' — ' + C.dateFR(c.date), width: 'max-w-3xl',
          body: el('div.space-y-4', null, [
            U.descList([['Référence', c.reference], ['Date', C.dateFR(c.date)],
              ['Fournisseur', c.fournisseurNom], ['Délai de livraison', (c.delaiLivraison || '—') + ' jours'],
              ['Montant', C.money(c.montant)], ['Statut', U.badge(labelCmd(c.statutCommande), toneCmd(c.statutCommande))],
              ['Validée par (RG-04)', c.valideePar || 'En attente'],
              ['Date de validation', c.dateValidation ? C.dateFR(c.dateValidation) : '—']]),
            c.statutCommande === 'attente_validation'
              ? K.note('Cette commande <strong>ne peut être transmise</strong> au fournisseur tant que la Directrice Administrative ne l’a pas validée (RG-04).', { tone: 'warning', icon: 'shield-alert' })
              : null,
            U.card('Articles commandés', K.miniTable([
              { label: 'Article', key: 'produit' },
              { label: 'Quantité', align: 'right', render: function (l) { return l.quantite + ' ' + l.unite; } },
              { label: 'P.U.', align: 'right', render: function (l) { return C.money(l.prixUnitaire, false); } },
              { label: 'Montant', align: 'right', render: function (l) { return C.money(l.montant, false); } },
            ], c.lignes || [])),
          ]),
          footer: [
            c.statutCommande === 'attente_validation'
              ? K.commande('Valider (DA)', { variant: 'success', icon: 'shield-check', onclick: function () { valider(c); } }) : null,
            K.btn('Imprimer', { variant: 'primary', icon: 'printer', onclick: function () { etat(c); } }),
          ].filter(Boolean),
        });
      }

      function etat(c) {
        P.etat({
          titre: 'Bon de commande',
          sousTitre: c.reference,
          cartouche: [['Référence', c.reference], ['Date', C.dateFR(c.date)],
            ['Fournisseur', c.fournisseurNom], ['Délai de livraison', (c.delaiLivraison || '—') + ' jours'],
            ['Statut', labelCmd(c.statutCommande)], ['Validée par', c.valideePar || 'En attente']],
          contenu: P.tableau([
            { label: 'Désignation', key: 'produit' },
            { label: 'Unité', key: 'unite' },
            { label: 'Quantité', key: 'quantite', align: 'right' },
            { label: 'Prix unitaire', align: 'right', value: function (l) { return C.money(l.prixUnitaire, false); } },
            {
              label: 'Montant', align: 'right',
              value: function (l) { return C.money(l.montant, false); },
              /* Le bon de commande engage la clinique : son total doit être
                 celui de ses propres lignes, refait à l’impression. */
              somme: function (l) { return l.montant; },
            },
          ], c.lignes || [], { total: true }),
          signatures: [
            { role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' },
            { role: 'La Directrice Administrative', nom: 'TAKI Alimatou', mention: 'Bon pour commande (RG-04)' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * BONS DE LIVRAISON
   * ======================================================================== */
  global.SIGH.screen('m7-livraisons', {
    title: 'Bons de livraison',
    description: 'Bordereaux de livraison fournisseurs, rapprochés des bons de commande correspondants.',
    render: function (root) {
      amorcer();
      var col = S.collection('livraisons', { module: 'M7', entite: 'BonLivraison' });
      var host = el('div.space-y-4');

      host.appendChild(U.kpiGrid([
        { label: 'Bons de livraison', value: C.num(col.active().length), icon: 'package-check', tone: 'navy' },
        { label: 'Réceptions conformes', value: C.num(col.active().filter(function (l) { return l.statutReception === 'conforme'; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Avec écart', value: C.num(col.active().filter(function (l) { return l.statutReception === 'ecart'; }).length), icon: 'triangle-alert', tone: 'danger' },
        { label: 'Valeur livrée', value: C.money(C.sum(col.active(), 'montant')), icon: 'wallet', tone: 'info' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Bons de livraison',
        rows: function () { return col.active(); },
        exportName: 'bons-livraison', pageSize: 12,
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'fournisseur', label: 'Fournisseur', options: optionsFournisseurs() },
          { name: 'statutReception', label: 'Réception', options: [{ value: 'conforme', label: 'Conforme' }, { value: 'ecart', label: 'Avec écart' }] },
        ],
        columns: [
          { key: 'reference', label: 'N° BL', nowrap: true, render: function (l) { return el('span.font-mono.text-xs.font-semibold', { text: l.reference }); } },
          { key: 'commandeRef', label: 'Commande', nowrap: true, render: function (l) { return el('span.font-mono.text-xs.text-slate-500', { text: l.commandeRef }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (l) { return C.dateFR(l.date); }, render: function (l) { return C.dateFR(l.date); } },
          { key: 'fournisseurNom', label: 'Fournisseur' },
          { key: 'nbLignes', label: 'Articles', align: 'right', value: function (l) { return (l.lignes || []).length; }, render: function (l) { return String((l.lignes || []).length); } },
          {
            key: 'montant', label: 'Montant', align: 'right',
            text: function (l) { return C.money(l.montant, false); },
            render: function (l) { return C.money(l.montant, false); },
          },
          {
            key: 'statutReception', label: 'Réception',
            render: function (l) { return l.statutReception === 'conforme' ? U.badge('Conforme', 'success') : U.badge('Écart constaté', 'danger'); },
          },
        ],
        onRowClick: function (l) {
          U.drawer({
            title: 'Bon de livraison ' + l.reference, subtitle: l.fournisseurNom + ' — ' + C.dateFR(l.date), width: 'max-w-3xl',
            body: el('div.space-y-4', null, [
              U.descList([['N° bordereau', l.reference], ['Commande rattachée', l.commandeRef],
                ['Fournisseur', l.fournisseurNom], ['Date de livraison', C.dateFR(l.date)],
                ['Montant', C.money(l.montant)],
                ['Contrôlé par', (l.controlePar || []).join(', ')],
                ['Réception', l.statutReception === 'conforme' ? U.badge('Conforme', 'success') : U.badge('Écart constaté', 'danger')]]),
              U.card('Articles livrés', K.miniTable([
                { label: 'Article', key: 'produit' },
                { label: 'Commandé', align: 'right', key: 'quantite' },
                { label: 'Livré', align: 'right', key: 'quantiteLivree' },
                {
                  label: 'Écart', align: 'right',
                  render: function (x) {
                    return x.ecart ? el('span.font-semibold.text-danger-600', { text: String(x.ecart) }) : U.badge('OK', 'success');
                  },
                },
                { label: 'Montant', align: 'right', render: function (x) { return C.money(x.montant, false); } },
              ], l.lignes || [])),
            ]),
            footer: [K.btn('Imprimer', { variant: 'primary', icon: 'printer', onclick: function () { etat(l); } })],
          });
        },
        /* Le bordereau se corrige : une date mal saisie, un contrôleur oublié
           ou un écart constaté après coup ne doivent pas obliger à ressaisir. */
        rowActions: function (l) {
          return [K.iconBtn('printer', 'Imprimer', function () { etat(l); })]
            .concat(K.actionsLigne(col, champsLivraison, { entite: 'bon de livraison' })(l));
        },
        actions: [K.creer(col, champsLivraison, {
          titre: 'Nouveau bon de livraison', entite: 'Bon de livraison',
          defauts: function () { return { date: C.iso(AUJ), statutReception: 'conforme' }; },
          transform: function (v) {
            v.reference = C.nextRef('BL-', 5);
            var f = D.FOURNISSEURS.filter(function (x) { return x.code === v.fournisseur; })[0];
            v.fournisseurNom = f ? f.nom : v.fournisseur;
            v.lignes = v.lignes || [];
            v.montant = v.montant || 0;
            v.controlePar = v.controlePar ? [v.controlePar] : [];
            return v;
          },
          apres: function () { global.location.reload(); },
        })],
      }));
      root.appendChild(host);
      return null;

      function champsLivraison() {
        return [
          { name: 'commandeRef', label: 'Commande rattachée', required: true },
          {
            name: 'fournisseur', label: 'Fournisseur', type: 'select', required: true,
            options: optionsFournisseurs(),
          },
          { name: 'date', label: 'Date de livraison', type: 'date', required: true },
          { name: 'montant', label: 'Montant livré (FCFA)', type: 'money', min: 0 },
          {
            name: 'statutReception', label: 'Réception', type: 'select', required: true,
            options: [{ value: 'conforme', label: 'Conforme' }, { value: 'ecart', label: 'Écart constaté' }],
          },
          { name: 'controlePar', label: 'Contrôlé par', col: 'full' },
        ];
      }

      function etat(l) {
        P.etat({
          titre: 'Bon de livraison',
          sousTitre: l.reference + ' — ' + l.fournisseurNom,
          cartouche: [['N° bordereau', l.reference], ['Commande', l.commandeRef],
            ['Fournisseur', l.fournisseurNom], ['Date', C.dateFR(l.date)],
            ['Contrôlé par', (l.controlePar || []).join(', ')],
            ['Réception', l.statutReception === 'conforme' ? 'Conforme' : 'Écart constaté']],
          contenu: P.tableau([
            { label: 'Désignation', key: 'produit' },
            { label: 'Unité', key: 'unite' },
            { label: 'Qté commandée', key: 'quantite', align: 'right' },
            { label: 'Qté livrée', key: 'quantiteLivree', align: 'right' },
            { label: 'Écart', align: 'right', value: function (x) { return x.ecart || 0; } },
            { label: 'Montant', align: 'right', value: function (x) { return C.money(x.montant, false); },
              somme: function (x) { return x.montant || 0; } },
          ], l.lignes || [], { total: true }),
          signatures: [
            { role: 'Le Livreur', mention: 'Fournisseur' },
            { role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' },
            { role: 'Le Contrôleur', mention: 'Vérification contradictoire' },
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * RÉCEPTIONS & CONTRÔLES
   * ======================================================================== */
  global.SIGH.screen('m7-receptions', {
    title: 'Réceptions & contrôles',
    description: 'Réception physique des livraisons, vérification contradictoire par 2 à 3 personnes et entrée en stock gros.',
    regle: 'La vérification est réalisée par <strong>2 à 3 personnes</strong> (processus de la clinique). '
      + 'Après validation, les quantités reçues sont enregistrées au stock gros et le CUMP est recalculé.',
    render: function (root) {
      amorcer();
      var cmds = S.collection('commandes', { module: 'M7', entite: 'BonCommande' });
      var host = el('div.space-y-4');
      var table;

      function aReceptionner() {
        return cmds.active().filter(function (c) { return ['validee', 'transmise'].indexOf(c.statutCommande) !== -1; });
      }

      host.appendChild(U.kpiGrid([
        { label: 'Commandes à réceptionner', value: C.num(aReceptionner().length), icon: 'package-open', tone: 'warning' },
        { label: 'Réceptions réalisées', value: C.num(cmds.active().filter(function (c) { return ['livree', 'soldee'].indexOf(c.statutCommande) !== -1; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Valeur attendue', value: C.money(C.sum(aReceptionner(), 'montant')), icon: 'wallet', tone: 'info' },
        { label: 'Fournisseurs concernés', value: C.num(Object.keys(C.groupBy(aReceptionner(), 'fournisseur')).length), icon: 'truck', tone: 'neutral' },
      ]));

      /* Modèle de référence : la liasse SoBAPS analysée lors du cadrage. */
      var ex = D.PARAM_FISCAL.exemple;
      host.appendChild(U.card('Modèle de référence — liasse SoBAPS du cadrage', el('div.space-y-3', null, [
        K.miniTable([
          { label: 'Étape', key: 'etape' },
          { label: 'Document', render: function (x) { return el('span.font-mono.text-xs.font-semibold', { text: x.num }); } },
          { label: 'Date', key: 'date' },
          { label: 'Montant', align: 'right', key: 'montant' },
        ], [
          { etape: '1. Pro-forma / bon de commande', num: ex.proforma, date: '09/07/2026', montant: C.money(ex.totalTTC, false) },
          { etape: '2. Bordereau de livraison', num: ex.bonLivraison, date: '10/07/2026', montant: C.money(ex.totalTTC, false) },
          { etape: '3. Facture de vente normalisée', num: ex.facture, date: '10/07/2026', montant: C.money(ex.totalTTC, false) },
        ]),
        K.note('Les trois documents portent le <strong>même montant</strong> : c’est ce rapprochement que le système contrôle. '
          + 'La convention de numérotation du fournisseur est <code>' + D.PARAM_FISCAL.numerotation.modele + '</code> — '
          + '<strong>B</strong> pour le bon, <strong>L</strong> pour la livraison, <strong>F</strong> pour la facture.',
          { tone: 'info', icon: 'file-check-2' }),
        K.note('La facture est certifiée <strong>MECeF</strong> : code DGI <code>' + ex.codeMecef + '</code>, '
          + 'total HT ' + C.money(ex.totalHT) + ', AIB 1 % ' + C.money(ex.aib) + ', net à payer ' + C.money(ex.totalTTC) + '. '
          + 'La TVA y est portée à zéro, les produits de santé étant exonérés.', { tone: 'success', icon: 'shield-check' }),
      ])));

      table = U.dataTable({
        title: 'Commandes en attente de réception',
        rows: aReceptionner,
        exportName: 'receptions-attendues', pageSize: 10,
        emptyMessage: 'Aucune commande en attente de réception.',
        columns: [
          { key: 'reference', label: 'N° commande', nowrap: true, render: function (c) { return el('span.font-mono.text-xs.font-semibold', { text: c.reference }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (c) { return C.dateFR(c.date); }, render: function (c) { return C.dateFR(c.date); } },
          { key: 'fournisseurNom', label: 'Fournisseur' },
          { key: 'nbLignes', label: 'Articles', align: 'right', value: function (c) { return (c.lignes || []).length; }, render: function (c) { return String((c.lignes || []).length); } },
          { key: 'montant', label: 'Montant', align: 'right', text: function (c) { return C.money(c.montant, false); }, render: function (c) { return C.money(c.montant, false); } },
          { key: 'valideePar', label: 'Validée par' },
        ],
        rowActions: function (c) {
          return [K.btn('Réceptionner', { size: 'sm', variant: 'primary', icon: 'package-check', onclick: function () { receptionner(c); } })];
        },
      });
      host.appendChild(table);
      root.appendChild(host);
      return null;

      function receptionner(c) {
        var saisies = {};
        var body = el('div.space-y-4');
        body.appendChild(K.note('Saisir les quantités <strong>réellement reçues</strong>. Tout écart entre la commande et la livraison est signalé et pris en compte lors de la livraison suivante.', { tone: 'info' }));

        var f = U.form([
          { name: 'referenceBL', label: 'N° bordereau de livraison', required: true, placeholder: 'ex. 26LNA00026' },
          { name: 'date', label: 'Date de réception', type: 'date', required: true, value: C.iso(AUJ) },
          { name: 'controleur1', label: 'Contrôleur 1', required: true, value: 'MAMAN Zoukanéri' },
          { name: 'controleur2', label: 'Contrôleur 2', required: true, value: 'DIEYABIDI Aïssatou' },
          { name: 'controleur3', label: 'Contrôleur 3 (facultatif)' },
          { name: 'observations', label: 'Observations', type: 'textarea', rows: 2, col: 'full' },
        ], {});
        body.appendChild(f);

        var t = el('table.tbl');
        t.appendChild(el('thead', null, el('tr', null, [
          el('th', { text: 'Article' }), el('th.text-right', { text: 'Commandé' }),
          el('th.text-right', { text: 'Reçu' }), el('th.text-right', { text: 'Écart' }),
        ])));
        var tb = el('tbody');
        (c.lignes || []).forEach(function (l) {
          var tr = el('tr');
          tr.appendChild(el('td', null, el('div', null, [
            el('p.text-sm.text-slate-700', { text: l.produit }),
            el('p.text-xs.text-slate-400', { text: l.unite }),
          ])));
          tr.appendChild(el('td.text-right.num', { text: C.num(l.quantite) }));
          var input = el('input.input.w-24.text-right', { type: 'number', min: 0, value: l.quantite });
          tr.appendChild(el('td.text-right', null, input));
          var ecartCell = el('td.text-right.num', { text: '0' });
          tr.appendChild(ecartCell);
          saisies[l.produitId] = { ligne: l, recu: l.quantite, ecart: 0 };
          input.addEventListener('input', function () {
            var r = Number(input.value) || 0;
            var e = r - l.quantite;
            saisies[l.produitId] = { ligne: l, recu: r, ecart: e };
            ecartCell.textContent = (e > 0 ? '+' : '') + C.num(e);
            ecartCell.className = 'text-right num ' + (e === 0 ? '' : 'font-semibold text-danger-600');
          });
          tb.appendChild(tr);
        });
        t.appendChild(tb);
        body.appendChild(el('div.overflow-x-auto.rounded-lg.border.border-slate-200', null, t));

        var m = U.modal({
          title: 'Réception de la commande ' + c.reference,
          subtitle: c.fournisseurNom + ' — ' + C.money(c.montant),
          size: 'xl', body: body,
          footer: [
            K.btn('Annuler', { onclick: function () { m.close(); } }),
            K.btn('Valider la réception', {
              variant: 'primary', icon: 'package-check',
              onclick: function () {
                var v = f.collect();
                if (!v) { U.toast('Le formulaire comporte des erreurs.', { type: 'error' }); return; }
                var vals = Object.keys(saisies).map(function (k) { return saisies[k]; });
                var ecarts = vals.filter(function (x) { return x.ecart !== 0; });

                var controleurs = [v.controleur1, v.controleur2, v.controleur3].filter(Boolean);
                var bl = S.collection('livraisons', { module: 'M7', entite: 'BonLivraison' }).insert({
                  reference: v.referenceBL, commandeRef: c.reference, date: v.date,
                  fournisseur: c.fournisseur, fournisseurNom: c.fournisseurNom,
                  lignes: vals.map(function (x) {
                    return Object.assign({}, x.ligne, { quantiteLivree: x.recu, ecart: x.ecart });
                  }),
                  montant: C.sum(vals, function (x) { return x.recu * x.ligne.prixUnitaire; }),
                  controlePar: controleurs,
                  statutReception: ecarts.length ? 'ecart' : 'conforme',
                  observations: v.observations,
                });

                /* Entrée en stock gros et recalcul du CUMP */
                var annulations = [];
                vals.forEach(function (x) {
                  if (x.recu <= 0) return;
                  var p = produits().filter(function (pp) { return pp.id === x.ligne.produitId; })[0];
                  if (!p) return;
                  var avant = { stockGros: p.stockGros, stock: p.stock, cump: p.cump };
                  /* CUMP = (valeur du stock existant + valeur de l'entrée) / quantité totale */
                  var nouvelleQte = p.stock + x.recu;
                  var nouveauCump = nouvelleQte > 0
                    ? Math.round((p.stock * p.cump + x.recu * x.ligne.prixUnitaire) / nouvelleQte)
                    : x.ligne.prixUnitaire;
                  S.collection('produits').update(p.id, {
                    stockGros: p.stockGros + x.recu, stock: nouvelleQte, cump: nouveauCump,
                  });
                  var mv = S.collection('mouvements', { module: 'M6', entite: 'MouvementStock' }).insert({
                    reference: C.nextRef('M', 6), date: v.date,
                    produitId: p.id, produit: p.designation,
                    type: 'entree', typeLabel: 'Entrée', quantite: x.recu, stockType: 'gros',
                    justificatif: 'Bon de livraison ' + v.referenceBL,
                    utilisateur: controleurs[0],
                  });
                  annulations.push(function () { S.collection('produits').update(p.id, avant); mv.undo(); });
                });

                var maj = cmds.update(c.id, { statutCommande: 'livree' });
                m.close(); table.refresh();
                U.toast('Réception enregistrée — ' + (ecarts.length ? ecarts.length + ' écart(s) constaté(s).' : 'livraison conforme.'), {
                  type: ecarts.length ? 'warning' : 'success',
                  detail: 'Stock gros mis à jour, CUMP recalculé.',
                  undo: function () {
                    annulations.forEach(function (u) { u(); });
                    bl.undo(); maj.undo(); table.refresh();
                  },
                });
              },
            }),
          ],
        });
      }
    },
  });

  /* ==========================================================================
   * ÉCARTS DE LIVRAISON
   * ======================================================================== */
  global.SIGH.screen('m7-ecarts', {
    title: 'Écarts de livraison',
    description: 'Suivi des manquants entre commande et livraison, avec prise en compte automatique lors de la livraison suivante.',
    regle: 'Écran en lecture seule. Les écarts sont la <strong>différence entre quantités commandées et reçues</strong> : ils se corrigent en modifiant la réception correspondante.',
    render: function (root) {
      amorcer();
      var livs = S.collection('livraisons').active().filter(function (l) { return l.statutReception === 'ecart'; });
      var rows = [];
      livs.forEach(function (l) {
        (l.lignes || []).forEach(function (x) {
          if (x.ecart && x.ecart !== 0) {
            rows.push({
              id: l.id + '-' + x.produitId,
              bl: l.reference, commande: l.commandeRef, date: l.date,
              fournisseur: l.fournisseurNom, produit: x.produit, unite: x.unite,
              commande_qte: x.quantite, livree: x.quantiteLivree, ecart: x.ecart,
              valeur: Math.abs(x.ecart) * x.prixUnitaire,
              regularise: false,
            });
          }
        });
      });

      var host = el('div.space-y-4');
      host.appendChild(U.kpiGrid([
        { label: 'Écarts constatés', value: C.num(rows.length), icon: 'triangle-alert', tone: 'danger' },
        { label: 'Livraisons concernées', value: C.num(livs.length), icon: 'package-x', tone: 'warning' },
        { label: 'Valeur des manquants', value: C.money(C.sum(rows, 'valeur')), icon: 'wallet', tone: 'danger' },
        { label: 'Fournisseurs concernés', value: C.num(Object.keys(C.groupBy(rows, 'fournisseur')).length), icon: 'truck', tone: 'neutral' },
      ]));

      host.appendChild(K.note('Les manquants sont notifiés au fournisseur et <strong>reportés automatiquement sur la livraison suivante</strong>, conformément au processus de la clinique.', { tone: 'warning', icon: 'repeat' }));

      host.appendChild(U.dataTable({
        title: 'Écarts entre commande et livraison', rows: rows, exportName: 'ecarts-livraison', pageSize: 15,
        emptyMessage: 'Aucun écart de livraison constaté.',
        filters: [{ name: 'fournisseur', label: 'Fournisseur', options: Object.keys(C.groupBy(rows, 'fournisseur')).sort() }],
        columns: [
          { key: 'bl', label: 'N° BL', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.bl }); } },
          { key: 'commande', label: 'Commande', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.text-slate-500', { text: r.commande }); } },
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'fournisseur', label: 'Fournisseur' },
          { key: 'produit', label: 'Article' },
          { key: 'commande_qte', label: 'Commandé', align: 'right' },
          { key: 'livree', label: 'Livré', align: 'right' },
          {
            key: 'ecart', label: 'Écart', align: 'right',
            render: function (r) { return el('span.font-semibold.text-danger-600', { text: String(r.ecart) }); },
          },
          {
            key: 'valeur', label: 'Valeur', align: 'right',
            text: function (r) { return C.money(r.valeur, false); },
            render: function (r) { return C.money(r.valeur, false); },
          },
        ],
        actions: [K.btn('Éditer l’état des manquants', {
          size: 'sm', icon: 'printer',
          onclick: function () {
            P.etat({
              titre: 'État des écarts de livraison',
              sousTitre: 'Manquants à reporter sur les prochaines livraisons',
              cartouche: [['Écarts constatés', C.num(rows.length)],
                ['Valeur totale', C.money(C.sum(rows, 'valeur'))],
                ['Date d’édition', C.dateFR(AUJ)], ['Établi par', S.currentUser()]],
              contenu: P.tableau([
                { label: 'N° BL', key: 'bl' }, { label: 'Fournisseur', key: 'fournisseur' },
                { label: 'Article', key: 'produit' },
                { label: 'Commandé', key: 'commande_qte', align: 'right' },
                { label: 'Livré', key: 'livree', align: 'right' },
                { label: 'Écart', key: 'ecart', align: 'right' },
                { label: 'Valeur', align: 'right', value: function (r) { return C.money(r.valeur, false); },
                  somme: function (r) { return r.valeur || 0; } },
              ], rows, { total: true }),
              signatures: [{ role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' },
                { role: 'La Directrice Administrative', nom: 'TAKI Alimatou' }],
            });
          },
        })],
      }));
      root.appendChild(host);
      return null;
    },
  });

  /* ==========================================================================
   * FOURNISSEURS
   * ======================================================================== */
  global.SIGH.screen('m7-fournisseurs', {
    title: 'Fournisseurs',
    description: 'Référentiel des fournisseurs, habilitation pour les retours de produits périmés et historique des commandes.',
    render: K.crud({
      collection: 'fournisseurs', entite: 'fournisseur', entiteP: 'fournisseurs', module: 'M7',
      defaultSort: 'nom',
      source: 'Facture fournisseur SoBAPS et retours CAME identifiés au cadrage.',
      columns: [
        { key: 'code', label: 'Code', nowrap: true, render: function (f) { return el('span.font-mono.text-xs.font-semibold', { text: f.code }); } },
        { key: 'nom', label: 'Raison sociale' },
        { key: 'type', label: 'Type', render: function (f) { return U.badge(f.type, 'navy'); } },
        { key: 'ville', label: 'Ville' },
        { key: 'tel', label: 'Téléphone', nowrap: true },
        { key: 'delai', label: 'Délai (j)', align: 'right' },
        {
          key: 'habilite', label: 'Retours périmés',
          text: function (f) { return f.habilite ? 'Habilité' : 'Non habilité'; },
          render: function (f) { return f.habilite ? U.badge('Habilité', 'success') : el('span.text-xs.text-slate-400', { text: 'Non habilité' }); },
        },
        {
          key: 'commandes', label: 'Commandes', align: 'right', sortable: false,
          value: function (f) { return S.collection('commandes').active().filter(function (c) { return c.fournisseur === f.code; }).length; },
          render: function (f) { return String(S.collection('commandes').active().filter(function (c) { return c.fournisseur === f.code; }).length); },
        },
      ],
      fields: [
        { name: 'code', label: 'Code fournisseur', required: true },
        { name: 'nom', label: 'Raison sociale', required: true, col: 'full' },
        { name: 'type', label: 'Type', type: 'select', required: true, options: ['Grossiste pharmaceutique', 'Centrale d’achat', 'Réactifs & consommables labo', 'Matériel médical', 'Fournitures & entretien', 'Prestataire de services'] },
        { name: 'ville', label: 'Ville' },
        { name: 'tel', label: 'Téléphone', type: 'tel' },
        { name: 'delai', label: 'Délai de livraison (jours)', type: 'number', min: 0 },
        { name: 'habilite', label: 'Habilité pour les retours de produits périmés', type: 'checkbox', col: 'full' },
      ],
      kpis: function (rows) {
        var cmds = S.collection('commandes').active();
        return [
          { label: 'Fournisseurs référencés', value: C.num(rows.length), icon: 'truck', tone: 'navy' },
          { label: 'Habilités aux retours', value: C.num(rows.filter(function (f) { return f.habilite; }).length), icon: 'shield-check', tone: 'success' },
          { label: 'Volume d’achats', value: C.money(C.sum(cmds, 'montant')), icon: 'wallet', tone: 'info' },
          { label: 'Délai moyen', value: (rows.length ? Math.round(C.sum(rows, 'delai') / rows.length) : 0) + ' j', icon: 'clock', tone: 'neutral' },
        ];
      },
      detail: function (f) {
        var cmds = S.collection('commandes').active().filter(function (c) { return c.fournisseur === f.code; });
        return el('div.space-y-4', null, [
          U.descList([['Code', f.code], ['Raison sociale', f.nom], ['Type', f.type],
            ['Adresse', f.adresse || f.ville], ['Téléphone', f.tel],
            ['IFU', f.ifu ? el('span.font-mono', { text: f.ifu }) : '—'],
            ['Délai de livraison', f.delai + ' jours'],
            ['Code client chez le fournisseur', f.codeClient || '—'],
            ['Domiciliation bancaire', f.banque ? f.banque + ' — compte ' + f.compte + ' (clé ' + f.cleRib + ')' : '—'],
            ['Certifications', f.certification || '—'],
            ['Retours de périmés', f.habilite ? U.badge('Habilité', 'success') : U.badge('Non habilité', 'neutral')],
            ['Provenance', f.source ? el('span.text-xs.text-slate-500', { text: f.source }) : '—']]),
          U.kpiGrid([
            { label: 'Commandes passées', value: C.num(cmds.length), icon: 'truck', tone: 'navy' },
            { label: 'Volume cumulé', value: C.money(C.sum(cmds, 'montant')), icon: 'wallet', tone: 'info' },
          ], 'grid-cols-2'),
          cmds.length ? U.card('Historique des commandes', K.miniTable([
            { label: 'N°', render: function (c) { return el('span.font-mono.text-xs', { text: c.reference }); } },
            { label: 'Date', render: function (c) { return C.dateFR(c.date); } },
            { label: 'Montant', align: 'right', render: function (c) { return C.money(c.montant, false); } },
            { label: 'Statut', render: function (c) { return U.badge(c.statutCommande, 'navy'); } },
          ], C.sortBy(cmds, 'date', 'desc').slice(0, 12))) : U.empty('Aucune commande enregistrée.', { icon: 'truck' }),
        ]);
      },
      etat: function (f) {
        var cmds = S.collection('commandes').active().filter(function (c) { return c.fournisseur === f.code; });
        P.etat({
          titre: 'Fiche fournisseur',
          sousTitre: f.nom,
          cartouche: [['Code', f.code], ['Raison sociale', f.nom], ['Type', f.type],
            ['Ville', f.ville], ['Téléphone', f.tel], ['Délai', f.delai + ' jours']],
          contenu: cmds.length
            ? P.tableau([
              { label: 'N° commande', key: 'reference' },
              { label: 'Date', value: function (c) { return C.dateFR(c.date); } },
              { label: 'Articles', value: function (c) { return (c.lignes || []).length; }, align: 'right' },
              { label: 'Montant', align: 'right', value: function (c) { return C.money(c.montant, false); },
                somme: function (c) { return c.montant || 0; } },
              { label: 'Statut', key: 'statutCommande' },
            ], C.sortBy(cmds, 'date', 'desc'), { total: true })
            : el('p.italic', { text: 'Aucune commande enregistrée auprès de ce fournisseur.' }),
          signatures: [{ role: 'Le Gestionnaire de Stock', nom: 'MAMAN Zoukanéri' }],
        });
      },
    }),
  });

  /* ==========================================================================
   * FACTURES FOURNISSEURS
   * ======================================================================== */
  global.SIGH.screen('m7-factures-fournisseurs', {
    title: 'Factures fournisseurs',
    description: 'Rapprochement facture pro-forma → validation → facture normalisée → bordereau de livraison.',
    regle: 'Le système détecte les incohérences <strong>commande ≠ livraison</strong> et <strong>livraison ≠ facture</strong> et génère une anomalie.',
    render: function (root) {
      amorcer();
      /* Semées au socle depuis le 22/09/2026 — elles pèsent sur le BFR. */
      amorcer();
      var col = S.collection('facturesFournisseurs', { module: 'M7', entite: 'FactureFournisseur' });

      var rows = col.active();
      var host = el('div.space-y-4');
      var anomalies = rows.filter(function (r) { return r.statutRappro === 'anomalie'; });

      if (anomalies.length) {
        host.appendChild(K.note('<strong>' + anomalies.length + ' anomalie(s) de rapprochement</strong> détectée(s) : le montant facturé diffère du montant livré. Vérification requise avant règlement.', { tone: 'danger', icon: 'triangle-alert' }));
      }

      host.appendChild(U.kpiGrid([
        { label: 'Factures fournisseurs', value: C.num(rows.length), icon: 'file-text', tone: 'navy' },
        { label: 'Rapprochées', value: C.num(rows.filter(function (r) { return r.statutRappro === 'rapproche'; }).length), icon: 'check-circle-2', tone: 'success' },
        { label: 'Anomalies', value: C.num(anomalies.length), icon: 'triangle-alert', tone: 'danger' },
        { label: 'Impayées', value: C.money(C.sum(rows.filter(function (r) { return r.statutPaiement !== 'payee'; }), 'montantFacture')), icon: 'wallet', tone: 'warning' },
      ]));

      host.appendChild(U.dataTable({
        title: 'Factures fournisseurs', rows: rows, exportName: 'factures-fournisseurs', pageSize: 12,
        rowActions: K.actionsLigne(col, [
          { name: 'numero', label: 'N° de facture', required: true },
          { name: 'date', label: 'Date de facture', type: 'date', required: true },
          { name: 'fournisseur', label: 'Fournisseur', required: true },
          { name: 'montant', label: 'Montant (FCFA)', type: 'number', min: 0 },
          { name: 'echeance', label: 'Échéance', type: 'date' },
          {
            /* « payée » et non « soldée » : le registre, son filtre et son
               indicateur comptent sur `payee`. Une pièce éditée à « soldée »
               reparaissait donc dans les impayées — et pèse désormais sur le
               BFR, qui lit la même colonne (22/09/2026). */
            name: 'statutPaiement', label: 'Règlement', type: 'select',
            options: [{ value: 'impayee', label: 'Impayée' }, { value: 'partielle', label: 'Partielle' }, { value: 'payee', label: 'Payée' }],
          },
        ]),
        defaultSort: 'date', defaultDir: 'desc',
        filters: [
          { name: 'statutRappro', label: 'Rapprochement', options: [{ value: 'rapproche', label: 'Rapprochée' }, { value: 'anomalie', label: 'Anomalie' }] },
          { name: 'statutPaiement', label: 'Règlement', options: [{ value: 'payee', label: 'Payée' }, { value: 'partielle', label: 'Partielle' }, { value: 'impayee', label: 'Impayée' }] },
          { name: 'fournisseur', label: 'Fournisseur', options: optionsFournisseurs() },
        ],
        columns: [
          { key: 'reference', label: 'N° interne', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { key: 'numeroFournisseur', label: 'N° fournisseur', nowrap: true },
          { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
          { key: 'fournisseurNom', label: 'Fournisseur' },
          { key: 'blRef', label: 'BL rattaché', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.text-slate-500', { text: r.blRef }); } },
          {
            key: 'montantLivraison', label: 'Montant livré', align: 'right',
            text: function (r) { return C.money(r.montantLivraison, false); },
            render: function (r) { return C.money(r.montantLivraison, false); },
          },
          {
            key: 'montantFacture', label: 'Montant facturé', align: 'right',
            text: function (r) { return C.money(r.montantFacture, false); },
            render: function (r) { return el('span.font-semibold', { text: C.money(r.montantFacture, false) }); },
          },
          {
            key: 'ecart', label: 'Écart', align: 'right',
            text: function (r) { return C.money(r.ecart, false); },
            render: function (r) {
              return r.ecart === 0 ? U.badge('Conforme', 'success')
                : el('span.font-semibold.text-danger-600', { text: (r.ecart > 0 ? '+' : '') + C.money(r.ecart, false) });
            },
          },
          { key: 'echeance', label: 'Échéance', nowrap: true, text: function (r) { return C.dateFR(r.echeance); }, render: function (r) { return C.dateFR(r.echeance); } },
          {
            key: 'statutPaiement', label: 'Règlement',
            render: function (r) {
              var m = { payee: ['Payée', 'success'], partielle: ['Partielle', 'warning'], impayee: ['Impayée', 'danger'] };
              return U.badge(m[r.statutPaiement][0], m[r.statutPaiement][1]);
            },
          },
        ],
        onRowClick: function (r) {
          U.drawer({
            title: 'Facture ' + r.reference, subtitle: r.fournisseurNom + ' — ' + C.dateFR(r.date),
            body: el('div.space-y-4', null, [
              U.descList([['Référence interne', r.reference], ['N° fournisseur', r.numeroFournisseur],
                ['Fournisseur', r.fournisseurNom], ['Date', C.dateFR(r.date)],
                ['Commande', r.commandeRef], ['Bordereau de livraison', r.blRef],
                ['Montant livré', C.money(r.montantLivraison)], ['Montant facturé', C.money(r.montantFacture)],
                ['Écart', r.ecart === 0 ? U.badge('Conforme', 'success') : U.badge(C.money(r.ecart), 'danger')],
                ['Échéance', C.dateFR(r.echeance)]]),
              r.statutRappro === 'anomalie'
                ? K.note('<strong>Anomalie de rapprochement.</strong> Le montant facturé ne correspond pas au montant effectivement livré. '
                  + 'Le règlement doit être suspendu jusqu’à régularisation avec le fournisseur.', { tone: 'danger', icon: 'triangle-alert' })
                : K.note('Rapprochement conforme : commande, livraison et facture concordent.', { tone: 'success', icon: 'check-circle-2' }),
            ]),
          });
        },
      }));
      root.appendChild(host);
      return null;
    },
  });
  /* ==========================================================================
   * PV DE RÉCEPTION — CONSOMMABLES ET RÉACTIFS (phase 5, cible Instructions)
   * --------------------------------------------------------------------------
   * Le procès-verbal CONSTATE la réception : ce qui a été commandé, ce qui est
   * arrivé, l'état des lots, les réserves — et il se SIGNE à trois (magasinier,
   * DAF, représentant du fournisseur). Deux écrans, une mécanique : les
   * réactifs de laboratoire n'appellent pas les mêmes contrôles (chaîne du
   * froid, lots, péremptions courtes) que les consommables de soins.
   * ======================================================================== */
  function colPV() {
    return S.collection('pvReceptions', { module: 'M7', entite: 'PV de réception', prefix: 'PVR' });
  }
  function estReactif(produitId) {
    var pr = produits().filter(function (x) { return x.id === produitId; })[0];
    return !!pr && (pr.categorie === 'reactif' || pr.categorie === 'conso_labo');
  }
  function lignesDeNature(liv, nature) {
    return (liv.lignes || []).filter(function (l) {
      var reactif = estReactif(l.produitId);
      return nature === 'reactifs' ? reactif : !reactif;
    });
  }

  function amorcerPV() {
    var col = colPV();
    if (col.all().length) return;
    var rnd = C.seeded(1517);
    var livs = S.collection('livraisons').active();
    var n = 0;

    function poser(nature, lignes, meta) {
      n++;
      var reserves = lignes.some(function (l) { return (l.ecart || 0) < 0; });
      col.all().push({
        id: 'PVR' + C.pad(n, 4), statut: 'actif',
        reference: 'PV-' + (nature === 'reactifs' ? 'REA' : 'CON') + '-2026-' + C.pad(n, 4),
        nature: nature,
        date: meta.date,
        livraisonRef: meta.reference || null, commandeRef: meta.commandeRef || null,
        fournisseurNom: meta.fournisseurNom,
        lignes: lignes,
        chaineFroid: nature === 'reactifs' ? rnd() > 0.1 : null,
        conclusion: reserves ? 'Conforme avec réserves' : 'Conforme',
        reserves: reserves ? 'Écarts de quantité constatés sur ' + lignes.filter(function (l) { return (l.ecart || 0) < 0; }).length + ' ligne(s).' : '',
        magasinier: 'MAMAN Zoukanéri',
        representantFournisseur: 'Livreur ' + (meta.fournisseurNom || ''),
      });
    }

    /* CHAQUE NATURE A SON REGISTRE : on balaie TOUTES les livraisons par
       nature — se limiter aux huit premières laissait le registre des
       réactifs vide quand le tirage du jeu n'y avait mis aucun réactif. */
    ['consommables', 'reactifs'].forEach(function (nature) {
      var pris = 0;
      livs.forEach(function (liv) {
        if (pris >= 4) return;
        var lignes = lignesDeNature(liv, nature);
        if (!lignes.length) return;
        pris++;
        poser(nature, lignes.map(function (l) {
          return { produit: l.produit, unite: l.unite,
            commandee: l.quantite, livree: l.quantiteLivree, ecart: l.ecart || 0 };
        }), liv);
      });
      /* Aucune livraison du jeu ne porte cette nature : le PV de
         démonstration est fabriqué depuis le catalogue — un registre vide
         ferait croire que l'écran ne fonctionne pas. */
      if (!pris) {
        var refs = produits().filter(function (p) {
          var reactif = p.categorie === 'reactif' || p.categorie === 'conso_labo';
          return nature === 'reactifs' ? reactif : !reactif;
        }).slice(0, 5);
        if (refs.length) {
          var f = C.pick(rnd, D.FOURNISSEURS);
          poser(nature, refs.map(function (p) {
            var q = C.between(rnd, 10, 60);
            return { produit: p.designation, unite: p.unite, commandee: q, livree: q, ecart: 0 };
          }), { date: C.iso(C.addDays(AUJ, -C.between(rnd, 3, 40))), fournisseurNom: f.nom });
        }
      }
    });
    S.save();
  }

  function ecranPV(nature, titre, description, regle) {
    return {
      title: titre,
      description: description,
      regle: regle,
      render: function (root) {
        amorcer(); amorcerPV();
        var vue = el('div.space-y-4');
        root.appendChild(vue);
        afficher();
        return null;

        function rows() {
          return colPV().active().filter(function (r) { return r.nature === nature; });
        }

        function afficher() {
          C.clear(vue);
          var r2 = rows();
          var reserves = r2.filter(function (r) { return r.conclusion === 'Conforme avec réserves'; });
          var nonConformes = r2.filter(function (r) { return r.conclusion === 'Non conforme'; });

          vue.appendChild(U.kpiGrid([
            { label: 'PV établis', value: C.num(r2.length), icon: 'clipboard-check', tone: 'navy' },
            { label: 'Conformes', value: C.num(r2.filter(function (r) { return r.conclusion === 'Conforme'; }).length), icon: 'check-circle-2', tone: 'success' },
            { label: 'Avec réserves', value: C.num(reserves.length), icon: 'triangle-alert', tone: reserves.length ? 'warning' : 'neutral' },
            { label: 'Non conformes', value: C.num(nonConformes.length), icon: 'x-circle', tone: nonConformes.length ? 'danger' : 'neutral' },
          ]));

          vue.appendChild(U.dataTable({
            title: 'Registre des procès-verbaux',
            rows: r2, exportName: 'pv-reception-' + nature, pageSize: 12, searchable: true,
            defaultSort: 'date', defaultDir: 'desc',
            emptyMessage: 'Aucun PV établi.',
            emptyHint: 'Un PV se dresse à la réception d\u2019une livraison — bouton « Nouveau PV ».',
            actions: [K.commande('Nouveau PV', {
              variant: 'primary', size: 'sm', icon: 'plus', onclick: nouveau,
            })].filter(Boolean),
            columns: [
              { key: 'reference', label: 'N° PV', nowrap: true, render: function (r) { return el('span.font-mono.text-xs.font-semibold', { text: r.reference }); } },
              { key: 'date', label: 'Date', nowrap: true, text: function (r) { return C.dateFR(r.date); }, render: function (r) { return C.dateFR(r.date); } },
              { key: 'livraisonRef', label: 'Bon de livraison', nowrap: true, render: function (r) { return el('span.font-mono.text-xs', { text: r.livraisonRef }); } },
              { key: 'fournisseurNom', label: 'Fournisseur' },
              { key: 'lignes', label: 'Lignes', align: 'right', value: function (r) { return (r.lignes || []).length; }, render: function (r) { return String((r.lignes || []).length); } },
              {
                key: 'conclusion', label: 'Conclusion',
                render: function (r) {
                  var ton = r.conclusion === 'Conforme' ? 'success'
                    : (r.conclusion === 'Non conforme' ? 'danger' : 'warning');
                  return U.badge(r.conclusion, ton);
                },
              },
              { key: 'magasinier', label: 'Magasinier' },
            ],
            onRowClick: consulter,
            rowActions: function (r) {
              return [
                K.iconBtn('eye', 'Consulter', function () { consulter(r); }),
                K.iconBtn('printer', 'Imprimer le PV', function () { imprimer(r); }),
              ];
            },
          }));
          U.icons(vue);
        }

        function nouveau() {
          var livs = C.sortBy(S.collection('livraisons').active().filter(function (l) {
            return lignesDeNature(l, nature).length > 0;
          }), 'date', 'desc');
          if (!livs.length) { U.toast('Aucune livraison ne porte de ' + (nature === 'reactifs' ? 'réactifs' : 'consommables') + '.', { type: 'warning' }); return; }

          var f = U.form([
            { name: 'livraisonRef', label: 'Bon de livraison', type: 'select', required: true, col: 'full',
              options: livs.map(function (l) {
                return { value: l.reference, label: l.reference + ' — ' + (l.fournisseurNom || ''),
                  detail: C.dateFR(l.date) + ' · ' + lignesDeNature(l, nature).length + ' ligne(s) concernée(s)' };
              }) },
            { name: 'date', label: 'Date du PV', type: 'date', required: true, value: C.iso(AUJ) },
          ].concat(nature === 'reactifs' ? [
            { name: 'chaineFroid', label: 'Chaîne du froid respectée à l\u2019arrivée', type: 'checkbox',
              help: 'Un réactif arrivé hors température se refuse — le PV en fait foi.' },
          ] : []).concat([
            { name: 'conclusion', label: 'Conclusion du contrôle', type: 'select', required: true,
              options: ['Conforme', 'Conforme avec réserves', 'Non conforme'] },
            { name: 'reserves', label: 'Réserves et observations', type: 'textarea', rows: 3, col: 'full',
              help: 'Obligatoires dès que la conclusion n\u2019est pas « Conforme » : une réserve muette ne protège personne.' },
            { name: 'representantFournisseur', label: 'Représentant du fournisseur (nom)', required: true },
          ]), { conclusion: 'Conforme', chaineFroid: true });

          var m = U.modal({
            title: 'Nouveau PV de réception — ' + (nature === 'reactifs' ? 'réactifs' : 'consommables'),
            size: 'lg', body: f,
            footer: [
              K.btn('Annuler', { onclick: function () { m.close(); } }),
              K.btn('Établir le PV', {
                variant: 'primary', icon: 'clipboard-check',
                onclick: function () {
                  var v = f.collect(); if (!v) return;
                  if (v.conclusion !== 'Conforme' && !(v.reserves || '').trim()) {
                    U.toast('Une conclusion avec réserves ou non conforme EXIGE ses réserves écrites.', { type: 'error' });
                    return;
                  }
                  var liv = livs.filter(function (l) { return l.reference === v.livraisonRef; })[0];
                  var lignes = lignesDeNature(liv, nature);
                  var sess = S.session() || {};
                  var res = colPV().insert({
                    reference: C.nextRef('PV-' + (nature === 'reactifs' ? 'REA' : 'CON') + '-2026-', 4),
                    nature: nature,
                    date: v.date,
                    livraisonRef: liv.reference, commandeRef: liv.commandeRef,
                    fournisseurNom: liv.fournisseurNom,
                    lignes: lignes.map(function (l) {
                      return { produit: l.produit, unite: l.unite,
                        commandee: l.quantite, livree: l.quantiteLivree, ecart: l.ecart || 0 };
                    }),
                    chaineFroid: nature === 'reactifs' ? !!v.chaineFroid : null,
                    conclusion: v.conclusion,
                    reserves: v.reserves || '',
                    magasinier: sess.nomComplet || 'MAMAN Zoukanéri',
                    representantFournisseur: v.representantFournisseur,
                  });
                  m.close(); afficher();
                  U.toast('PV ' + res.record.reference + ' établi.', {
                    type: 'success', detail: v.conclusion,
                    undo: function () { res.undo(); afficher(); },
                  });
                  imprimer(res.record);
                },
              }),
            ],
          });
        }

        function consulter(r) {
          U.drawer({
            title: 'PV ' + r.reference,
            /* Un PV de démonstration fabriqué depuis le catalogue ne porte pas
               de bon de livraison : le sous-titre affichait « undefined ». */
            subtitle: [r.livraisonRef, r.fournisseurNom].filter(Boolean).join(' — '),
            body: el('div.space-y-4', null, [
              U.descList([
                ['Référence', r.reference], ['Date', C.dateFR(r.date)],
                ['Bon de livraison', r.livraisonRef], ['Commande', r.commandeRef || '—'],
                ['Fournisseur', r.fournisseurNom || '—'],
                nature === 'reactifs' ? ['Chaîne du froid', r.chaineFroid ? 'Respectée' : 'ROMPUE'] : null,
                ['Conclusion', r.conclusion],
                ['Magasinier', r.magasinier], ['Représentant fournisseur', r.representantFournisseur || '—'],
              ].filter(Boolean)),
              K.section('Lignes contrôlées',
                K.miniTable(['Article', 'Commandée', 'Livrée', 'Écart'],
                  (r.lignes || []).map(function (l) {
                    return [l.produit, String(l.commandee), String(l.livree),
                      (l.ecart || 0) === 0 ? '—' : String(l.ecart)];
                  }))),
              /* Les réserves sont un texte SAISI : elles passent par le canal
                 échappé de K.note (texteEnrichi), jamais concaténées en HTML. */
              r.reserves ? K.note('Réserves : ' + r.reserves, { tone: 'warning', icon: 'triangle-alert' }) : null,
            ].filter(Boolean)),
            footer: [K.btn('Imprimer le PV', { icon: 'printer', onclick: function () { imprimer(r); } })],
          });
        }

        function imprimer(r) {
          P.etat({
            titre: 'PROCÈS-VERBAL DE RÉCEPTION',
            sousTitre: (nature === 'reactifs' ? 'Réactifs et consommables de laboratoire' : 'Consommables') + ' — ' + r.reference,
            cartouche: [['N° PV', r.reference], ['Date', C.dateFR(r.date)],
              ['Bon de livraison', r.livraisonRef], ['Commande', r.commandeRef || '—'],
              ['Fournisseur', r.fournisseurNom || '—'], ['Conclusion', r.conclusion]],
            contenu: el('div.space-y-3', null, [
              P.tableau([
                { label: 'Article', value: function (l) { return l.produit; } },
                { label: 'Unité', value: function (l) { return l.unite || '—'; } },
                { label: 'Qté commandée', align: 'right', value: function (l) { return String(l.commandee); },
                  somme: function (l) { return l.commandee; } },
                { label: 'Qté livrée', align: 'right', value: function (l) { return String(l.livree); },
                  somme: function (l) { return l.livree; } },
                { label: 'Écart', align: 'right', value: function (l) { return (l.ecart || 0) === 0 ? '' : String(l.ecart); } },
              ], r.lignes || []),
              nature === 'reactifs' ? el('p.text-\[10px\]', { text: 'Chaîne du froid à l\u2019arrivée : '
                + (r.chaineFroid ? 'respectée.' : 'ROMPUE — réserve majeure.') }) : null,
              r.reserves ? el('p.text-\[10px\]', { text: 'Réserves : ' + r.reserves }) : null,
              el('p.mt-3.text-\[10px\].italic', { text: 'Le présent procès-verbal est établi '
                + 'contradictoirement entre la clinique et le représentant du fournisseur.' }),
            ].filter(Boolean)),
            signatures: [
              { role: 'Le Magasinier', nom: r.magasinier },
              { role: 'La Directrice de l\u2019Administration et des Finances', nom: 'TAKI Alimatou' },
              { role: 'Le représentant du fournisseur', nom: r.representantFournisseur || '' },
            ],
          });
        }
      },
    };
  }

  global.SIGH.screen('m7-pv-reception-consommables', ecranPV('consommables',
    'PV de réception — consommables',
    'Procès-verbaux de réception des consommables : quantités, écarts, réserves et signatures.',
    'Le PV <strong>constate</strong> la réception et se signe à trois — magasinier, DAF, représentant du '
      + 'fournisseur. Une conclusion « avec réserves » ou « non conforme » <strong>exige ses réserves '
      + 'écrites</strong> : une réserve muette ne protège personne.'));

  global.SIGH.screen('m7-pv-reception-reactifs', ecranPV('reactifs',
    'PV de réception — réactifs',
    'Procès-verbaux de réception des réactifs de laboratoire : chaîne du froid, lots, écarts, réserves.',
    'Les réactifs appellent un contrôle propre : la <strong>chaîne du froid</strong> à l\u2019arrivée fait '
      + 'partie du PV — un réactif arrivé hors température se refuse, et le PV en fait foi devant le '
      + 'fournisseur. Signature à trois, comme pour les consommables.'));

})(window);
