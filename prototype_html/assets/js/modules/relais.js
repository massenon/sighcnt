/* =============================================================================
 * RELAIS EN LIGNE (apps/web) — le panneau superadmin du relais, en pages de prototype
 * -----------------------------------------------------------------------------
 * Le relais est hébergé en ligne (cPanel mutualisé). Il est OPAQUE : il stocke des enveloppes chiffrées et des
 * indicateurs sans nom ; il ne détient aucune clé. Le superadmin le supervise, il ne lit AUCUNE donnée de patient.
 * Les quatre premiers écrans existent déjà dans apps/web (Livewire) ; les huit suivants sont ceux que l on doit
 * attendre d un relais exploité en production. Source : docs/architecture/MODULES-WEB-RELAIS.md
 *
 * PROTOTYPE : données de démonstration figées, gestes simulés.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, K = global.SIGH.kit;
  var el = C.el;

  function kpi(label, value, icon, tone, hint) { return { label: label, value: String(value), icon: icon, tone: tone || 'navy', hint: hint }; }
  function note(html, tone, icon) { return K.note(html, { tone: tone || 'info', icon: icon || 'info' }); }
  function simuler(geste) { U.toast('Simulation — ' + geste + '.', { type: 'info' }); }
  function bouton(label, icon, onclick, variante) {
    var b = el('button.btn.btn-sm', { type: 'button', class: variante === 'danger' ? 'btn-danger' : (variante === 'primary' ? 'btn-primary' : 'btn-secondary') });
    b.appendChild(el('i', { dataset: { lucide: icon } })); b.appendChild(document.createTextNode(' ' + label));
    b.addEventListener('click', onclick); return b;
  }
  function barre() { var d = el('div.flex.flex-wrap.gap-2'); Array.prototype.slice.call(arguments).forEach(function (x) { d.appendChild(x); }); return d; }
  function tableau(colonnes, lignes) { return lignes.length ? K.miniTable(colonnes, lignes) : U.empty('Rien à afficher.', { icon: 'inbox' }); }
  var ETATS = { ok: ['OK', 'success'], attention: ['À surveiller', 'warning'], alerte: ['ALERTE', 'danger'] };
  function etat(e) { var x = ETATS[e]; return U.badge(x[0], x[1]); }
  var BANDEAU = 'Prototype du <strong>relais en ligne</strong> (<code>apps/web</code>, Laravel + Livewire). Le relais ne contient <strong>aucune donnée de patient lisible</strong>. Données de démonstration.';
  function page(root, blocs) {
    var h = el('div.space-y-4'); h.appendChild(note(BANDEAU, 'neutral', 'cloud'));
    blocs.forEach(function (b) { if (b) h.appendChild(b); }); root.appendChild(h);
  }
  function ecran(id, meta, fn) { global.SIGH.screen(id, { title: meta.title, description: meta.description, regle: meta.regle, render: function (root) { fn(root); return null; } }); }

  var APP = [
    ['u-01', 'Poste Caisse principale', 'actif', 'il y a 2 min', 0], ['u-02', 'Poste Accueil', 'actif', 'il y a 1 min', 0], ['u-06', 'Mobile — Dr YENI M’PO', 'actif', 'il y a 12 min', 2],
    ['u-07', 'Mobile — Sage-femme de garde', 'bloqué', 'il y a 4 h', 1], ['u-08', 'Mobile — Réception de secours', 'actif', 'il y a 10 h', 0], ['u-09', 'Ancien poste Archives', 'révoqué', 'il y a 30 j', 0],
  ];

  ecran('rls-tableau', {
    title: 'Tableau de bord du relais', description: 'La mère est-elle vivante, à jour, sauvegardée ? Volumes et alertes — sans aucun nom de patient.',
    regle: 'Le relais lève une <strong>alerte « battement »</strong> si la mère se tait plus de 5 minutes. Les indicateurs sont le <strong>seul contenu en clair</strong>.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Mère', 'Vivante', 'heart-pulse', 'success', 'Dernier battement il y a 40 s'), kpi('Appareils actifs', 4, 'monitor-smartphone'), kpi('Enveloppes stockées', '3 912', 'mails'), kpi('Alertes', 1, 'bell-ring', 'warning')]),
      U.card('Dernières alertes', tableau(['Quand', 'Alerte', 'Durée'], [['il y a 2 h', 'Battement manquant', '7 min (résolue)'], ['il y a 4 h', 'Appareil bloqué : Mobile — Sage-femme de garde', 'en cours']]))]);
  });

  ecran('rls-appareils', {
    title: 'Appareils', description: 'Les appareils appairés : état, dernier contact, boîte aux lettres. Révocation.',
    regle: 'Un appareil révoqué est <strong>effacé à son prochain contact</strong> s’il s’agit d’un mobile ; sa fiche reste (RG-14). Le jeton n’est jamais conservé en clair (seul son empreinte l’est).',
  }, function (root) {
    page(root, [U.card('Appareils', tableau(['Appareil', 'Identifiant', 'État', 'Dernier contact', 'En attente', ''], APP.map(function (a) {
      return [a[1], el('code.text-xs', { text: a[0] }), U.badge(a[2], a[2] === 'actif' ? 'success' : (a[2] === 'bloqué' ? 'danger' : 'neutral')), a[3], String(a[4]), a[2] === 'révoqué' ? '' : bouton('Révoquer', 'ban', function () { U.confirm({ title: 'Révoquer ' + a[1] + ' ?', message: 'Action journalisée.', confirmLabel: 'Révoquer', danger: true }).then(function (ok) { if (ok) simuler('révocation enregistrée'); }); }, 'danger')];
    })))]);
  });

  ecran('rls-boites', {
    title: 'Boîtes aux lettres', description: 'Pour chaque mobile : enveloppes déposées par la mère, enveloppes envoyées par le mobile, rangs, tailles.',
    regle: 'Chaque boîte est une suite <strong>contiguë</strong> (appareil, sens, rang). Un trou est détecté par la mère et <strong>bloque l’appareil</strong> : le relais ne supprime donc jamais une enveloppe seul.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Boîtes', 3, 'inbox'), kpi('Vers les mobiles', 41, 'arrow-down-to-line'), kpi('Depuis les mobiles', 9, 'arrow-up-from-line')]),
      U.card('Boîtes', tableau(['Mobile', 'Vers le mobile', 'Depuis le mobile', 'Dernier rang reçu', 'Taille', 'Plus ancienne'], [['Dr YENI M’PO', '18', '4', '4', '212 Ko', 'il y a 8 h'], ['Sage-femme de garde', '12', '3', '3', '96 Ko', 'il y a 1 j'], ['Réception de secours', '11', '2', '2', '58 Ko', 'il y a 2 j']]))]);
  });

  ecran('rls-codes', {
    title: 'Codes d’appairage', description: 'Codes à usage unique créés par la mère : ils expirent, ne servent qu’une fois, ne sont jamais conservés en clair.',
    regle: 'Le relais ne stocke que l’<strong>empreinte</strong> d’un code. Un code utilisé ou expiré est refusé <strong>avec la même réponse</strong>.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Codes valides', 1, 'ticket', 'warning'), kpi('Utilisés (30 j)', 5, 'check', 'success'), kpi('Expirés', 2, 'clock')]),
      U.card('Codes', tableau(['Empreinte', 'Créé', 'Expire', 'État'], [['9f2c…a1e0', 'il y a 6 min', 'dans 9 min', U.badge('Valide', 'warning')], ['04bd…77c2', 'hier', 'expiré', U.badge('Expiré', 'neutral')], ['c3a1…5e19', 'il y a 3 j', '—', U.badge('Utilisé', 'success')]]))]);
  });

  ecran('rls-indicateurs', {
    title: 'Indicateurs reçus', description: 'Les compteurs publiés par la mère à chaque battement. Aucun nom, aucun motif.',
    regle: 'Tout champ qui ressemblerait à une donnée de santé est <strong>refusé</strong> à la réception : le relais ne l’enregistre pas.',
  }, function (root) {
    page(root, [U.card('Dernier envoi', el('pre.text-xs.bg-slate-50.border.border-slate-200.rounded.p-3', { text: JSON.stringify({ epoque: 3, seq: 12480, appareils_actifs: 8, conflits_ouverts: 3, appareils_bloques: 1, derniere_sauvegarde: 'aujourd’hui 02:10', retard_replication: 14 }, null, 2) })),
      U.card('Historique (24 h)', tableau(['Heure', 'Séquence', 'Appareils actifs', 'Conflits', 'Bloqués'], [['08:00', '12 480', '8', '3', '1'], ['07:00', '12 391', '8', '3', '1'], ['06:00', '12 322', '7', '2', '1']]))]);
  });

  ecran('rls-alertes', {
    title: 'Alertes et notifications', description: 'Règles d’alerte du relais et canaux de notification du superadmin (courriel).',
    regle: 'Une alerte porte <strong>un type, un appareil, une heure</strong> — jamais un contenu métier. Le courriel du superadmin ne contient aucun nom de patient.',
  }, function (root) {
    page(root, [U.card('Règles', tableau(['Alerte', 'Seuil', 'Canal', 'Active'], [['Battement manquant', '5 min', 'Courriel + panneau', U.badge('Oui', 'success')], ['Appareil bloqué', 'immédiat', 'Courriel + panneau', U.badge('Oui', 'success')], ['Espace disque faible', '10 %', 'Courriel', U.badge('Oui', 'success')], ['Tâche cron non exécutée', '5 min', 'Panneau', U.badge('Oui', 'success')]])),
      barre(bouton('Envoyer un courriel de test', 'mail', function () { simuler('courriel de test envoyé'); }, 'primary'))]);
  });

  ecran('rls-journal', {
    title: 'Journal d’audit du relais', description: 'Qui a fait quoi sur le panneau : connexions, révocations, codes, changements de paramètres.',
    regle: 'Aucune action anonyme (RG-12). Conservation 365 jours (30 au minimum) ; la purge <strong>ne touche jamais aux enveloppes</strong>.',
  }, function (root) {
    page(root, [U.card('Journal', tableau(['Quand', 'Acteur', 'Action', 'Détail'], [['il y a 5 min', 'admin@clinique.bj', 'connexion', '—'], ['il y a 1 h', 'admin@clinique.bj', 'code_cree', 'poste'], ['il y a 4 h', 'système', 'appareil_bloque', 'u-07 · authentification'], ['hier', 'console', 'audit_purge', '0 ligne']]))]);
  });

  ecran('rls-superadmin', {
    title: 'Comptes superadmin', description: 'Les comptes qui administrent le relais : création par commande, mot de passe, sessions, double facteur.',
    regle: 'Un compte se crée <strong>par commande</strong> (<code>relais:superadmin</code>, tâche cron à usage unique sur cPanel) : pas d’inscription publique. Mot de passe de 12 caractères au moins.',
  }, function (root) {
    page(root, [U.card('Comptes', tableau(['Courriel', 'Créé', 'Dernière connexion', 'Double facteur'], [['admin@clinique.bj', '12/10/2026', 'il y a 5 min', U.badge('À activer', 'warning')]])),
      U.card('Sessions ouvertes', tableau(['Appareil', 'Adresse', 'Depuis'], [['Chrome · Windows', '41.xx.xx.12', 'il y a 5 min']])),
      barre(bouton('Changer le mot de passe', 'key-round', function () { simuler('changement de mot de passe'); }, 'primary'))]);
  });

  ecran('rls-parametres', {
    title: 'Paramètres du relais', description: 'Secret de la mère, seuil de battement, rétention de l’audit, crochets du banc d’essai (fermés).',
    regle: 'Le <strong>secret de la mère</strong> se pose dans le <code>.env</code> du relais (jamais en base). Les crochets du banc d’essai sont <strong>fermés en production</strong>.',
  }, function (root) {
    page(root, [U.card('Paramètres', tableau(['Paramètre', 'Valeur', 'Où'], [['Seuil de battement', '5 min', 'RELAIS_SEUIL_BATTEMENT_MS'], ['Secret de la mère', '•••••••• (non affichable)', 'RELAIS_SECRET_MERE'], ['Rétention de l’audit', '365 jours', 'relais:purger'], ['Crochets du banc', U.badge('Fermés', 'success'), 'RELAIS_BANC=false']])),
      note('Faire tourner le secret : le changer dans le <code>.env</code> du relais <strong>et</strong> dans la configuration de la mère, dans la même minute.', 'warning', 'key-round')]);
  });

  ecran('rls-hebergement', {
    title: 'Hébergement (cPanel)', description: 'Santé de l’hébergement mutualisé : PHP, base, cron, disque, certificat.',
    regle: 'Contraintes connues : PHP 8.2 ou plus, PostgreSQL, <strong>cron toutes les minutes</strong>, pas de SSH, pas de Redis, pas de WebSocket (la mère interroge, le relais n’appelle jamais).',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('PHP', '8.3.12', 'code', 'success'), kpi('Base', 'PostgreSQL 15', 'database', 'success'), kpi('Cron', 'il y a 40 s', 'timer', 'success'), kpi('Disque', '38 %', 'hard-drive')]),
      U.card('Contrôles', tableau(['Contrôle', 'État', 'Détail'], [['Cron schedule:run', etat('ok'), 'dernier passage il y a 40 s'], ['Certificat TLS', etat('ok'), 'valide 74 jours'], ['Dossier storage/', etat('ok'), 'écriture possible'], ['Extension pdo_pgsql', etat('ok'), 'chargée']]))]);
  });

  ecran('rls-sauvegarde', {
    title: 'Sauvegarde du relais', description: 'Export de la base du relais avant toute migration ; le journal chiffré qu’elle contient sert à restaurer la mère.',
    regle: 'Avant chaque <code>migrate</code> : export de la base (phpPgAdmin ou <code>pg_dump</code> par cron). Le contenu est <strong>déjà chiffré</strong> : un export ne contient aucune donnée lisible.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Dernier export', 'hier 03:00', 'database-backup', 'success'), kpi('Taille', '86 Mo', 'file-archive')]),
      U.card('Exports', tableau(['Date', 'Taille', 'Avant migration'], [['hier 03:00', '86 Mo', 'non'], ['il y a 9 j', '71 Mo', 'oui — v2026_10_30']])),
      barre(bouton('Exporter maintenant', 'download', function () { simuler('export de la base'); }, 'primary'))]);
  });

  ecran('rls-opacite', {
    title: 'Preuve d’opacité', description: 'Ce que le relais détient et ne détient pas : la démonstration que l’hébergeur ne peut rien lire.',
    regle: 'Le relais n’a <strong>aucun code de chiffrement ni clé</strong>. Un test d’opacité décode les enveloppes et mesure leur entropie (plus de 7 bits par octet).',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Clé de clinique au relais', 'Aucune', 'key-round', 'success'), kpi('Entropie moyenne', '7,98 bits/octet', 'binary', 'success'), kpi('Noms de collection lisibles', 0, 'eye-off', 'success')]),
      U.card('Ce que le relais voit', tableau(['Information', 'Visible ?'], [['Identifiant et état de l’appareil', 'oui'], ['Sens, rang, taille, date d’une enveloppe', 'oui'], ['Contenu d’une enveloppe', U.badge('non (chiffré)', 'success')], ['Nom d’une collection ou d’un champ', U.badge('non', 'success')], ['La clé de clinique', U.badge('non', 'success')]]))]);
  });
})(window);
