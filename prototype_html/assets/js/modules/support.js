/* =============================================================================
 * SUP — Aide, À propos et contact éditeur
 * -----------------------------------------------------------------------------
 * Deux écrans hors ruban, atteints depuis le menu profil de la barre
 * supérieure : la documentation d'usage (présentation, modules, FAQ) et le
 * formulaire de contact de l'éditeur (message, signalement d'anomalie).
 * Les demandes envoyées sont conservées comme toute autre donnée : elles sont
 * journalisées (RG-12) et restent consultables.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store,
      N = global.SIGH.nav, K = global.SIGH.kit;
  var el = C.el;
  var AUJ = C.aujourdhui();   /* l’horloge réelle — vague 68 */

  /* --- Coordonnées de l'éditeur ------------------------------------------- */
  var EDITEUR = {
    auteur: 'Dr MASSENON Rhodes',
    emails: ['rarhodes06@gmail.com', 'contact@massenonrhodes.com'],
    telephone: '+229 01 51 33 50 40',
    horaires: 'Lundi au vendredi, 8h – 17h (GMT)',
    version: 'Prototype v1.0 — août 2026',
  };

  /* --- Ce que fait chaque module, en une phrase ---------------------------- */
  var RESUMES = {
    DASH: 'Un tableau de bord par profil : indicateurs, alertes et accès rapides propres au poste de travail.',
    PIL: 'La lecture transversale de l’activité : synthèse de la Direction, statistiques et tableau croisé dynamique.',
    M1: 'Dossier patient unique : identité, antécédents, allergies, documents numérisés et historique complet.',
    M2: 'Agenda, rendez-vous, consultations, ordonnances et soins à domicile, en remplacement des registres papier.',
    M3: 'Admissions, plan des lits, feuilles de température et de soins, sorties avec les signatures exigées.',
    M4: 'Suivi de grossesse, accouchements, registres officiels des naissances et des décès.',
    M5: 'Demandes d’analyses, saisie des résultats, réactifs et banque de sang, du prélèvement au compte rendu.',
    M6: 'Pharmacie et magasin : produits, lots, péremptions FEFO, mouvements, inventaires et dispensation.',
    M7: 'Expression des besoins, commandes validées par la Direction, livraisons, réceptions et factures fournisseurs.',
    M8: 'Facturation, encaissements, reliquats et état de caisse journalier.',
    M9: 'Compagnies partenaires, cartes d’assurés, prises en charge, factures mensuelles et créances.',
    MECEF: 'Facture normalisée : structure fiscale, transmission, avoirs et journal des transactions certifiées.',
    M12: 'Comptabilité SYSCOHADA : plan comptable, journaux, écritures équilibrées, balance et états financiers.',
    M10: 'Personnel, contrats, planning des gardes, présences, congés, évaluations et primes.',
    M11: 'Calcul de la paie, bulletins, cotisations CNSS / ITS / VPS et validation par la Direction.',
    M13: 'Courriers, réunions, plan annuel de travail, notes de service et interventions de l’ambulance.',
    GED: 'Bibliothèque documentaire, circuit de validation et archivage avec durée de conservation.',
    RAP: 'Bibliothèque des états officiels, générateur de rapports et historique des éditions.',
    M14: 'Utilisateurs, rôles et permissions, sessions actives, journal d’audit et sauvegardes.',
    CFG: 'Organigramme, papier à en-tête, référentiel tarifaire, règles métier et paramètres fiscaux.',
  };

  /* --- Questions les plus fréquentes -------------------------------------- */
  var FAQ = [
    {
      q: 'Comment est attribué le numéro de dossier d’un patient ?',
      r: 'Automatiquement, au format <code>CNT/[n° d’ordre]/[année]</code> — par exemple <code>CNT/530/25</code>. '
        + 'Le champ est verrouillé à la saisie : il ne peut être ni choisi ni modifié après création (règle RG-01). '
        + 'C’est cette unicité qui permet de retrouver un dossier partout dans l’application.',
    },
    {
      q: 'Pourquoi le prix de vente d’un médicament est-il égal à son prix d’achat ?',
      r: 'C’est la règle RG-02 arrêtée par la clinique : les médicaments sont facturés au prix d’achat, sans marge. '
        + 'Toute exception doit être validée par la Direction et reste tracée. Le référentiel tarifaire signale '
        + 'immédiatement une ligne dont le prix de vente s’écarterait du prix d’achat.',
    },
    {
      q: 'Un patient présente une carte d’assurance expirée : que fait le système ?',
      r: 'La prise en charge n’est pas appliquée et la facturation devient intégrale au patient (règle RG-09). '
        + 'L’écran de facturation affiche un bandeau rouge rappelant la date d’expiration ; il suffit de mettre à jour '
        + 'la validité dans le dossier du patient pour rétablir la couverture.',
    },
    {
      q: 'Pourquoi une sortie de stock est-elle refusée ?',
      r: 'Parce que la quantité demandée dépasse le stock disponible : le stock ne peut jamais devenir négatif '
        + '(règle RG-03). Vérifier l’état réel du rayon, puis régulariser par un inventaire ou une réception.',
    },
    {
      q: 'Comment obtenir un document en PDF ?',
      r: 'Chaque état dispose d’un bouton <strong>Imprimer</strong> qui ouvre l’aperçu au papier à en-tête de la '
        + 'clinique, puis la boîte d’impression du navigateur. Y choisir la destination '
        + '<strong>« Enregistrer au format PDF »</strong>. Le catalogue complet se trouve dans '
        + '<em>Rapports & Impression → Bibliothèque des états</em>.',
    },
    {
      q: 'J’ai supprimé un enregistrement par erreur : est-il perdu ?',
      r: 'Non. La suppression physique n’existe pas (règle RG-14) : l’enregistrement est <strong>archivé</strong>. '
        + 'Il reste consultable dans l’onglet « Archivés » de son écran et peut être restauré. Juste après '
        + 'l’opération, le message de confirmation propose d’ailleurs « Annuler ».',
    },
    {
      q: 'Pourquoi certains écrans ne proposent-ils pas de modification ?',
      r: 'Parce qu’ils affichent un <strong>état calculé</strong> ou une <strong>preuve</strong> : grand livre, '
        + 'balance, état de caisse, alertes de stock, journal d’audit, journal MECeF. Les modifier reviendrait à '
        + 'falsifier un résultat. Chacun de ces écrans indique où corriger la donnée d’origine.',
    },
    {
      q: 'Qui a accès à quoi ?',
      r: 'Le périmètre dépend du profil de connexion (règle RG-13) : le médical est réservé aux soignants habilités, '
        + 'le financier et les ressources humaines aux profils comptables et RH. Le menu lui-même est filtré : un '
        + 'écran interdit n’apparaît pas. Toute action reste journalisée avec son auteur (RG-12).',
    },
    {
      q: 'Mes saisies disparaissent après un rechargement de la page.',
      r: 'C’est le comportement du prototype ouvert par double-clic : le navigateur refuse alors l’accès au stockage '
        + 'local et les données ne vivent qu’en mémoire. Servir le dossier (<code>npx serve .</code>) pour les '
        + 'conserver. La version définitive s’appuiera sur une base PostgreSQL installée sur le serveur.',
    },
  ];

  function collectionSupport() {
    return S.collection('support', { module: 'SUP', entite: 'DemandeSupport' });
  }

  function optionsModules() {
    var out = [];
    N.NAV.forEach(function (dom) {
      dom.modules.forEach(function (mod) {
        out.push({ value: mod.code, label: mod.code + ' — ' + mod.label, icon: mod.icon });
      });
    });
    out.push({ value: 'AUTRE', label: 'Autre / je ne sais pas', icon: 'circle-help' });
    return out;
  }

  /* ==========================================================================
   * CONTACTEZ L'ÉDITEUR
   * ======================================================================== */
  global.SIGH.screen('contact-editeur', {
    title: 'Contactez l’éditeur',
    description: 'Assistance technique, suggestions d’amélioration et signalement d’anomalies.',
    render: function (root) {
      var col = collectionSupport();
      var host = el('div.grid.gap-4.lg\\:grid-cols-3');
      var principal = el('div.space-y-4.lg\\:col-span-2');
      var lateral = el('div.space-y-4');
      var listeHost = el('div');

      /* --- Envoyer un message ---------------------------------------------- */
      var fMessage = U.form([
        {
          name: 'objet', label: 'Objet', required: true, col: 'full',
          placeholder: 'ex. : question sur le module Comptabilité',
        },
        {
          name: 'message', label: 'Message', type: 'textarea', rows: 5, required: true, col: 'full',
          placeholder: 'Décrivez votre question ou votre suggestion…',
        },
      ], {});

      principal.appendChild(U.card('Envoyer un message', el('div.space-y-3', null, [
        fMessage,
        el('div.flex.justify-end', null,
          K.btn('Envoyer le message', {
            variant: 'primary', icon: 'send',
            onclick: function () {
              var v = fMessage.collect();
              if (!v) { U.toast('Renseigner l’objet et le message.', { type: 'error' }); return; }
              enregistrer({
                type: 'message', objet: v.objet, description: v.message,
                module: null, etapes: null, capture: null,
              });
              fMessage.controls.objet.value = '';
              fMessage.controls.message.value = '';
            },
          })),
      ])));

      /* --- Signaler une anomalie ------------------------------------------- */
      var capture = el('input.hidden', { type: 'file', accept: 'image/*' });
      var nomCapture = el('p.text-xs.text-slate-500', { text: 'Aucune capture jointe.' });
      capture.addEventListener('change', function () {
        var f = capture.files && capture.files[0];
        nomCapture.textContent = f ? 'Pièce jointe : ' + f.name : 'Aucune capture jointe.';
      });

      var fBug = U.form([
        {
          name: 'module', label: 'Module concerné', type: 'select', required: true, col: 'full',
          options: optionsModules(), placeholder: '— Sélectionner —',
          searchPlaceholder: 'Code ou nom du module…',
        },
        {
          name: 'description', label: 'Description du problème', type: 'textarea', rows: 4, required: true, col: 'full',
          placeholder: 'Que s’est-il passé ? Qu’attendiez-vous à la place ?',
        },
        {
          name: 'etapes', label: 'Étapes pour reproduire', type: 'textarea', rows: 3, col: 'full',
          placeholder: '1. Aller dans…   2. Cliquer sur…   3. Le message suivant apparaît…',
        },
      ], {});

      principal.appendChild(U.card('Signaler une anomalie', el('div.space-y-3', null, [
        fBug,
        el('div.rounded-lg.border.border-dashed.border-slate-300.bg-slate-50.p-3', null, [
          el('p.mb-2.text-xs.font-medium.text-slate-600', { text: 'Capture d’écran (facultative)' }),
          el('div.flex.flex-wrap.items-center.gap-3', null, [
            K.btn('Joindre une capture d’écran', {
              icon: 'image-plus', size: 'sm',
              onclick: function () { capture.click(); },
            }),
            nomCapture,
          ]),
          capture,
        ]),
        el('div.flex.justify-end', null,
          K.btn('Signaler l’anomalie', {
            variant: 'danger', icon: 'bug',
            onclick: function () {
              var v = fBug.collect();
              if (!v) { U.toast('Indiquer le module et décrire le problème.', { type: 'error' }); return; }
              var f = capture.files && capture.files[0];
              enregistrer({
                type: 'anomalie',
                objet: 'Anomalie — ' + v.module,
                module: v.module, description: v.description, etapes: v.etapes,
                capture: f ? f.name : null,
              });
              fBug.controls.description.value = '';
              fBug.controls.etapes.value = '';
              capture.value = '';
              nomCapture.textContent = 'Aucune capture jointe.';
            },
          })),
      ])));

      principal.appendChild(listeHost);

      /* --- Coordonnées de l'éditeur ---------------------------------------- */
      var coord = el('div.space-y-3');
      coord.appendChild(el('div.flex.items-center.gap-3', null, [
        el('span.grid.h-11.w-11.shrink-0.place-items-center.rounded-full.bg-navy-900.text-sm.font-semibold.text-white',
          { text: C.initials(EDITEUR.auteur) }),
        el('div.min-w-0', null, [
          el('p.text-sm.font-semibold.text-slate-900', { text: EDITEUR.auteur }),
          el('p.text-xs.text-slate-500', { text: 'Éditeur du logiciel SIGH-CNT' }),
        ]),
      ]));
      [['mail', EDITEUR.emails.join('   ·   ')],
       ['phone', EDITEUR.telephone],
       ['clock', EDITEUR.horaires]].forEach(function (l) {
        coord.appendChild(el('div.flex.items-start.gap-2\\.5', null, [
          el('span.mt-0\\.5.shrink-0.text-slate-400', null, C.icon(l[0], 'h-4 w-4')),
          el('p.min-w-0.break-words.text-sm.text-slate-700', { text: l[1] }),
        ]));
      });
      lateral.appendChild(U.card('Coordonnées de l’éditeur', coord));

      lateral.appendChild(U.card('Avant de nous écrire', el('div.space-y-3', null, [
        el('div.flex.items-start.gap-2\\.5', null, [
          el('span.mt-0\\.5.shrink-0.text-warning-500', null, C.icon('lightbulb', 'h-4 w-4')),
          el('p.text-sm.text-slate-600', {
            text: 'La réponse se trouve peut-être déjà dans la documentation : présentation des modules, '
              + 'règles de gestion et questions fréquentes y sont réunies.',
          }),
        ]),
        K.lien('aide-apropos', 'Consulter l’aide & la FAQ', { icon: 'life-buoy', variant: 'primary' }),
      ])));

      lateral.appendChild(K.note('Les demandes envoyées depuis cet écran sont <strong>enregistrées et journalisées</strong> '
        + 'comme toute autre opération : elles restent consultables sous les formulaires.', { tone: 'info' }));

      host.appendChild(principal);
      host.appendChild(lateral);
      root.appendChild(host);
      majListe();
      return null;

      /* --- Enregistrement d'une demande ------------------------------------ */
      function enregistrer(donnees) {
        var res = col.insert(Object.assign({
          reference: C.nextRef('SUP-2026-', 4),
          date: C.iso(AUJ),
          auteur: S.currentUser(),
          etat: 'envoyee',
        }, donnees));
        majListe();
        U.toast(donnees.type === 'anomalie' ? 'Anomalie signalée à l’éditeur.' : 'Message envoyé à l’éditeur.', {
          type: 'success',
          detail: 'Référence ' + res.record.reference + ' — réponse sous 48 h ouvrées.',
          undo: function () { res.undo(); majListe(); },
        });
      }

      function majListe() {
        C.clear(listeHost);
        var rows = C.sortBy(col.active(), 'reference', 'desc');
        if (!rows.length) return;
        listeHost.appendChild(U.card('Demandes envoyées', K.miniTable([
          { label: 'Référence', render: function (r) { return el('span.font-mono.text-xs', { text: r.reference }); } },
          { label: 'Date', render: function (r) { return C.dateFR(r.date); } },
          {
            label: 'Nature',
            render: function (r) {
              return r.type === 'anomalie' ? U.badge('Anomalie', 'danger') : U.badge('Message', 'info');
            },
          },
          { label: 'Objet', key: 'objet' },
          { label: 'Module', render: function (r) { return r.module || '—'; } },
          { label: 'État', render: function () { return U.badge('Envoyée', 'success'); } },
        ], rows.slice(0, 10))));
        U.icons(listeHost);
      }
    },
  });

  /* ==========================================================================
   * AIDE & À PROPOS
   * ======================================================================== */
  global.SIGH.screen('aide-apropos', {
    title: 'Aide & À propos',
    description: 'Documentation d’usage : présentation du logiciel, guide des modules et foire aux questions.',
    render: function (root) {
      var host = el('div.space-y-5');

      /* --- Présentation ----------------------------------------------------- */
      var presentation = el('div.grid.gap-4.lg\\:grid-cols-3');
      var texte = el('div.space-y-3.lg\\:col-span-2');
      texte.appendChild(el('p.text-sm.leading-relaxed.text-slate-600', {
        text: 'Le SIGH-CNT est le Système Intégré de Gestion Hospitalière de la ' + C.BRAND.nom + '. '
          + 'Il réunit en une seule application des activités jusqu’ici réparties entre plusieurs logiciels cloisonnés '
          + 'et de nombreux registres papier : dossier patient, consultations, hospitalisation, laboratoire, '
          + 'pharmacie, achats, facturation, assurances, ressources humaines, paie et comptabilité.',
      }));
      texte.appendChild(el('p.text-sm.leading-relaxed.text-slate-600', {
        text: 'Une donnée saisie une fois circule ensuite d’un module à l’autre : une prescription alimente la '
          + 'facturation, une dispensation décrémente le stock, un planning validé nourrit le calcul des primes.',
      }));
      texte.appendChild(K.note('Les quatorze <strong>règles de gestion</strong> du cahier des charges sont appliquées '
        + 'et rappelées à l’écran là où elles s’imposent : identifiant patient, marge nulle sur les médicaments, '
        + 'stock jamais négatif, signatures de sortie, validité des cartes d’assurance, équilibre des écritures, '
        + 'journalisation et archivage logique.', { tone: 'info' }));
      presentation.appendChild(texte);

      var carte = el('div.space-y-2');
      [['Version', EDITEUR.version],
       ['Éditeur', EDITEUR.auteur],
       ['Établissement', C.BRAND.nom],
       ['IFU', C.BRAND.ifu],
       ['RCCM', C.BRAND.rccm]].forEach(function (l) {
        carte.appendChild(el('div.flex.items-baseline.justify-between.gap-3.border-b.border-slate-100.pb-1\\.5', null, [
          el('span.shrink-0.text-xs.text-slate-500', { text: l[0] }),
          el('span.text-right.text-xs.font-medium.text-slate-800', { text: l[1] }),
        ]));
      });
      presentation.appendChild(U.card('À propos', carte));
      host.appendChild(presentation);

      /* --- Chiffres clés ---------------------------------------------------- */
      /* On compte les ecrans fonctionnels du manifeste : ni pages d'accueil de
         module, ni ecrans d'authentification. */
      var nbEcrans = 0, nbModules = 0;
      N.NAV.forEach(function (d) {
        nbModules += d.modules.length;
        d.modules.forEach(function (m) { nbEcrans += m.items.length; });
      });
      host.appendChild(U.kpiGrid([
        { label: 'Modules fonctionnels', value: C.num(nbModules), icon: 'layout-grid', tone: 'navy' },
        { label: 'Écrans disponibles', value: C.num(nbEcrans), icon: 'monitor', tone: 'info' },
        { label: 'Règles de gestion appliquées', value: '14', icon: 'shield-check', tone: 'success' },
        { label: 'Profils d’utilisateur', value: C.num(Object.keys(N.ROLES).length), icon: 'users-round', tone: 'neutral' },
      ]));

      /* --- Modules du logiciel ---------------------------------------------- */
      host.appendChild(K.section('Modules du logiciel',
        'Chaque module ouvre sa page d’accueil, où figurent tous ses écrans.'));
      var grille = el('div.grid.gap-3.sm\\:grid-cols-2.xl\\:grid-cols-3');
      N.NAV.forEach(function (dom) {
        dom.modules.forEach(function (mod) {
          var c = el('a.hub-card.group.flex.gap-3.rounded-xl.border.border-slate-200.bg-white.p-4.shadow-card.transition-all.hover\\:-translate-y-0\\.5.hover\\:border-navy-300.hover\\:shadow-raise',
            { href: global.SIGH.app.href(N.hubId(mod.code)) });
          c.appendChild(el('span.grid.h-10.w-10.shrink-0.place-items-center.rounded-lg.bg-navy-50.text-navy-700.transition-colors.group-hover\\:bg-navy-900.group-hover\\:text-white',
            null, C.icon(mod.icon, 'h-5 w-5')));
          c.appendChild(el('span.min-w-0.flex-1', null, [
            el('span.flex.flex-wrap.items-center.gap-2', null, [
              el('span.text-sm.font-semibold.text-slate-900', { text: mod.label }),
              el('span.badge.badge-navy.font-mono', { text: mod.code }),
            ]),
            el('span.mt-1.block.text-xs.leading-relaxed.text-slate-500', {
              text: RESUMES[mod.code] || 'Module du système.',
            }),
            el('span.mt-1.block.text-\\[11px\\].text-slate-400', { text: 'Domaine ' + dom.domain }),
          ]));
          grille.appendChild(c);
        });
      });
      host.appendChild(grille);

      /* --- Foire aux questions ---------------------------------------------- */
      host.appendChild(K.section('Foire aux questions',
        'Les situations le plus souvent rencontrées, et ce que le système en fait.'));
      var accordeon = el('div.divide-y.divide-slate-200.overflow-hidden.rounded-xl.border.border-slate-200.bg-white.shadow-card');
      FAQ.forEach(function (item, i) {
        var d = el('details.group', i === 0 ? { open: true } : {});
        var s = el('summary.flex.cursor-pointer.list-none.items-center.justify-between.gap-3.px-5.py-3\\.5.text-sm.font-medium.text-slate-800.transition-colors.hover\\:bg-slate-50');
        s.appendChild(el('span', { text: item.q }));
        s.appendChild(el('span.shrink-0.text-slate-400.transition-transform.group-open\\:rotate-180', null,
          C.icon('chevron-down', 'h-4 w-4')));
        d.appendChild(s);
        d.appendChild(el('div.border-t.border-slate-100.bg-slate-50.px-5.py-3\\.5', null,
          el('p.text-sm.leading-relaxed.text-slate-600', { html: item.r })));
        accordeon.appendChild(d);
      });
      host.appendChild(accordeon);

      /* --- Renvoi vers l'éditeur -------------------------------------------- */
      var appel = el('div.flex.flex-wrap.items-center.gap-4.rounded-xl.border.border-navy-200.bg-navy-50.p-5');
      appel.appendChild(el('span.grid.h-11.w-11.shrink-0.place-items-center.rounded-full.bg-navy-900.text-white',
        null, C.icon('headset', 'h-5 w-5')));
      appel.appendChild(el('div.min-w-0.flex-1', null, [
        el('p.text-sm.font-semibold.text-navy-900', { text: 'Vous ne trouvez pas de réponse ?' }),
        el('p.text-xs.text-navy-800', {
          text: 'Écrivez à l’éditeur : question, suggestion ou signalement d’anomalie. Réponse sous 48 h ouvrées.',
        }),
      ]));
      appel.appendChild(K.lien('contact-editeur', 'Contacter l’éditeur', { icon: 'mail', variant: 'primary' }));
      host.appendChild(appel);

      root.appendChild(host);
      return null;
    },
  });
})(window);
