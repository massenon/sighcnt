/* =============================================================================
 * POSTE MÈRE — les 22 modules complémentaires du mode mère (prototype de la cible)
 * -----------------------------------------------------------------------------
 * Ces écrans N EXISTENT QUE sur le serveur local de la clinique : le même exécutable que les postes fileuls, mais
 * activé en mode mère. Ils pilotent la synchronisation, la supervision, la sécurité et le cycle de vie du serveur.
 * Source : docs/architecture/MODULES-COMPLEMENTAIRES-MERE.md (M-01 à M-22).
 *
 * PROTOTYPE : toutes les données ci-dessous sont des données de DÉMONSTRATION figées. Aucun écran ne parle à un
 * service réel ; les gestes annoncent ce qu ils feraient (toast « Simulation »), sauf quand ils sont locaux.
 * Quand un écran existe déjà en Dart (M-01, M-02, M-03, M-08, M-12), sa maquette en est la référence visuelle.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, K = global.SIGH.kit;
  var el = C.el;

  /* --- briques communes ---------------------------------------------------------------------------------------- */
  var ETATS = { ok: ['OK', 'success'], attention: ['À surveiller', 'warning'], alerte: ['ALERTE', 'danger'], inconnu: ['Inconnu', 'neutral'] };
  function etat(e) { var x = ETATS[e] || ETATS.inconnu; return U.badge(x[0], x[1]); }
  function kpi(label, value, icon, tone, hint) { return { label: label, value: String(value), icon: icon, tone: tone || 'navy', hint: hint }; }
  function note(html, tone, icon) { return K.note(html, { tone: tone || 'info', icon: icon || 'info' }); }
  function simuler(geste) { U.toast('Simulation — ' + geste + '. Le service de la mère le ferait ici.', { type: 'info' }); }
  function bouton(label, icon, onclick, variante) {
    var b = el('button.btn.btn-sm', { type: 'button', class: variante === 'danger' ? 'btn-danger' : (variante === 'primary' ? 'btn-primary' : 'btn-secondary') });
    b.appendChild(el('i', { dataset: { lucide: icon } })); b.appendChild(document.createTextNode(' ' + label));
    b.addEventListener('click', onclick); return b;
  }
  function barre() { var d = el('div.flex.flex-wrap.gap-2'); Array.prototype.slice.call(arguments).forEach(function (x) { d.appendChild(x); }); return d; }
  function carte(titre, contenu) { return U.card(titre, contenu); }
  function tableau(colonnes, lignes, vide) {
    return lignes.length ? K.miniTable(colonnes, lignes) : U.empty(vide || 'Rien à afficher.', { icon: 'inbox' });
  }
  function il(min) { return min < 1 ? 'à l’instant' : (min < 60 ? 'il y a ' + min + ' min' : 'il y a ' + Math.round(min / 60) + ' h'); }
  var BANDEAU = 'Prototype de la <strong>cible</strong> : ce module n’existe que sur le <strong>poste mère</strong> (serveur local). Données de démonstration.';
  function page(root, blocs) {
    var h = el('div.space-y-4'); h.appendChild(note(BANDEAU, 'neutral', 'server'));
    blocs.forEach(function (b) { if (b) h.appendChild(b); });
    root.appendChild(h); return h;
  }

  /* --- données de démonstration ---------------------------------------------------------------------------------- */
  var APPAREILS = [
    { id: 'u-01', nom: 'Caisse principale', role: 'fileul', agent: 'DIEYABIDI Aïssatou', etat: 'actif', contact: 0, retard: 0, derive: 0, version: '1.0.3' },
    { id: 'u-02', nom: 'Accueil', role: 'fileul', agent: 'OROU YO Edmond', etat: 'actif', contact: 0, retard: 2, derive: 0, version: '1.0.3' },
    { id: 'u-03', nom: 'Laboratoire', role: 'fileul', agent: 'KINNOU A. Ganiou', etat: 'actif', contact: 1, retard: 0, derive: 0, version: '1.0.3' },
    { id: 'u-04', nom: 'Pharmacie', role: 'fileul', agent: 'DIEYABIDI Aïssatou', etat: 'actif', contact: 3, retard: 5, derive: 410000, version: '1.0.2' },
    { id: 'u-05', nom: 'Salle de soins', role: 'fileul', agent: 'BADO BANI A. B. Zoulehath', etat: 'actif', contact: 190, retard: 14, derive: 0, version: '1.0.3' },
    { id: 'u-06', nom: 'Mobile — Dr YENI M’PO', role: 'mobile · soignant', agent: 'YENI M’PO Florent', etat: 'actif', contact: 12, retard: 0, derive: 0, version: '1.0.1' },
    { id: 'u-07', nom: 'Mobile — Sage-femme de garde', role: 'mobile · soignant', agent: 'Sage-femme (garde)', etat: 'actif', contact: 45, retard: 3, derive: 0, version: '1.0.1' },
    { id: 'u-08', nom: 'Mobile — Réception de secours', role: 'mobile · réception', agent: 'OROU YO Edmond', etat: 'actif', contact: 600, retard: 0, derive: 0, version: '1.0.1' },
    { id: 'u-09', nom: 'Ancien poste Archives', role: 'fileul', agent: '—', etat: 'revoque', contact: 43200, retard: 0, derive: 0, version: '0.9.8' },
  ];
  var CONFLITS = [
    { id: 7, coll: 'patients', fiche: 'CNT/12/26', champ: 'telephone', a: '97 11 22 33', b: '96 44 55 66', de: 'Accueil / Caisse' },
    { id: 8, coll: 'patients', fiche: 'CNT/1140/26', champ: 'doublon_possible', a: 'CNT/1140/26 · AKPO Marc, 34 a', b: 'CNT/871/24 · AKPO Marc, 34 a', de: 'Mobile réception' },
    { id: 9, coll: 'rendezVous', fiche: 'RDV-2210', champ: 'date', a: '03/11/2026 09:00', b: '03/11/2026 10:30', de: 'Accueil / Dr YENI' },
  ];
  var REFUS = [
    { appareil: 'Pharmacie', op: 'sortie stock · PARA500', code: 'STOCK_INSUFFISANT', motif: 'Stock disponible : 4 ; demandé : 6 (RG-03).', geste: 'Corriger la quantité ou demander un transfert du gros.', age: 18 },
    { appareil: 'Mobile — Réception de secours', op: 'facture · FC-PROV-3', code: 'PROFIL_NON_COUVERT', motif: 'Le profil « réception de secours » ne couvre pas la caisse.', geste: 'Ressaisir la facture à la caisse.', age: 95 },
    { appareil: 'Salle de soins', op: 'administration · ORD-4471', code: 'FICHE_ARCHIVEE', motif: 'Ordonnance archivée : non modifiable (RG-14).', geste: 'Restaurer l’ordonnance depuis la corbeille, puis ressaisir.', age: 240 },
  ];
  var OPERATIONS = (function () {
    var rnd = C.seeded(4410), types = ['creer', 'modifier', 'modifier', 'archiver', 'sortie'], colls = ['patients', 'factures', 'consultations', 'demandesAnalyses', 'stock', 'rendezVous'];
    var postes = ['Caisse principale', 'Accueil', 'Laboratoire', 'Pharmacie', 'Salle de soins', 'Mobile — Dr YENI M’PO'];
    var out = [];
    for (var i = 0; i < 60; i++) {
      out.push({ seq: 12480 - i, hlc: Date.now() - i * 91000, appareil: postes[Math.floor(rnd() * postes.length)], type: types[Math.floor(rnd() * types.length)], coll: colls[Math.floor(rnd() * colls.length)], fiche: 'F' + (9000 + Math.floor(rnd() * 900)) });
    }
    return out;
  })();
  var EVENEMENTS = [
    { q: 2, n: 'info', s: 'mere', m: 'Réplication vers le relais : 14 enveloppes déposées.' },
    { q: 11, n: 'alerte', s: 'sync', m: 'Poste « Pharmacie » : horloge en avance de 6 min 50 s (seuil 2 min).' },
    { q: 34, n: 'info', s: 'sauvegarde', m: 'Sauvegarde chiffrée effectuée (191 Mo, conservation 7 jours).' },
    { q: 95, n: 'erreur', s: 'relais', m: 'Relais injoignable (délai dépassé) — nouvelle tentative dans 30 s.' },
    { q: 96, n: 'info', s: 'relais', m: 'Liaison rétablie ; retard de réplication résorbé.' },
    { q: 240, n: 'alerte', s: 'securite', m: 'Enveloppe refusée : authentification échouée (appareil u-07, rang 4).' },
    { q: 600, n: 'info', s: 'mere', m: 'Démarrage du service de synchronisation (époque 3).' },
  ];

  var DEF = global.SIGH.screen;
  function ecran(id, meta, fn) {
    DEF(id, { title: meta.title, description: meta.description, regle: meta.regle, render: function (root) { fn(root); return null; } });
  }

  /* =========================== A. EXPLOITATION DE LA SYNCHRONISATION ===================================== */
  ecran('mere-supervision', {
    title: 'Supervision', description: 'Santé de la mère d’un coup d’œil : base, disque, sauvegarde, relais, postes, horloges, intégrité.',
    regle: 'Un contrôle qui ne peut pas être mesuré se lit <strong>« Inconnu »</strong> et ne rassure jamais : l’état global est le <strong>pire</strong> des contrôles.',
  }, function (root) {
    var controles = [
      ['Base de données', 'ok', 'PostgreSQL 16 · 4,8 Go · parité tables ↔ magasin : 0 écart'],
      ['Espace disque', 'ok', '212 Go libres (seuil d’attention 10 Go, d’alerte 2 Go)'],
      ['Sauvegarde', 'ok', 'Dernière : aujourd’hui 02:10 (chiffrée) · conservation 7 jours'],
      ['Relais en ligne', 'attention', 'Retard de réplication : 14 opérations · dernier battement il y a 40 s'],
      ['Poste « Pharmacie »', 'attention', 'Horloge en avance de 6 min 50 s'],
      ['Poste « Salle de soins »', 'attention', 'Silencieux depuis 3 h 10'],
      ['Intégrité', 'ok', 'Aucun appareil bloqué, aucune enveloppe altérée'],
      ['Conflits', 'attention', '3 conflits ouverts à arbitrer'],
      ['Erreurs internes', 'ok', 'Aucune sur 24 h'],
    ];
    var pire = controles.some(function (c) { return c[1] === 'alerte'; }) ? 'alerte' : (controles.some(function (c) { return c[1] === 'attention'; }) ? 'attention' : 'ok');
    page(root, [
      U.kpiGrid([kpi('Santé de la mère', ETATS[pire][0], 'heart-pulse', pire === 'ok' ? 'success' : 'warning'), kpi('Époque', 3, 'history'), kpi('Opérations', '12 480', 'list-ordered'), kpi('Retard vers le relais', 14, 'cloud-upload', 'warning')]),
      barre(bouton('Sauvegarder maintenant', 'save', function () { simuler('sauvegarde chiffrée immédiate'); }, 'primary'), bouton('Actualiser', 'refresh-cw', function () { U.toast('Contrôles actualisés.', { type: 'success' }); })),
      carte('Contrôles', tableau(['Contrôle', 'État', 'Détail'], controles.map(function (c) { return [c[0], etat(c[1]), c[2]]; }))),
    ]);
  });

  ecran('mere-appareils', {
    title: 'Appareils et appairage', description: 'Postes fileuls et mobiles de la clinique : contact, retard, horloge, version ; appairer, révoquer, débloquer.',
    regle: 'Un code d’appairage <strong>ne sert qu’une fois</strong> et expire. Un mobile reçoit en plus la <strong>clé de clinique</strong> par QR — jamais par le relais. Un appareil révoqué reste dans la liste (RG-14).',
  }, function (root) {
    var hote = el('div.space-y-4');
    function peindre() {
      C.clear(hote);
      hote.appendChild(tableau(['Appareil', 'Type', 'Agent', 'Dernier contact', 'Retard', 'Horloge', 'Version', 'État', ''], APPAREILS.map(function (a) {
        var derive = a.derive ? Math.round(a.derive / 1000) + ' s' : 'ok';
        return [a.nom, a.role, a.agent, a.etat === 'revoque' ? 'le ' + C.dateFR(new Date(Date.now() - a.contact * 60000)) : il(a.contact), a.retard + ' op.', a.derive ? U.badge('Dérive ' + derive, 'warning') : '—', a.version,
          a.etat === 'revoque' ? U.badge('Révoqué', 'neutral') : U.badge('Actif', 'success'),
          a.etat === 'revoque' ? '' : bouton('Révoquer', 'ban', function () {
            U.confirm({ title: 'Révoquer ' + a.nom + ' ?', message: 'L’appareil <strong>cessera de synchroniser</strong> et sera effacé au prochain contact s’il s’agit d’un mobile. Ses opérations non envoyées sont exportées d’abord.', confirmLabel: 'Révoquer', danger: true }).then(function (ok) {
              if (ok) { a.etat = 'revoque'; U.toast('Appareil révoqué (simulation).', { type: 'success' }); peindre(); }
            });
          }, 'danger')];
      })));
    }
    function code(mobile) {
      var c = Array.from({ length: 8 }, function () { return 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'.charAt(Math.floor(Math.random() * 31)); }).join('');
      var corps = el('div.space-y-3', {}, el('p.text-sm', { text: 'Valable 15 minutes, à usage unique.' }), el('p.text-3xl.font-mono.font-bold.tracking-widest.text-navy-900', { text: c }));
      if (mobile) { corps.appendChild(el('p.text-sm.text-slate-600', { text: 'Clé de clinique à scanner sur le téléphone (clé de DÉMONSTRATION) :' })); try { corps.appendChild(C.qr('SIGH-DEMO-CLE-' + c)); } catch (e) { /* encodeur absent hors serveur */ } }
      U.modal({ title: mobile ? 'Code d’appairage — mobile' : 'Code d’appairage — poste', body: corps, size: 'sm' });
    }
    page(root, [
      U.kpiGrid([kpi('Appareils actifs', APPAREILS.filter(function (a) { return a.etat === 'actif'; }).length, 'monitor-smartphone', 'success'), kpi('Postes fileuls', 5, 'monitor'), kpi('Mobiles', 3, 'smartphone'), kpi('Horloge à vérifier', 1, 'clock-alert', 'warning', 'Dérive supérieure à 2 minutes')]),
      barre(bouton('Appairer un poste', 'plus', function () { code(false); }, 'primary'), bouton('Appairer un mobile', 'smartphone', function () { code(true); }, 'primary'), bouton('Renvoyer vers tous', 'send', function () { simuler('renvoi du journal à tous les appareils (chacun acquitte)'); })),
      hote,
    ]);
    peindre();
  });

  ecran('mere-conflits', {
    title: 'Conflits et doublons', description: 'Ce que la mère ne peut pas trancher seule : même champ modifié sur deux postes, homonymes créés hors ligne.',
    regle: 'Les conflits portent des <strong>données de santé</strong> : ils s’arbitrent ICI et nulle part ailleurs ; le panneau en ligne n’en montre que le nombre. Un « doublon possible » n’est jamais refusé : on le classe (le code patient ne change pas, RG-01).',
  }, function (root) {
    var lignes = CONFLITS.map(function (c) {
      var doublon = c.champ === 'doublon_possible';
      return [String(c.id), c.coll + ' · ' + c.fiche, doublon ? U.badge('Doublon possible', 'warning') : c.champ, c.a, c.b, c.de,
        barre(bouton(doublon ? 'Fusionner à la main' : 'Garder A', 'check', function () { simuler('décision enregistrée et diffusée à tous les postes'); }), bouton(doublon ? 'Ce n’est pas un doublon' : 'Garder B', 'x', function () { simuler('décision enregistrée et diffusée'); }))];
    });
    page(root, [U.kpiGrid([kpi('Ouverts', 3, 'git-compare', 'warning'), kpi('Doublons possibles', 1, 'copy', 'warning'), kpi('Tranchés (30 j)', 18, 'check-check', 'success')]),
      carte('À arbitrer', tableau(['N°', 'Fiche', 'Champ', 'Version A', 'Version B', 'Origine', 'Décision'], lignes, 'Aucun conflit ouvert.'))]);
  });

  ecran('mere-a-traiter', {
    title: '« À traiter » consolidé', description: 'Toutes les opérations refusées par la mère, tous appareils confondus, avec la cause nommée et le geste de correction.',
    regle: 'Un refus n’est jamais muet : il porte un <strong>code</strong>, un <strong>motif</strong> et le <strong>geste</strong> qui le résout. L’opération reste sur l’appareil d’origine, rien n’est perdu.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Refus ouverts', REFUS.length, 'octagon-alert', 'warning'), kpi('Appareils concernés', 3, 'monitor'), kpi('Plus ancien', '4 h', 'clock')]),
      carte('Opérations refusées', tableau(['Appareil', 'Opération', 'Code', 'Motif', 'Geste de correction', 'Âge', ''], REFUS.map(function (r) {
        return [r.appareil, r.op, el('code.text-xs', { text: r.code }), r.motif, r.geste, il(r.age), bouton('Relancer', 'rotate-cw', function () { simuler('relance auprès de l’appareil'); })];
      })))]);
  });

  ecran('mere-journal-operations', {
    title: 'Journal des opérations', description: 'Explorateur du journal : chaque geste d’écriture, dans l’ordre posé par la mère (séquence), jamais par l’horloge d’un poste.',
    regle: 'L’ordre vient de la <strong>séquence</strong> (<code>seq</code>) attribuée par la mère. Le journal ne se modifie pas : une correction est une <strong>nouvelle opération</strong>. Aucune suppression ne se propage (RG-14).',
  }, function (root) {
    var tab = U.dataTable({
      title: 'Opérations récentes', pageSize: 15, searchable: true, exportName: 'journal-operations',
      rows: OPERATIONS.map(function (o) { return { seq: o.seq, quand: C.dateHeure(new Date(o.hlc)), appareil: o.appareil, type: o.type, coll: o.coll, fiche: o.fiche }; }),
      columns: [{ key: 'seq', label: 'Séq.' }, { key: 'quand', label: 'Date' }, { key: 'appareil', label: 'Appareil' }, { key: 'type', label: 'Type' }, { key: 'coll', label: 'Collection' }, { key: 'fiche', label: 'Fiche' }],
    });
    var curseurs = tableau(['Appareil', 'Curseur (dernière séq. reçue)', 'Retard'], APPAREILS.filter(function (a) { return a.etat === 'actif'; }).map(function (a, i) { return [a.nom, String(12480 - a.retard), a.retard + ' op.']; }));
    page(root, [U.kpiGrid([kpi('Séquence courante', '12 480', 'list-ordered'), kpi('Époque', 3, 'history'), kpi('Appareils à jour', 6, 'check-check', 'success')]),
      barre(bouton('Renvoyer vers tous', 'send', function () { simuler('rejeu du journal à tous les appareils ; accusés attendus'); }, 'primary')),
      tab, carte('Curseurs par appareil', curseurs)]);
  });

  ecran('mere-plages-baux', {
    title: 'Plages de numéros et baux de stock', description: 'Codes patients réservés à chaque appareil pour travailler hors ligne ; quotas de stock alloués par article.',
    regle: 'Hors ligne, un poste consomme sa <strong>plage</strong> ; épuisée, il utilise un numéro <strong>provisoire</strong> (<code>PROV-</code>) réconcilié à l’arrivée. Un <strong>bail</strong> garantit qu’aucun stock ne devient négatif (RG-03).',
  }, function (root) {
    var plages = [['Caisse principale', '1141 → 1190', 31, 'ok'], ['Accueil', '1191 → 1240', 47, 'ok'], ['Mobile — Réception de secours', '1241 → 1260', 3, 'attention'], ['Mobile — Dr YENI M’PO', '1261 → 1280', 12, 'ok']];
    var baux = [['Salle de soins', 'Gants latex M', 40, 31, 9], ['Pharmacie', 'Paracétamol 500 mg', 200, 148, 52], ['Laboratoire', 'Tubes EDTA', 120, 120, 0]];
    page(root, [U.kpiGrid([kpi('Plages actives', 4, 'hash'), kpi('Numéros PROV- à réconcilier', 2, 'shuffle', 'warning'), kpi('Baux ouverts', 3, 'package-check')]),
      barre(bouton('Allouer une plage', 'plus', function () { simuler('allocation d’une plage de 50 numéros'); }, 'primary'), bouton('Accorder un bail', 'package-plus', function () { simuler('bail de stock accordé'); })),
      carte('Plages de codes patients', tableau(['Appareil', 'Plage', 'Restants', 'État'], plages.map(function (p) { return [p[0], p[1], String(p[2]), etat(p[3])]; }))),
      carte('Baux de stock', tableau(['Appareil', 'Article', 'Alloué', 'Consommé', 'Restant'], baux.map(function (b) { return [b[0], b[1], String(b[2]), String(b[3]), String(b[4])]; })))]);
  });

  ecran('mere-lots-tournee', {
    title: 'Lots de tournée (mobiles)', description: 'Les dossiers déposés chaque jour sur le téléphone d’un soignant, leur validité et ce qui n’est pas encore remonté.',
    regle: 'Un lot est <strong>chiffré</strong>, déposé dans la boîte de l’appareil et <strong>expire</strong> : passé le délai, les dossiers s’effacent du téléphone, sauf ce qui n’est pas parti.',
  }, function (root) {
    var lots = [['Mobile — Dr YENI M’PO', 'Visites à domicile', 8, 'Aujourd’hui 06:30', 'Aujourd’hui 20:00', 2, 'actif'], ['Mobile — Sage-femme de garde', 'Suivi post-partum', 5, 'Hier 18:00', 'Aujourd’hui 18:00', 0, 'actif'], ['Mobile — Dr YENI M’PO', 'Visites à domicile', 6, 'Avant-hier', 'Hier 20:00', 1, 'expire']];
    page(root, [U.kpiGrid([kpi('Lots actifs', 2, 'package', 'success'), kpi('Dossiers sur le terrain', 13, 'users'), kpi('Saisies à remonter', 2, 'upload', 'warning')]),
      barre(bouton('Composer un lot', 'package-plus', function () { simuler('composition du lot : choix des dossiers, du soignant et de la durée'); }, 'primary')),
      carte('Lots', tableau(['Appareil', 'Tournée', 'Dossiers', 'Déposé', 'Expire', 'Saisies non parties', 'État'], lots.map(function (l) { return [l[0], l[1], String(l[2]), l[3], l[4], String(l[5]), l[6] === 'actif' ? U.badge('Actif', 'success') : U.badge('Expiré', 'neutral')]; }))),
      note('Une saisie faite à domicile <strong>remonte par le relais</strong> dès que le téléphone retrouve le réseau ; la mère la relève, la distribue aux postes et accuse réception.', 'info', 'route')]);
  });

  /* =========================== B. SÉCURITÉ ET CONTINUITÉ ================================================= */
  ecran('mere-journal-technique', {
    title: 'Journal technique', description: 'Évènements du service de la mère : démarrages, erreurs, alertes, sauvegardes, liaison avec le relais.',
    regle: 'Distinct du <strong>journal d’audit</strong> (qui a fait quoi, RG-12) : celui-ci dit ce que le <strong>service</strong> a fait. Il ne contient aucune donnée de patient.',
  }, function (root) {
    var tab = U.dataTable({
      title: 'Évènements', pageSize: 10, searchable: true, exportName: 'journal-technique',
      rows: EVENEMENTS.map(function (e) { return { quand: il(e.q), niveau: e.n, source: e.s, message: e.m }; }),
      columns: [{ key: 'quand', label: 'Quand' }, { key: 'niveau', label: 'Niveau', render: function (r) { return U.badge(r.niveau, r.niveau === 'erreur' ? 'danger' : (r.niveau === 'alerte' ? 'warning' : 'neutral')); } }, { key: 'source', label: 'Source' }, { key: 'message', label: 'Message' }],
    });
    page(root, [U.kpiGrid([kpi('Évènements (24 h)', 41, 'scroll-text'), kpi('Alertes', 2, 'triangle-alert', 'warning'), kpi('Erreurs', 1, 'circle-x', 'danger')]), tab]);
  });

  ecran('mere-sauvegardes', {
    title: 'Sauvegardes et restauration', description: 'Sauvegarde chiffrée quotidienne, vérification de restauration, restauration depuis le relais, remplacement de la mère.',
    regle: 'La restauration passe par le <strong>journal chiffré du relais</strong> avec la <strong>clé de clinique</strong> ; elle <strong>incrémente l’époque</strong> pour que les anciens appareils ne ressuscitent rien. Une mauvaise clé n’écrit <strong>rien</strong>.',
  }, function (root) {
    var sauvegardes = [['Aujourd’hui 02:10', '191 Mo', 'quotidienne', 'Vérifiée'], ['Hier 02:10', '189 Mo', 'quotidienne', 'Vérifiée'], ['Il y a 2 jours', '187 Mo', 'quotidienne', 'Non vérifiée'], ['Avant réinitialisation (15/10)', '172 Mo', 'préalable', 'Vérifiée']];
    var tabs = U.tabs([
      { id: 'liste', label: 'Sauvegardes', render: function (p) { p.appendChild(barre(bouton('Sauvegarder maintenant', 'save', function () { simuler('sauvegarde chiffrée'); }, 'primary'), bouton('Vérifier la dernière', 'shield-check', function () { simuler('restauration à blanc dans une base temporaire, puis comparaison des empreintes'); }))); p.appendChild(el('div.mt-3')); p.appendChild(tableau(['Date', 'Taille', 'Nature', 'Vérification'], sauvegardes)); } },
      { id: 'restaurer', label: 'Restaurer', render: function (p) {
        p.appendChild(note('<strong>Opération grave.</strong> Une sauvegarde préalable est faite, l’époque est incrémentée, les appareils reçoivent la nouvelle époque. Les opérations non envoyées d’un appareil sont exportées avant purge.', 'warning', 'triangle-alert'));
        p.appendChild(el('div.mt-3.flex.gap-2', {}, bouton('Restaurer depuis une sauvegarde', 'archive-restore', function () { simuler('choix d’une sauvegarde, confirmation à deux profils'); }, 'danger'), bouton('Restaurer depuis le relais', 'cloud-download', function () { simuler('relecture du journal du relais déchiffré avec la clé de clinique'); }, 'danger')));
      } },
      { id: 'remplacement', label: 'Remplacer la mère', render: function (p) {
        p.appendChild(el('ol.list-decimal.pl-5.space-y-2.text-sm', {}, ['Sur la nouvelle machine : installer SIGH-CNT et lancer l’assistant de première mise en service (M-20), choix « restaurer une mère existante ».', 'Saisir le secret de la mère et la clé de clinique (copie papier sous scellé).', 'L’application relit le journal du relais, reconstruit la base et compare l’empreinte de toutes les fiches.', 'Arrêter l’ancienne mère : un seul poste mère par clinique. L’époque est incrémentée.', 'Réappairer les postes qui ne retrouvent pas la nouvelle adresse.'].map(function (t) { return el('li', { text: t }); })));
      } },
    ]);
    page(root, [U.kpiGrid([kpi('Dernière sauvegarde', 'aujourd’hui 02:10', 'database-backup', 'success'), kpi('Conservation', '7 jours', 'calendar-clock'), kpi('Dernière vérification', 'hier', 'shield-check', 'success')]), tabs]);
  });

  ecran('mere-cle-clinique', {
    title: 'Clé de clinique', description: 'La clé qui chiffre tout ce qui quitte le serveur : empreinte de contrôle, copie papier sous scellé, QR d’appairage mobile, rotation.',
    regle: 'La clé <strong>n’est jamais envoyée au relais</strong>. Sa perte rend le relais et les sauvegardes <strong>irrécupérables</strong> : une copie papier sous scellé est obligatoire. <em>Détenteur de la copie : à désigner par la Direction.</em>',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Empreinte (SHA-256, 8 premiers)', 'A41C-9E07', 'fingerprint'), kpi('Créée le', '12/10/2026', 'calendar'), kpi('Copie papier', 'Non attestée', 'file-lock', 'warning', 'Détenteur à désigner')]),
      note('<strong>Détenteur de la copie papier non désigné.</strong> Tant qu’il ne l’est pas, la perte du serveur et de son disque serait définitive pour tout ce qui a été sauvegardé.', 'warning', 'triangle-alert'),
      barre(bouton('Imprimer la copie papier', 'printer', function () { simuler('édition de la clé en 8 groupes lisibles + QR, à glisser sous scellé'); }, 'primary'), bouton('Afficher le QR d’appairage mobile', 'qr-code', function () { simuler('QR de la clé, affiché 60 secondes'); }), bouton('Faire tourner la clé', 'refresh-cw', function () { simuler('rotation : nouvelle clé, rechiffrement progressif, anciens appareils réappairés'); }, 'danger')),
      carte('Attestation de la copie papier', tableau(['Date', 'Détenteur', 'Scellé n°', 'Contrôlé par'], [['—', 'À désigner', '—', '—']], ''))]);
  });

  ecran('mere-integrite', {
    title: 'Intégrité et altérations', description: 'Enveloppes altérées ou manquantes, appareils bloqués, décisions de l’administrateur.',
    regle: 'Une enveloppe dont l’authentification échoue, ou un <strong>trou</strong> dans la suite des rangs, <strong>bloque l’appareil</strong> concerné sans toucher aux autres ; la donnée suspecte n’est <strong>jamais appliquée</strong>.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Appareils bloqués', 1, 'shield-alert', 'danger'), kpi('Enveloppes altérées (30 j)', 1, 'file-warning', 'warning'), kpi('Trous détectés', 0, 'unplug', 'success')]),
      carte('Appareils bloqués', tableau(['Appareil', 'Cause', 'Détecté', 'Rang', ''], [['Mobile — Sage-femme de garde', U.badge('Authentification échouée', 'danger'), il(240), '4', barre(bouton('Débloquer', 'unlock', function () { simuler('déblocage après vérification en personne'); }), bouton('Révoquer', 'ban', function () { simuler('révocation'); }, 'danger'))]])),
      note('Avant de débloquer : vérifier l’appareil <strong>en personne</strong> (perdu ? volé ? relais compromis ?). Débloquer sans vérifier annule le contrôle.', 'info', 'shield')]);
  });

  ecran('mere-reinit', {
    title: 'Réinitialisation de production', description: 'Vider l’activité (tests de mise en service) en gardant les essentiels : tarifs, secteurs, comptes, droits, catalogues.',
    regle: 'Fenêtre <strong>fermée par défaut</strong> et qui se referme d’elle-même ; <strong>second profil</strong> de confirmation ; <strong>sauvegarde préalable</strong> ; <strong>époque + 1</strong> ; opérations non envoyées <strong>exportées</strong> avant purge. Le bouton est <strong>absent</strong>, pas grisé, quand la fenêtre est fermée.',
  }, function (root) {
    var ouverte = false, hote = el('div.space-y-3');
    function peindre() {
      C.clear(hote);
      if (!ouverte) { hote.appendChild(note('La fenêtre de réinitialisation est <strong>fermée</strong>.', 'neutral', 'lock')); hote.appendChild(bouton('Ouvrir la fenêtre (30 min)', 'unlock', function () { ouverte = true; peindre(); }, 'primary')); return; }
      hote.appendChild(note('Fenêtre ouverte — elle se refermera seule dans 30 minutes.', 'warning', 'triangle-alert'));
      var confirmation = el('input.input', { type: 'text', placeholder: 'Taper RÉINITIALISER' }), second = el('input.input', { type: 'text', placeholder: 'Identifiant du second profil (DAF / Direction)' });
      hote.appendChild(el('div', { class: 'grid gap-3 sm:grid-cols-2' }, confirmation, second));
      hote.appendChild(barre(bouton('Réinitialiser', 'trash-2', function () {
        if (confirmation.value !== 'RÉINITIALISER' || !second.value.trim()) { U.toast('Confirmation et second profil obligatoires.', { type: 'error' }); return; }
        simuler('sauvegarde préalable, purge de l’activité, essentiels conservés, époque + 1'); ouverte = false; peindre();
      }, 'danger'), bouton('Refermer la fenêtre', 'lock', function () { ouverte = false; peindre(); })));
    }
    page(root, [carte('Fenêtre de réinitialisation', hote), carte('Ce qui est conservé', el('p.text-sm.text-slate-600', { text: 'Tarifs, secteurs, catalogues du laboratoire et de l’imagerie, comptes, matrice des droits, modules actifs, règles datées, modèles. Tout le reste (patients, factures, stocks, écritures) est archivé puis purgé de la base active.' }))]);
    peindre();
  });

  /* =========================== C. LIAISON AVEC LE RELAIS ================================================== */
  ecran('mere-relais', {
    title: 'Relais en ligne', description: 'État de la liaison avec le relais (hébergement mutualisé) : battement, retard de réplication, secret de la mère.',
    regle: 'La mère <strong>interroge</strong> le relais toutes les 10 à 15 s ; le relais n’appelle jamais la mère. Il est <strong>opaque</strong> : il ne détient aucune clé et ne voit que des enveloppes chiffrées.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Liaison', 'Établie', 'cloud', 'success'), kpi('Dernier battement', 'il y a 40 s', 'activity', 'success'), kpi('Retard de réplication', '14 op.', 'cloud-upload', 'warning'), kpi('Enveloppes au relais', '3 912', 'mails')]),
      barre(bouton('Tester la liaison', 'plug-zap', function () { U.toast('Relais joignable (simulation) — 182 ms.', { type: 'success' }); }, 'primary'), bouton('Faire tourner le secret de la mère', 'key-round', function () { simuler('nouveau secret, à reporter dans le .env du relais'); }, 'danger')),
      carte('Derniers échanges', tableau(['Quand', 'Sens', 'Contenu', 'Résultat'], [[il(2), 'mère → relais', '14 enveloppes (journal)', U.badge('Reçu', 'success')], [il(2), 'relais → mère', '1 enveloppe de mobile', U.badge('Appliquée', 'success')], [il(95), 'mère → relais', 'battement', U.badge('Délai dépassé', 'danger')], [il(96), 'mère → relais', 'battement', U.badge('Reçu', 'success')]]))]);
  });

  ecran('mere-indicateurs', {
    title: 'Indicateurs publiés', description: 'Ce que la mère publie au relais pour la supervision à distance : des compteurs, jamais un nom de patient.',
    regle: 'Les indicateurs sont <strong>le seul contenu en clair</strong> du relais. Aucun nom, aucun motif, aucun diagnostic. L’aperçu ci-dessous est l’<strong>exact contenu</strong> du dernier envoi.',
  }, function (root) {
    var json = { quand: new Date().toISOString(), epoque: 3, seq: 12480, appareils_actifs: 8, conflits_ouverts: 3, appareils_bloques: 1, derniere_sauvegarde: 'aujourd’hui 02:10', retard_replication: 14 };
    page(root, [U.kpiGrid([kpi('Fréquence', '1 min', 'timer'), kpi('Champs publiés', Object.keys(json).length, 'list'), kpi('Données de santé', 0, 'shield-check', 'success')]),
      carte('Dernier envoi (aperçu exact)', el('pre.text-xs.bg-slate-50.border.border-slate-200.rounded.p-3.overflow-x-auto', { text: JSON.stringify(json, null, 2) })),
      note('Sert au superadmin en ligne : « la mère est-elle vivante, à jour, sauvegardée ? ». Pas à lire un dossier.', 'info', 'eye-off')]);
  });

  /* =========================== D. PLATEFORME LOCALE ======================================================= */
  ecran('mere-service', {
    title: 'Service et démarrage', description: 'Activation du mode mère sur ce serveur, démarrage automatique, ports, arrêt propre.',
    regle: 'Il n’y a <strong>qu’un seul poste mère</strong> par clinique : l’activation exige le secret de la mère et la clé de clinique, et se <strong>refuse en la nommant</strong> si une autre mère est déjà active.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Mode de ce poste', 'Mère', 'server', 'success'), kpi('Service', 'En marche', 'play', 'success'), kpi('Démarrage automatique', 'Activé', 'power', 'success'), kpi('Port', '9000', 'network')]),
      barre(bouton('Arrêter proprement', 'square', function () { simuler('arrêt : fin des envois en cours, fermeture de la base'); }, 'danger'), bouton('Redémarrer', 'rotate-cw', function () { simuler('redémarrage du service'); }), bouton('Désactiver le mode mère', 'server-off', function () { simuler('retour en poste fileul ; les données sont conservées'); }, 'danger')),
      carte('Configuration', tableau(['Paramètre', 'Valeur'], [['Service Windows / systemd', 'sigh-mere (automatique)'], ['Dossier de données', 'D:\\SIGH\\donnees'], ['Dossier des sauvegardes', 'D:\\SIGH\\sauvegardes'], ['Relais', 'https://relais.exemple.bj'], ['Journaux', 'D:\\SIGH\\journaux (30 jours)']]))]);
  });

  ecran('mere-base', {
    title: 'Base de données locale', description: 'PostgreSQL du serveur : état, taille, version de schéma, migrations, parité avec le magasin.',
    regle: 'Le magasin des fiches reste l’autorité ; les <strong>tables par module</strong> en sont une copie relationnelle. La parité est vérifiée : <strong>0 écart</strong> attendu.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Moteur', 'PostgreSQL 16', 'database', 'success'), kpi('Taille', '4,8 Go', 'hard-drive'), kpi('Schéma', 'v66', 'git-branch'), kpi('Parité', '0 écart', 'scale', 'success')]),
      barre(bouton('Vérifier la parité', 'scale', function () { U.toast('123 collections · 10 558 fiches · 0 écart (simulation).', { type: 'success' }); }, 'primary'), bouton('Reconstruire les tables', 'hammer', function () { simuler('reconstruction de la copie relationnelle depuis le magasin'); })),
      carte('Migrations appliquées', tableau(['Version', 'Date', 'Résumé'], [['v66', '20/10/2026', 'Exercices, suivi des ventes par secteur'], ['v65', '20/10/2026', 'Rôle biomédical supprimé'], ['v64', '12/10/2026', 'Badges, jetons d’enquête']]))]);
  });

  ecran('mere-reseau', {
    title: 'Réseau local', description: 'Adresses de la mère, accessibilité depuis les postes, certificat TLS du réseau local, aide pare-feu.',
    regle: 'Les postes joignent la mère par son adresse locale. Un poste qui ne la trouve plus se déclare <strong>hors ligne</strong> et continue de travailler ; il rattrape au retour.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Adresse locale', '192.168.1.10', 'network'), kpi('Port', '9000', 'plug'), kpi('Certificat TLS', 'Valide 11 mois', 'lock', 'success'), kpi('Postes joignables', '5 / 5', 'wifi', 'success')]),
      barre(bouton('Tester depuis un poste', 'radio', function () { simuler('test d’accessibilité demandé à un poste choisi'); }, 'primary'), bouton('Renouveler le certificat', 'file-key', function () { simuler('nouveau certificat auto-signé du réseau local'); })),
      carte('Aide pare-feu', el('p.text-sm.text-slate-600', { text: 'Autoriser le port 9000 en entrée sur le réseau privé uniquement. Ne jamais l’ouvrir vers Internet : les mobiles passent par le relais.' }))]);
  });

  ecran('mere-planificateur', {
    title: 'Planificateur', description: 'Les tâches que le serveur évalue à heure fixe : échéances, stocks, péremptions, rendez-vous, créances, sauvegarde.',
    regle: 'Une tâche <strong>lit</strong> les registres et <strong>n’en écrit aucun</strong> (les postes réécrivent les leurs). Une alerte <strong>disparaît quand sa cause cesse</strong> ; elle n’est jamais supprimée (RG-14).',
  }, function (root) {
    var t = [['Échéances fiscales dépassées ou à moins de 7 jours', 60, 'il y a 12 min', 'Réussie', 10], ['Seuils de stock', 15, 'il y a 4 min', 'Réussie', 51], ['Péremptions (FEFO)', 60, 'il y a 12 min', 'Réussie', 54], ['Rendez-vous du lendemain', 60, 'il y a 12 min', 'Réussie', 0], ['Créances assureurs âgées', 360, 'il y a 2 h', 'Réussie', 13], ['Sauvegarde nocturne', 1440, 'aujourd’hui 02:10', 'Réussie', 0]];
    page(root, [U.kpiGrid([kpi('Tâches actives', 6, 'timer'), kpi('En erreur', 0, 'circle-check', 'success'), kpi('Alertes ouvertes', 128, 'bell-ring', 'neutral')]),
      carte('Registre des tâches', tableau(['Tâche', 'Fréquence', 'Dernière exécution', 'Résultat', 'Alertes', ''], t.map(function (x) { return [x[0], 'toutes les ' + x[1] + ' min', x[2], U.badge(x[3], 'success'), String(x[4]), bouton('Exécuter', 'play', function () { U.toast('Tâche exécutée (simulation).', { type: 'success' }); })]; })))]);
  });

  ecran('mere-notifications', {
    title: 'Notifications serveur', description: 'Alertes ouvertes, routées par rôle au serveur, résolues quand la cause cesse ; source de la cloche des postes.',
    regle: 'Le routage se fait <strong>au serveur</strong> (RG-13) : la réception ne reçoit ni échéance fiscale ni alerte de stock. <strong>Aucune donnée médicale</strong> dans le texte d’une alerte.',
  }, function (root) {
    var a = [['Échéance fiscale dépassée — Acompte IS', 'critique', 'Comptable, DAF, Direction', 'il y a 3 j'], ['RUPTURE — Gants latex M', 'haute', 'Gestionnaire de stock', 'il y a 40 min'], ['Péremption à 30 jours — Amoxicilline 500', 'normale', 'Pharmacie, stock', 'il y a 1 j'], ['Créance assureur de plus de 60 jours — NSIA', 'important', 'Comptable, DAF', 'il y a 2 j']];
    page(root, [U.kpiGrid([kpi('Ouvertes', 128, 'bell', 'neutral'), kpi('Critiques', 4, 'siren', 'danger'), kpi('Résolues (7 j)', 31, 'check-check', 'success')]),
      carte('Alertes ouvertes', tableau(['Alerte', 'Priorité', 'Destinataires', 'Ouverte'], a.map(function (x) { return [x[0], U.badge(x[1], x[1] === 'critique' ? 'danger' : 'warning'), x[2], x[3]]; })))]);
  });

  /* =========================== E. CYCLE DE VIE ============================================================ */
  ecran('mere-mise-en-service', {
    title: 'Assistant de première mise en service', description: 'Du serveur vide à la clinique prête : identité, administrateur, jeu de départ, activation de la mère, premier appairage.',
    regle: 'Chaque étape est <strong>reprenable</strong>. Le jeu de départ garde les essentiels (tarifs, droits, catalogues) ; la démonstration est un choix explicite.',
  }, function (root) {
    var etapes = [['1', 'Identité de la clinique', 'Dénomination, IFU, RCCM, en-tête légal unique', 'fait'], ['2', 'Premier administrateur', 'Compte, mot de passe, second profil de confirmation', 'fait'], ['3', 'Jeu de départ', 'Essentiels seuls · ou essentiels + démonstration', 'fait'], ['4', 'Clé de clinique', 'Génération, copie papier sous scellé', 'en cours'], ['5', 'Activation du mode mère', 'Secret de la mère, relais, port', 'à faire'], ['6', 'Premier appairage', 'Code pour le premier poste (la caisse)', 'à faire']];
    page(root, [U.kpiGrid([kpi('Étapes faites', '3 / 6', 'list-checks', 'warning')]),
      carte('Parcours', tableau(['#', 'Étape', 'Contenu', 'État', ''], etapes.map(function (e) { return [e[0], e[1], e[2], e[3] === 'fait' ? U.badge('Fait', 'success') : (e[3] === 'en cours' ? U.badge('En cours', 'warning') : U.badge('À faire', 'neutral')), e[3] === 'fait' ? '' : bouton('Ouvrir', 'arrow-right', function () { simuler('ouverture de l’étape ' + e[0]); })]; })))]);
  });

  ecran('mere-mises-a-jour', {
    title: 'Mises à jour et compatibilité', description: 'Version de l’application et du schéma par poste ; refus nommé d’un poste trop ancien ; déploiement planifié.',
    regle: 'Un poste dont la version est <strong>incompatible</strong> avec le schéma est refusé <strong>en le nommant</strong> et passe en lecture seule jusqu’à sa mise à jour ; ses saisies restent en file.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Version de la mère', '1.0.3', 'package'), kpi('Schéma', 'v66', 'git-branch'), kpi('Postes à jour', '6 / 8', 'check', 'warning'), kpi('Postes refusés', 0, 'ban', 'success')]),
      carte('Versions par appareil', tableau(['Appareil', 'Application', 'Schéma', 'État'], APPAREILS.filter(function (a) { return a.etat === 'actif'; }).map(function (a) { return [a.nom, a.version, a.version === '1.0.3' ? 'v66' : 'v65', a.version === '1.0.3' || a.version === '1.0.1' ? etat('ok') : etat('attention')]; }))),
      barre(bouton('Planifier le déploiement', 'calendar-clock', function () { simuler('déploiement planifié hors des heures de caisse'); }, 'primary'))]);
  });

  ecran('mere-import', {
    title: 'Import de migration', description: 'Reprise des données existantes (SAGE, classeurs, jeux de départ) avec traçabilité complète.',
    regle: 'Jamais de saisie manuelle pour une migration : chaque lot porte <strong>source</strong>, <strong>numéro de lot</strong> et <strong>validateur</strong>. Un lot se <strong>simule</strong> avant de s’appliquer, et se <strong>rejoue</strong> sans doublon.',
  }, function (root) {
    page(root, [U.kpiGrid([kpi('Lots importés', 4, 'upload'), kpi('Lignes rejetées', 0, 'circle-check', 'success')]),
      barre(bouton('Importer un fichier', 'file-up', function () { simuler('choix du fichier, correspondance des colonnes, simulation, validation'); }, 'primary')),
      carte('Lots', tableau(['Lot', 'Source', 'Date', 'Lignes', 'Validé par', 'État'], [['IMP-2026-004', 'Inventaire SAGE « Grand Stock »', '14/10/2026', '184 articles', 'MAMAN Zoukanéri', U.badge('Appliqué', 'success')], ['IMP-2026-003', 'Plan comptable SYSCOHADA', '12/10/2026', '93 comptes', 'KASSA Augustin', U.badge('Appliqué', 'success')], ['IMP-2026-002', 'Organigramme', '12/10/2026', '44 agents', 'TAKI Alimatou', U.badge('Appliqué', 'success')], ['IMP-2026-001', 'Catalogue d’analyses', '11/10/2026', '48 analyses', 'KINNOU A. Ganiou', U.badge('Appliqué', 'success')]]))]);
  });

})(window);
