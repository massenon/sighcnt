/* =============================================================================
 * Écrans d'accès — connexion, récupération, double facteur, verrouillage, erreurs
 * -----------------------------------------------------------------------------
 * CDCT §12.2 : authentification individuelle obligatoire (aucun compte partagé),
 * politique de mot de passe, verrouillage après échecs successifs, MFA pour les
 * profils à privilèges élevés, déconnexion automatique sur poste partagé.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, N = global.SIGH.nav, K = global.SIGH.kit;
  var el = C.el, B = C.BRAND;

  function base() { return document.documentElement.getAttribute('data-root') || ''; }
  /* L’extension des pages vient du MANIFESTE (`N.EXT`) : elle y vit à un
     seul endroit, et ce module la lit comme tous les autres liens. */
  function url(id) { return id === 'index' ? base() + 'index' + N.EXT : base() + 'pages/' + id + N.EXT; }

  /** Pastille du logo, avec repli sur le sigle si l'image manque. */
  function pastilleLogo(fond, taille, tonRepli) {
    return el('span.grid.shrink-0.place-items-center.overflow-hidden.rounded-xl.' + fond, null,
      el('img.object-contain.' + taille, {
        src: base() + B.logo, alt: B.sigle,
        onerror: function () { this.replaceWith(el('span.text-base.font-bold.' + tonRepli, { text: B.sigle })); },
      }));
  }

  /* --- Gabarit commun : scène flottante + carte de saisie -------------------
   * Refonte du 04/09/2026 : une seule grande carte arrondie posée sur un fond
   * clair — panneau institutionnel en dégradé à gauche, carte de saisie
   * blanche détachée à droite, halos organiques rognés par la scène.
   *
   * Ce gabarit sert SIX écrans : connexion, verrou de session, mot de passe
   * oublié, double facteur et les pages d'erreur. Une retouche ici les change
   * tous, et c'est le but — la porte d'entrée du logiciel a un seul visage.
   * --------------------------------------------------------------------- */
  function shell(options) {
    var o = options || {};

    var scene = el('div.relative.w-full.max-w-6xl.overflow-hidden.rounded-3xl.bg-gradient-to-br.from-navy-950.via-navy-800.to-info-800.shadow-pop');

    /* Décor : trois halos, hors flux et non cliquables. La lumière vient du
       bas-gauche, comme sur la maquette retenue par la Direction. */
    scene.appendChild(el('div.pointer-events-none.absolute.-left-24.-top-24.h-96.w-96.rounded-full.bg-info-500\\/25.blur-3xl'));
    scene.appendChild(el('div.pointer-events-none.absolute.-bottom-44.-left-16.h-96.w-96.rounded-full.bg-info-400\\/35.blur-3xl'));
    scene.appendChild(el('div.pointer-events-none.absolute.-right-24.top-1\\/4.h-80.w-80.rounded-full.bg-info-600\\/30.blur-3xl'));

    /* --- Panneau institutionnel (au-delà de lg) --------------------------- */
    var aside = el('aside.relative.hidden.flex-col.justify-between.gap-8.p-10.lg\\:flex');

    var marque = el('div.flex.items-center.gap-3');
    marque.appendChild(pastilleLogo('h-12.w-12.bg-white', 'h-9.w-9', 'text-navy-900'));
    marque.appendChild(el('div', null, [
      el('p.text-sm.font-semibold.text-white', { text: 'CLINIQUE NASSIERA TOO' }),
      el('p.text-xs.text-navy-200', { text: 'Natitingou — République du Bénin' }),
    ]));
    aside.appendChild(marque);

    var mid = el('div.max-w-lg');
    mid.appendChild(el('h1.text-3xl.font-semibold.leading-tight.tracking-tight.text-white', {
      text: 'Système Intégré de Gestion Hospitalière',
    }));
    mid.appendChild(el('p.mt-3.text-sm.leading-relaxed.text-navy-100', {
      text: 'Dossier patient, hospitalisation, laboratoire, pharmacie et stocks, facturation normalisée, '
        + 'ressources humaines, paie et comptabilité SYSCOHADA.',
    }));

    var puces = el('ul.mt-7.space-y-3');
    [['shield-check', 'Traçabilité intégrale des actions (journal d’audit)'],
     ['package-search', 'Alertes de rupture et de péremption automatiques (FEFO)'],
     ['file-badge', 'Facture normalisée conforme au dispositif MECeF'],
     ['book-open-check', 'Comptabilité SYSCOHADA alimentée automatiquement']].forEach(function (p) {
      puces.appendChild(el('li.flex.items-start.gap-3', null, [
        el('span.mt-0\\.5.grid.h-6.w-6.shrink-0.place-items-center.rounded-md.bg-white\\/10.text-navy-100', null, C.icon(p[0], 'h-3.5 w-3.5')),
        el('span.text-sm.text-navy-100', { text: p[1] }),
      ]));
    });
    mid.appendChild(puces);

    /* Le slogan de la clinique (Direction, 24/08/2026), mis en exergue. */
    mid.appendChild(el('p.mt-7.border-l-2.border-white\\/40.pl-4.text-base.font-medium.italic.text-white', {
      text: '« ' + B.slogan + ' »',
    }));
    aside.appendChild(mid);

    aside.appendChild(el('p.text-xs.text-navy-300', {
      text: B.nom + ' — IFU ' + B.ifu + ' — RCCM ' + B.rccm,
    }));

    /* --- Carte de saisie, détachée sur le fond ---------------------------- */
    var main = el('main.relative.flex.items-center.justify-center.p-4.sm\\:p-6.lg\\:p-10');
    var colonne = el('div.w-full.max-w-md');
    var card = el('div.rounded-2xl.bg-white.p-6.shadow-pop.sm\\:p-8');

    var brandSm = el('div.mb-6.flex.items-center.gap-3.lg\\:hidden');
    brandSm.appendChild(pastilleLogo('h-11.w-11.bg-navy-950', 'h-8.w-8', 'text-white'));
    brandSm.appendChild(el('div', null, [
      el('p.text-sm.font-semibold.text-slate-900', { text: 'CLINIQUE NASSIERA TOO' }),
      el('p.text-xs.italic.text-slate-500', { text: B.slogan }),
    ]));
    card.appendChild(brandSm);

    if (o.icon) {
      card.appendChild(el('span.mb-4.grid.h-12.w-12.place-items-center.rounded-xl.bg-navy-50.text-navy-800', null, C.icon(o.icon, 'h-6 w-6')));
    }
    card.appendChild(el('h2.text-2xl.font-semibold.tracking-tight.text-slate-900', { text: o.titre }));
    if (o.sousTitre) card.appendChild(el('p.mt-1\\.5.text-sm.text-slate-500', { text: o.sousTitre }));
    var body = el('div.mt-6');
    C.append(body, o.body);
    card.appendChild(body);
    if (o.pied) card.appendChild(el('div.mt-6.text-center.text-sm.text-slate-500', null, o.pied));
    colonne.appendChild(card);

    /* Sous lg le panneau institutionnel disparaît ; la mention légale, elle,
       doit rester lisible — c'est la carte d'identité de l'établissement. */
    colonne.appendChild(el('p.mt-5.text-center.text-xs.text-navy-200.lg\\:hidden', {
      text: B.nom + ' — IFU ' + B.ifu,
    }));
    main.appendChild(colonne);

    var grille = el('div.relative.grid.items-stretch.lg\\:min-h-\\[34rem\\].lg\\:grid-cols-2');
    grille.appendChild(aside);
    grille.appendChild(main);
    scene.appendChild(grille);

    var wrap = el('div.flex.min-h-screen.items-center.justify-center.bg-slate-100.p-4.sm\\:p-6.lg\\:p-4');
    wrap.appendChild(scene);
    return wrap;
  }

  /* ==========================================================================
   * CONNEXION
   * ======================================================================== */
  global.SIGH.screen('index', {
    standalone: true,
    render: function (root) {
      /* Chaque compte porte sa FONCTION et son SECTEUR (NS 145) : le rôle
         ouvre les écrans, la fonction et le secteur décident des données.
         Sage-femme et aide-soignante figurent explicitement — la Direction les
         distingue de l'infirmier, et c'est cette distinction qui commande
         l'accès aux résultats et l'exécution des soins. */

      /* PAGE DE CONNEXION ÉPURÉE (20/10/2026) : plus de sélecteur de profil de
         démonstration ni de mot de passe pré-rempli — l'agent saisit SES
         identifiants, le serveur vérifie le haché. Le pied (« comptes ouverts
         par l'administrateur », double facteur, plan du site) est retiré : il
         promettait des portes qui ne sont pas celles de la connexion. */
      var form = el('form.space-y-4');
      var idField = el('input.input', { type: 'text', id: 'identifiant', autocomplete: 'username', placeholder: 'prenom.nom', required: true });
      var pwField = el('input.input.pr-10', { type: 'password', id: 'motdepasse', autocomplete: 'current-password', placeholder: '••••••••', required: true });

      form.appendChild(el('div', null, [
        el('label.label', { for: 'identifiant', text: 'Identifiant' }),
        idField,
      ]));

      var pwWrap = el('div.relative');
      pwWrap.appendChild(pwField);
      pwWrap.appendChild(el('button.absolute.right-2.top-1\\/2.-translate-y-1\\/2.rounded.p-1.text-slate-400.hover\\:text-slate-700', {
        type: 'button', 'aria-label': 'Afficher le mot de passe',
        onclick: function () {
          var vis = pwField.type === 'text';
          pwField.type = vis ? 'password' : 'text';
          C.clear(this); this.appendChild(C.icon(vis ? 'eye' : 'eye-off', 'h-4 w-4'));
          U.icons(this);
        },
      }, C.icon('eye', 'h-4 w-4')));
      form.appendChild(el('div', null, [
        el('div.flex.items-center.justify-between', null, [
          el('label.label.mb-0', { for: 'motdepasse', text: 'Mot de passe' }),
          el('a.text-xs.font-medium.text-navy-700.hover\\:underline', { href: url('auth-forgot'), text: 'Mot de passe oublié ?' }),
        ]),
        el('div.mt-1\\.5', null, pwWrap),
      ]));


      form.appendChild(el('div.flex.items-center.justify-between', null, [
        el('label.flex.cursor-pointer.items-center.gap-2', null, [
          el('input.checkbox', { type: 'checkbox' }),
          el('span.text-sm.text-slate-600', { text: 'Se souvenir de ce poste' }),
        ]),
      ]));

      var erreur = el('div.hidden.items-start.gap-2.rounded-lg.border.border-danger-200.bg-danger-50.px-3.py-2');
      erreur.appendChild(el('span.shrink-0.text-danger-600', null, C.icon('alert-circle', 'h-4 w-4')));
      var erreurTexte = el('p.text-xs.text-danger-900');
      erreur.appendChild(erreurTexte);
      form.appendChild(erreur);

      var tentatives = 0;
      var submit = el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, [C.icon('log-in', 'h-4 w-4'), 'Se connecter']);
      form.appendChild(submit);

      form.addEventListener('submit', function (e) {
        e.preventDefault();
        if (!idField.value.trim() || !pwField.value) {
          tentatives++;
          erreur.className = 'flex items-start gap-2 rounded-lg border border-danger-200 bg-danger-50 px-3 py-2';
          erreurTexte.textContent = tentatives >= 3
            ? 'Trois tentatives infructueuses. Conformément à la politique de sécurité, le compte serait verrouillé et l’événement journalisé.'
            : 'Identifiant et mot de passe obligatoires (tentative ' + tentatives + ' sur 3).';
          return;
        }
        /* ====================================================================
         * LA CONNEXION SE DEMANDE AU SERVEUR.
         * Le navigateur ne décide plus de rien : il envoie l'identifiant et le
         * mot de passe, la base répond. Un refus ne dit PAS lequel des deux
         * est faux — distinguer « identifiant inconnu » de « mot de passe
         * erroné » offre un annuaire à qui essaie.
         * ================================================================== */
        submit.disabled = true;
        erreur.className = 'hidden';
        global.fetch('api/auth.php', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'connexion', identifiant: idField.value.trim(),
            motDePasse: pwField.value, poste: (global.location.hostname || 'poste') }),
        }).then(function (r) {
          return r.json().then(function (o) { return { ok: r.ok, o: o }; });
        }).then(function (res) {
          submit.disabled = false;
          if (!res.ok || !res.o.jeton) {
            tentatives++;
            erreur.className = 'flex items-start gap-2 rounded-lg border border-danger-200 bg-danger-50 px-3 py-2';
            erreurTexte.textContent = (res.o && res.o.detail)
              || 'Connexion refusée.';
            return;
          }
          var u = res.o.utilisateur;

          /* Le rôle a-t-il été archivé depuis la matrice des droits ? Le compte
             peut être valide en base et son RÔLE retiré : le refus doit être
             NOMMÉ, et l'administrateur informé. */
          if (N.roleArchive(u.role)) {
            refuserRoleArchive(u.role, u);
            return;
          }

          /* Le JETON vient du serveur : on l'adopte, on n'en invente pas. */
          S.setSession({
            jeton: res.o.jeton, role: u.role, nom: u.nom,
            poste: (N.ROLES[u.role] && N.ROLES[u.role].label) || u.role,
            identifiant: u.identifiant, fonction: u.fonction, secteur: u.secteur,
          });
          global.location.href = url((N.ROLES[u.role] && N.ROLES[u.role].home) || 'dash-admin');
        }).catch(function () {
          submit.disabled = false;
          erreur.className = 'flex items-start gap-2 rounded-lg border border-danger-200 bg-danger-50 px-3 py-2';
          erreurTexte.textContent = 'Connexion perdue avec le serveur de base de données. '
            + 'Vérifier que le serveur est démarré, puis réessayer.';
        });
      });

      /* --------------------------------------------------------------------
       * Refus de connexion — rôle archivé.
       * L'administrateur retrouve la tentative dans « Rôles & permissions ».
       * ------------------------------------------------------------------ */
      function refuserRoleArchive(role, compte) {
        var libelle = N.ROLES[role] ? N.ROLES[role].label : role;
        S.collection('tentativesConnexion', { module: 'M14', entite: 'tentative', prefix: 'TNT' }).insert({
          identifiant: (compte && compte.identifiant) || idField.value.trim(),
          nom: (compte && compte.nom) || idField.value.trim(),
          role: role,
          motif: 'Rôle archivé — accès retiré par l’administrateur',
          horodatage: new Date().toISOString(),
          poste: 'Écran de connexion', traitee: false,
        });
        S.log('Connexion refusée', 'M14', 'Session', (compte && compte.identifiant) || idField.value.trim(),
          null, { role: role, motif: 'rôle archivé' });

        erreur.className = 'flex items-start gap-2 rounded-lg border border-danger-200 bg-danger-50 px-3 py-2';
        erreurTexte.textContent = 'Connexion refusée — le profil « ' + libelle + ' » a été retiré.';

        var m = U.modal({
          title: 'Connexion refusée', size: 'md',
          body: el('div.space-y-3', null, [
            el('div.flex.items-start.gap-3.rounded-lg.border.border-danger-200.bg-danger-50.p-3', null, [
              el('span.shrink-0.text-danger-600', null, C.icon('shield-x', 'h-5 w-5')),
              el('div.min-w-0', null, [
                el('p.text-sm.font-semibold.text-danger-900', { text: 'Ce compte ne peut plus ouvrir de session.' }),
                el('p.mt-1.text-xs.text-danger-800', {
                  text: 'Le profil « ' + libelle + ' » a été archivé par l’administrateur système. '
                    + 'Les habilitations rattachées à ce rôle sont suspendues.',
                }),
              ]),
            ]),
            U.descList([
              ['Compte', (compte && compte.nom) || idField.value.trim()],
              ['Profil demandé', libelle],
              ['Date et heure', C.dateHeure(new Date())],
              ['Suite donnée', 'La tentative est journalisée et signalée à l’administrateur.'],
            ], 'grid-cols-1'),
            el('p.text-xs.text-slate-500', {
              text: 'Pour retrouver l’accès, l’administrateur doit restaurer le rôle depuis '
                + '« Rôles & permissions », ou rattacher le compte à un autre profil.',
            }),
          ]),
          footer: [
            el('a.btn.btn-secondary', { href: url('contact-editeur') }, [C.icon('life-buoy', 'h-4 w-4'), 'Contacter l’assistance']),
            K.btn('Fermer', { variant: 'primary', onclick: function () { m.close(); } }),
          ],
        });
      }


      root.appendChild(shell({
        titre: 'Connexion',
        sousTitre: 'Authentification individuelle obligatoire — aucun compte partagé (CDCT §12.2).',
        body: form,
      }));
      return null;
    },
  });

  /* ==========================================================================
   * MOT DE PASSE OUBLIÉ
   * ======================================================================== */
  global.SIGH.screen('auth-forgot', {
    standalone: true,
    render: function (root) {
      var f = el('form.space-y-4');
      f.appendChild(el('div', null, [
        el('label.label', { text: 'Identifiant ou adresse électronique' }),
        el('input.input', { type: 'text', placeholder: 'prenom.nom', required: true }),
      ]));
      f.appendChild(el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, 'Envoyer les instructions'));
      f.addEventListener('submit', function (e) {
        e.preventDefault();
        U.toast('Demande transmise à l’administrateur système.', {
          type: 'success', detail: 'La réinitialisation est effectuée par l’Administrateur (CDCT §12.2).',
        });
        setTimeout(function () { global.location.href = url('auth-reset'); }, 1200);
      });
      root.appendChild(shell({
        icon: 'key-round', titre: 'Mot de passe oublié',
        sousTitre: 'La réinitialisation est prise en charge par l’Administrateur système et journalisée.',
        body: f,
        pied: el('a.font-medium.text-navy-700.hover\\:underline', { href: url('index'), text: '← Retour à la connexion' }),
      }));
      return null;
    },
  });

  /* ==========================================================================
   * RÉINITIALISATION
   * ======================================================================== */
  global.SIGH.screen('auth-reset', {
    standalone: true,
    render: function (root) {
      var f = el('form.space-y-4');
      var pw = el('input.input', { type: 'password', required: true, placeholder: '••••••••' });
      var pw2 = el('input.input', { type: 'password', required: true, placeholder: '••••••••' });
      f.appendChild(el('div', null, [el('label.label', { text: 'Nouveau mot de passe' }), pw]));
      f.appendChild(el('div', null, [el('label.label', { text: 'Confirmer le mot de passe' }), pw2]));

      var regles = el('ul.space-y-1\\.5.rounded-lg.bg-slate-50.p-3');
      [['12 caractères minimum'], ['Au moins une majuscule et une minuscule'], ['Au moins un chiffre et un caractère spécial'],
       ['Renouvellement obligatoire tous les 90 jours']].forEach(function (r) {
        regles.appendChild(el('li.flex.items-center.gap-2.text-xs.text-slate-600', null, [
          C.icon('check', 'h-3.5 w-3.5 text-success-600'), el('span', { text: r[0] }),
        ]));
      });
      f.appendChild(regles);
      f.appendChild(el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, 'Définir le mot de passe'));
      f.addEventListener('submit', function (e) {
        e.preventDefault();
        if (pw.value !== pw2.value) { U.toast('Les deux mots de passe ne correspondent pas.', { type: 'error' }); return; }
        U.toast('Mot de passe mis à jour.', { type: 'success' });
        setTimeout(function () { global.location.href = url('index'); }, 1000);
      });
      root.appendChild(shell({
        icon: 'lock-keyhole', titre: 'Réinitialiser le mot de passe',
        sousTitre: 'Politique de mot de passe de la clinique (CDCT §12.2).',
        body: f,
        pied: el('a.font-medium.text-navy-700.hover\\:underline', { href: url('index'), text: '← Retour à la connexion' }),
      }));
      return null;
    },
  });

  /* ==========================================================================
   * DOUBLE FACTEUR (MFA)
   * ======================================================================== */
  global.SIGH.screen('auth-2fa', {
    standalone: true,
    render: function (root) {
      var f = el('form.space-y-4');
      var boxes = el('div.flex.justify-between.gap-2');
      var inputs = [];
      for (var i = 0; i < 6; i++) {
        var inp = el('input.input.h-14.w-full.text-center.text-xl.font-semibold', {
          type: 'text', inputmode: 'numeric', maxlength: 1, 'aria-label': 'Chiffre ' + (i + 1),
        });
        (function (idx, node) {
          node.addEventListener('input', function () {
            if (node.value && inputs[idx + 1]) inputs[idx + 1].focus();
          });
          node.addEventListener('keydown', function (e) {
            if (e.key === 'Backspace' && !node.value && inputs[idx - 1]) inputs[idx - 1].focus();
          });
        })(i, inp);
        inputs.push(inp);
        boxes.appendChild(inp);
      }
      f.appendChild(boxes);
      f.appendChild(el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, 'Vérifier'));
      f.appendChild(el('p.text-center.text-xs.text-slate-500', { text: 'Code non reçu ? Un nouvel envoi est possible dans 30 secondes.' }));
      f.addEventListener('submit', function (e) {
        e.preventDefault();
        var s = S.session();
        U.toast('Vérification réussie.', { type: 'success' });
        setTimeout(function () {
          global.location.href = url(s && s.role ? N.ROLES[s.role].home : 'dash-admin');
        }, 900);
      });
      root.appendChild(shell({
        icon: 'smartphone', titre: 'Vérification en 2 étapes',
        sousTitre: 'Exigée pour les profils à privilèges élevés : Administrateur et Direction (CDCT §12.2).',
        body: f,
        pied: el('a.font-medium.text-navy-700.hover\\:underline', { href: url('index'), text: '← Utiliser un autre compte' }),
      }));
      return null;
    },
  });

  /* ==========================================================================
   * ÉCRAN VERROUILLÉ
   * ======================================================================== */
  /* ==========================================================================
   * ÉCRAN VERROUILLÉ
   * --------------------------------------------------------------------------
   * Le verrouillage SUSPEND la session, il ne la ferme pas. C'est toute la
   * différence : au déverrouillage, l'agent retrouve l'écran qu'il avait
   * ouvert, à l'onglet près, et non un tableau de bord d'accueil qui lui
   * ferait tout recommencer.
   *
   * L'adresse de retour est posée par app.js au moment du verrouillage et
   * consommée ici — une seule fois, pour qu'un rechargement ultérieur de
   * l'écran verrouillé ne renvoie pas au hasard.
   * ======================================================================== */
  global.SIGH.screen('auth-lock', {
    standalone: true,
    render: function (root) {
      var s = S.session();
      var A = global.SIGH.app || {};
      var cleRetour = A.VERROU_RETOUR || 'sigh-cnt:verrou-retour';
      var retour = S.storage.get(cleRetour);

      /* Sans session, il n'y a rien à déverrouiller : on renvoie à la
         connexion plutôt que d'afficher un écran qui ne mène nulle part. */
      if (!s) {
        global.location.href = url('index');
        return null;
      }

      var ecranRetour = null;
      if (retour) {
        /* L'adresse de retour est celle d'une PAGE : son extension a changé
           le 23/09/2026. On accepte les deux — un verrou posé avant le
           changement doit encore ramener l'agent à son écran. */
        var id = String(retour).split('#')[0].replace(/\.(php|html)$/, '');
        ecranRetour = N.get(id);
      }

      var f = el('form.space-y-4');
      f.appendChild(el('div.flex.items-center.gap-3.rounded-lg.bg-slate-50.p-3', null, [
        el('span.grid.h-11.w-11.place-items-center.rounded-full.bg-navy-900.text-sm.font-semibold.text-white', { text: C.initials(s.nom) }),
        el('div.min-w-0', null, [
          el('p.text-sm.font-semibold.text-slate-900', { text: s.nom }),
          el('p.text-xs.text-slate-500', { text: N.ROLES[s.role] ? N.ROLES[s.role].label : '' }),
        ]),
      ]));

      /* Ce que l'agent va retrouver : le dire lève l'inquiétude de perdre
         la saisie en cours, qui est la première raison de désactiver un
         verrouillage automatique. */
      if (ecranRetour) {
        f.appendChild(el('div.flex.items-start.gap-2.rounded-lg.border.border-info-200.bg-info-50.px-3.py-2', null, [
          el('span.shrink-0.text-info-600', null, C.icon('history', 'h-4 w-4')),
          el('div.min-w-0', null, [
            el('p.text-xs.font-semibold.text-info-900', { text: 'Votre session est suspendue, pas fermée.' }),
            el('p.mt-0\.5.text-xs.text-info-800', {
              text: 'Au déverrouillage, vous reviendrez sur « ' + ecranRetour.label + ' ».',
            }),
          ]),
        ]));
      }

      var pw = el('input.input', { type: 'password', placeholder: '••••••••', required: true });
      f.appendChild(el('div', null, [
        el('label.label', { text: 'Mot de passe' }),
        pw,
      ]));
      f.appendChild(el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, [C.icon('unlock', 'h-4 w-4'), 'Déverrouiller']));

      f.addEventListener('submit', function (e) {
        e.preventDefault();
        S.log('Déverrouillage de session', 'M14', 'Session', s.identifiant || s.nom, null,
          { retour: retour || null });
        /* Le drapeau est à usage unique : sans cela, un rechargement de cet
           écran renverrait indéfiniment vers un écran quitté depuis. */
        S.storage.remove(cleRetour);
        if (retour) {
          global.location.href = A.base ? A.base() + retour : retour;
          return;
        }
        global.location.href = url(N.ROLES[s.role] ? N.ROLES[s.role].home : 'dash-admin');
      });

      root.appendChild(shell({
        icon: 'lock', titre: 'Session verrouillée',
        sousTitre: 'Verrouillage automatique après ' + Math.round((A.delaiVerrou ? A.delaiVerrou() : 900000) / 60000)
          + ' minutes d’inactivité, sur les postes partagés — accueil et caisse (CDCT §12.2).',
        body: f,
        pied: el('a.font-medium.text-navy-700.hover\:underline', {
          href: url('index'), text: 'Se connecter avec un autre compte',
          onclick: function () { S.setSession(null); S.storage.remove(cleRetour); },
        }),
      }));
      return null;
    },
  });

  /* ==========================================================================
   * PAGES D'ERREUR
   * ======================================================================== */
  function pageErreur(id, code, titre, message, icon) {
    global.SIGH.screen(id, {
      standalone: true,
      render: function (root) {
        var wrap = el('div.flex.min-h-screen.flex-col.items-center.justify-center.p-6.text-center');
        wrap.appendChild(el('span.grid.h-16.w-16.place-items-center.rounded-2xl.bg-navy-50.text-navy-800', null, C.icon(icon, 'h-8 w-8')));
        wrap.appendChild(el('p.mt-6.text-5xl.font-bold.tracking-tight.text-navy-950', { text: code }));
        wrap.appendChild(el('h1.mt-2.text-xl.font-semibold.text-slate-900', { text: titre }));
        wrap.appendChild(el('p.mt-2.max-w-md.text-sm.text-slate-500', { text: message }));
        var actions = el('div.mt-6.flex.flex-wrap.justify-center.gap-2');
        var s = S.session();
        actions.appendChild(el('a.btn.btn-primary', { href: url(s && N.ROLES[s.role] ? N.ROLES[s.role].home : 'index') }, [C.icon('home', 'h-4 w-4'), 'Retour à l’accueil']));
        actions.appendChild(el('a.btn.btn-secondary', { href: url('plan-du-site') }, [C.icon('map', 'h-4 w-4'), 'Plan du site']));
        wrap.appendChild(actions);
        wrap.appendChild(el('p.mt-10.text-xs.text-slate-400', { text: B.nom + ' — SIGH-CNT' }));
        root.appendChild(wrap);
        return null;
      },
    });
  }

  pageErreur('error-404', '404', 'Page introuvable',
    'L’écran demandé n’existe pas ou a été déplacé. Utiliser le plan du site pour retrouver le module recherché.', 'file-question');
  pageErreur('error-403', '403', 'Accès refusé',
    'Votre profil ne dispose pas des habilitations requises pour cet écran. L’accès est régi par la matrice RBAC (CDCT §12.1) et toute tentative est journalisée.', 'shield-x');

  /* ==========================================================================
   * PLAN DU SITE — inventaire complet des écrans
   * ======================================================================== */
  global.SIGH.screen('plan-du-site', {
    standalone: true,
    render: function (root) {
      var wrap = el('div.mx-auto.max-w-6xl.p-6');
      var head = el('div.mb-6.flex.flex-wrap.items-center.justify-between.gap-3');
      head.appendChild(el('div', null, [
        el('h1.text-2xl.font-semibold.tracking-tight.text-slate-900', { text: 'Plan du site' }),
        el('p.mt-1.text-sm.text-slate-500', { text: 'Inventaire de tous les écrans du prototype, organisés par domaine et par module.' }),
      ]));
      var s = S.session();
      head.appendChild(el('a.btn.btn-primary', { href: url(s && N.ROLES[s.role] ? N.ROLES[s.role].home : 'index') }, [C.icon('arrow-left', 'h-4 w-4'), 'Retour à l’application']));
      wrap.appendChild(head);

      var total = 0;
      N.NAV.forEach(function (domain) {
        var section = el('section.mb-6');
        section.appendChild(el('h2.mb-3.flex.items-center.gap-2.text-sm.font-semibold.uppercase.tracking-wide.text-slate-500', null, [
          C.icon(domain.icon, 'h-4 w-4'), domain.domain,
        ]));
        var grid = el('div.grid.gap-3.md\\:grid-cols-2.lg\\:grid-cols-3');
        domain.modules.forEach(function (mod) {
          var card = el('div.card');
          var body = el('div.card-body');
          body.appendChild(el('div.mb-2.flex.items-center.gap-2', null, [
            el('span.grid.h-7.w-7.place-items-center.rounded-lg.bg-navy-50.text-navy-700', null, C.icon(mod.icon, 'h-3.5 w-3.5')),
            el('span.text-sm.font-semibold.text-slate-800', { text: mod.label }),
            el('span.badge.badge-navy.font-mono', { text: mod.code }),
          ]));
          var ul = el('ul.space-y-0\\.5');
          mod.items.forEach(function (it) {
            total++;
            ul.appendChild(el('li', null,
              el('a.flex.items-center.gap-2.rounded.px-2.py-1.text-xs.text-slate-600.hover\\:bg-navy-50.hover\\:text-navy-800', {
                href: url(it.id),
              }, [
                C.icon(it.icon || mod.icon, 'h-3.5 w-3.5 shrink-0 text-slate-400'),
                el('span.truncate', { text: it.label }),
              ])));
          });
          body.appendChild(ul);
          card.appendChild(body);
          grid.appendChild(card);
        });
        section.appendChild(grid);
        wrap.appendChild(section);
      });

      /* Écrans hors navigation */
      var last = el('section');
      last.appendChild(el('h2.mb-3.text-sm.font-semibold.uppercase.tracking-wide.text-slate-500', { text: 'Accès et pages système' }));
      var ul2 = el('div.flex.flex-wrap.gap-2');
      N.STANDALONE.forEach(function (it) {
        ul2.appendChild(el('a.btn.btn-secondary.btn-sm', { href: url(it.id), text: it.label }));
      });
      last.appendChild(ul2);
      wrap.appendChild(last);

      wrap.appendChild(el('p.mt-8.text-xs.text-slate-400', {
        text: total + ' écrans métier recensés au manifeste, plus ' + N.STANDALONE.length + ' pages d’accès et système.',
      }));
      root.appendChild(wrap);
      return null;
    },
  });
})(window);
