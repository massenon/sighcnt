/* =============================================================================
 * MOTEUR DE NOTIFICATION ET D'ALERTE — couche transversale
 * -----------------------------------------------------------------------------
 * PRINCIPE DIRECTEUR : cette couche CONSOMME les événements que le logiciel
 * produit déjà. Elle ne redéfinit aucune règle métier.
 *
 * Concrètement, elle ne décide jamais « si le stock est sous X, alerter ».
 * C'est le module de stock qui a déjà déterminé qu'un article est sous son
 * seuil — seuil que la clinique a fixé, référence par référence. Le moteur se
 * contente de demander : « une situation déjà qualifiée doit-elle produire une
 * notification, pour qui, et sur quels canaux ? »
 *
 * Le jour où la clinique change un seuil, ce fichier n'a rien à changer.
 *
 * QUATRE COUCHES, dans cet ordre :
 *
 *   1. ÉVÉNEMENT MÉTIER  — produit par un module, lu ici sans interprétation ;
 *   2. MOTEUR            — collecte, déduplique, route, priorise ;
 *   3. DISTRIBUTION      — cloche, badge, toast, centre de notifications ;
 *   4. SONORISATION      — canal supplémentaire, jamais un point de défaillance.
 *
 * LE SON EST UN CANAL, PAS UNE LOGIQUE. Aucun module n'appelle `sonner()` :
 * ils émettent leur événement, et le service audio est le SEUL composant qui
 * lit un son. Sans cette règle, chaque module finirait par avoir sa propre
 * politique sonore, et les couper toutes demanderait de les retrouver.
 *
 * DEUX CHOSES QUE LE SON NE DOIT JAMAIS FAIRE :
 *   · porter une donnée médicale — le son est générique, le détail reste dans
 *     l'application, derrière les permissions existantes ;
 *   · bloquer quoi que ce soit — audio absent, refusé ou coupé, l'alerte
 *     visuelle demeure entière.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, S = global.SIGH.store, N = global.SIGH.nav;

  /* ==========================================================================
   * PARAMÈTRES DE L'UTILISATEUR — ils gouvernent le CANAL, jamais la règle
   * --------------------------------------------------------------------------
   * Couper le son ne coupe pas l'alerte : la cloche, le badge, le toast et
   * l'historique continuent. C'est la distinction qui rend le mode silencieux
   * utilisable en salle de soins sans perdre d'information.
   * ======================================================================== */
  var CLE_PARAMS = 'sigh-cnt:notifications';

  var PROFILS_AUDIO = [
    { id: 'silencieux', label: 'Silencieux', volume: 0, repetition: 0,
      note: 'Aucun son. La cloche, le badge et les toasts continuent de fonctionner.' },
    { id: 'discret', label: 'Discret', volume: 0.4, repetition: 0,
      note: 'Un son court, jamais répété. Pour les postes en salle.' },
    { id: 'standard', label: 'Standard', volume: 1, repetition: 0,
      note: 'Son court pour l’information, son renforcé pour l’urgent.' },
    { id: 'critique', label: 'Critique seulement', volume: 1, repetition: 1,
      note: 'Seules les alertes graves sonnent, et elles se répètent une fois.' },
  ];

  var DEFAUTS = {
    visuel: true,
    son: true,
    profil: 'standard',
    volume: 0.8,
    /* Délai minimal entre deux sonorisations d'une MÊME alerte, en minutes.
       Une alerte persistante — un stock sous son seuil le reste des jours —
       ne doit pas sonner à chaque passage. */
    temporisation: 30,
  };

  function params() {
    try {
      var brut = JSON.parse(S.storage.get(CLE_PARAMS));
      return Object.assign({}, DEFAUTS, brut || {});
    } catch (e) { return Object.assign({}, DEFAUTS); }
  }
  function setParams(p) {
    S.storage.set(CLE_PARAMS, JSON.stringify(Object.assign({}, params(), p || {})));
  }
  function profilAudio() {
    var p = params();
    return PROFILS_AUDIO.filter(function (x) { return x.id === p.profil; })[0] || PROFILS_AUDIO[2];
  }

  /* ==========================================================================
   * COUCHE 1 — LES ÉVÉNEMENTS, LUS OÙ ILS SONT DÉJÀ PRODUITS
   * --------------------------------------------------------------------------
   * Chaque source déclare : où elle lit, comment elle qualifie, à quel POSTE
   * elle s'adresse. Rien de tout cela n'est inventé ici — les seuils, les
   * états et les destinataires viennent des modules.
   *
   * La CATÉGORIE sépare le métier du système : c'est une classification
   * d'affichage, pas une règle. Elle permet à un poste de filtrer sans que le
   * moteur ait à connaître le métier.
   * ======================================================================== */
  var SOURCES = [
    {
      code: 'stock_seuil', categorie: 'metier', domaine: 'Stock',
      /* Le module de stock a DÉJÀ déterminé qu'un article est sous son seuil.
         Le seuil est fixé par la clinique, référence par référence ; une
         référence sans seuil n'alerte pas, et c'est déjà sa règle. */
      lire: function () {
        return S.collection('produits').active()
          .filter(function (p) { return p.seuilAlerte != null && p.stock <= p.seuilAlerte; })
          .map(function (p) {
            return {
              cle: 'stock:' + p.id,
              priorite: p.stock <= 0 ? 'critique' : 'important',
              titre: p.designation + ' — ' + C.num(p.stock) + ' en stock',
              detail: 'Seuil d’alerte fixé à ' + C.num(p.seuilAlerte) + '. Établir un bon '
                + 'de commande — validation de la Direction requise (RG-04).',
              lien: 'm6-alertes',
              postes: ['stock', 'pharmacien', 'caissier', 'da'],
            };
          });
      },
    },
    {
      code: 'lots_peremption', categorie: 'metier', domaine: 'Pharmacie',
      lire: function () {
        return S.collection('lots').active()
          .filter(function (l) { return l.statut === 'perime' || l.statut === 'alerte'; })
          .map(function (l) {
            return {
              cle: 'lot:' + l.id,
              priorite: l.statut === 'perime' ? 'critique' : 'important',
              titre: l.statut === 'perime'
                ? 'Lot périmé — ' + (l.produit || l.numero)
                : 'Péremption proche — ' + (l.produit || l.numero),
              detail: l.statut === 'perime'
                ? 'À sortir du rayon et à déclarer en perte.'
                : 'Appliquer le principe FEFO (RG-05).',
              lien: 'm6-lots',
              postes: ['stock', 'pharmacien', 'caissier', 'laborantin'],
            };
          });
      },
    },
    {
      code: 'mecef_rejet', categorie: 'metier', domaine: 'Facturation',
      lire: function () {
        return S.collection('factures').active()
          .filter(function (f) { return f.statutMecef === 'rejete'; })
          .map(function (f) {
            return {
              cle: 'mecef:' + f.id,
              priorite: 'important',
              titre: 'Facture ' + (f.numero || f.id) + ' rejetée par la MECeF',
              detail: 'Corriger puis réémettre auprès de l’administration fiscale.',
              lien: 'mecef-transmission',
              postes: ['caissier', 'comptable', 'da', 'assistant_comptable'],
            };
          });
      },
    },
    {
      code: 'echeance_fiscale', categorie: 'metier', domaine: 'Comptabilité',
      /* Le calendrier fiscal est un référentiel : le moteur ne recalcule
         aucune date, il lit ce qui est déjà dépassé. */
      lire: function () {
        var auj = C.iso(new Date(2026, 7, 16));
        return S.collection('echeancesFiscales').active()
          .filter(function (e) { return !e.paye && String(e.echeance) < auj; })
          .map(function (e) {
            return {
              cle: 'fisc:' + e.id,
              priorite: 'critique',
              titre: (e.libelle || e.obligation) + ' — échéance dépassée',
              detail: 'Échéance au ' + C.dateFR(e.echeance) + '. Une pénalité court.',
              lien: 'm12-echeances',
              postes: ['comptable', 'da', 'assistant_comptable', 'direction'],
            };
          });
      },
    },
    {
      code: 'creance_agee', categorie: 'metier', domaine: 'Recouvrement',
      /* BFR_TABLEAU.txt : « si le délai de recouvrement d'un assureur
         partenaire dépasse un seuil critique paramétrable […] le SIGH
         déclenche une notification automatique ».
         LE SEUIL N'EST PAS ICI : il vit dans `objectifsPilotage`, où la
         Direction le règle, et le moteur du BFR l'applique. Cette source
         ROUTE, elle ne décide pas — le jour où le seuil passe de 60 à 45
         jours, ce fichier n'a rien à changer. C'est la règle de toute la
         couche de notification, et l'écrire ici en dur l'aurait rompue. */
      lire: function () {
        var PR = global.SIGH.parcours;
        if (!PR || !PR.alertesRecouvrement) return [];
        return PR.alertesRecouvrement().map(function (a) {
          var nom = (global.SIGH.data.ASSUREURS || [])
            .filter(function (x) { return x.code === a.assureur; })[0];
          return {
            cle: 'creance:' + a.assureur,
            priorite: a.jours > a.seuil * 1.5 ? 'critique' : 'important',
            titre: (nom ? nom.nom : a.assureur) + ' — ' + C.money(a.montant, false) + ' en souffrance',
            detail: C.num(a.nb) + ' facture(s), jusqu’à ' + a.jours + ' jours d’ancienneté '
              + '(seuil retenu : ' + a.seuil + ' jours). Cette créance pèse sur le besoin '
              + 'en fonds de roulement.',
            lien: 'm9-relances',
            postes: ['da', 'comptable', 'direction', 'assistant_comptable', 'aide_comptable'],
          };
        });
      },
    },
    {
      code: 'labo_a_traiter', categorie: 'metier', domaine: 'Laboratoire',
      /* L'encaissement a DÉJÀ fait passer la demande en attente de
         prélèvement : c'est la règle du circuit, on la lit, on ne la refait
         pas. */
      lire: function () {
        return S.collection('demandesAnalyses').active()
          .filter(function (d) { return d.etatAnalyse === 'attente_prelevement'; })
          .map(function (d) {
            return {
              cle: 'labo-prel:' + d.id,
              priorite: 'important',
              titre: 'Analyse réglée, prélèvement à faire',
              detail: (d.analyse || 'Analyse') + ' — le patient a payé, il peut être appelé.',
              lien: 'm5-prelevement',
              postes: ['laborantin'],
            };
          });
      },
    },
    {
      code: 'labo_a_saisir', categorie: 'metier', domaine: 'Laboratoire',
      lire: function () {
        return S.collection('demandesAnalyses').active()
          .filter(function (d) { return d.recuLaboLe && d.etatAnalyse === 'en_cours'; })
          .map(function (d) {
            return {
              cle: 'labo-saisie:' + d.id,
              priorite: 'information',
              titre: 'Échantillon reçu, résultat à saisir',
              detail: (d.analyse || 'Analyse') + ' — reçu le ' + C.dateFR(d.recuLaboLe) + '.',
              lien: 'm5-resultats',
              postes: ['laborantin'],
            };
          });
      },
    },
    {
      code: 'poste', categorie: 'metier', domaine: 'Poste',
      /* Les notifications de POSTE, écrites par le moteur transactionnel
         (`PR.notifier`). Elles s'adressent à un poste et non à une personne :
         le prescripteur peut être en congé, c'est le service qui doit voir
         passer l'information. */
      lire: function () {
        return S.collection('notifications').active()
          .filter(function (n) { return !n.lue; })
          .map(function (n) {
            return {
              cle: 'notif:' + n.id,
              priorite: n.priorite || (n.ton === 'danger' ? 'critique' : 'important'),
              titre: n.titre || n.message || 'Notification',
              detail: n.detail || n.message || '',
              lien: n.ecran || null,
              postes: n.poste ? [n.poste] : null,
              enregistree: n.id,
            };
          });
      },
    },
    {
      code: 'audio', categorie: 'systeme', domaine: 'Périphérique audio',
      /* Une notification SYSTÈME, distincte du métier : elle informe de l'état
         du poste, pas de celui de la clinique. */
      lire: function () {
        if (audioDisponible() !== false) return [];
        return [{
          cle: 'sys:audio',
          priorite: 'information',
          titre: 'Sonorisation indisponible sur ce poste',
          detail: 'Le périphérique audio n’a pas répondu. Les alertes restent visibles : '
            + 'cloche, badge et messages fonctionnent normalement.',
          lien: 'cfg-notifications',
          postes: null,
        }];
      },
    },
  ];

  /* ==========================================================================
   * COUCHE 2 — LE MOTEUR : collecte, routage, priorité, anti-spam
   * ======================================================================== */
  var PRIORITES = {
    critique: { rang: 0, ton: 'danger', son: 'alerte', label: 'Critique' },
    important: { rang: 1, ton: 'warning', son: 'rappel', label: 'Important' },
    information: { rang: 2, ton: 'info', son: 'information', label: 'Information' },
  };
  function priorite(id) { return PRIORITES[id] || PRIORITES.information; }

  /** Le poste courant, au sens du routage : rôle de la session. */
  function posteCourant() {
    var se = S.session() || {};
    return se.role || null;
  }

  /**
   * La notification s'adresse-t-elle à ce poste ?
   *
   * Le ciblage vient des règles DÉJÀ définies : les postes déclarés par la
   * source, et le RBAC pour l'écran visé. Une notification qui renvoie vers un
   * écran interdit au profil ne lui sert à rien — et lui promettrait une porte
   * fermée.
   */
  function pourMoi(n, poste) {
    if (!poste) return false;
    if (n.postes && n.postes.indexOf(poste) < 0) return false;
    if (n.lien) {
      var e = N.get(n.lien);
      if (e && !N.can(poste, e)) return false;
    }
    return true;
  }

  /* --- Acquittement et résolution ---------------------------------------- */
  var CLE_ACQ = 'sigh-cnt:notifications-acquittees';
  function acquittees() {
    try { return JSON.parse(S.storage.get(CLE_ACQ)) || {}; } catch (e) { return {}; }
  }
  /* Acquitter une ligne GROUPÉE acquitte ses membres : sinon le badge ne
     bougerait pas, et l'utilisateur cliquerait sans effet visible. */
  function acquitter(cle, membres) {
    var a = acquittees();
    var quand = new Date().toISOString();
    a[cle] = quand;
    (membres || []).forEach(function (m) { a[m] = quand; });
    S.storage.set(CLE_ACQ, JSON.stringify(a));
  }
  function reprendre(cle, membres) {
    var a = acquittees();
    delete a[cle];
    (membres || []).forEach(function (m) { delete a[m]; });
    S.storage.set(CLE_ACQ, JSON.stringify(a));
  }

  /**
   * ENTENDRE N'EST PAS TRAITER. Une alerte acquittée cesse de sonner et de
   * peser sur le badge, mais elle RESTE dans le centre de notifications tant
   * que la situation dure. Elle ne disparaît que lorsque sa cause disparaît —
   * c'est la source qui cesse de la produire, pas l'utilisateur qui la fait
   * taire.
   */
  /* --------------------------------------------------------------------------
   * REGROUPEMENT — une cloche à cent est une cloche qu'on n'ouvre plus
   * --------------------------------------------------------------------------
   * Une source qui produit plusieurs alertes de même priorité en rend UNE,
   * portant le compte. Le détail n'est pas perdu : il vit dans l'écran, qui est
   * fait pour l'afficher.
   *
   * LE SEUIL EST À TROIS. En dessous, nommer l'article rend service — « lot
   * périmé, AMOXICILLINE » se traite tout de suite. Au-delà, le nom devient du
   * bruit et c'est le NOMBRE qui informe.
   * ----------------------------------------------------------------------- */
  var SEUIL_REGROUPEMENT = 3;

  var LIBELLES_GROUPE = {
    stock_seuil: ['article(s) sous leur seuil d’alerte',
      'Établir un bon de commande — validation de la Direction requise (RG-04).'],
    lots_peremption: ['lot(s) périmés ou proches de la péremption',
      'Appliquer le principe FEFO (RG-05) et déclarer les pertes constatées.'],
    mecef_rejet: ['facture(s) rejetée(s) par la MECeF',
      'Corriger puis réémettre auprès de l’administration fiscale.'],
    echeance_fiscale: ['échéance(s) fiscale(s) dépassée(s)',
      'Une pénalité court sur chacune. Déclarer et payer.'],
    labo_a_traiter: ['analyse(s) réglée(s), prélèvement à faire',
      'Les patients ont payé : ils peuvent être appelés en salle de prélèvement.'],
    labo_a_saisir: ['échantillon(s) reçu(s), résultat à saisir',
      'Le prescripteur ne verra rien tant que le résultat n’est pas validé.'],
    poste: ['notification(s) de poste', 'À consulter dans les écrans concernés.'],
  };

  function regrouper(liste) {
    /* Les acquittements déjà posés, y compris sur les clés de GROUPE : un
       appelant qui n'a que la clé sous la main doit obtenir le même résultat
       que celui qui énumère les membres. */
    var acq = acquittees();
    var paquets = {}, ordre = [];
    liste.forEach(function (x) {
      var cle = x.source + '|' + x.priorite;
      if (!paquets[cle]) { paquets[cle] = []; ordre.push(cle); }
      paquets[cle].push(x);
    });

    var out = [];
    ordre.forEach(function (cle) {
      var g = paquets[cle];
      if (g.length < SEUIL_REGROUPEMENT) { out = out.concat(g); return; }
      var lib = LIBELLES_GROUPE[g[0].source] || [g[0].domaine.toLowerCase() + ' — alertes', ''];
      /* Une alerte groupée est acquittée si TOUS ses membres le sont — faire
         taire la ligne alors que quinze articles restent en rupture ferait
         perdre l'information au moment où elle compte — OU si la ligne
         elle-même a été acquittée, ce qui est un geste délibéré de
         l'utilisateur sur ce qu'il voit. */
      var cleGroupe = 'groupe:' + cle;
      var toutesAcquittees = g.every(function (x) { return !!x.acquitteeLe; });
      var acquitteeLe = acq[cleGroupe] || (toutesAcquittees ? g[0].acquitteeLe : null);
      out.push({
        cle: cleGroupe,
        groupe: true,
        membres: g.map(function (x) { return x.cle; }),
        nombre: g.length,
        source: g[0].source, categorie: g[0].categorie, domaine: g[0].domaine,
        priorite: g[0].priorite,
        titre: C.num(g.length) + ' ' + lib[0],
        detail: lib[1],
        lien: g[0].lien,
        postes: g[0].postes,
        acquitteeLe: acquitteeLe,
      });
    });
    return out;
  }

  function collecter(opts) {
    opts = opts || {};
    var poste = opts.poste || posteCourant();
    var acq = acquittees();
    var out = [];
    SOURCES.forEach(function (src) {
      var lues;
      try { lues = src.lire() || []; } catch (e) { lues = []; }
      lues.forEach(function (n) {
        if (!opts.tousPostes && !pourMoi(n, poste)) return;
        out.push(Object.assign({}, n, {
          source: src.code,
          categorie: src.categorie,
          domaine: src.domaine,
          acquitteeLe: acq[n.cle] || null,
        }));
      });
    });
    /* On REGROUPE avant de trier : sans cela, la cloche porterait cent cinq
       lignes que personne ne lit. */
    if (!opts.detaille) out = regrouper(out);

    /* Le plus grave d'abord : c'est l'ordre dans lequel on veut les lire. */
    out.sort(function (a, b) {
      var pa = priorite(a.priorite).rang, pb = priorite(b.priorite).rang;
      if (pa !== pb) return pa - pb;
      return String(a.titre).localeCompare(String(b.titre));
    });
    return out;
  }

  /** Ce qui pèse sur le badge : les non acquittées. */
  function enAttente(poste) {
    return collecter({ poste: poste }).filter(function (n) { return !n.acquitteeLe; });
  }

  /* ==========================================================================
   * COUCHE 4 — LE SERVICE AUDIO : seul composant qui lit un son
   * --------------------------------------------------------------------------
   * Il est appelé par le moteur, jamais par un module. Sans cette règle,
   * chaque module finirait par avoir sa propre politique sonore, et les couper
   * toutes demanderait de les retrouver une à une.
   * ======================================================================== */
  var _audio = null;   /* null = pas encore testé, true/false = résultat */

  /** Détection au démarrage — une panne audio ne bloque jamais l'application. */
  function audioDisponible() {
    if (_audio !== null) return _audio;
    try {
      var Ctx = global.AudioContext || global.webkitAudioContext;
      _audio = !!Ctx;
    } catch (e) { _audio = false; }
    return _audio;
  }

  /* Dernière sonorisation par clé — c'est la temporisation anti-spam. */
  var _dernier = {};

  /**
   * sonoriser(notification) — applique la POLITIQUE du profil audio.
   *
   * La priorité appartient au métier ; le comportement sonore appartient à ce
   * moteur. C'est pourquoi on ne lit ici que `n.priorite`, jamais la nature de
   * l'événement.
   */
  function sonoriser(n) {
    var p = params();
    if (!p.son) return { joue: false, motif: 'son désactivé' };
    if (!audioDisponible()) return { joue: false, motif: 'audio indisponible' };

    var prof = profilAudio();
    if (prof.volume === 0) return { joue: false, motif: 'profil silencieux' };
    if (prof.id === 'critique' && n.priorite !== 'critique') {
      return { joue: false, motif: 'profil critique seulement' };
    }

    /* ANTI-SPAM. Une alerte persistante — un stock sous son seuil le reste des
       jours — ne doit pas sonner à chaque passage. La temporisation est une
       propriété du CANAL : l'alerte, elle, reste entière. */
    var maintenant = Date.now();
    var precedent = _dernier[n.cle] || 0;
    if (maintenant - precedent < (p.temporisation || 30) * 60000) {
      return { joue: false, motif: 'temporisation' };
    }
    _dernier[n.cle] = maintenant;

    var son = priorite(n.priorite).son;
    var joue = global.SIGH.ui.sonner(son);
    /* Répétition contrôlée : au plus une, et seulement si le profil l'exige. */
    if (joue && prof.repetition > 0 && n.priorite === 'critique') {
      global.setTimeout(function () { global.SIGH.ui.sonner(son); }, 900);
    }
    return { joue: !!joue, motif: joue ? null : 'lecture refusée' };
  }

  /**
   * TESTER LE SON sans créer de fausse alerte.
   * Ne crée aucune notification métier, ne modifie aucune donnée, ne déclenche
   * aucun workflow — un test qui laisserait une trace serait pire qu'aucun
   * test, puisqu'il faudrait ensuite la nettoyer.
   */
  function tester() {
    if (!audioDisponible()) return { joue: false, motif: 'Aucun périphérique audio détecté.' };
    var joue = global.SIGH.ui.sonner('rappel');
    return {
      joue: !!joue,
      motif: joue ? null : 'Le navigateur a refusé la lecture — cliquer dans la page puis réessayer.',
    };
  }

  /* ==========================================================================
   * COUCHE 3 — DISTRIBUTION
   * --------------------------------------------------------------------------
   * La surveillance tourne EN ARRIÈRE-PLAN, quelle que soit la page ouverte :
   * une alerte ne doit pas attendre que l'agent revienne au tableau de bord.
   * ======================================================================== */
  var _abonnes = [];
  var _timer = null;
  var _vues = {};     /* clés déjà annoncées dans cette session */

  function abonner(fn) {
    if (typeof fn === 'function') _abonnes.push(fn);
    return function () { _abonnes = _abonnes.filter(function (x) { return x !== fn; }); };
  }
  function prevenir(liste) {
    _abonnes.forEach(function (fn) {
      try { fn(liste); } catch (e) { /* un abonné défaillant n'arrête pas les autres */ }
    });
  }

  /**
   * Le tour de surveillance. Il ne calcule aucune règle : il relit les sources,
   * repère ce qui est NOUVEAU depuis le dernier tour, et distribue.
   */
  function tour(premier) {
    var liste = enAttente();
    var nouveaux = liste.filter(function (n) { return !_vues[n.cle]; });
    liste.forEach(function (n) { _vues[n.cle] = true; });

    prevenir(liste);

    if (!nouveaux.length) return liste;

    /* Au premier tour on ne sonne QUE pour le critique : ouvrir une page ne
       doit pas déclencher un concert pour des alertes qui durent depuis des
       jours. */
    var aSonoriser = premier
      ? nouveaux.filter(function (n) { return n.priorite === 'critique'; })
      : nouveaux;
    if (!aSonoriser.length) return liste;

    /* REGROUPEMENT : un seul son pour la salve, sur la plus grave. Cinq
       alertes simultanées ne doivent pas produire cinq sons. */
    var plusGrave = aSonoriser.slice().sort(function (a, b) {
      return priorite(a.priorite).rang - priorite(b.priorite).rang;
    })[0];
    sonoriser(plusGrave);

    if (params().visuel) {
      /* LE MESSAGE RESTE GÉNÉRIQUE : jamais de donnée médicale dans une alerte
         qui peut être lue ou entendue par-dessus l'épaule. Le détail vit dans
         l'application, derrière les permissions existantes. */
      var texte = aSonoriser.length === 1
        ? 'Une nouvelle alerte nécessite votre attention.'
        : aSonoriser.length + ' nouvelles alertes nécessitent votre attention.';
      global.SIGH.ui.toast(texte, {
        type: priorite(plusGrave.priorite).ton === 'danger' ? 'error' : 'warning',
        duration: 8000,
        detail: 'Ouvrir la cloche pour le détail.',
        silencieux: true,
      });
    }
    return liste;
  }

  var INTERVALLE = 45000;   /* 45 s : assez pour être vivant, assez peu pour ne pas peser */

  function demarrer() {
    if (_timer) return;
    /* Le premier tour est différé : la page doit finir de se monter, et le
       magasin d'être amorcé. Sonner pendant l'amorçage donnerait une alerte
       sur un état transitoire. */
    global.setTimeout(function () { tour(true); }, 1500);
    _timer = global.setInterval(function () { tour(false); }, INTERVALLE);
  }
  function arreter() {
    if (_timer) { global.clearInterval(_timer); _timer = null; }
  }

  global.SIGH.notifications = {
    /* Lecture */
    collecter: collecter, enAttente: enAttente, priorite: priorite, PRIORITES: PRIORITES,
    SOURCES: SOURCES,
    /* Acquittement */
    acquitter: acquitter, reprendre: reprendre, acquittees: acquittees,
    /* Paramètres — canal, jamais règle métier */
    params: params, setParams: setParams,
    PROFILS_AUDIO: PROFILS_AUDIO, profilAudio: profilAudio, DEFAUTS: DEFAUTS,
    /* Audio */
    audioDisponible: audioDisponible, tester: tester, sonoriser: sonoriser,
    /* Distribution */
    abonner: abonner, demarrer: demarrer, arreter: arreter, tour: tour,
  };
})(window);
