/* =============================================================================
 * SIGH-CNT — Magasin de données
 * -----------------------------------------------------------------------------
 * Persistance localStorage + CRUD complet.
 *  - RG-14 : suppression LOGIQUE uniquement (statut « archivé »), jamais physique.
 *  - RG-12 : toute création / modification / archivage / restauration est
 *            journalisée (utilisateur, date/heure, entité, ancienne → nouvelle).
 *  - Toute mutation retourne un jeton d'ANNULATION (undo) exploité par les toasts.
 * Les jeux de démonstration sont générés par un PRNG à graine fixe : les données
 * sont donc identiques d'une session à l'autre (tests reproductibles).
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, D = global.SIGH.data, L = global.SIGH.labo;
  var KEY = 'sigh-cnt:v1';   /* CONSERVÉE pour EFFACER un reliquat, jamais pour écrire */

  /* ==========================================================================
   * LE SERVEUR EST LA SEULE VÉRITÉ (bascule du 03/10/2026)
   * --------------------------------------------------------------------------
   * La donnée métier ne vit plus dans le navigateur. Le magasin en mémoire est
   * un MIROIR : il meurt avec l'onglet, et il n'a d'autre rôle que de laisser
   * les ~300 écrans lire de façon synchrone, comme ils l'ont toujours fait.
   *
   * POURQUOI PAS DE REPLI. Un repli silencieux sur le `localStorage` laisse
   * l'agent travailler une heure dans un stockage que personne ne relira, et
   * il ne s'en aperçoit qu'au moment où il cherche sa saisie. Mieux vaut un
   * écran qui s'arrête en disant pourquoi.
   * ======================================================================== */
  var PANNE = { active: false, motif: '' };

  /* La coquille rendue AVANT que l'hydratation ait répondu est PROVISOIRE :
     `collection()` lit la variable de module, il faut donc bien la poser —
     mais elle doit céder la place au vrai magasin dès que le serveur répond.
     La rendre sans la poser laissait `db` à null et cassait au premier
     `db[name]` (« Cannot read properties of null »). */
  var _provisoire = false;

  /** Le bandeau de panne. Il est bâti ICI, sans `ui.js` : le magasin se charge
   *  avant lui, et une panne doit pouvoir s'annoncer même tôt. */
  function signalerPanne(motif) {
    PANNE.active = true;
    PANNE.motif = motif || '';
    try {
      var doc = global.document;
      if (!doc || doc.getElementById('sigh-panne-base')) return;
      var fond = doc.createElement('div');
      fond.id = 'sigh-panne-base';
      fond.setAttribute('role', 'alertdialog');
      fond.style.cssText = 'position:fixed;inset:0;z-index:2147483647;display:flex;'
        + 'align-items:center;justify-content:center;padding:1rem;'
        + 'background:rgba(15,23,42,.72);backdrop-filter:blur(2px)';
      var carte = doc.createElement('div');
      carte.style.cssText = 'max-width:34rem;width:100%;background:#fff;border-radius:.75rem;'
        + 'box-shadow:0 25px 50px -12px rgba(0,0,0,.4);padding:1.5rem;font-family:Inter,'
        + 'Segoe UI,system-ui,sans-serif';
      carte.innerHTML = '<p style="margin:0 0 .5rem;font-size:1.05rem;font-weight:600;color:#7f1d1d">'
        + 'Connexion perdue avec le serveur de base de données</p>'
        + '<p style="margin:0 0 .75rem;font-size:.875rem;line-height:1.5;color:#334155">'
        + 'L’enregistrement a été <strong>refusé</strong> et la saisie n’a pas été conservée. '
        + 'Rien n’est écrit dans ce navigateur : les données de la clinique vivent sur le '
        + 'serveur, et lui seul en répond.</p>'
        + '<p style="margin:0 0 1rem;font-size:.8125rem;line-height:1.5;color:#64748b">'
        + 'Vérifier que le serveur est démarré, puis recharger la page. Le travail déjà '
        + 'enregistré est intact.</p>';
      var det = doc.createElement('p');
      det.style.cssText = 'margin:0 0 1rem;font-size:.75rem;color:#94a3b8;font-family:ui-monospace,monospace';
      det.textContent = PANNE.motif;
      carte.appendChild(det);
      var b = doc.createElement('button');
      b.type = 'button';
      b.textContent = 'Recharger la page';
      b.style.cssText = 'width:100%;padding:.625rem 1rem;border:0;border-radius:.5rem;'
        + 'background:#0f2f5b;color:#fff;font-size:.875rem;font-weight:600;cursor:pointer';
      b.onclick = function () { global.location.reload(); };
      carte.appendChild(b);
      fond.appendChild(carte);
      (doc.body || doc.documentElement).appendChild(fond);
    } catch (e) { /* l'essentiel est que l'écriture ait été refusée */ }
    if (global.console && global.console.error) {
      global.console.error('[SIGH] Base indisponible — ' + PANNE.motif);
    }
  }
  /* LA VERSION DU SCHÉMA VIT ICI, ET NULLE PART AILLEURS. Trois endroits la
     lisent — la semence, la garde du navigateur, la garde du serveur — et
     tant qu'elle était recopiée dans chacun, elle finissait par diverger :
     la vague 67 a bougé les deux premiers et laissé le troisième à 61, si
     bien qu'un poste hydraté depuis la base ne se ré-amorçait jamais.
     Incrémenter ce nombre, et lui seul, à toute modification de forme. */
  var VERSION = 66;
  var db = null;
  var listeners = {};

  /* --- Stockage tolérant ---------------------------------------------------
   * Ouvert par double-clic (protocole file://), Chrome refuse l'accès à
   * localStorage selon la configuration. On bascule alors silencieusement sur
   * un stockage en mémoire : le prototype reste pleinement fonctionnel, seules
   * les données ne survivent pas au rechargement.
   * ---------------------------------------------------------------------- */
  var mem = {};
  var persistant = (function () {
    try {
      var t = '__sigh_test__';
      global.localStorage.setItem(t, '1');
      global.localStorage.removeItem(t);
      return true;
    } catch (e) { return false; }
  })();

  var storage = {
    disponible: persistant,
    get: function (k) {
      try { return persistant ? global.localStorage.getItem(k) : (mem[k] != null ? mem[k] : null); }
      catch (e) { return mem[k] != null ? mem[k] : null; }
    },
    set: function (k, v, silencieux) {
      try { if (persistant) { global.localStorage.setItem(k, v); return true; } } catch (e) {
        /* QUOTA DÉPASSÉ. Le repli en mémoire garde la page fonctionnelle, mais
           les données seront PERDUES au changement d'écran. Se taire ferait
           chercher le défaut dans les écrans pendant des heures.
           `silencieux` : l'appelant va RETENTER en compressé (vague 62). Crier
           « données perdues » avant une seconde tentative qui réussit était une
           fausse alarme — c'est l'échec de la seconde qui s'annonce. */
        if (silencieux) return false;
        if (!storage.quotaSignale) {
          storage.quotaSignale = true;
          storage.quotaMessage = 'Le stockage local du navigateur est saturé ('
            + Math.round(String(v).length / 1024) + ' Ko à écrire). Les données restent en mémoire '
            + 'et seront perdues au changement d’écran. Réinitialiser le jeu de démonstration depuis '
            + '« Paramètres système » libère la place.';
          if (global.console && global.console.error) global.console.error('[SIGH] ' + storage.quotaMessage);
          /* Une écriture refusée s'ANNONCE : la console ne suffit pas, personne
             ne l'a ouverte au guichet. ui.js n'est pas encore chargé quand le
             magasin s'initialise — d'où la consultation paresseuse. */
          var Ui = global.SIGH && global.SIGH.ui;
          if (Ui && Ui.alerter) {
            try { Ui.alerter(storage.quotaMessage, { type: 'danger', duration: 0 }); } catch (e2) { /* visuel seul */ }
          }
        }
      }
      mem[k] = v; return false;
    },
    remove: function (k) {
      try { if (persistant) global.localStorage.removeItem(k); } catch (e) { /* sans effet */ }
      delete mem[k];
    },
  };

  /* --- Utilisateur courant (session) -------------------------------------- */
  function session() {
    try { return JSON.parse(storage.get('sigh-cnt:session')) || null; } catch (e) { return null; }
  }
  /* --------------------------------------------------------------------------
   * MÉTHODE DE VALORISATION DES SORTIES DE STOCK
   * --------------------------------------------------------------------------
   * Prix de vente ou CUMP — c'est un PARAMÈTRE, comme l'annotation manuscrite
   * le demandait. Il vit ici et non dans l'écran de configuration : une
   * bascule d'exploitation lue par le moteur de stock, les états de la
   * Direction et les points du gestionnaire ne peut pas dépendre d'un module
   * que ces pages ne chargent pas.
   * ----------------------------------------------------------------------- */
  /* ==========================================================================
   * LES RÉGLAGES D'EXPLOITATION VIVENT DANS LE MAGASIN
   * --------------------------------------------------------------------------
   * Donc en base, donc partagés par tous les postes. Ce sont des décisions de
   * la clinique, pas des préférences d'écran : les laisser par navigateur
   * permettait à deux agents de valoriser le même stock de deux façons.
   *
   * `_reglages` n'est pas un tableau : il voyage dans `meta`, à côté de
   * `_version`.
   * ======================================================================== */
  function reglage(cle, defaut) {
    var d = load();
    return (d && d._reglages && d._reglages[cle] !== undefined) ? d._reglages[cle] : defaut;
  }
  function setReglage(cle, valeur) {
    var d = load();
    if (!d._reglages) d._reglages = {};
    d._reglages[cle] = valeur;
    save();
    return valeur;
  }


  function valorisationSortie() {
    return reglage('valorisationSortie', null)
      || (global.SIGH.data && global.SIGH.data.PARAM_STOCK
        && global.SIGH.data.PARAM_STOCK.valorisationSortie) || 'prixVente';
  }
  function setValorisationSortie(id) {
    setReglage('valorisationSortie', id);
    /* Le référentiel suit, pour que tout code qui le lit encore directement
       voie la même chose. Deux vérités sur une même bascule, c'est le défaut
       qu'on corrige ici. */
    if (global.SIGH.data && global.SIGH.data.PARAM_STOCK) {
      global.SIGH.data.PARAM_STOCK.valorisationSortie = id;
    }
  }
  /** Valeur unitaire d'un article selon la méthode en vigueur. */
  function valeurUnitaire(produit) {
    if (!produit) return 0;
    return valorisationSortie() === 'cump'
      ? Math.round(produit.cump || produit.prixAchat || 0)
      : Math.round(produit.prixVente || produit.prixAchat || 0);
  }

  /* Les jeux enregistrés avant la fusion portent encore « Administration ».
     On les rattache au chargement plutôt que d'attendre une réinitialisation :
     un graphique faux pendant une semaine, c'est une semaine de décisions
     prises sur un effectif coupé en deux. */
  /* Les jeux enregistrés portent l'ancien code : sans reprise, le laboratoire
     resterait muet jusqu'à la prochaine réinitialisation. */
  function normaliserEtatsResultat(base) {
    if (!base || !base.demandesAnalyses) return;
    base.demandesAnalyses.forEach(function (d) {
      if (d.etatAnalyse === 'valide_bio' || d.etatAnalyse === 'rendu') d.etatAnalyse = 'valide';

      /* DEUX NOMS POUR LA MÊME DATE. L'écran de la salle de prélèvement range
         ses onglets sur `preleveLe` ; d'anciens jeux portent
         `prelevementLe`. Sans reprise, l'onglet « À transmettre » resterait
         vide alors que des échantillons sont prélevés. */
      if (!d.preleveLe && d.prelevementLe) d.preleveLe = d.prelevementLe;

      /* UN RÉSULTAT SAISI SUPPOSE UN ÉCHANTILLON PARVENU. Sans cette
         déduction, cent dix-huit demandes analysées resteraient éternellement
         « à transmettre ». */
      var avance = ['en_cours', 'saisi', 'valide_technique', 'valide', 'rectifie'];
      if (avance.indexOf(d.etatAnalyse) >= 0) {
        if (!d.preleveLe) d.preleveLe = d.saisiLe || d.dateHeure || null;
        if (!d.recuLaboLe) d.recuLaboLe = d.saisiLe || d.preleveLe || null;
      }
    });
  }

  function fusionnerServiceDirection(base) {
    if (!base) return;
    (base.personnel || []).forEach(function (a) {
      if (a.service === 'Administration') a.service = 'Direction';
    });
    /* Le centre de coût est amorcé en collection : il reste figé dans les jeux
       déjà enregistrés tant qu'on ne le reprend pas ici. Les imputations qui
       le désignaient suivent, sans quoi elles pointeraient vers un centre
       disparu. */
    if (base.centresCouts) {
      base.centresCouts = base.centresCouts.filter(function (c) { return c.id !== 'administration'; });
    }
    ['ecritures', 'depenses', 'budgets'].forEach(function (nom) {
      (base[nom] || []).forEach(function (e) {
        if (e.centreCout === 'administration') e.centreCout = 'direction';
      });
    });
  }

  /**
   * Pose la session.
   *
   * `s.jeton` RENSEIGNÉ signifie que le serveur l'a déjà délivrée (connexion
   * par `api/auth.php`) : on l'adopte telle quelle, sans en ouvrir une
   * seconde — deux sessions pour un même poste fausseraient le compte des
   * postes actifs, et la seconde n'aurait pas vérifié de mot de passe.
   *
   * Ce qui reste dans le navigateur n'est PAS la session : c'est un POINTEUR
   * vers elle. Le rôle, les droits et l'identité font foi en base, et chaque
   * écriture les y relit (RG-12, RG-13).
   */
  function setSession(s) {
    if (s) storage.set('sigh-cnt:session', JSON.stringify(s));
    else storage.remove('sigh-cnt:session');
    if (s && s.jeton) {
      SRV.jeton = s.jeton;
      SRV.promesseSession = global.Promise.resolve(s.jeton);
      try { storage.set(CLE_JETON, s.jeton); } catch (e) { /* sans effet */ }
      return;
    }
    /* LA SESSION DU SERVEUR SUIT CELLE DE L'ÉCRAN. Tant que les données
       vivaient dans le même navigateur, une session déclarée par la page
       n'engageait personne ; dès lors que plusieurs postes écrivent dans la
       même base, ce qu'un poste écrit, les autres le lisent. Le serveur
       délivre donc son propre jeton — et refuse l'anonyme. */
    if (!SRV.actif) return;
    if (s) {
      ouvrirSessionServeur(s);
    } else if (SRV.jeton) {
      var j = SRV.jeton;
      SRV.jeton = null;
      try { storage.remove(CLE_JETON); } catch (e) { /* sans effet */ }
      try {
        global.fetch(urlApi('session.php?jeton=' + encodeURIComponent(j)), { method: 'DELETE' });
      } catch (e) { /* la session expirera d'elle-même */ }
    }
  }
  function currentUser() {
    var s = session();
    return (s && s.nom) || 'Utilisateur non identifié';
  }

  /* ==========================================================================
   * GÉNÉRATION DES JEUX DE DÉMONSTRATION
   * ======================================================================== */
  var PRENOMS_M = ['Abdoul', 'Ganiou', 'Florent', 'Rodrigue', 'Augustin', 'Hervé', 'Edmond', 'Nourou',
    'Séko', 'Yahouza', 'Idrissou', 'Boukari', 'Sabi', 'Orou', 'Moussa', 'Salifou', 'Tamou', 'Djibril',
    'Kassim', 'Bio', 'Yacoubou', 'Souleymane', 'Zakari', 'Alassane'];
  var PRENOMS_F = ['Alimatou', 'Aïssatou', 'Séraphine', 'Rabiatou', 'Zoukanéri', 'Fatouma', 'Adissa',
    'Bibata', 'Salamatou', 'Ramatou', 'Bertine', 'Colette', 'Justine', 'Hélène', 'Marguerite',
    'Chantal', 'Nadège', 'Sylvie', 'Rachida', 'Kadidjatou', 'Awaou', 'Foussena'];
  var NOMS = ['BASSONGUI', 'TAKI', 'KASSA', 'GBEDJI', 'YENI', 'AHOHOU', 'KINNOU', 'GARBA', 'TEPA',
    'DIEYABIDI', 'OURTCHA', 'ISSA', 'OROU YO', 'MAMAN', 'TCHANE', 'SANNI', 'DAOUDA', 'KORA',
    'N’TCHA', 'TIGRI', 'YARO', 'SAMBIENI', 'TCHOUKOUROU', 'BOUKARI', 'ADAM', 'SEIDOU', 'BAKO',
    'PARAISO', 'DOSSOU', 'HOUNKPATIN', 'AGOSSOU', 'ZIME', 'SOULE', 'WOROU', 'BANI'];
  var QUARTIERS = ['Tchirimina', 'Yimporima', 'Kantaborifa', 'Peporiyakou', 'Santa', 'Ourbouga',
    'Bérécingou', 'Perma', 'Kouandé', 'Boukoumbé', 'Toucountouna', 'Kotopounga'];
  var MOTIFS = ['Fièvre persistante', 'Céphalées', 'Douleurs abdominales', 'Suivi de grossesse',
    'Paludisme suspecté', 'Toux chronique', 'Hypertension artérielle', 'Contrôle post-opératoire',
    'Plaie infectée', 'Vomissements', 'Asthénie', 'Diarrhée aiguë', 'Consultation prénatale',
    'Traumatisme', 'Infection urinaire', 'Contrôle diabète'];
  var DIAGNOSTICS = ['Paludisme simple', 'Paludisme grave', 'Fièvre typhoïde', 'Gastro-entérite',
    'Infection respiratoire aiguë', 'HTA essentielle', 'Anémie ferriprive', 'Infection urinaire basse',
    'Grossesse évolutive', 'Diabète de type 2', 'Bronchite aiguë', 'Dermatose infectieuse'];

  /* Antécédents, allergies et actes de soins : référentiels cliniques tenus
     dans data.js, administrables par la clinique. */
  var ANTECEDENTS = D.ANTECEDENTS, ALLERGIES = D.ALLERGIES, ACTES_SOINS = D.ACTES_SOINS;

  var MEDICAMENTS = [
    ['Artéméther-Luméfantrine 20/120mg', 'Comprimé', 'medicament', 1200, 40],
    ['Artésunate injectable 60mg', 'Flacon', 'medicament', 2500, 20],
    ['Paracétamol 500mg', 'Comprimé', 'medicament', 25, 500],
    ['Paracétamol injectable 1g', 'Flacon', 'medicament', 850, 60],
    ['Amoxicilline 500mg', 'Gélule', 'medicament', 60, 400],
    ['Amoxicilline + Ac. clavulanique 1g', 'Comprimé', 'medicament', 350, 150],
    ['Ciprofloxacine 500mg', 'Comprimé', 'medicament', 120, 200],
    ['Ceftriaxone 1g injectable', 'Flacon', 'medicament', 1500, 80],
    ['Métronidazole 500mg', 'Comprimé', 'medicament', 45, 300],
    ['Ibuprofène 400mg', 'Comprimé', 'medicament', 35, 250],
    ['Diclofénac 75mg injectable', 'Ampoule', 'medicament', 200, 100],
    ['Oméprazole 20mg', 'Gélule', 'medicament', 90, 180],
    ['Sérum glucosé 5% 500ml', 'Poche', 'medicament', 750, 120],
    ['Sérum salé isotonique 0,9% 500ml', 'Poche', 'medicament', 700, 150],
    ['Ringer lactate 500ml', 'Poche', 'medicament', 800, 90],
    ['Fer + Acide folique', 'Comprimé', 'medicament', 30, 400],
    ['Ocytocine 5UI', 'Ampoule', 'medicament', 350, 80],
    ['Méthyldopa 250mg', 'Comprimé', 'medicament', 80, 150],
    ['Amlodipine 5mg', 'Comprimé', 'medicament', 55, 200],
    ['Metformine 850mg', 'Comprimé', 'medicament', 45, 250],
    ['Insuline rapide 100UI/ml', 'Flacon', 'medicament', 4500, 15],
    ['Dexaméthasone 4mg', 'Ampoule', 'medicament', 250, 100],
    ['Salbutamol spray', 'Flacon', 'medicament', 2200, 25],
    ['Vitamine C 500mg', 'Comprimé', 'medicament', 20, 300],
    ['Albendazole 400mg', 'Comprimé', 'medicament', 150, 200],
  ];
  var CONSOMMABLES = [
    ['Gants d’examen latex (boîte 100)', 'Boîte', 'conso_medical', 4500, 40],
    ['Gants stériles chirurgicaux', 'Paire', 'conso_medical', 350, 200],
    ['Seringue 5ml', 'Unité', 'conso_medical', 60, 800],
    ['Seringue 10ml', 'Unité', 'conso_medical', 80, 600],
    ['Cathéter IV G18', 'Unité', 'conso_medical', 250, 300],
    ['Cathéter IV G22', 'Unité', 'conso_medical', 250, 300],
    ['Compresses stériles', 'Sachet', 'conso_medical', 150, 400],
    ['Bande de gaze 10cm', 'Rouleau', 'conso_medical', 300, 200],
    ['Sparadrap', 'Rouleau', 'conso_medical', 500, 100],
    ['Alcool 70° 500ml', 'Flacon', 'conso_medical', 900, 60],
    ['Bétadine dermique 125ml', 'Flacon', 'conso_medical', 2200, 40],
    ['Fil de suture résorbable', 'Unité', 'conso_medical', 1200, 80],
    ['Sonde urinaire Foley', 'Unité', 'conso_medical', 850, 50],
    ['Perfuseur', 'Unité', 'conso_medical', 200, 400],
    ['Masque chirurgical (boîte 50)', 'Boîte', 'conso_medical', 2500, 30],
  ];
  var REACTIFS = [
    ['Réactif Glycémie (kit 100 tests)', 'Kit', 'reactif', 18000, 8],
    ['Réactif Créatinine (kit 100 tests)', 'Kit', 'reactif', 22000, 6],
    ['Réactif Transaminases ASAT/ALAT', 'Kit', 'reactif', 25000, 6],
    ['Réactif Cholestérol total', 'Kit', 'reactif', 20000, 5],
    ['Test rapide Paludisme (TDR)', 'Boîte 25', 'reactif', 12000, 15],
    ['Test rapide VIH 1/2', 'Boîte 25', 'reactif', 15000, 12],
    ['Test rapide Hépatite B (AgHBs)', 'Boîte 25', 'reactif', 14000, 10],
    ['Sérum test Anti-A / Anti-B / Anti-D', 'Coffret', 'reactif', 16000, 6],
    ['Réactif Widal', 'Kit', 'reactif', 19000, 5],
    ['Lames porte-objet (boîte 50)', 'Boîte', 'conso_labo', 3500, 20],
    ['Tubes EDTA 5ml', 'Unité', 'conso_labo', 90, 500],
    ['Tubes secs 5ml', 'Unité', 'conso_labo', 85, 500],
    ['Pipettes Pasteur', 'Unité', 'conso_labo', 45, 400],
    ['Bandelettes urinaires (boîte 100)', 'Boîte', 'conso_labo', 8500, 12],
    ['Huile à immersion', 'Flacon', 'conso_labo', 4200, 8],
  ];
  var DIVERS = [
    ['Ramette papier A4', 'Ramette', 'fourniture', 3500, 30],
    ['Registre grand format', 'Unité', 'fourniture', 2500, 20],
    ['Cartouche encre imprimante', 'Unité', 'fourniture', 18000, 6],
    ['Eau de javel 1L', 'Bidon', 'entretien', 800, 40],
    ['Savon liquide antiseptique 5L', 'Bidon', 'entretien', 6500, 12],
    ['Balai et raclette', 'Unité', 'entretien', 2000, 10],
    ['Tensiomètre électronique', 'Unité', 'petit_materiel', 35000, 4],
    ['Thermomètre infrarouge', 'Unité', 'petit_materiel', 18000, 6],
    ['Stéthoscope', 'Unité', 'petit_materiel', 22000, 5],
    ['Oxymètre de pouls', 'Unité', 'petit_materiel', 15000, 6],
  ];

  /* ==========================================================================
   * JEUX DE DROITS DES RÔLES CRÉÉS
   * --------------------------------------------------------------------------
   * Un rôle créé part de zéro : la surcharge FERME chaque module nommément,
   * puis en rouvre quelques-uns. Sans cette fermeture explicite, les modules
   * portant `roles: '*'` au manifeste — M1 et RAP — resteraient ouverts à un
   * rôle qu'on vient d'inventer.
   * ======================================================================== */
  var MODULES_TOUS = ["DASH","M1","M2","M3","M4","M5","M6","M7","M8","M9","MECEF","M10","M11","M12","M13","GED","RAP","M14","CFG"];

  /* ==========================================================================
   * LE MODULE DES TABLEAUX DE BORD NE SE DÉCLARE JAMAIS AU NIVEAU DU MODULE.
   * --------------------------------------------------------------------------
   * DASH porte `roles: ALL` au manifeste et ce sont les listes de CHAQUE écran
   * qui filtrent. Les deux façons de le déclarer sont donc fautives, et de
   * manière symétrique :
   *
   *   `DASH: VOIR`  → une surcharge ACCORDE : le rôle récupère les VINGT
   *                   tableaux de bord d'un coup. Mesuré sur les quatre rôles
   *                   créés : l'aide-soignante lisait les tableaux de la
   *                   comptabilité et des ressources humaines, et le
   *                   technicien d'échographie ceux de la caisse et de la
   *                   comptabilité — alors que « aucun accès financier » est
   *                   la condition même que la Direction a posée pour ce
   *                   poste.
   *   `DASH: fermé` → le rôle perdrait AUSSI son propre tableau, donc sa page
   *                   d'accueil.
   *
   * On ne le déclare donc pas : le manifeste décide, écran par écran, et
   * chaque rôle voit exactement le sien.
   *
   * La création d'un rôle en cours d'exploitation est un autre cas : là, tout
   * est fermé DASH compris, parce qu'un rôle inventé n'a pas de tableau à lui.
   * ======================================================================== */
  function fermerTout(ouverts) {
    var out = {};
    MODULES_TOUS.forEach(function (m) {
      if (m === 'DASH') return;
      out[m] = ouverts[m] || { voir: false, editer: false, annuler: false };
    });
    return out;
  }
  var VOIR = { voir: true, editer: false, annuler: false };
  var EDITER = { voir: true, editer: true, annuler: false };
  var TOUT = { voir: true, editer: true, annuler: true };

  /* L'aide-soignante participe aux soins : elle voit le patient et
     l'hospitalisation, elle ne voit AUCUN résultat d'analyse — c'est la règle
     métier posée par la Direction pour cette fonction. */
  /* RESSERRÉE SUR LA CIBLE DU 10/10/2026 (×17 mesuré : 68 écrans pour 4
     demandés). M3 ouvert pour trois écrans lui en donnait vingt, dont le
     rapport médical et la sortie contre avis. Les modules sont fermés ; ses
     quatre écrans s'ouvrent nommément dans sa fiche. */
  var droitsAideSoignant = fermerTout({});

  /* Le technicien d'échographie : dossier en LECTURE, imagerie en CRÉATION,
     AUCUN accès financier — ni caisse, ni assurances, ni comptabilité. C'est
     la condition posée par la Direction, et elle est structurante : un
     manipulateur qui verrait la caisse pourrait faire dépendre l'examen du
     paiement, ce qui n'est pas son rôle. */
  /* M2 EN LECTURE, et l'imagerie seule en écriture par surcharge d'écran.
     « M2: EDITER » lui ouvrait aussi les ordonnances, la salle de soins et la
     file d'attente : un technicien d'échographie qui rédige une ordonnance,
     ce n'est pas une habilitation trop large, c'est un exercice illégal. */
  var droitsEchographiste = fermerTout({
    M1: VOIR, M2: VOIR, M5: VOIR, RAP: VOIR,
  });

  /* Le surveillant : agendas, retards, présences, absences, planning et
     gardes. Ce sont exactement les missions 1 et 5 de la description de poste
     de l'Infirmier Général. Aucun accès financier ni comptable. */
  /* RESSERRÉ SUR LA CIBLE DU 10/10/2026 (×16 mesuré : 97 écrans pour 6
     demandés). M10 lui ouvrait les vingt-quatre écrans des ressources
     humaines — personnel, contrats, badges, congés, sanctions — quand son
     métier en demande cinq : le planning et les présences. */
  var droitsSurveillant = fermerTout({});

  /* L'assistant comptable, d'après ses 30 activités : livres de compte,
     rapprochements, recouvrement des créances chez les particuliers ET les
     compagnies, obligations fiscales, point journalier de la caisse,
     inventaire des médicaments d'urgence et des réactifs de laboratoire. */
  /* ==========================================================================
   * ASSISTANT DE DIRECTION — DEUX FERMETURES DU 24/09/2026
   * --------------------------------------------------------------------------
   * NEINSTRUCTION pose une « RESTRICTION ABSOLUE : pas de menu Soins, pas de
   * sous-menu Laboratoire ». M5 en lecture lui donnait les demandes
   * d'analyses et les RÉSULTATS — des données de santé nominatives que RG-13
   * réserve au soignant habilité. Le module est donc FERMÉ.
   *
   * MAIS SA DESCRIPTION DE POSTE LUI DONNE « L'INVENTAIRE DES MÉDICAMENTS
   * D'URGENCE ET DES RÉACTIFS », et c'est écrit au motif de sa propre fiche.
   * Fermer M5 en bloc lui retirait une de ses trente activités. L'écran
   * `m5-reactifs` lui est donc ACCORDÉ NOMMÉMENT : une surcharge accorde
   * autant qu'elle restreint, et c'est exactement ce qu'elle sert à faire —
   * un stock de réactifs n'est pas un résultat d'analyse.
   *
   * M12 RESTE À TOUT, et c'est délibéré. NEINSTRUCTION1 ne donne aucun
   * Financier à son « assistant de direction » ; mais le poste qu'il décrit
   * est un secrétariat, quand le nôtre est bâti sur une description de poste
   * explicitement comptable — « livres de compte, rapprochements bancaires,
   * recouvrement des créances, obligations fiscales ». Les deux documents ne
   * parlent pas du même agent. On ne retire pas une attribution documentée
   * sur la foi d'une homonymie : la question est posée à la Direction.
   * ======================================================================== */
  /* L'ADMINISTRATION ET LA GED SONT SON MÉTIER (cible du 10/10/2026).
     `fermerTout` les fermait : il ne voyait ni courrier, ni réunion, ni note
     de service — la totalité de sa description de poste — et gardait
     l'intégralité du financier. On lui rend le secrétariat ; ce qu'il a de
     trop par ailleurs attend un arbitrage, il ne se retire pas au passage
     d'une correction qui ne portait pas là-dessus. */
  var droitsAssistantComptable = fermerTout({
    M13: EDITER, GED: EDITER,
  });

  /* ==========================================================================
   * LES TROIS RÔLES DE LA PHASE 2 — arbitrage et cible du 31/08/2026
   * --------------------------------------------------------------------------
   * Le CHIRURGIEN : même base que le médecin, PLUS le bloc, MOINS la
   * maternité — la matrice cible ferme M4 nommément pour ce profil. D interdit
   * partout (pas d'annulation) : un compte rendu opératoire ne se retire pas.
   *
   * L'ANESTHÉSISTE : le péri-opératoire — patients en lecture, hospitalisation
   * et bloc en écriture, résultats de laboratoire en lecture. Ni maternité, ni
   * consultations générales : il n'ouvre pas de dossier de médecine, il
   * sécurise une intervention. Ses écrans propres (CPA, feuille d'anesthésie)
   * arrivent en phase 6 et hériteront de M3.
   *
   * L'ASSISTANT COMPTABLE (16ᵉ rôle, créé par arbitrage — distinct de
   * l'Assistant de Direction) : saisie financière SANS pouvoir d'annulation —
   * dépenses, écritures, réceptions fournisseurs — et AUCUN accès clinique.
   * La clôture annuelle lui est fermée nommément : elle engage l'exercice, et
   * la cible la réserve au Comptable principal et à la DAF.
   * ======================================================================== */
  var droitsChirurgien = fermerTout({
    M1: EDITER, M2: EDITER, M3: EDITER, M5: VOIR, RAP: VOIR,
  });
  var droitsAnesthesiste = fermerTout({
    M1: VOIR, M3: EDITER, M5: VOIR, RAP: VOIR,
  });
  var droitsAideComptable = fermerTout({
    M7: EDITER, M8: VOIR, M9: EDITER, MECEF: VOIR, M12: EDITER, RAP: VOIR,
  });

  function genPersonnel(rnd) {
    var out = [], mat = 1;
    function add(nom, fonctionId, service, salaire, sexe, poste) {
      var parts = nom ? nom.split('|') : null;
      var nomF = parts ? parts[0] : C.pick(rnd, NOMS);
      var prenom = parts ? parts[1] : (sexe === 'F' ? C.pick(rnd, PRENOMS_F) : C.pick(rnd, PRENOMS_M));
      var ech = 'E' + C.between(rnd, 1, 5) + '-' + C.between(rnd, 1, 3);
      var embauche = new Date(2016 + C.between(rnd, 0, 9), C.between(rnd, 0, 11), C.between(rnd, 1, 28));
      out.push({
        id: 'EMP' + C.pad(mat), matricule: String(mat++),
        nom: nomF, prenom: prenom, nomComplet: nomF + ' ' + prenom,
        sexe: sexe, fonction: fonctionId, poste: poste || '', service: service,
        categorie: ech, salaireBase: salaire,
        dateEmbauche: C.iso(embauche),
        cnss: '2' + C.between(rnd, 100000, 999999) + C.between(rnd, 10, 99),
        telephone: '0' + C.between(rnd, 1, 9) + C.between(rnd, 10000000, 99999999),
        situation: C.pick(rnd, ['Célibataire', 'Marié(e)', 'Marié(e)', 'Veuf(ve)']),
        statut: 'actif',
      });
    }
    /* Effectif arrêté par la Direction le 26/08/2026 : 45 agents, répartis
       entre les fonctions médicales, paramédicales, administratives, le soutien
       logistique et la sécurité. L'organigramme en totalisait 44 ; le poste
       ajouté est le second biologiste, que le document comptait dans
       « Laborantins (02) » sans le nommer. */
    add('BASSONGUI|Chabi Séko', 'medecin', 'Direction', 450000, 'M', 'Directeur Médical');
    add('TAKI|Alimatou', 'direction', 'Direction', 350000, 'F', 'Directrice de l’Administration et des Finances');
    add('KASSA|Augustin', 'comptable', 'Comptabilité', 180000, 'M', 'Comptable');
    /* Assistant de DIRECTION, non assistant comptable : c'est le poste que
     décrit la seconde description de poste, celle qui s'intitule
     « Directrice Administrative » mais décrit son adjoint. */
    add('GBEDJI|Hervé', 'comptable', 'Direction', 110000, 'M', 'Assistant de Direction');
    add('YENI|M’PO Florent', 'medecin', 'Médecine générale', 280000, 'M', 'Médecin Généraliste');
    add(null, 'medecin', 'Médecine générale', 275000, 'M', 'Médecin Généraliste');
    add('AHOHOU|Rodrigue', 'medecin', 'Imagerie / Échographie', 240000, 'M', 'Échographiste');
    /* Poste rectifié par la Direction le 25/08/2026 : KINNOU A. Ganiou est
       INGÉNIEUR BIOMÉDICAL. Il entretient les automates, il ne rend pas de
       résultats — lui laisser le compte du laboratoire lui aurait ouvert la
       validation biologique, qui engage la responsabilité du biologiste. */
    /* DEUX BIOLOGISTES MÉDICAUX — décision de la Direction du 26/08/2026.
       Ce sont les deux agents que l'organigramme appelle « Laborantins (02) » ;
       le terme est renommé, la fonction ne change pas. KINNOU A. Ganiou reste
       au laboratoire comme chef de service : la mention « Ingénieur Biomédical »
       de la liste de comptes est écartée au profit de l'organigramme. */
    add('KINNOU|A. Ganiou', 'tsl', 'Laboratoire', 150000, 'M', 'Biologiste médical — Chef de service');
    add(null, 'tsl', 'Laboratoire', 130000, 'M', 'Biologiste médical');
    add('GARBA|Yahouza', 'infirmier', 'Soins infirmiers', 130000, 'M', 'Surveillant');
    /* Trois infirmiers nommés par la Direction le 25/08/2026 ; les quatre
       autres restent à nommer — l'effectif soignant (7) est confirmé, la liste
       des comptes n'en couvre que trois. */
    add('IDRISSOU ANIKI|Baba-Toundé', 'infirmier', 'Soins infirmiers', 95000, 'M', 'Infirmier');
    add('NKOUÉ|Jean', 'infirmier', 'Soins infirmiers', 90000, 'M', 'Infirmier');
    add('BAGRI|Elvyre', 'infirmier', 'Soins infirmiers', 90000, 'F', 'Infirmière');
    for (var i = 0; i < 4; i++) add(null, 'infirmier', 'Soins infirmiers', 85000 + C.between(rnd, 0, 3) * 5000, i % 2 ? 'F' : 'M', 'Infirmier(ère)');
    /* La sage-femme nommée est celle qui prescrit les échographies
       obstétricales sur les comptes rendus réels — « SFE BADO BANI Zouléhath ». */
    add('BADO BANI|A. B. Zoulehath', 'sage_femme', 'Maternité', 105000, 'F', 'Sage-femme');
    for (var j = 0; j < 2; j++) add(null, 'sage_femme', 'Maternité', 95000 + C.between(rnd, 0, 2) * 5000, 'F', 'Sage-femme');
    add('TEPA|Séraphine', 'aide_soignant', 'Soins infirmiers', 65000, 'F', 'Aide-soignante — Chef de service');
    for (var k = 0; k < 7; k++) add(null, 'aide_soignant', 'Soins infirmiers', 60000, 'F', 'Aide-soignante');
    /* Poste COMBINÉ, confirmé par la Direction : la même personne tient la
     caisse et la dispensation. C'est ce qui justifie le rattachement de la
     pharmacie au compte Caissier. */
    add('DIEYABIDI|Aïssatou', 'caissiere', 'Pharmacie', 90000, 'F', 'Caissière-Dispensatrice');
    for (var l = 0; l < 3; l++) add(null, 'dispensatrice', 'Pharmacie', 70000, 'F', 'Dispensatrice');
    add('OROU YO|Edmond', 'accueil', 'Accueil', 75000, 'M', 'Secrétaire Médical — Chef de service');
    add(null, 'caissiere', 'Accueil', 70000, 'F', 'Caissière');
    add(null, 'accueil', 'Accueil', 62000, 'F', 'Secrétaire Médicale');
    add(null, 'accueil', 'Accueil', 62000, 'F', 'Secrétaire Médicale');
    add('MAMAN|Zoukanéri', 'stock', 'Direction', 105000, 'F', 'Gestionnaire de Stock');
    add('OURTCHA|Tereyama', 'securite', 'Direction', 55000, 'M', 'Agent de Sécurité — Chef de service');
    for (var m = 0; m < 2; m++) add(null, 'securite', 'Direction', 50000, 'M', 'Agent de Sécurité');
    add('ISSA|Rabiatou', 'entretien', 'Direction', 50000, 'F', 'Agent d’Entretien — Chef de service');
    for (var n = 0; n < 2; n++) add(null, 'entretien', 'Direction', 45000, 'F', 'Agent d’Entretien');
    add('TCHANE|Nourou', 'chauffeur', 'Direction', 60000, 'M', 'Chauffeur Coursier');
    return out;
  }

  function genPatients(rnd, n) {
    var out = [];
    for (var i = 1; i <= n; i++) {
      var sexe = rnd() > 0.45 ? 'F' : 'M';
      var annee = rnd() > 0.25 ? 26 : 25;
      var anneeComplete = 2000 + Number(String(annee).slice(-2));
      var age = C.between(rnd, 1, 82);
      var naiss = new Date(2026 - age, C.between(rnd, 0, 11), C.between(rnd, 1, 28));
      var assure = rnd() > 0.62;
      var comp = assure ? C.pick(rnd, D.ASSUREURS) : null;
      out.push({
        id: 'PAT' + C.pad(i, 4),
        /* Le format est porté par C.codePatient() et NULLE PART AILLEURS.
           Le reconstruire ici en faisait une seconde règle, qui a divergé dès
           que la Direction a demandé « CNT/[n° d'ordre]/[année] ». */
        code: C.codePatient(i, anneeComplete),
        nom: C.pick(rnd, NOMS),
        prenom: sexe === 'F' ? C.pick(rnd, PRENOMS_F) : C.pick(rnd, PRENOMS_M),
        sexe: sexe,
        dateNaissance: C.iso(naiss),
        age: age,
        telephone: '0' + C.between(rnd, 1, 9) + C.between(rnd, 10000000, 99999999),
        quartier: C.pick(rnd, QUARTIERS),
        adresse: C.pick(rnd, QUARTIERS) + ', Natitingou',
        personneAPrevenir: C.pick(rnd, NOMS) + ' ' + C.pick(rnd, PRENOMS_M),
        groupeSanguin: C.pick(rnd, D.GROUPES_SANGUINS),
        assureur: comp ? comp.code : null,
        assureurNom: comp ? comp.nom : null,
        numeroPolice: comp ? comp.code + '-' + C.between(rnd, 100000, 999999) : null,
        /* Rattachement au souscripteur : c'est le contrat de l'employeur, pas la
           compagnie, qui porte la grille de garanties (relevés par souscripteur). */
        souscripteurId: null,
        categorieAssurance: comp ? C.pick(rnd, ['particulier', 'personnel', 'entreprise', 'entreprise']) : null,
        /* Conservé pour l'historique des factures déjà émises ; la répartition
           se calcule désormais garantie par garantie. */
        tauxPriseEnCharge: comp ? C.pick(rnd, [70, 80, 80, 90, 100]) : 0,
        carteExpiration: comp ? C.iso(new Date(2026, C.between(rnd, 0, 11), C.between(rnd, 1, 28))) : null,
        dateCreation: C.iso(new Date(2000 + annee, C.between(rnd, 0, 7), C.between(rnd, 1, 28))),
        antecedents: C.pick(rnd, ANTECEDENTS),
        antecedentsAutres: rnd() > 0.8 ? C.pick(rnd, ANTECEDENTS) : '',
        allergies: C.pick(rnd, ALLERGIES),
        traitementEnCours: rnd() > 0.7 ? C.pick(rnd, ['Antihypertenseur', 'Antidiabétique oral', 'Antirétroviral', 'Insuline']) : '',
        statut: 'actif',
      });
    }
    return out;
  }

  /* --------------------------------------------------------------------------
   * Le référentiel produits est issu de la REPRISE de l'inventaire « Grand
   * Stock » SAGE 100 arrêté au 15/07/2026 : références, désignations,
   * quantités et coûts unitaires moyens pondérés sont ceux du document.
   * Seuls la ventilation gros/détail, l'emplacement et le seuil d'alerte sont
   * proposés par le système et restent à valider par la clinique.
   * ----------------------------------------------------------------------- */
  function genProduits(rnd) {
    var SG = global.SIGH.sage;
    /* La médiane des coûts unitaires VALORISÉS de chaque catégorie — le
       « montant juste » de l'arbitrage : plausible, dérivé du document, et
       recalculé si l'inventaire change. Une catégorie sans aucun coût
       valorisé retombe sur la médiane générale. */
    var parCategorie = {};
    SG.INVENTAIRE_SAGE.forEach(function (a) {
      var v = Math.round(a.cump);
      if (v > 0) (parCategorie[a.categorie] = parCategorie[a.categorie] || []).push(v);
    });
    var toutes = [];
    Object.keys(parCategorie).forEach(function (k) {
      parCategorie[k].sort(function (x, y) { return x - y; });
      toutes = toutes.concat(parCategorie[k]);
    });
    toutes.sort(function (x, y) { return x - y; });
    function medianeCategorie(cat) {
      var vals = parCategorie[cat] && parCategorie[cat].length ? parCategorie[cat] : toutes;
      return vals.length ? vals[Math.floor(vals.length / 2)] : 500;
    }
    return SG.INVENTAIRE_SAGE.map(function (a, i) {
      /* Le magasin central conserve l'essentiel ; la pharmacie de détail est
         approvisionnée par transferts successifs. */
      var qDetail = Math.min(a.quantite, Math.round(a.quantite * (0.15 + rnd() * 0.25)));
      var qGros = a.quantite - qDetail;
      /* Le CMUP exact sert à la valorisation (quantité × cump = P.R. global du
         document) ; la facturation, elle, s'exprime en francs entiers. */
      var prix = Math.round(a.cump);
      /* ARBITRAGE DU 01/09/2026 — plus aucun article à montant NUL : une
         référence non valorisée par SAGE reçoit une VALEUR D'ATTENTE, la
         MÉDIANE de sa catégorie (calculée, jamais écrite en dur — le jour où
         l'inventaire change, la médiane suit). Marquée provisoire, tracée
         dans `valorisationsSage` : la surcouche, jamais la réécriture du
         document — INVENTAIRE_SAGE reste ce qu'il est. */
      var provisoire = !(prix > 0);
      if (provisoire) prix = medianeCategorie(a.categorie);
      return Object.assign(provisoire ? {
        valorisationProvisoire: true,
        sourceValorisation: 'Décision de la Direction du 01/09/2026 — médiane de la catégorie, à confirmer',
      } : {}, {
        id: 'PRD' + C.pad(i + 1, 4),
        code: a.code,
        designation: a.designation,
        unite: SG.uniteDe(a.designation),
        categorie: a.categorie,
        prixAchat: prix,
        /* RG-02 : les médicaments sont facturés au prix d'achat, sans marge. */
        prixVente: prix,
        cump: provisoire ? prix : a.cump,
        /* Seuils proposés (20 % du stock repris, plancher 5), CONFIRMÉS par
           la clinique le 01/09/2026 (vague 51) — révisables référence par
           référence à l'écran des réactifs et du stock. */
        seuilAlerte: SG.seuilPropose(a.quantite),
        seuilConfirmeLe: '2026-09-01',
        stockGros: qGros, stockDetail: qDetail,
        stock: a.quantite,
        emplacement: 'Rayon ' + String.fromCharCode(65 + (i % 6)) + ' — Casier ' + ((i % 8) + 1),
        fournisseur: C.pick(rnd, D.FOURNISSEURS).code,
        /* Traçabilité de la reprise (draf1 §10). */
        source: SG.LOT_IMPORT.source,
        lotImport: SG.LOT_IMPORT.reference,
        dateImport: SG.LOT_IMPORT.dateArrete,
        quantiteImportee: a.quantite,
        valoriseSage: a.valorise,
        seuilAValider: false,
        statut: 'actif',
      });
    });
  }

  function genLots(rnd, produits) {
    var out = [], today = new Date(2026, 7, 16);
    produits.forEach(function (p, i) {
      if (p.categorie === 'fourniture' || p.categorie === 'petit_materiel' || p.categorie === 'immobilisation') return;
      var nb = C.between(rnd, 1, 3);
      for (var k = 0; k < nb; k++) {
        var jours = C.between(rnd, -40, 640);
        out.push({
          id: 'LOT' + C.pad(out.length + 1, 4),
          produitId: p.id, produit: p.designation,
          numeroLot: 'L' + (2025 + (k % 2)) + '-' + C.pad(C.between(rnd, 1, 999), 3),
          datePeremption: C.iso(C.addDays(today, jours)),
          quantiteRestante: C.between(rnd, 0, Math.max(1, Math.round(p.stock / nb))),
          emplacement: p.emplacement,
          statut: jours < 0 ? 'perime' : (jours < 90 ? 'alerte' : 'actif'),
        });
      }
    });
    return out;
  }

  function genConsultations(rnd, patients, personnel) {
    var medecins = personnel.filter(function (e) { return e.fonction === 'medecin'; });
    var out = [], today = new Date(2026, 7, 16);
    for (var i = 0; i < 260; i++) {
      var p = C.pick(rnd, patients), m = C.pick(rnd, medecins);
      var d = C.addDays(today, -C.between(rnd, 0, 120));
      d.setHours(C.between(rnd, 8, 18), C.pick(rnd, [0, 15, 30, 45]));
      out.push({
        id: 'CONS' + C.pad(i + 1, 4),
        reference: 'C' + C.pad(i + 1, 5),
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        medecinId: m.id, medecin: m.nomComplet,
        date: d.toISOString(),
        motif: C.pick(rnd, MOTIFS),
        diagnostic: C.pick(rnd, DIAGNOSTICS),
        type: C.pick(rnd, ['Consultation', 'Consultation', 'Consultation', 'Contrôle', 'Urgence', 'Domicile']),
        tarif: C.pick(rnd, [3000, 3000, 5000, 5000, 10000]),
        statut: C.pick(rnd, ['terminee', 'terminee', 'terminee', 'en_cours', 'planifiee']),
      });
    }
    return C.sortBy(out, 'date', 'desc');
  }

  function genAdmissions(rnd, patients, personnel) {
    var lits = [];
    D.CHAMBRES.forEach(function (ch) { ch.lits.forEach(function (l) { lits.push({ chambre: ch, lit: l }); }); });
    var infirmiers = personnel.filter(function (e) { return e.fonction === 'infirmier' || e.fonction === 'sage_femme'; });
    var out = [], today = new Date(2026, 7, 16), occupes = {};
    for (var i = 0; i < 90; i++) {
      var p = C.pick(rnd, patients), inf = C.pick(rnd, infirmiers);
      var entree = C.addDays(today, -C.between(rnd, 0, 150));
      var duree = C.between(rnd, 1, 12);
      var enCours = i < 14;
      var slot = lits[i % lits.length];
      if (enCours && occupes[slot.lit.code]) enCours = false;
      if (enCours) occupes[slot.lit.code] = true;
      out.push({
        id: 'ADM' + C.pad(i + 1, 4),
        reference: 'H' + C.pad(i + 1, 5),
        patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
        chambre: slot.chambre.code, lit: slot.lit.label, typeChambre: slot.chambre.type,
        dateEntree: enCours ? C.iso(C.addDays(today, -C.between(rnd, 0, 9))) : C.iso(entree),
        dateSortie: enCours ? null : C.iso(C.addDays(entree, duree)),
        diagnosticEntree: C.pick(rnd, DIAGNOSTICS),
        symptomes: C.pick(rnd, MOTIFS),
        priseEnCharge: rnd() > 0.3 ? 'plus_8h' : 'moins_8h',
        infirmierId: inf.id, infirmier: inf.nomComplet,
        statut: enCours ? 'en_cours' : 'sortie',
      });
    }
    return out;
  }

  /* ==========================================================================
   * FACTURES — ENGENDRÉES À PARTIR DE LEURS LIGNES
   * --------------------------------------------------------------------------
   * Le montant est la SOMME des lignes, jamais un nombre tiré à part : une
   * facture dont le total ne correspond pas à son détail est un piège, et c'est
   * exactement ce que produisait la version précédente. Le reçu n'avait alors
   * rien à détailler, et un règlement partiel n'avait aucune ligne à
   * sélectionner — d'où le défaut signalé par la Direction le 25/08/2026.
   *
   * Chaque ligne porte son statut de paiement propre. C'est lui qui permet à la
   * caisse de dire « ces trois examens-là sont réglés, ces deux-là ne le sont
   * pas » — et au laboratoire de ne recevoir que les premiers.
   * ======================================================================== */
  /* ==========================================================================
   * ÉCHÉANCES FISCALES
   * --------------------------------------------------------------------------
   * Chaque obligation mensuelle donne douze échéances, chaque obligation
   * annuelle en donne une. Une échéance tombant un samedi ou un dimanche est
   * REPORTÉE au jour ouvrable suivant, jamais avancée — l'administration
   * n'ouvre pas le week-end, et anticiper ferait payer avant d'y être tenu.
   * ======================================================================== */
  function genEcheances() {
    var AUJ2 = new Date(2026, 7, 16);
    function jourOuvrableSuivant(d) {
      var x = new Date(d.getTime());
      while (x.getDay() === 0 || x.getDay() === 6) x = C.addDays(x, 1);
      return x;
    }
    var annee = AUJ2.getFullYear();
    var out = [], n = 0;
    (D.CALENDRIER_FISCAL || []).forEach(function (o) {
      var dates = [];
      if (o.periodicite === 'mensuelle') {
        for (var m = 0; m < 12; m++) dates.push(new Date(annee, m, o.jour));
      } else {
        dates.push(new Date(annee, o.mois, Math.min(o.jour, 28)));
      }
      dates.forEach(function (d) {
        n++;
        var echue = jourOuvrableSuivant(d);
        var passee = echue < AUJ2;
        out.push({
          id: 'ECH' + C.pad(n, 4), statut: 'actif',
          code: o.code, libelle: o.libelle, famille: o.famille,
          periodicite: o.periodicite, part: o.part, declaration: o.declaration, note: o.note,
          exercice: annee,
          periode: o.periodicite === 'mensuelle'
            ? C.MOIS[Math.max(0, d.getMonth() - 1)] + ' ' + annee : String(annee),
          echeance: C.iso(echue),
          reportee: C.iso(echue) !== C.iso(d),
          /* Les échéances passées sont réputées honorées, SAUF les plus
             récentes — sans quoi l'écran de suivi et le tableau de bord du
             comptable n'auraient jamais rien à montrer. */
          paye: passee && C.daysBetween(echue, AUJ2) > 25,
          datePaiement: null, montant: null, reference: null, valideePar: null,
        });
      });
    });
    out.forEach(function (e) {
      if (e.paye) {
        e.datePaiement = e.echeance;
        e.valideePar = 'KASSA Augustin';
        e.reference = 'QUIT-' + e.code + '-' + e.exercice;
      }
    });
    return out;
  }

  /* Une remise se JUSTIFIE. Un rabais sans motif au dossier est exactement ce
     qu'un contrôle interne cherche : la colonne « motif » n'est pas
     décorative. */
  var MOTIFS_REMISE = [
    { code: 'famille_agent', label: 'Famille d’un agent', taux: 50 },
    { code: 'indigent', label: 'Cas social — décision de la Direction', taux: 100 },
    { code: 'fidelite', label: 'Client de longue date', taux: 10 },
    { code: 'geste', label: 'Geste commercial — Direction', taux: 20 },
    { code: 'convention', label: 'Convention d’établissement', taux: 15 },
  ];

  function genFactures(rnd, patients, consultations, produits) {
    var out = [], today = new Date(2026, 7, 16);

    /* Le catalogue réel sert de source : facturer des libellés inventés
       rendrait les statistiques par prestation inexploitables. */
    var analyses = (D.ANALYSES || []).filter(function (a) { return a.prix; });
    var actes = (D.ACTES || []).filter(function (a) { return a.prix; });
    var meds = (produits || []).filter(function (x) { return x.prixAchat > 0; });

    /* Les natures de facture et ce qu'elles portent. */
    var NATURES = [
      { type: 'Consultation', lignes: function () {
        var a = C.pick(rnd, actes.filter(function (x) { return /consultation/i.test(x.libelle); }) );
        return a ? [{ categorie: 'consultation', designation: a.libelle, quantite: 1, prixUnitaire: a.prix }] : [];
      } },
      { type: 'Laboratoire', lignes: function () {
        var n = C.between(rnd, 1, 5), l = [];
        for (var k = 0; k < n; k++) {
          var a = C.pick(rnd, analyses);
          if (a && !l.some(function (x) { return x.designation === a.designation; })) {
            l.push({ categorie: 'analyse', designation: a.designation, quantite: 1, prixUnitaire: a.prix });
          }
        }
        return l;
      } },
      { type: 'Pharmacie', lignes: function () {
        var n = C.between(rnd, 1, 4), l = [];
        for (var k = 0; k < n; k++) {
          var m2 = C.pick(rnd, meds);
          if (m2 && !l.some(function (x) { return x.designation === m2.designation; })) {
            /* RG-02 — le médicament se facture au prix d'achat, sans marge. */
            l.push({ categorie: 'medicament', designation: m2.designation,
              quantite: C.between(rnd, 1, 3), prixUnitaire: m2.prixAchat, produitId: m2.id });
          }
        }
        return l;
      } },
      { type: 'Soins', lignes: function () {
        var n = C.between(rnd, 1, 3), l = [];
        for (var k = 0; k < n; k++) {
          var a = C.pick(rnd, actes);
          if (a && !l.some(function (x) { return x.designation === a.libelle; })) {
            l.push({ categorie: 'acte', designation: a.libelle, quantite: 1,
              prixUnitaire: a.prix, acteCode: a.code });
          }
        }
        return l;
      } },
      { type: 'Hospitalisation', lignes: function () {
        var jours = C.between(rnd, 1, 7);
        var l = [{ categorie: 'hospitalisation', designation: 'Journée d’hospitalisation',
          quantite: jours, prixUnitaire: 5000 }];
        var a = C.pick(rnd, actes);
        if (a) l.push({ categorie: 'acte', designation: a.libelle, quantite: 1, prixUnitaire: a.prix, acteCode: a.code });
        return l;
      } },
    ];

    /* Densité réduite le 26/08/2026 : c'est l'ÉTENDUE de neuf mois qui porte
       les statistiques, pas le nombre de lignes. À 320 pièces le magasin
       frôlait le quota du navigateur, et une écriture de plus aurait été
       silencieusement perdue. */
    for (var i = 0; i < 230; i++) {
      var pat = C.pick(rnd, patients);
      var d = C.addDays(today, -C.between(rnd, 0, 150));
      var nature = C.pick(rnd, NATURES);
      var brutes = nature.lignes();
      /* Une nature qui ne produit rien ne fabrique pas de facture vide : mieux
         vaut 315 factures justes que 320 dont cinq sont creuses. */
      if (!brutes.length) continue;

      var taux = pat.assureur ? (pat.tauxPriseEnCharge || 0) : 0;

      /* L'AGENT DE LA CLINIQUE est pris en charge à 100 % par l'établissement.
         Ce n'est PAS une assurance : aucun tiers ne rembourse, aucune créance
         ne naît. La part correspondante a donc son propre compartiment. */
      var estAgent = !!pat.personnelId;

      /* Une pièce sur huit porte une remise, avec son motif. Jamais sur un
         agent — il est déjà pris en charge en totalité, et cumuler les deux
         n'aurait aucun sens. */
      var remise = (!estAgent && rnd() > 0.87) ? C.pick(rnd, MOTIFS_REMISE) : null;

      var lignes = brutes.map(function (l, k) {
        var brut = l.quantite * l.prixUnitaire;

        /* RG-02 — le médicament se facture au prix d'achat, sans marge : une
           remise le vendrait à perte. Les remises ne portent donc que sur les
           prestations. */
        var remisable = remise && l.categorie !== 'medicament';
        var montantRemise = remisable ? Math.round(brut * remise.taux / 100) : 0;
        var net = brut - montantRemise;

        var partAssureur = estAgent ? 0 : Math.round(net * taux / 100);
        var partPersonnel = estAgent ? net : 0;

        return {
          id: 'L' + C.pad(k + 1, 3),
          categorie: l.categorie, designation: l.designation,
          quantite: l.quantite, prixUnitaire: l.prixUnitaire,
          /* Le prix unitaire NET est la colonne « P.U NET » des pièces réelles :
             il se lit sans refaire la division. */
          prixUnitaireNet: l.quantite ? Math.round(net / l.quantite) : net,
          montantBrut: brut,
          remise: montantRemise,
          tauxRemise: remisable ? remise.taux : 0,
          motifRemise: remisable ? remise.label : null,
          montant: net,
          partAssureur: partAssureur,
          partPersonnel: partPersonnel,
          partPatient: net - partAssureur - partPersonnel,
          produitId: l.produitId || null, acteCode: l.acteCode || null,
          demandeId: null,
          statutPaiement: 'du', montantRegle: 0, payeLe: null, payePar: null,
        };
      });

      /* LE TOTAL EST LA SOMME DES LIGNES. Le tirer à part était le défaut. */
      var montantBrut = lignes.reduce(function (n, l) { return n + l.montantBrut; }, 0);
      var totalRemise = lignes.reduce(function (n, l) { return n + l.remise; }, 0);
      var montantTTC = lignes.reduce(function (n, l) { return n + l.montant; }, 0);
      var partAssurance = lignes.reduce(function (n, l) { return n + l.partAssureur; }, 0);
      var partPersonnel = lignes.reduce(function (n, l) { return n + l.partPersonnel; }, 0);
      var partPatient = montantTTC - partAssurance - partPersonnel;

      /* Le règlement porte sur des LIGNES ENTIÈRES : un demi-examen ne se
         prélève pas. On règle donc les premières lignes, dans l'ordre de la
         pièce, jusqu'à épuisement de ce que le patient a versé. */
      var solde = rnd() > 0.22;
      var aRegler = solde ? lignes.length : C.between(rnd, 0, lignes.length - 1);
      var paye = 0;
      lignes.forEach(function (l, k) {
        if (k < aRegler) {
          l.statutPaiement = 'paye';
          l.montantRegle = l.partPatient;
          l.payeLe = C.iso(d);
          l.payePar = 'Caisse';
          paye += l.partPatient;
        }
      });

      out.push({
        id: 'FAC' + C.pad(i + 1, 4),
        numero: 'FN-2026-' + C.pad(i + 1, 5),
        numeroMecef: rnd() > 0.12 ? 'MECEF' + C.between(rnd, 1000000, 9999999) : null,
        patientId: pat.id, patient: pat.nom + ' ' + pat.prenom, patientCode: pat.code,
        date: C.iso(d), type: nature.type,
        lignes: lignes,
        montantHT: montantTTC, montantTTC: montantTTC,
        /* Le brut et la remise restent lisibles à l'en-tête : c'est ce que
           le point de vente totalise, et le recalculer ligne à ligne à chaque
           état ferait diverger deux façons de compter la même chose. */
        montantBrut: montantBrut, totalRemise: totalRemise,
        motifRemise: remise ? remise.label : null,
        tauxRemise: remise ? remise.taux : 0,
        /* La prise en charge de l'établissement pour ses propres agents.
           Distincte de l'assurance : elle ne crée aucune créance. */
        partPersonnel: partPersonnel,
        priseEnChargePersonnel: estAgent,
        personnelId: pat.personnelId || null,
        assureur: pat.assureur, tauxPriseEnCharge: taux,
        /* Le SOUSCRIPTEUR est le niveau intermédiaire de la prise en charge —
           compagnie → souscripteur → assuré — et c'est lui que la facture mère
           consolide. Sans lui, toutes les pièces tombaient dans « Sans
           souscripteur désigné ». */
        souscripteur: pat.souscripteur || pat.souscripteurNom || null,
        partAssurance: partAssurance, partPatient: partPatient,
        montantPaye: paye, reliquat: partPatient - paye,
        /* Exigence écrite du cahier de charge : la base MECeF ne porte QUE la
           part réglée par le patient — ni la part assureur, ni les remises. */
        baseMecef: paye,
        modePaiement: C.pick(rnd, D.MODES_PAIEMENT.slice(0, 4)).id,
        statutPaiement: paye >= partPatient ? 'soldee' : (paye > 0 ? 'partielle' : 'impayee'),
        statutMecef: rnd() > 0.12 ? 'valide' : C.pick(rnd, ['en_attente', 'rejete']),
        statut: 'actif',
      });
    }
    return C.sortBy(out, 'date', 'desc');
  }

  function genMouvements(rnd, produits) {
    var out = [], today = new Date(2026, 7, 16);
    for (var i = 0; i < 400; i++) {
      var p = C.pick(rnd, produits);
      var t = C.pick(rnd, D.TYPES_MOUVEMENT);
      out.push({
        id: 'MVT' + C.pad(i + 1, 5),
        reference: 'M' + C.pad(i + 1, 6),
        date: C.iso(C.addDays(today, -C.between(rnd, 0, 90))),
        produitId: p.id, produit: p.designation,
        type: t.id, typeLabel: t.label,
        quantite: C.between(rnd, 1, 60),
        stockType: C.pick(rnd, D.TYPES_STOCK).id,
        /* RG-03 : tout mouvement porte un justificatif. */
        justificatif: C.pick(rnd, ['Facture FN-2026-00' + C.between(rnd, 100, 999), 'BL-26LNA000' + C.between(rnd, 10, 99),
          'Bon de transfert T-' + C.between(rnd, 100, 999), 'Constat de perte P-' + C.between(rnd, 10, 99),
          'Retour péremption R-' + C.between(rnd, 10, 99)]),
        utilisateur: C.pick(rnd, ['MAMAN Zoukanéri', 'DIEYABIDI Aïssatou', 'KINNOU Addoul Ganiou']),
        statut: 'actif',
      });
    }
    return C.sortBy(out, 'date', 'desc');
  }

  /* Vingt-cinq jours pointés par agent. Le taux de présence se calcule sur les
     jours RENSEIGNÉS et non sur le calendrier : un service dont on n'a pointé
     que dix jours ne doit pas paraître absent les vingt autres. */
  function genPresences(rnd, personnel) {
    var out = [], today = new Date(2026, 7, 16);
    (personnel || []).forEach(function (e) {
      for (var j = 0; j < 25; j++) {
        var d = C.addDays(today, -j);
        var r = rnd();
        var etat = r > 0.94 ? 'absent' : (r > 0.86 ? 'retard' : 'present');
        out.push({
          id: 'PRS' + C.uid(), statut: 'actif',
          date: C.iso(d), employeId: e.id, employe: e.nomComplet,
          matricule: e.matricule, service: e.service,
          etat: etat,
          heureArrivee: etat === 'absent' ? null
            : (etat === 'retard' ? '08:' + C.pad(C.between(rnd, 20, 55)) : '07:' + C.pad(C.between(rnd, 40, 59))),
          heureDepart: etat === 'absent' ? null
            : '1' + C.between(rnd, 6, 8) + ':' + C.pad(C.between(rnd, 0, 59)),
          motif: etat === 'absent'
            ? C.pick(rnd, ['Maladie', 'Congé', 'Absence non justifiée', 'Autorisation']) : null,
        });
      }
    });
    return out;
  }

  /* ==========================================================================
   * ÉCRITURES DU JEU DE DÉMONSTRATION — DES PIÈCES, PAS DES LIGNES AU HASARD
   * --------------------------------------------------------------------------
   * LE JEU DE DÉMONSTRATION VIOLAIT RG-10, et de trois façons à la fois :
   * chaque ligne tirait son compte au hasard dans TOUT le plan, puis son sens
   * par deux tirages INDÉPENDANTS. Mesuré sur les 260 lignes engendrées :
   * 6 157 000 F d'écart entre débit et crédit ; 68 lignes portant à la fois un
   * débit ET un crédit — une ligne d'écriture a un sens, pas deux ; 81 lignes
   * de CLASSE 6 au crédit, d'où des charges NÉGATIVES au rapprochement, et
   * 6 lignes de classe 7 au débit, d'où des produits négatifs.
   *
   * Le moteur, lui, a toujours contrôlé l'équilibre AVANT d'écrire
   * (`PR.ecrireEncaissement` refuse une pièce déséquilibrée) : c'est le
   * peuplement qui écrivait ce que l'application refuse. Un jeu de
   * démonstration qui enfreint l'invariant le plus visible du module fait
   * douter de tous les états qui le lisent — balance, grand livre, compte de
   * résultat, analytique, seuil de rentabilité.
   *
   * Une PIÈCE porte désormais deux lignes de MÊME numéro, de même date, de
   * même statut et de même montant : une au débit, une au crédit, sur des
   * comptes que l'opération désigne. L'équilibre n'est donc pas contrôlé
   * après coup, il est CONSTRUIT.
   * ======================================================================== */
  var OPERATIONS_COMPTABLES = [
    /* Ventes et recettes — le produit au crédit, la contrepartie au débit. */
    { journal: 'VTE', libelle: 'Facturation patient', debit: '411000', credit: '706000', centre: 'consultation' },
    { journal: 'VTE', libelle: 'Facture compagnie d’assurance', debit: '411200', credit: '706100', centre: 'hospitalisation' },
    { journal: 'VTE', libelle: 'Analyses facturées', debit: '411000', credit: '706200', centre: 'laboratoire' },
    { journal: 'VTE', libelle: 'Vente de médicaments au comptant', debit: '571000', credit: '701000', centre: 'pharmacie' },
    { journal: 'VTE', libelle: 'Accouchement facturé', debit: '411000', credit: '706100', centre: 'maternite' },
    { journal: 'VTE', libelle: 'Échographie facturée', debit: '571000', credit: '706100', centre: 'imagerie' },
    /* Trésorerie — un mouvement d'un compte à l'autre, jamais une charge. */
    { journal: 'CAI', libelle: 'Encaissement caisse', debit: '571000', credit: '411000', centre: 'consultation' },
    { journal: 'BQ', libelle: 'Versement d’espèces en banque', debit: '521000', credit: '571000', centre: 'direction' },
    { journal: 'BQ', libelle: 'Règlement fournisseur', debit: '401000', credit: '521000', centre: 'direction' },
    /* Achats et charges — la charge au DÉBIT, toujours. */
    /* Le libellé nomme l'OPÉRATION, pas le fournisseur du jour : le compte
       601100 est « Achats de marchandises » au plan SYSCOHADA, et c'est ce
       qu'on lit au grand livre. Le fournisseur, lui, vit sur la pièce. */
    { journal: 'ACH', libelle: 'Achat de marchandises — Médicaments', debit: '601100', credit: '401000', centre: 'pharmacie' },
    { journal: 'ACH', libelle: 'Achat de réactifs', debit: '604100', credit: '401000', centre: 'laboratoire' },
    { journal: 'ACH', libelle: 'Consommables de soins', debit: '604100', credit: '401000', centre: 'hospitalisation' },
    { journal: 'ACH', libelle: 'Consommables de maternité', debit: '604100', credit: '401000', centre: 'maternite' },
    { journal: 'ACH', libelle: 'Petit matériel de consultation', debit: '605600', credit: '401000', centre: 'consultation' },
    { journal: 'ACH', libelle: 'Fournitures de bureau', debit: '604700', credit: '401000', centre: 'direction' },
    { journal: 'ACH', libelle: 'Produits d’entretien', debit: '604300', credit: '401000', centre: 'direction' },
    { journal: 'CAI', libelle: 'Électricité', debit: '605200', credit: '571000', centre: 'direction' },
    { journal: 'CAI', libelle: 'Eau', debit: '605100', credit: '571000', centre: 'direction' },
    { journal: 'CAI', libelle: 'Frais de téléphone', debit: '628100', credit: '571000', centre: 'direction' },
    { journal: 'OD', libelle: 'Entretien et réparations', debit: '624100', credit: '401000', centre: 'hospitalisation' },
    { journal: 'OD', libelle: 'Maintenance des automates', debit: '624300', credit: '401000', centre: 'laboratoire' },
    { journal: 'OD', libelle: 'Maintenance de l’échographe', debit: '624300', credit: '401000', centre: 'imagerie' },
    { journal: 'BQ', libelle: 'Frais bancaires', debit: '631810', credit: '521000', centre: 'direction' },
    { journal: 'OD', libelle: 'Honoraires du comptable', debit: '632400', credit: '401000', centre: 'direction' },
    /* Paie — la charge au débit, la dette envers l'agent ou l'organisme au crédit. */
    { journal: 'SAL', libelle: 'Salaires du mois', debit: '661100', credit: '422000', centre: 'direction' },
    { journal: 'SAL', libelle: 'Cotisations CNSS', debit: '664120', credit: '431000', centre: 'direction' },
    { journal: 'SAL', libelle: 'Taxe sur salaires (VPS)', debit: '641300', credit: '442100', centre: 'direction' },
  ];

  function genEcritures(rnd) {
    var out = [], today = new Date(2026, 7, 16);
    function libelleCompte(num) {
      var c = D.PLAN_COMPTABLE.filter(function (x) { return String(x.num) === String(num); })[0];
      return c ? c.libelle : num;
    }
    /* 130 pièces de deux lignes : le même volume qu'auparavant, mais
       équilibré. */
    for (var i = 0; i < 130; i++) {
      var op = C.pick(rnd, OPERATIONS_COMPTABLES);
      var j = D.JOURNAUX.filter(function (x) { return x.code === op.journal; })[0] || D.JOURNAUX[0];
      var montant = C.between(rnd, 5, 800) * 1000;
      var numero = op.journal + '-2026-' + C.pad(i + 1, 5);
      var base = {
        numero: numero,
        date: C.iso(C.addDays(today, -C.between(rnd, 0, 220))),
        journal: j.code, journalLibelle: j.libelle,
        libelle: op.libelle,
        centreCout: op.centre,
        origine: C.pick(rnd, ['Automatique — Caisse', 'Automatique — Achats', 'Automatique — Paie', 'Saisie manuelle']),
        /* Le statut est celui de la PIÈCE : valider une moitié d'écriture
           n'a aucun sens, et laisserait la balance boiteuse. */
        statut: C.pick(rnd, ['validee', 'validee', 'validee', 'brouillon']),
      };
      out.push(Object.assign({}, base, {
        id: 'ECR' + C.pad(out.length + 1, 5),
        compte: op.debit, compteLibelle: libelleCompte(op.debit),
        debit: montant, credit: 0,
      }));
      out.push(Object.assign({}, base, {
        id: 'ECR' + C.pad(out.length + 1, 5),
        compte: op.credit, compteLibelle: libelleCompte(op.credit),
        debit: 0, credit: montant,
      }));
    }
    return C.sortBy(out, 'date', 'desc');
  }

  /* --------------------------------------------------------------------------
   * Le planning reproduit les rotations réelles relevées sur les plannings de
   * la clinique : chaque catégorie a son propre régime (types de vacation,
   * durée du repos, longueur du cycle), défini dans REGLES_PLANNING.
   * Les agents d'une même catégorie sont décalés les uns par rapport aux
   * autres, de sorte qu'un poste soit couvert chaque jour.
   * ----------------------------------------------------------------------- */
  function genPlanning(rnd, personnel) {
    var out = [], today = new Date(2026, 7, 16);
    var concernes = personnel.filter(function (e) { return !!D.regleDe(e.fonction); });
    var parFonction = C.groupBy(concernes, 'fonction');

    Object.keys(parFonction).forEach(function (fonction) {
      var regle = D.regleDe(fonction);
      var agents = parFonction[fonction];
      var cycle = Math.max(regle.cycle, regle.vacations.length + (regle.repos ? 1 : 0));

      agents.forEach(function (e, rang) {
        for (var d = -20; d <= 20; d++) {
          var jour = C.addDays(today, d);
          /* Position de l'agent dans le cycle, décalée par son rang. */
          var pos = (((d + rang) % cycle) + cycle) % cycle;
          var type;
          if (pos < regle.vacations.length) {
            type = regle.vacations[pos];
          } else {
            type = regle.repos || 'repos24';
          }
          /* Les secrétaires n'assurent pas de permanence le dimanche. */
          if (type === 'permanence' && fonction !== 'entretien' && jour.getDay() === 0) {
            type = regle.repos || 'repos24';
          }
          out.push({
            id: 'PLN' + out.length,
            date: C.iso(jour), employeId: e.id, employe: e.nomComplet,
            fonction: e.fonction, service: e.service, type: type,
            regime: regle.libelle,
            statut: 'validee',
          });
        }
      });
    });
    return out;
  }

  /* Feuille de soins : actes réalisés au chevet des patients hospitalisés. */
  /* ==========================================================================
   * RELEVÉS DE CONSTANTES AU LIT DU PATIENT
   * --------------------------------------------------------------------------
   * Trois fois par jour, aux heures de la feuille papier : 08 h, 14 h et 20 h —
   * matin, midi, soir, les trois colonnes que porte le document.
   *
   * La diurèse est relevée en MILLILITRES au lit du patient, alors que
   * l'échelle de la feuille de température est graduée en litres. La conversion
   * se fait à l'affichage : convertir ici perdrait la précision de la mesure.
   * ======================================================================== */
  function genReleves(rnd, admissions) {
    var out = [];
    var ref = new Date(2026, 7, 16);
    /* Une admission en cours est celle qui n'a pas de date de sortie. Le
       champ statut vaut 'en_cours', pas 'actif' — les confondre ne filtrait
       rien du tout, et la fiche de surveillance restait vide sur un patient
       hospitalisé depuis six jours. */
    admissions.filter(function (a) { return !a.dateSortie; })
      .forEach(function (a) {
        var debut = C.toDate(a.dateEntree);
        var jours = Math.min(Math.max(1, Math.round((ref - debut) / 86400000)), 7);
        for (var j = jours; j >= 0; j--) {
          ['08:00', '14:00', '20:00'].forEach(function (h) {
            out.push({
              id: 'REL' + C.uid(), statut: 'actif',
              admissionId: a.id, date: C.iso(C.addDays(ref, -j)), heure: h,
              temperature: Number((36.4 + rnd() * 2.2).toFixed(1)),
              tension: C.between(rnd, 10, 15) + '/' + C.between(rnd, 6, 9),
              fc: C.between(rnd, 62, 108), spo2: C.between(rnd, 92, 100),
              fr: C.between(rnd, 14, 24), diurese: C.between(rnd, 600, 2200),
              poids: C.between(rnd, 45, 92), taille: C.between(rnd, 150, 188),
              traitement: C.pick(rnd, ['Perfusion RL 500ml', 'Paracétamol 1g IV',
                'Ceftriaxone 1g', 'Artésunate 60mg', 'Surveillance simple']),
              saisiPar: a.infirmier,
            });
          });
        }
      });
    return out;
  }

  function genSoins(rnd, admissions, produits) {
    var out = [], n = 0;
    var consommables = produits.filter(function (p) { return p.categorie === 'medicament' || p.categorie === 'consommable'; });
    admissions.filter(function (a) { return a.statut !== 'archive'; }).forEach(function (a) {
      var nb = C.between(rnd, 2, 6);
      for (var i = 0; i < nb; i++) {
        var jours = C.between(rnd, 0, 6);
        var d = C.addDays(new Date(2026, 7, 16), -jours);
        var prod = rnd() > 0.35 ? C.pick(rnd, consommables) : null;
        out.push({
          id: 'SOIN' + C.pad(++n, 4),
          date: C.iso(d),
          heure: C.pad(C.between(rnd, 6, 22)) + ':' + C.pick(rnd, ['00', '15', '30', '45']),
          admissionId: a.id,
          patientId: a.patientId,
          patient: a.patient,
          patientCode: a.patientCode,
          lit: a.lit,
          acte: C.pick(rnd, ACTES_SOINS),
          produit: prod ? prod.designation : '',
          quantite: prod ? C.between(rnd, 1, 3) : 0,
          soignant: a.infirmier,
          observations: '',
          etat: C.pick(rnd, ['realise', 'realise', 'realise', 'planifie']),
          statut: 'actif',
        });
      }
    });
    return out;
  }

  function genAudit(rnd, personnel) {
    var out = [], today = new Date(2026, 7, 16);
    var actions = [
      ['Connexion', 'M14', 'Session'], ['Création', 'M1', 'Patient'], ['Modification', 'M1', 'Patient'],
      ['Validation', 'M7', 'BonCommande'], ['Impression', 'M8', 'Facture'], ['Archivage', 'M6', 'Produit'],
      ['Création', 'M8', 'Facture'], ['Modification', 'M6', 'Stock'], ['Consultation', 'M10', 'BulletinPaie'],
      ['Échec de connexion', 'M14', 'Session'], ['Restauration', 'M1', 'Patient'], ['Validation', 'M11', 'Paie'],
    ];
    for (var i = 0; i < 220; i++) {
      var a = C.pick(rnd, actions), e = C.pick(rnd, personnel);
      var d = C.addDays(today, -C.between(rnd, 0, 30));
      d.setHours(C.between(rnd, 7, 21), C.between(rnd, 0, 59));
      out.push({
        id: 'LOG' + C.pad(i + 1, 5),
        dateHeure: d.toISOString(),
        utilisateur: e.nomComplet,
        action: a[0], module: a[1], entite: a[2],
        reference: a[2].toUpperCase().slice(0, 3) + C.pad(C.between(rnd, 1, 999), 4),
        poste: 'POSTE-' + C.pick(rnd, ['ACCUEIL', 'CAISSE', 'PHARMA', 'LABO', 'COMPTA', 'DIR']),
        succes: a[0].indexOf('Échec') === -1,
      });
    }
    return C.sortBy(out, 'dateHeure', 'desc');
  }

  /* ==========================================================================
   * AMORÇAGE
   * ======================================================================== */
  function seed() {
    var rnd = C.seeded(20260716);
    var personnel = genPersonnel(rnd);
    var patients = genPatients(rnd, 180);
    rattacherPersonnelPatients(rnd, patients, personnel);
    var souscripteurs = genSouscripteurs(rnd);
    rattacherSouscripteurs(rnd, patients, souscripteurs);
    var produits = genProduits(rnd);
    var consultations = genConsultations(rnd, patients, personnel);
    var admissions = genAdmissions(rnd, patients, personnel);

    return {
      /* 39 — phase 1 : catalogue des actes au socle, réunions et GED semées
         par data-seed, formes canoniques courriers/ambulance, compression.
         40 — phase 2 : rôles chirurgien, anesthésiste et aide_comptable
         (Assistant Comptable, 16ᵉ), fermetures caissier m6-transferts/
         mouvements/lots.
         41 — phase 3a : tarifs publics ouverts en lecture à la réception
         (cfg-tarifs, cfg-catalogue, cfg-certificats).
         42 — phase 3b : fusion Rendez-vous & visites — une venue peut porter
         `nonPatient` et `visiteurNom` (individu non enregistré, affaire
         privée), sans consommer de code CNT (RG-01).
         43 — phase 4 (rapport maternité du 27/08/2026) : sept collections
         nouvelles (grossesses, partogrammes, cpon, planificationFamiliale,
         registreSONU, ptme, soinsCuratifsMaternite), naissances enrichies
         (PC/PT, Apgar 1-5-10, vitamine K1, réanimation, vaccins J0), M4 semé
         AU SOCLE (les stats et tableaux de bord le lisent), acte SAA au
         catalogue.
         44 — phase 5 : `avoirs` au socle (une pièce, deux vues M8/MECeF, avec
         lignes annulées et contre-passation), une dépense porte des LIGNES
         (arbitrage — le total est leur somme), `pvReceptions` (M7), et
         M8.annuler fermé au caissier (l'avoir est le canal de correction).
         45 — phase 6 : le code d'analyse unique NNNNN-AAAA sur les demandes
         (fabrique unique PR.codeAnalyse, série annuelle) et la collection
         `plagesReactif` (bornes par lot de réactif, versionnées par date).
         46 — phase 7 : les collections `cpa` (consultation pré-anesthésique)
         et `crAnesthesie` (compte rendu d'anesthésie), et la demande
         d'analyse peut porter l'origine 'service' (fiche m3-demande-examen).
         47 — phase 8 : l'imagerie éclatée — `demandesImagerie` (états du
         labo : demandée → payée → exécutée → validée), `clichesImagerie`
         (galerie), `examensImagerie` et `variablesImagerie` au socle
         (administrables par cfg-imagerie-catalogue), la ligne payable porte
         `demandeImagerieId`.
         48 — phase 10 : les collections `enquetes` (modèles de
         questionnaires — le formulaire naît du modèle) et
         `reponsesEnquetes`.
         49 — arbitrage du 01/09/2026 : plus aucun montant NUL — GY-SAA
         reçoit un tarif d'attente aligné sur l'AMIU, les 34 références
         SAGE non valorisées reçoivent la MÉDIANE de leur catégorie
         (marquées `valorisationProvisoire`, tracées dans la surcouche
         `valorisationsSage` désormais semée au socle).
         50 — vague 49 : les validations du ressort de la DIRECTION sont
         levées — tarifs d'attente ARRÊTÉS (`tarifArreteLe`, la semence
         garde son marquage), valorisations confirmées, groupes d'articles
         confirmés, questionnaire validé. Les marquages qui attendent un
         professionnel nommé (variables labo, pathologies, check-listes)
         restent.
         51 — vague 51 : les validations écrites des PROFESSIONNELS sont
         arrivées (variables labo par le biologiste, pathologies par les
         médecins — `valideLe`/`validePar`, la semence garde son marquage),
         seuils d'alerte confirmés, et la « journée des postes » du seed
         (brouillons validés, résultats rendus, files résiduelles).
         52 — vague 53 : les CINQ fiches RBAC qui manquaient (dm, direction,
         comptable, agentadmin, ambulancier — un rôle sans fiche avait tous
         les droits), fermetures caissier (stock-gros, dashboard stock,
         dépenses), M1 fermé au magasinier, bon de livraison fermé au
         biologiste.
         53 — vague 54 : les BADGES DU PERSONNEL (`badges`, `modelesBadge` —
         un badge se RETIRE, il ne se supprime pas) et le PARTAGE d'une
         fiche d'enquête à un tiers (`jetonsEnquete` : un jeton daté et
         révocable, jamais un identifiant d'enquête dans l'adresse).
         54 — corrections du 06/09/2026 : les SIX SECTEURS productifs
         deviennent le vocabulaire unique (groupes de prestation ET centres
         de coûts — Laboratoire, Pharmacie, Consultation, Échographie,
         Maternité, Hospitalisation et soins, plus la Direction transverse).
         La collection `centresCouts` change de forme : son `code` EST
         désormais l'identifiant porté par les écritures (`laboratoire`…) et
         non plus un `CC01` que rien ne rapprochait d'elles.
         55 — vague 56 : le jeu d'ÉCRITURES respecte enfin RG-10. Il
         engendrait des lignes au compte tiré au hasard et au sens tiré par
         deux tirages indépendants — 6 157 000 F d'écart, 68 lignes à la
         fois au débit ET au crédit, 81 lignes de classe 6 au crédit (d'où
         les charges NÉGATIVES du rapprochement). Une PIÈCE porte désormais
         deux lignes de même numéro, date, statut et montant.
         56 — vague 60 : dossier obstétrical, couverture datée.
         57 — vague 61 : l'imagerie à CINQ modalités — examens et variables
         de radiographie, mammographie, scanner et IRM semés au catalogue
         (`examensImagerie` porte `modalite`).
         58 — vague 62 : le dossier de consultation structuré (anamnèse,
         antécédents, IPPOA par appareil en `examensPhysiques`), les
         transferts gros → détail peuplés ligne à ligne, les demandes
         d'imagerie, constantes d'accueil, patients et certificats externes
         peuplés ; les champs nuls ne s'écrivent plus.
         59 — vague 63 : le RYTHME CARDIAQUE du 1er trimestre revient au
         catalogue des variables d'imagerie, déplacé après le LCC (et après
         la biométrie sur l'examen évolué) au lieu d'être supprimé. Les
         variables vivant au MAGASIN, un poste amorcé en 58 aurait gardé le
         jeu sans ce champ et l'échographiste n'aurait rien vu changer.
         60 — vague 63, second temps : « Amnios » remplace « anamnios » dans
         l'abondance du liquide amniotique (arbitrage de l'échographiste).
         Les OPTIONS d'une variable vivent au magasin comme la variable
         elle-même : sans incrément, un poste amorcé en 59 aurait continué
         de proposer le mot que l'échographiste n'emploie pas.
         61 — vague 64 : les OBJECTIFS DU PILOTAGE (`objectifsPilotage`,
         semés au socle — le BFR, la grille objectif/réel et le moteur
         d'alertes les lisent) et l'amorçage des achats remonté au socle,
         sans quoi la dette fournisseur valait zéro et le BFR s'en trouvait
         surestimé sur tout poste n'ayant jamais ouvert M7.
         62 — vague 67 : l'ASSISTANT DE DIRECTION perd le laboratoire (M5,
         données de santé nominatives qu'aucune de ses activités ne demande)
         et passe de TOUT à VOIR sur M12 — écrire et annuler des écritures
         comptables appartient au Comptable. Les fiches RBAC étant SEMÉES,
         sans incrément un poste garderait l'ancienne matrice. */
      _version: VERSION,
      _seededAt: new Date().toISOString(),
      personnel: personnel,
      patients: patients,
      produits: produits,
      /* La SURCOUCHE de valorisation (vague 33) porte la trace de l'arbitrage
         du 01/09/2026 : une fiche par référence que SAGE ne valorisait pas,
         datée, sourcée, marquée à valider. Le document reste ce qu'il est. */
      valorisationsSage: produits.filter(function (p) { return p.valorisationProvisoire; })
        .map(function (p, i) {
          return {
            id: 'VSG' + C.pad(i + 1, 3), statut: 'actif',
            code: p.code, designation: p.designation,
            prixRevient: p.prixAchat,
            date: '2026-09-01', auteur: 'Direction',
            source: p.sourceValorisation + ' ; confirmée par la Direction le 01/09/2026',
            observation: 'Médiane de la catégorie, confirmée par la Direction — révisable à la première facture fournisseur.',
            aValider: false,
          };
        }),
      lots: genLots(rnd, produits),
      consultations: consultations,
      admissions: admissions,
      soins: genSoins(rnd, admissions, produits),
      /* Relevés de constantes au lit du patient. Lus par la feuille de
         température, par la fiche de surveillance ET par le dossier patient :
         amorcés ICI, jamais par un écran — sinon celui qu'on ouvre en premier
         décide si les autres voient quelque chose. */
      releves: genReleves(rnd, admissions),
      factures: genFactures(rnd, patients, consultations, produits),
      mouvements: genMouvements(rnd, produits),
      ecritures: genEcritures(rnd),
      planning: genPlanning(rnd, personnel),
      audit: genAudit(rnd, personnel),
      analyses: D.ANALYSES.map(function (a) { return Object.assign({}, a); }),
      /* Catalogue des actes — lu par la consultation, l'hospitalisation, la
         facturation, la recherche globale ET le moteur de parcours : amorcé ICI.
         L'amorcer depuis l'écran de configuration laissait la prescription sans
         options sur tout poste qui n'avait jamais ouvert cfg-tarifs, et le
         moteur tarifait depuis D.ACTES pendant que les écrans lisaient la
         collection — deux vérités. D.ACTES n'est que la semence. */
      actes: D.ACTES.map(function (a, i) {
        var rec = Object.assign({ id: 'ACT' + C.pad(i + 1, 3) }, a);
        /* VALIDATION DE LA DIRECTION DU 01/09/2026 : les tarifs d'ATTENTE
           sont ARRÊTÉS — plus aucun « provisoire » au catalogue vivant. La
           SEMENCE (D.ACTES) garde son marquage : elle documente ce qui
           venait d'un document et ce qui n'en venait pas ; c'est l'arrêté
           qui rend le tarif opposable, et il est daté. */
        if (rec.tarifProvisoire) {
          rec.tarifProvisoire = false;
          rec.tarifArreteLe = '2026-09-01';
          rec.source = (rec.source ? rec.source + ' ; ' : '')
            + 'tarif arrêté par la Direction le 01/09/2026';
        }
        return rec;
      }).concat(D.TYPES_CHAMBRE.map(function (t, i) {
        return {
          id: 'ACH' + C.pad(i + 1, 3), statut: 'actif',
          code: 'HO' + C.pad(i + 1, 2),
          libelle: 'Journée d’hospitalisation — chambre ' + t.label,
          secteur: 'Hospitalisation', prix: t.tarif,
          source: 'CDCT — types de chambre et tarifs journaliers',
        };
      })).concat([(function () {
        /* DEMANDE ÉCRITE du rapport maternité (Module A) : « Ajout de l'acte
           Avortement / Soins Après Avortement (SAA) dans la nomenclature ».
           Aucun document ne le tarife ; l'ARBITRAGE DU 01/09/2026 (« plus
           aucun montant nul ») lui donne un TARIF D'ATTENTE aligné sur
           l'AMIU — la SAA se pratique par aspiration manuelle intra-utérine,
           c'est le même geste. Marqué provisoire : une valeur d'attente ne
           se présente jamais comme un tarif validé. */
        var amiu = (D.CATALOGUE || []).filter(function (e) { return e.code === 'AMIU'; })[0] || {};
        return {
          id: 'ACT-SAA', statut: 'actif', code: 'GY-SAA',
          libelle: 'Avortement — Soins Après Avortement (SAA)',
          secteur: 'Gynéco-obstétrique',
          prix: amiu.prixNonAssure != null ? amiu.prixNonAssure : null,
          prixNonAssure: amiu.prixNonAssure != null ? amiu.prixNonAssure : null,
          prixAssure: amiu.prixAssure != null ? amiu.prixAssure : null,
          assurable: amiu.assurable,
          tarifProvisoire: false, tarifArreteLe: '2026-09-01',
          motifPrix: 'Tarif aligné sur l’AMIU (la SAA se pratique par AMIU), arrêté par la Direction le 01/09/2026.',
          source: 'Rapport maternité 27/08/2026 — Module A ; tarif arrêté par la Direction le 01/09/2026',
        };
      })()]),
      /* Amorcées par leur écran : parcours de prescription. */
      ordonnances: [],
      /* FACTURES D'AVOIR — une seule pièce, deux vues : la gestion (M8,
         contre-passation comptable, lignes annulées, remboursement) et le
         registre fiscal (MECeF). Lue par les deux modules ET par la
         comptabilité : amorcée ICI. */
      avoirs: [],
      /* PV de réception (M7) — consommables et réactifs, deux écrans d'un
         même module. Vide au socle pour la corbeille. */
      pvReceptions: [],
      taches: [],
      assureurs: D.ASSUREURS.map(function (a, i) {
        return Object.assign({ id: 'ASS' + C.pad(i + 1), statut: 'actif', convention: 'Signée', assures: 0 }, a);
      }),
      fournisseurs: D.FOURNISSEURS.map(function (f) { return Object.assign({ statut: 'actif' }, f); }),
      /* Référentiels lus depuis plusieurs modules : amorcés ici, pas par un écran. */
      naturesFacture: D.NATURES_FACTURE.map(function (n) { return Object.assign({}, n); }),
      souscripteurs: souscripteurs,
      /* Lus par la configuration ET par le moteur d'habilitations : amorcés ici. */
      secteurs: D.NS145.secteurs.map(function (x) { return Object.assign({}, x); }),
      /* Grilles de garanties : vides tant qu'une convention n'est pas saisie. */
      garanties: [],
      centresCouts: D.CENTRES_COUTS.map(function (c) { return Object.assign({}, c); }),

      /* LES OBJECTIFS DU PILOTAGE (22/09/2026) — amorcés AU SOCLE parce que
         trois modules les lisent : la comptabilité (BFR), le pilotage
         (grille objectif / réel) et le moteur d'alertes, qui n'appartient à
         aucun écran. C'est la règle de placement du prototype, et c'est ici
         qu'on a déjà payé de l'avoir oubliée. */
      objectifsPilotage: (D.OBJECTIFS_PILOTAGE || []).map(function (o, i) {
        return Object.assign({ id: 'OBJ' + C.pad(i + 1, 2), statut: 'actif' }, o);
      }),

      /* ====================================================================
       * COMPTES DE TRÉSORERIE — d'où l'argent sort
       * --------------------------------------------------------------------
       * Amorcés ICI et non par l'écran des rapprochements : la saisie des
       * dépenses lit la même liste, et une page ne charge que le module de son
       * écran. Les trois banques sont celles que le plan comptable de la
       * clinique nomme (631810 BOA, 631820 Orabank, 631830 Coris Bank).
       *
       * LA CAISSE EN FAIT PARTIE : une dépense de trésorerie sort le plus
       * souvent en espèces. L'omettre obligerait à imputer un décaissement de
       * caisse sur une banque, et le rapprochement bancaire s'en trouverait
       * faussé.
       * ================================================================== */
      banques: [
        { id: 'BQ00', statut: 'actif', banque: 'Caisse', intitule: 'Caisse de la clinique',
          numeroCompte: null, compteComptable: '571000', devise: 'FCFA', statutCompte: 'actif',
          nature: 'caisse',
          source: 'Compte 571 — caisse. Les décaissements en espèces sortent d’ici.' },
        { id: 'BQ01', statut: 'actif', banque: 'BOA', intitule: 'Compte courant BOA',
          numeroCompte: '001 40218 001', compteComptable: '521100', devise: 'FCFA', statutCompte: 'actif',
          nature: 'banque',
          source: 'Plan comptable de la clinique — compte 631810 « Frais bancaire BOA ».' },
        { id: 'BQ02', statut: 'actif', banque: 'Orabank', intitule: 'Compte courant Orabank',
          numeroCompte: '002 51907 001', compteComptable: '521200', devise: 'FCFA', statutCompte: 'actif',
          nature: 'banque',
          source: 'Plan comptable de la clinique — compte 631820 « Frais bancaire Orabank ».' },
        { id: 'BQ03', statut: 'actif', banque: 'Coris Bank', intitule: 'Compte courant Coris Bank',
          numeroCompte: '003 33184 001', compteComptable: '521300', devise: 'FCFA', statutCompte: 'actif',
          nature: 'banque',
          source: 'Plan comptable de la clinique — compte 631830 « Frais bancaire Coris bank ».' },
      ],

      /* Les dépenses de trésorerie directes — voir m12-depenses. */
      depenses: [],

      /* ======================================================================
       * CATALOGUE TARIFAIRE — DEUX PRIX PAR ACTE
       * ----------------------------------------------------------------------
       * Les six grilles officielles portent chacune deux colonnes, « PRIX NON
       * ASSURE » et « PRIX ASSURE », le second étant presque toujours le plus
       * élevé. C'est le modèle économique de la clinique, pas une coquille :
       * le tarif conventionné opposable à une compagnie n'est pas le tarif de
       * guichet.
       *
       * Amorcé ICI parce que six modules le lisent — prescription, laboratoire,
       * pharmacie, facturation, assurances, comptabilité. Le poser dans un
       * écran le rendrait vide partout ailleurs.
       * ==================================================================== */
      catalogueTarifs: (D.CATALOGUE || []).map(function (t, i) {
        return Object.assign({ id: 'TAR' + C.pad(i + 1, 3) }, t);
      }),

      /* ======================================================================
       * EN-TÊTE UNIQUE — ARBITRAGE DU 31/08/2026
       * ----------------------------------------------------------------------
       * Le référentiel des variantes d'en-tête est RETIRÉ sur décision de la
       * Direction (Bugs 7/8/13 des Instructions) : toutes les pièces portent
       * désormais l'unique identité légale de C.BRAND — IFU 3201642748214,
       * RCCM RB/NAT/2016-B-268. Les trois IFU / trois RCCM relevés sur les
       * pièces anciennes restent documentés dans les scans de docs/ ; le
       * logiciel, lui, n'imprime plus qu'un en-tête.
       * ==================================================================== */

      /* ======================================================================
       * TYPES DE PIÈCES CERTIFIANTES
       * ----------------------------------------------------------------------
       * Quatorze gabarits officiels, chacun avec son sigle de référence, sa
       * direction émettrice et son en-tête. La numérotation relevée est
       * « <SIGLE> n°/n°/CNT/<direction>/<année> ».
       *
       * DEUX COLLISIONS DE SIGLES existent dans les documents sources : CMA
       * désigne l'accouchement ET l'aptitude, CMD le décès ET le genre de mort.
       * Elles sont CONSERVÉES telles quelles et signalées : renuméroter
       * d'office romprait la correspondance avec les registres papier tenus
       * depuis des années.
       * ==================================================================== */
      typesPiece: [
        ['ATG', 'Attestation de grossesse', 'DG/DE', 'CERT-ATG'],
        ['CMNI', 'Certificat médical de non-infirmité', 'DG/DE', null],
        ['CMA', 'Certificat médical d’accouchement', 'DG/DE', null,
          { collision: 'Le sigle CMA désigne aussi le certificat médical d’aptitude.' }],
        ['CMA', 'Certificat médical d’aptitude', 'DG/DE', 'CERT-APT',
          { collision: 'Le sigle CMA désigne aussi le certificat médical d’accouchement.' }],
        ['CMH', 'Certificat médical d’hospitalisation (garde-malade)', 'DG/DE', null],
        ['CMD', 'Certificat médical de décès', 'DA', 'CERT-DEC',
          { collision: 'Le sigle CMD désigne aussi le certificat de genre de mort.' }],
        ['CMD', 'Certificat médical de genre de mort', 'DA', null,
          { collision: 'Le sigle CMD désigne aussi le certificat médical de décès.' }],
        ['CMP', 'Certificat médical prénuptial', 'CN', null,
          { examens: ['LAB-GSRH', 'LAB-HEPB', 'LAB-HEPC', 'LAB-TPHA', 'LAB-HIV', 'LAB-EPHB'] }],
        ['CMCBV', 'Certificat médical de coups et blessures volontaires', 'CN', 'CERT-CBV'],
        ['CMDPS', 'Certificat médical de dispense aux activités physiques et sportives', 'DG/DE', 'CERT-DPS'],
        ['CMNCI', 'Certificat médical de non contre-indication aux activités physiques et sportives', 'DM/DA', null],
        ['CMVC', 'Certificat médical de visite et de contre-visite', 'DG/DE', 'CERT-VC'],
        ['CMR-H', 'Certificat médical d’arrêt de travail et/ou d’hospitalisation', 'DG/DA', null],
        ['SCAM', 'Sortie contre avis médical', 'CN', null],
      ].map(function (t, i) {
        var o = t[4] || {};
        return {
          id: 'TPC' + C.pad(i + 1, 2), sigle: t[0], libelle: t[1],
          direction: t[2], tarifCode: t[3],
          collision: o.collision || null,
          /* Le prénuptial ne se saisit pas : il se remplit depuis les
             résultats VALIDÉS BIOLOGIQUEMENT du patient. Un examen non validé
             ne peut pas y être coché. */
          examens: o.examens || null,
          statut: 'actif',
        };
      }),

      /* Pièces émises : le registre des certificats délivrés. */
      pieces: [],

      /* ======================================================================
       * SOIGNANTS — QUI PRESCRIT, QUI EXÉCUTE
       * ----------------------------------------------------------------------
       * Dérivés du personnel : une seconde liste de noms divergerait du dossier
       * RH au premier recrutement. La fiche ne porte que ce que le dossier RH
       * ne dit pas — les deux droits, et les secteurs d'exercice.
       *
       * DEUX DROITS DISTINCTS SUR UNE MÊME FICHE, parce que la sage-femme les
       * cumule : elle prescrit ET elle exécute. Deux listes séparées auraient
       * obligé à l'inscrire deux fois.
       *
       * Deux agents sont soignants sans être ni l'un ni l'autre : le
       * Surveillant Général supervise, l'Échographiste réalise. Les compter
       * comme prescripteurs aurait fait mentir les effectifs de la Direction.
       * ==================================================================== */
      soignants: personnel.filter(function (a) {
        return ['medecin', 'sage_femme', 'infirmier'].indexOf(a.fonction) !== -1;
      }).map(function (a, i) {
        var superviseur = /Surveillant/i.test(a.poste || '');
        var echographiste = /Échographiste|Echographiste/i.test(a.poste || '');
        var q = a.fonction;
        return {
          id: 'SOI' + C.pad(i + 1, 2),
          personnelId: a.id, nomComplet: a.nomComplet, poste: a.poste,
          qualite: q,
          /* Le médecin et la sage-femme prescrivent ; l'infirmier non. Le
             superviseur et l'échographiste sont retirés des deux listes. */
          prescrit: (q === 'medecin' || q === 'sage_femme') && !superviseur && !echographiste,
          execute: (q === 'infirmier' || q === 'sage_femme') && !superviseur,
          /* Le superviseur n'exécute pas : il contrôle. C'est l'IG de la
             description de poste du 26/10/2023. */
          supervise: superviseur,
          realiseImagerie: echographiste,
          secteurs: q === 'sage_femme' ? ['maternite', 'salle_soins']
            : q === 'infirmier' ? ['salle_soins', 'hospitalisation']
              : ['salle_soins', 'hospitalisation', 'maternite'],
          statut: 'actif',
          source: 'Dérivé de l’organigramme ; effectifs confirmés par la Direction le 24/08/2026',
        };
      }),

      /* ======================================================================
       * PRESCRIPTIONS — DEUX TYPES, QUATRE ORIGINES
       * ----------------------------------------------------------------------
       * Le prototype ne connaissait que l'ordonnance issue de la consultation.
       * La clinique prescrit depuis quatre endroits (consultation,
       * hospitalisation, bloc, maternité) et distingue deux objets :
       * l'ORDONNANCE (des médicaments à délivrer, qui sortent du stock) et les
       * SOINS (des actes à exécuter, qui ne sortent pas du stock).
       *
       * Amorcée vide : elle se remplit par le parcours, jamais par une saisie
       * de démonstration qui n'aurait traversé aucun module.
       * ==================================================================== */
      prescriptions: [],

      /* Administrations : une ligne par passage, avec son rang. C'est le rang
         qui décide du secteur (voir D.secteurAdministrateur) — la première
         administration d'un traitement hospitalier revient à la salle de
         soins, les suivantes à l'hospitalisation. */
      administrations: [],

      /* ======================================================================
       * BLOC OPÉRATOIRE
       * ----------------------------------------------------------------------
       * Le compte rendu opératoire est une pièce de preuve : c'est elle qu'on
       * ressort quand une suite opératoire est contestée. Elle porte ses trois
       * intervenants nommés — opérateur, aide-opérateur, anesthésiste.
       *
       * Les deux check-listes sont SÉPARÉES, à deux moments distincts. Les
       * fondre ferait cocher après l'intervention ce qui devait l'être avant,
       * ce qui vide l'exercice de son sens.
       * ==================================================================== */
      crOperatoires: [],
      checklistsBloc: [],

      /* ======================================================================
       * CALENDRIER FISCAL — DÉROULÉ SUR L'EXERCICE
       * ----------------------------------------------------------------------
       * Amorcé ICI et non par son écran : trois modules le lisent désormais —
       * M12 (le suivi), CFG (la référence documentaire) et les TABLEAUX DE BORD
       * de la Direction et du comptable.
       *
       * Un tableau de bord qui affiche « 0 échéance dépassée » faute d'avoir la
       * collection chargée ne montre pas un vide : il affirme une FAUSSETÉ, et
       * dit à la Direction qu'il n'y a rien à payer. C'est plus dangereux qu'un
       * tableau de bord absent.
       * ==================================================================== */
      echeancesFiscales: genEcheances(),

      /* Comptes rendus de maternité : accouchement, planning familial, AMIU.
         Trois pièces aux rubriques propres — un gabarit unique aurait fait
         remplir des champs sans objet. */
      crMaternite: [],

      /* ======================================================================
       * IMAGERIE
       * ----------------------------------------------------------------------
       * Les comptes rendus d'échographie et d'ECG. Lus par M1 (dossier du
       * patient), M2 (l'écran qui les produit) et RAP (statistiques) : amorcés
       * ici et non par l'écran.
       * ==================================================================== */
      resultatsImagerie: [],

      /* ======================================================================
       * RÉFÉRENCE ET CONTRE-RÉFÉRENCE
       * ----------------------------------------------------------------------
       * Deux collections et non une : la contre-référence est écrite par un
       * AUTRE établissement, souvent des semaines plus tard, et elle peut ne
       * jamais arriver. La fondre dans la fiche de référence obligerait à
       * distinguer « pas encore revenue » de « champs non remplis », ce qui est
       * précisément l'indicateur que la clinique veut suivre.
       *
       * Le lien se fait par le NUMÉRO de la fiche de référence, comme sur le
       * papier — c'est le seul identifiant que les deux établissements
       * partagent.
       * ==================================================================== */
      fichesReference: [],
      contreReferences: [],

      /* ======================================================================
       * FICHES CLINIQUES D'HOSPITALISATION
       * ==================================================================== */
      surveillancesTransfusion: [],
      scoresGlasgow: [],
      rapportsMedicaux: [],

      /* ======================================================================
       * FILE D'ATTENTE
       * ----------------------------------------------------------------------
       * FIFO tempéré par la PRIORITÉ DE TRIAGE : l'ordre d'arrivée gouverne,
       * sauf urgence. Un FIFO strict ferait attendre une urgence vitale
       * derrière douze consultations de routine ; une priorité sans FIFO
       * ferait passer indéfiniment les mêmes.
       * ==================================================================== */
      fileAttente: [],

      /* ======================================================================
       * RH — FICHES DE POSTE ET PRÊTS-ÉTUDES
       * ==================================================================== */
      fichesPoste: [],
      pretsEtudes: [],

      /* ======================================================================
       * RAPPELS ET MESSAGES
       * ----------------------------------------------------------------------
       * Le MESSAGE est un gabarit administrable, le RAPPEL est son envoi. Les
       * confondre obligerait à ressaisir le texte à chaque anniversaire.
       * ==================================================================== */
      /* ==================================================================
       * FACTURES MÈRES D'ASSURANCE
       * ------------------------------------------------------------------
       * Une facture mère consolide TOUS les souscripteurs d'une compagnie sur
       * une période. Ses filles sont les factures par souscripteur. Lue par M9
       * (qui l'émet) et M12 (qui la comptabilise) : amorcée ici.
       * ================================================================== */
      facturesMere: [],

      /* Répertoire des ambulances — tenu par l'accueil, lu par M13 et par le
         tableau de bord de l'accueil. */
      ambulances: [],

      /* Dossiers de consultation étendus : zones Accueil et Consultation. */
      dossiersConsultation: [],

      modelesMessage: [],
      rappels: [],
      /* Grille des primes NS 132 — lue par M10 (primes acquises) ET par M11
         (bulletin de paie), donc amorcée ici. Chaque prime porte sa date
         d’effet : c’est elle qui permet de ne pas réécrire le passé. */
      grillePrimes: D.NS132.primes.map(function (x, i) {
        return {
          id: 'GPR' + C.pad(i + 1, 2), statut: 'actif',
          primeId: x.id, label: x.label, mode: x.mode,
          montants: Object.assign({}, x.montants),
          dateEffet: D.NS132.dateEffet, version: D.NS132.version,
          source: D.NS132.reference,
        };
      }),
      historiquePrimes: [],
      /* Activité des modules. La clinique ne pratique NI la banque de sang NI
         la transfusion : les deux écrans sont fermés d'emblée, et rouvrables. */
      /* --- Décisions RBAC de la Direction --------------------------------
         Le laborantin consulte le répertoire des patients — il en a besoin
         pour rattacher un prélèvement — mais n'y modifie RIEN, et n'accède
         pas au dossier médical. Ce n'est pas une méfiance : le dossier
         médical, les antécédents et les documents numérisés relèvent du
         soignant, pas du laboratoire.

         Ces décisions vivent ici et non dans le manifeste : ce sont des choix
         d'organisation, que la clinique doit pouvoir défaire depuis
         « Rôles & permissions » sans qu'on touche au code. */
      rbac: [
        /* ====================================================================
         * RÈGLE DES FICHES CI-DESSOUS : ON NE DÉCLARE JAMAIS `voir` AU NIVEAU
         * DU MODULE.
         * --------------------------------------------------------------------
         * `surchargeExplicite()` ne consulte QUE `voir` : une entrée de module
         * qui l'omet borne l'écriture sans rien accorder, et la visibilité
         * reste celle du manifeste, écran par écran.
         *
         * Le déclarer à `true` OUVRE tous les écrans du module — y compris
         * ceux dont la liste `roles` excluait le rôle. C'est ainsi que le
         * caissier avait récupéré `m1-externe`, alors que « la caisse ne crée
         * jamais la demande » est un garde-fou de contrôle interne.
         *
         * `voir: false` reste possible : c'est une FERMETURE délibérée, et le
         * seul cas où déclarer `voir` a un sens ici.
         * ================================================================== */

        /* ====================================================================
         * LE CAISSIER-DISPENSATEUR
         * --------------------------------------------------------------------
         * Il encaisse et il délivre. La pharmacie lui est rattachée depuis la
         * fermeture du compte Pharmacien — mais la pharmacie, c'est le STOCK
         * DÉTAIL et la dispensation, PAS le magasin central.
         *
         * Le GROS relève du Gestionnaire de Stock : lui laisser le stock gros
         * et les transferts reviendrait à ce que le même agent commande,
         * receptionne, transfère et vende — c'est-à-dire à supprimer toute
         * séparation des tâches sur la chaîne d'approvisionnement.
         *
         * Il ne touche RIEN de clinique (RG-13) : il voit l'identité du
         * patient pour encaisser, jamais son dossier.
         * ================================================================== */
        {
          id: 'RBAC12', role: 'caissier', libelleOrigine: 'Caissier', statut: 'actif',
          libelle: 'Caissier — Dispensaire (Pharmacie)', libelleCourt: 'Caisse-Pharma',
          droits: {
            /* SEULS les modules que le manifeste lui ouvre — DASH, M1, M8,
               M9, MECEF, RAP. En ajouter un ici ne bornerait pas ses droits :
               cela LUI OUVRIRAIT le module, puisqu'une surcharge accorde
               autant qu'elle restreint. La pharmacie (M6) et la comptabilité
               (M12) lui viennent du manifeste par ailleurs. */
            M1: { editer: false, annuler: false },
            /* ARBITRAGE SOLDÉ (phase 5) : la facture d'avoir est LIVRÉE
               (m8-facture-avoir), le canal de correction existe — l'annulation
               de pièces est donc FERMÉE au caissier, comme la matrice cible
               l'exige. Une erreur de caisse se corrige par un AVOIR, émis par
               le Comptable ou la DAF, jamais par la disparition de la pièce. */
            M8: { editer: true, annuler: false },
            M9: { editer: true, annuler: false },
            MECEF: { editer: true, annuler: false },
          },
          droitsEcrans: {
            /* SES DEUX TABLEAUX : la caisse et la pharmacie. Il tient les
               deux activités — c'est un seul poste, Caissière-Dispensatrice. */
            'dash-caissier': { voir: true, editer: true, annuler: true },
            'dash-pharmacien': { voir: true, editer: true, annuler: true },

            /* Le patient s'identifie au guichet ; son dossier ne s'y ouvre pas. */
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-pieces': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },

            /* LE MAGASIN N'EST PAS LA PHARMACIE. Le gros relève du
               Gestionnaire de Stock : laisser au dispensateur le magasin ET
               les transferts reviendrait à ce que le même agent commande,
               réceptionne, transfère et vende. Décision du 02/09/2026 : la
               LECTURE même du magasin lui est retirée, ainsi que le tableau
               de bord stock — son poste est la pharmacie de détail. */
            'm6-stock-gros': { voir: false },
            'm6-dashboard': { voir: false },
            /* FERMÉS NOMMÉMENT — matrice cible des Instructions, phase 2 :
               « Interdiction d'accéder aux transferts Gros → Détail et aux
               mouvements de stock FEFO ». La lecture même est retirée : la
               chaîne d'approvisionnement ne se surveille pas depuis la
               caisse. */
            'm6-transferts': { voir: false, editer: false, annuler: false },
            'm6-mouvements': { voir: false, editer: false, annuler: false },
            'm6-lots': { voir: false, editer: false, annuler: false },
            'm6-inventaire': { voir: true, editer: false, annuler: false },
            'm6-reprise': { voir: false },

            /* L'AVOIR se consulte au guichet — le patient revient avec sa
               pièce — mais son ÉMISSION appartient au Comptable et à la DAF
               (matrice cible) : contre-passer une recette n'est pas un geste
               de caisse. */
            'm8-facture-avoir': { voir: true, editer: false, annuler: false },
            /* La configuration fiscale engage la clinique devant la DGI. */
            'mecef-config': { voir: false },
            /* Décision du 02/09/2026 — elle REMPLACE la doctrine antérieure
               (« une dépense se saisit au fil de l'eau, y compris à la
               caisse ») : les dépenses journalières sont un geste COMPTABLE,
               fermé à la caisse. Une dépense née au guichet remonte au
               comptable par pièce justificative, pas par saisie. */
            'm12-depenses': { voir: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Encaisse et délivre. La pharmacie de DÉTAIL lui est rattachée ; le magasin central '
            + 'et les transferts restent au Gestionnaire de Stock — séparation des tâches. Aucun accès '
            + 'clinique (RG-13).',
        },

        /* ====================================================================
         * LE MÉDECIN — il soigne, il ne tient ni la caisse ni le stock
         * ================================================================== */
        {
          id: 'RBAC13', role: 'medecin', libelleOrigine: 'Médecin', statut: 'actif',
          droits: {
            M1: { editer: true, annuler: false },
            M2: { editer: true, annuler: true },
            M3: { editer: true, annuler: true },
            M4: { editer: true, annuler: false },
            M5: { editer: true, annuler: false },
            M6: { editer: false, annuler: false },
          },
          droitsEcrans: {
            /* Il prescrit le médicament, il ne tient pas le stock. */
            'm6-stock-gros': { voir: false },
            'm6-stock-detail': { voir: false },
            'm6-transferts': { voir: false },
            'm6-inventaire': { voir: false },
            'm6-reprise': { voir: false },
            'm6-point-ventes': { voir: false },
            'm6-point-stock': { voir: false },
            /* Le catalogue et les valeurs de référence du laboratoire sont
               tenus par le biologiste : le médecin les LIT. */
            'm5-catalogue': { voir: true, editer: false, annuler: false },
            'm5-unites': { voir: false },
            'm5-valeurs-reference': { voir: true, editer: false, annuler: false },
            'm5-reactifs': { voir: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Consultations, prescriptions, hospitalisation et lecture des résultats. Il prescrit '
            + 'le médicament, il ne tient pas le stock ; il lit le catalogue d’analyses, il ne le tient pas.',
        },

        /* ====================================================================
         * L'INFIRMIER / SAGE-FEMME — il exécute, il ne prescrit pas au stock
         * ================================================================== */
        {
          id: 'RBAC14', role: 'infirmier', libelleOrigine: 'Infirmier / Sage-femme', statut: 'actif',
          droits: {
            M1: { editer: true, annuler: false },
            M2: { editer: true, annuler: false },
            M3: { editer: true, annuler: true },
            M4: { editer: true, annuler: true },
            /* M5 et M6 ne lui sont pas ouverts par le manifeste : les
               mentionner les lui OUVRIRAIT. Les écrans du laboratoire dont il
               a besoin — demandes, résultats, prélèvement — lui sont donnés
               nommément par leur propre liste `roles`. */
          },
          droitsEcrans: {
            /* Les certificats engagent le médecin : l'infirmier les lit. */
            'm1-pieces': { voir: true, editer: false, annuler: false },
            'm1-numerisation': { voir: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Exécute les soins, tient l’hospitalisation et la maternité. Les certificats engagent '
            + 'le médecin : il les lit sans les délivrer. Le filtre de DONNÉES (secteur, fonction) reste '
            + 'porté par les capacités métier — c’est lui qui distingue la sage-femme de l’infirmier.',
        },

        /* ====================================================================
         * LE GESTIONNAIRE DE STOCK — le magasin, pas le dossier ni la caisse
         * ================================================================== */
        {
          id: 'RBAC15', role: 'stock', libelleOrigine: 'Gestionnaire de Stock', statut: 'actif',
          droits: {
            M6: { editer: true, annuler: true },
            M7: { editer: true, annuler: true },
            M8: { editer: false, annuler: false },
            /* Décision du 02/09/2026 : AUCUN accès au dossier patient — M1
               est ouvert « à tous » au manifeste (roles: '*'), la fermeture
               se pose donc au MODULE : un écran M1 ajouté demain restera
               fermé au magasinier, qui gère des références, pas des
               personnes (RG-13). Le domaine des soins (M2-M5) ne lui est
               pas ouvert par le manifeste — rien à mentionner. */
            M1: { voir: false },
            /* M5 ne lui est pas ouvert par le manifeste ; l'écran des réactifs
               lui vient de sa propre liste `roles`. */
          },
          droitsEcrans: {
            /* Il suit les ventes, il n'encaisse pas. */
            'm8-caisse': { voir: true, editer: false, annuler: false },
            'm8-facturation': { voir: false },
            'm8-paiements': { voir: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Magasin, achats, réceptions et réactifs. Il SUIT les ventes — ce sont ses sorties — '
            + 'mais il n’encaisse pas : séparation des tâches. Aucun accès au dossier patient ni aux '
            + 'soins (décision du 02/09/2026).',
        },

        /* ====================================================================
         * LA RÉCEPTION — RG-13, aucun accès clinique ni financier
         * ================================================================== */
        {
          id: 'RBAC16', role: 'reception', libelleOrigine: 'Réception / Accueil', statut: 'actif',
          droits: {
            M1: { editer: true, annuler: false },
            M2: { editer: true, annuler: false },
            M3: { editer: false, annuler: false },
            M13: { editer: false, annuler: false },
          },
          droitsEcrans: {
            /* ZONE 1 — identification, coordonnées, couverture, constantes.
               La zone clinique ne lui est pas ouverte (RG-13), et chacune de
               ses consultations du dossier est journalisée. */
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            /* REFONTE ZONE 2 (14/09/2026) : le dossier de consultation a quitté
               le répertoire pour son écran clinique. L'accueil n'y a plus de
               vue « zone 1 » — sa zone 1 EST la fiche d'identité du répertoire
               et le relevé des constantes, qu'il saisit et verrouille. Le
               dossier (anamnèse, examen IPPOA) et la fiche (diagnostic,
               prescription) lui sont fermés symétriquement (RG-13). */
            'm1-dossier-etendu': { voir: false },
            'm2-dossiers-consultation': { voir: false },
            'm2-consultation-fiche': { voir: false },
            'm2-prescriptions': { voir: false },
            'm2-ordonnances': { voir: false },
            'm2-salle-soins': { voir: false },
            'm2-imagerie': { voir: false },
            /* Les tableaux des autres modalités suivent l'échographie (vague 61). */
            'm2-imagerie-radiographie': { voir: false },
            'm2-imagerie-mammographie': { voir: false },
            'm2-imagerie-scanner': { voir: false },
            'm2-imagerie-irm': { voir: false },
            'm2-pathologies': { voir: false },
            /* La sortie d'hospitalisation passe par elle. */
            'm3-sorties': { voir: true, editer: true, annuler: false },
            'm3-visites-patients': { voir: true, editer: true, annuler: false },
            /* LE REGISTRE DU COURRIER EST TENU À L'ACCUEIL — matrice cible
               des Instructions (C, R, U). Le reste de M13 ne s'ouvre pas. */
            'm13-courriers': { voir: true, editer: true, annuler: false },
            /* TARIFS PUBLICS À L'ACCUEIL (phase 3) : l'accueil renseigne le
               patient sur les prix — LECTURE seule, le référentiel se tient en
               configuration. Une surcharge d'écran ACCORDE sans ouvrir le
               module CFG. */
            'cfg-tarifs': { voir: true, editer: false, annuler: false },
            'cfg-catalogue': { voir: true, editer: false, annuler: false },
            'cfg-certificats': { voir: true, editer: false, annuler: false },
          },
          definiLe: '2026-08-27', definiPar: 'Direction',
          motif: 'Zone 1 du dossier — identification, coordonnées, couverture, constantes. La zone '
            + 'clinique ne lui est pas ouverte (RG-13) et chaque consultation du dossier est journalisée. '
            + 'Les tarifs publics lui sont ouverts en lecture (phase 3) : renseigner un prix au guichet.',
        },

        {
          id: 'RBAC01', role: 'laborantin', libelleOrigine: 'Laborantin', statut: 'actif',
          droits: {
            /* Le module reste ouvert — sinon le laborantin perdrait aussi le
               répertoire, dont il a besoin. C'est l'écran qui décide. */
            M1: { voir: true, editer: false, annuler: false },
          },
          droitsEcrans: {
            /* CE QU'IL LUI FAUT : identifier le patient, et ouvrir la demande
               d'un patient externe qui se présente avec une ordonnance. */
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            'm1-externe': { voir: true, editer: true, annuler: false },

            /* CE QUI EST CLINIQUE — RG-13. */
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-pieces': { voir: false },

            /* CE QUI EST LE GESTE D'UN AUTRE POSTE. Les constantes sont
               relevées à l'accueil ; la référence et la contre-référence sont
               des décisions d'évacuation, prises par le clinicien. Le
               laboratoire n'a rien à y faire, ni à les lire. */
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },

            /* La numérisation et la bibliothèque du dossier. */
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },

            /* IL UTILISE LES AUTOMATES, IL NE LES ENTRETIENT PAS. Le parc
               technique lui était ouvert par héritage du module M13 ; c'est
               l'administration qui le tient. */
            'm13-maintenance': { voir: false },

            /* Décision du 02/09/2026 : le BON DE LIVRAISON est le geste du
               MAGASINIER — ni le créer, ni le modifier, ni même l'imprimer
               depuis le laboratoire. L'écran lui est fermé ; il garde les
               bons de commande (suivre l'arrivée de SES réactifs) et les PV
               de réception des réactifs, où il constate. */
            'm7-livraisons': { voir: false },
          },
          /* UNE SEULE FICHE PAR RÔLE : le renommage décidé par la Direction
             le 24/08/2026 est porté ICI et non dans une seconde fiche. Deux
             fiches rendraient la matrice imprévisible — selon l'ordre de
             lecture, c'est l'une ou l'autre qui l'emporterait, et un archivage
             posé par la première serait annulé par le statut de la seconde. */
          libelle: 'Biologiste médical', libelleCourt: 'Biologiste',
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Le laboratoire consulte l’identité du patient, il ne tient pas son dossier médical. '
            + 'Rôle renommé « Biologiste médical » sur décision de la Direction du 24/08/2026.',
        },

        /* ====================================================================
         * LE COMPTE PHARMACIE EST FERMÉ — LA PHARMACIE PASSE AU CAISSIER
         * --------------------------------------------------------------------
         * « Supprimer » se traduit par ARCHIVER (RG-14) : les comptes cessent
         * d'ouvrir une session, la tentative est journalisée, et les mouvements
         * de stock que ce rôle a signés restent attribuables. Les effacer
         * rendrait anonymes des sorties de stock justifiées.
         *
         * L'archivage va AVEC son transfert : fermer la pharmacie sans l'ouvrir
         * au caissier laisserait le poste sans personne.
         * ================================================================== */
        {
          id: 'RBAC03', role: 'pharmacien', libelleOrigine: 'Pharmacien',
          /* C'est le STATUT de la fiche qui ferme le compte : roleArchive() le
             lit là, et nulle part ailleurs. */
          statut: 'archive',
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Compte fermé sur décision de la Direction. Ses droits — module M6 en totalité, '
            + 'annulation comprise — sont transférés au compte Caissier (fiche RBAC04). Rien n’est '
            + 'supprimé : la réouverture rendrait le compte en l’état (RG-14).',
          transfereA: 'caissier',
        },
        {
          id: 'RBAC04', role: 'caissier', libelleOrigine: 'Caissier', statut: 'actif',
          droits: {
            /* LA PHARMACIE EST TRANSFÉRÉE EN ENTIER, droit d'annulation
               compris. Un archivage va toujours avec son transfert : le
               pharmacien pouvait annuler un mouvement, le caissier qui reprend
               sa fonction doit le pouvoir aussi. Transférer à moitié, c'est
               fermer le métier. */
            M6: { voir: true, editer: true, annuler: true },
          },
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'La pharmacie — stock détail, pharmacie d’urgence et mouvements — est rattachée au '
            + 'compte Caissier, avec l’intégralité des droits du compte Pharmacien fermé.',
        },

        /* ====================================================================
         * LE COMPTE RH EST FERMÉ — LES RH PASSENT À LA DIRECTRICE ADMINISTRATIVE
         * --------------------------------------------------------------------
         * La Direction pourra le recréer plus tard : c'est précisément ce que
         * la matrice administrable permet, sans retoucher le logiciel.
         * ================================================================== */
        {
          id: 'RBAC05', role: 'rh', libelleOrigine: 'Responsable RH',
          statut: 'archive',
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Compte fermé sur décision de la Direction. Ses droits — M10 Ressources humaines et '
            + 'M11 Paie & Primes — sont transférés à la Directrice de l’Administration et des Finances '
            + '(fiche RBAC06). Un rôle s’ARCHIVE, il ne se supprime jamais (RG-14) : effacer rendrait '
            + 'anonymes les bulletins qu’il a émis.',
          transfereA: 'da',
        },
        {
          id: 'RBAC06', role: 'da', libelleOrigine: 'Directrice Administrative', statut: 'actif',
          /* Intitulé rectifié par la Direction le 25/08/2026. */
          libelle: 'Directrice de l’Administration et des Finances (DAF)', libelleCourt: 'DAF',
          droits: {
            M10: {
                  "voir": true,
                  "editer": true,
                  "annuler": true
        },
            M11: {
                  "voir": true,
                  "editer": true,
                  "annuler": true
        },
          },
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Les ressources humaines et la paie sont rattachées à la Directrice Administrative.',
        },

        /* ====================================================================
         * QUATRE COMPTES CRÉÉS
         * --------------------------------------------------------------------
         * Chacun part de ZÉRO — aucun module n'est ouvert tant qu'on ne l'écrit
         * pas. M1 et RAP portent `roles: '*'` au manifeste, mais « tous les
         * rôles » a été écrit pour ceux qui existaient alors, pas pour ceux
         * qu'on inventerait : la surcharge ferme donc chaque module nommément
         * avant d'en rouvrir quelques-uns.
         * ================================================================== */
        {
          id: 'RBAC07', role: 'aide_soignant', statut: 'actif', nouveau: true,
          libelle: 'Aide-soignante', libelleCourt: 'Aide-soign.', couleur: 'success',
          accueil: 'dash-aide-soignant',
          droits: droitsAideSoignant,
          droitsEcrans: {
            /* LES QUATRE ÉCRANS DE L'AIDE-SOIGNANTE, nommés un à un parce que
               leurs modules sont fermés. */
            'm1-constantes': { voir: true, editer: true, annuler: false },
            'm3-plan-lits': { voir: true, editer: false, annuler: false },
            'm3-chambres': { voir: true, editer: false, annuler: false },
            'm3-feuille-temperature': { voir: true, editer: true, annuler: false },
            /* LA BIBLIOTHÈQUE DES ÉTATS RESTE OUVERTE. Le cahier des charges
               fait de l'impression une exigence de CHAQUE poste, et c'est un
               catalogue : aucune écriture n'y est possible. Les trois écrans
               qui PRODUISENT un rapport restent fermés. */
            'rapports-bibliotheque': { voir: true, editer: false, annuler: false },
            /* Aucun résultat d'analyse : la règle métier le dit déjà, l'écran
               le confirme. */
            'm1-dossier-medical': { voir: false },
          },
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Compte demandé par la Direction — TEPA Séraphine, Aide-soignante chef de service.',
        },
        {
          id: 'RBAC08', role: 'echographiste', statut: 'actif', nouveau: true,
          libelle: 'Technicien d’échographie', libelleCourt: 'Échographie', couleur: 'info',
          accueil: 'dash-echographiste',
          droits: droitsEchographiste,
          droitsEcrans: {
            /* Le dossier patient informatisé en LECTURE SEULE : il consulte
               l'indication, il ne tient pas le dossier. */
            'm1-dossier-medical': { voir: true, editer: false, annuler: false },
            'm1-antecedents': { voir: true, editer: false, annuler: false },
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            /* Il ne modifie pas les prescriptions d'un autre service. */
            'm2-prescriptions': { voir: true, editer: false, annuler: false },
            'm2-consultations': { voir: true, editer: false, annuler: false },
            /* SON écran : le seul de M2 qu'il écrit. Un écran l'emporte sur
               son module, et une surcharge ACCORDE autant qu'elle restreint. */
            'm2-imagerie': { voir: true, editer: true, annuler: true },
            /* Vague 61 — le poste d'imagerie saisit les CR de toutes les
               modalités ; la PRESCRIPTION lui reste fermée. Qui réalise
               radiographie, scanner et IRM est à arbitrer (aucun radiologue
               au tableau des comptes). */
            'm2-imagerie-radiographie': { voir: true, editer: true, annuler: true },
            'm2-imagerie-mammographie': { voir: true, editer: true, annuler: true },
            'm2-imagerie-scanner': { voir: true, editer: true, annuler: true },
            'm2-imagerie-irm': { voir: true, editer: true, annuler: true },
            /* Phase 8 — l'imagerie éclatée : son poste de travail. Le module
               M2 ne le liste pas ; ce sont ces surcharges qui ACCORDENT.
               Sur le registre des demandes, il ÉCRIT — exécuter la demande
               et saisir le CR, c'est son métier — mais il n'en OUVRE pas :
               prescrire serait un exercice illégal, et l'écran ferme la
               commande de création à son rôle, nommément. */
            'm2-dashboard-imagerie': { voir: true, editer: true, annuler: false },
            'm2-imagerie-demandes': { voir: true, editer: true, annuler: false },
            'm2-echographie-galerie': { voir: true, editer: true, annuler: true },
            /* Les statistiques de SON activité : PIL lui est fermé au module
               (aucun accès financier), l'écran s'accorde nommément. */
            'm2-stats-echographie': { voir: true, editer: false, annuler: false },

            /* Les écrans de M1 ajoutés depuis, rouverts par héritage du
               module : l'échographiste lit l'indication, il ne tient ni le
               dossier clinique, ni les pièces médico-légales, ni les fiches
               d'évacuation. */
            'm1-dossier-etendu': { voir: false },
            'm1-pieces': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },
            'm13-maintenance': { voir: false },
            /* Ce qu'il ne doit pas toucher, nommément — un module en lecture
               le couvrirait déjà, mais l'écrire ici le rend vérifiable dans la
               matrice sans avoir à raisonner sur le module. */
            'm2-ordonnances': { voir: false, editer: false, annuler: false },
            'm2-salle-soins': { voir: false, editer: false, annuler: false },
            'm2-pathologies': { voir: false, editer: false, annuler: false },
            /* Le dossier de consultation (anamnèse, examen IPPOA) lui était
               fermé quand il vivait au répertoire (m1-dossier-etendu) : son
               déménagement en M2 ne doit rien rouvrir — il lit l'INDICATION
               portée par la demande d'imagerie, pas l'examen du médecin. */
            'm2-dossiers-consultation': { voir: false, editer: false, annuler: false },
          },
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Accès en lecture au dossier et aux consultations ; SEUL l’écran d’imagerie lui est '
            + 'ouvert en écriture. Aucun accès financier : un manipulateur qui verrait la caisse pourrait '
            + 'faire dépendre l’examen du paiement.',
        },
        {
          id: 'RBAC09', role: 'surveillant', statut: 'actif', nouveau: true,
          libelle: 'Surveillant', libelleCourt: 'Surveillant', couleur: 'navy',
          accueil: 'dash-surveillant',
          droits: droitsSurveillant,
          droitsEcrans: {
            /* LES TABLEAUX TRANSVERSES SE FERMENT (arbitrage du 12/10/2026).
               Ce ne sont pas des tableaux de poste mais les lectures de la
               Direction : on n'y trouve rien pour ce métier, et l'on y voit
               le chiffre d'affaires. Le tableau du poste, lui, reste ouvert —
               c'est sa page d'accueil. */
            'dash-croise': { voir: false, editer: false, annuler: false },
            'dash-da': { voir: false, editer: false, annuler: false },
            /* LES CINQ ÉCRANS DU SURVEILLANT. Il SURVEILLE : planning, gardes,
               permanences, taux de présence, présences et absences. Il ne tient
               ni les contrats, ni les congés, ni les sanctions — ce sont les
               gestes de la DAF, qui porte les RH depuis l'archivage du compte
               « rh ». */
            'm10-planning': { voir: true, editer: true, annuler: false },
            'm10-stats-gardes': { voir: true, editer: false, annuler: false },
            'm10-stats-permanences': { voir: true, editer: false, annuler: false },
            'm10-stats-presence': { voir: true, editer: false, annuler: false },
            'm10-presences': { voir: true, editer: true, annuler: false },
            /* LA BIBLIOTHÈQUE DES ÉTATS RESTE OUVERTE. Le cahier des charges
               fait de l'impression une exigence de CHAQUE poste, et c'est un
               catalogue : aucune écriture n'y est possible. Les trois écrans
               qui PRODUISENT un rapport restent fermés. */
            'rapports-bibliotheque': { voir: true, editer: false, annuler: false },
            /* LES BADGES : il VÉRIFIE, il n'ÉMET pas. Émettre un badge est un
               geste RH — c'est la RH qui répond de l'identité qu'elle
               atteste. Le registre et la vérification en lecture ; les
               modèles et la planche d'impression fermés nommément, pour que
               la matrice se vérifie sans raisonner sur le module. Son M10 est
               FERMÉ depuis le resserrage : ce sont les cinq écrans ci-dessus
               qui portent son droit, et non le module. */
            'm10-badges': { voir: true, editer: false, annuler: false },
            'm10-badges-verification': { voir: true, editer: false, annuler: false },
            'm10-badges-modeles': { voir: false },
            'm10-badges-impression': { voir: false },
          },
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Agendas, retards, présences, absences, planning et gardes. Correspond à l’Infirmier Général, '
            + 'dont la description de poste du 26/10/2023 porte déjà ces missions. Les badges : il '
            + 'les VÉRIFIE à l’entrée, il ne les émet pas (décision du 05/09/2026).',
        },
        {
          /* ASSISTANT DE DIRECTION, non « assistant comptable » : la Direction a
             rectifié l'intitulé le 25/08/2026. C'est le poste que décrit la
             seconde description de poste — celle qui s'intitule « Directrice
             Administrative » mais dont le corps décrit son adjoint. Ses droits
             restent ceux de ses 30 activités, qui sont bien comptables. */
          id: 'RBAC10', role: 'assistant_comptable', statut: 'actif', nouveau: true,
          libelle: 'Assistant de Direction', libelleCourt: 'Assist. Dir.', couleur: 'warning',
          accueil: 'dash-assistant-comptable',
          droits: droitsAssistantComptable,
          droitsEcrans: {
            /* LES TABLEAUX TRANSVERSES SE FERMENT (arbitrage du 12/10/2026).
               Ce ne sont pas des tableaux de poste mais les lectures de la
               Direction : on n'y trouve rien pour ce métier, et l'on y voit
               le chiffre d'affaires. Le tableau du poste, lui, reste ouvert —
               c'est sa page d'accueil. */
            'dash-croise': { voir: false, editer: false, annuler: false },
            'dash-da': { voir: false, editer: false, annuler: false },
            /* LA BIBLIOTHÈQUE DES ÉTATS RESTE OUVERTE. Le cahier des charges
               fait de l'impression une exigence de CHAQUE poste, et c'est un
               catalogue : aucune écriture n'y est possible. Les trois écrans
               qui PRODUISENT un rapport restent fermés. */
            'rapports-bibliotheque': { voir: true, editer: false, annuler: false },
            /* TROIS ÉCRANS DE M13 QUE LA CIBLE NE LUI DONNE PAS. Ouvrir le
               module lui en donnait onze quand elle en nomme huit : corriger
               un manque ne doit pas créer un surplus. Le parc technique est
               l'outil du biomédical, les enquêtes et la satisfaction celui de
               la Direction. */
            'm13-maintenance': { voir: false, editer: false, annuler: false },
            'adm-enquetes': { voir: false, editer: false, annuler: false },
            'adm-satisfaction': { voir: false, editer: false, annuler: false },
            /* M10 lui est FERMÉ au module : ces deux écrans lui sont
               ACCORDÉS nommément — une surcharge accorde autant qu'elle
               restreint. Il vérifie un badge présenté à l'accueil de la
               Direction ; il n'en émet aucun, et ne voit ni les modèles ni
               la planche d'impression. */
            'm10-badges': { voir: true, editer: false, annuler: false },
            'm10-badges-verification': { voir: true, editer: false, annuler: false },
            /* M5 lui est FERMÉ au module depuis le 24/09/2026 — pas de
               résultats d'analyses. Cet écran-ci lui est ACCORDÉ : sa
               description de poste porte « l'inventaire des médicaments
               d'urgence et des réactifs », et un stock de réactifs n'est
               pas une donnée de santé. */
            'm5-reactifs': { voir: true, editer: true, annuler: false },
          },
          definiLe: '2026-08-24', definiPar: 'Direction',
          motif: 'Rattaché à la Direction. Droits repris de la description de poste : livres de compte, '
            + 'rapprochements bancaires, recouvrement des créances, obligations fiscales, point journalier '
            + 'de la caisse, inventaire des médicaments d’urgence et des réactifs.',
        },

        /* ====================================================================
         * LES TROIS RÔLES DE LA PHASE 2 — décidés le 31/08/2026
         * ================================================================== */
        {
          id: 'RBAC17', role: 'chirurgien', statut: 'actif', nouveau: true,
          libelle: 'Chirurgien', libelleCourt: 'Chirurgien', couleur: 'danger',
          accueil: 'dash-chirurgien',
          droits: droitsChirurgien,
          droitsEcrans: {
            'dash-chirurgien': { voir: true, editer: true, annuler: false },
            /* Même discipline que le médecin sur le stock et le laboratoire :
               il prescrit, il ne tient ni l'un ni l'autre. */
            'm5-catalogue': { voir: true, editer: false, annuler: false },
            'm5-unites': { voir: false },
            'm5-valeurs-reference': { voir: true, editer: false, annuler: false },
            'm5-reactifs': { voir: false },
            /* L'imagerie s'écrit par l'échographiste ; le chirurgien la LIT. */
            'm2-imagerie': { voir: true, editer: false, annuler: false },
            'm2-imagerie-radiographie': { voir: true, editer: false, annuler: false },
            'm2-imagerie-mammographie': { voir: true, editer: false, annuler: false },
            'm2-imagerie-scanner': { voir: true, editer: false, annuler: false },
            'm2-imagerie-irm': { voir: true, editer: false, annuler: false },
          },
          definiLe: '2026-08-31', definiPar: 'Direction',
          motif: 'Base médecin + bloc opératoire (CRO, check-listes, transfusion, surveillance), '
            + 'MATERNITÉ FERMÉE — matrice cible des Instructions. Aucune suppression : un compte '
            + 'rendu opératoire est la pièce qu’on ressort quand une suite est contestée.',
        },
        {
          id: 'RBAC18', role: 'anesthesiste', statut: 'actif', nouveau: true,
          libelle: 'Anesthésiste — Réanimateur', libelleCourt: 'Anesthésiste', couleur: 'info',
          accueil: 'dash-anesthesiste',
          droits: droitsAnesthesiste,
          droitsEcrans: {
            'dash-anesthesiste': { voir: true, editer: true, annuler: false },
            /* Les constantes se saisissent — c'est son matériau de travail. */
            'm1-constantes': { voir: true, editer: true, annuler: false },
            'm5-catalogue': { voir: true, editer: false, annuler: false },
            'm5-unites': { voir: false },
            'm5-reactifs': { voir: false },
          },
          definiLe: '2026-08-31', definiPar: 'Direction',
          motif: 'Péri-opératoire : check-listes du bloc, Glasgow, transfusion, surveillance, soins. '
            + 'Résultats de laboratoire en lecture. Ni maternité, ni caisse, ni consultations '
            + 'générales. La CPA et la feuille d’anesthésie (phase 6) hériteront de M3.',
        },
        {
          /* LE 16ᵉ RÔLE — créé par l'arbitrage du 31/08/2026, DISTINCT de
             l'Assistant de Direction (rôle technique `assistant_comptable`,
             conservé tel quel : renommer un identifiant technique romprait
             listes, surcharges et comptes — la doctrine posée pour
             « laborantin »). L'identifiant technique est `aide_comptable` ;
             le LIBELLÉ, celui que l'agent lit, est « Assistant Comptable ». */
          id: 'RBAC19', role: 'aide_comptable', statut: 'actif', nouveau: true,
          libelle: 'Assistant Comptable', libelleCourt: 'Assist. Compta', couleur: 'warning',
          accueil: 'dash-aide-comptable',
          droits: droitsAideComptable,
          droitsEcrans: {
            'dash-aide-comptable': { voir: true, editer: true, annuler: false },
            /* LA CLÔTURE ENGAGE L'EXERCICE : réservée au Comptable principal
               et à la DAF — fermée nommément, matrice cible des Instructions. */
            'm12-cloture': { voir: false, editer: false, annuler: false },
            /* Il saisit dépenses et écritures ; les états de synthèse et le
               paramétrage restent en lecture par le module. */
            'm12-depenses': { voir: true, editer: true, annuler: false },
            'm12-ecritures': { voir: true, editer: true, annuler: false },
          },
          definiLe: '2026-08-31', definiPar: 'Direction',
          motif: 'Saisie financière sans pouvoir d’annulation : dépenses courantes, écritures, '
            + 'réceptions fournisseurs, suivi des créances. Aucun accès clinique (RG-13), '
            + 'clôture annuelle fermée. D = interdit sur toute la matrice — l’annulation '
            + 'appartient au Comptable principal et à la DAF.',
        },
        /* ====================================================================
         * VAGUE 53 (02/09/2026) — LES CINQ FICHES QUI MANQUAIENT
         * --------------------------------------------------------------------
         * Un rôle sans fiche a TOUS les droits sur ce que le manifeste lui
         * ouvre — l'inventaire montrait le comptable en édition/annulation
         * sur le dossier médical. Chaque fiche ne mentionne QUE les modules
         * que le manifeste ouvre au rôle (les mentionner ACCORDE) ; seul
         * l'administrateur système reste sans fiche — son poste EST
         * l'accès complet, et c'est assumé.
         * ================================================================== */
        {
          id: 'RBAC20', role: 'dm', libelleOrigine: 'Directeur Médical', statut: 'actif',
          droits: {
            M1: { editer: true, annuler: false },
            M2: { editer: true, annuler: true },
            M3: { editer: true, annuler: true },
            M4: { editer: true, annuler: false },
            M5: { editer: true, annuler: false },
            /* Il DIRIGE le médical : le stock et la caisse se lisent, ils ne
               se tiennent pas depuis son bureau (accès caisse en lecture —
               décision du 26/08/2026). */
            M6: { editer: false, annuler: false },
            M8: { editer: false, annuler: false },
            M13: { editer: true, annuler: false },
            RAP: { editer: true, annuler: false },
            /* PIL ne se déclare pas : le pilotage est fait de STATISTIQUES,
               qui n'ont rien à modifier — le déclarer en lecture créerait un
               état « lecture seule » sans objet, que l'audit relèverait. */
          },
          droitsEcrans: {
            'm6-stock-gros': { voir: false },
            'm6-transferts': { voir: false },
            'm6-reprise': { voir: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'Direction médicale : écrit le clinique (M1-M5), lit le stock et la caisse, ne les '
            + 'tient pas. L’annulation clinique reste possible en consultation et hospitalisation.',
        },
        {
          id: 'RBAC21', role: 'direction', libelleOrigine: 'Direction / Gérance', statut: 'actif',
          droits: {
            /* La Direction DÉCIDE et LIT ; elle ne saisit ni actes, ni
               caisse, ni stock, ni paie — ses gestes propres sont
               l'institutionnel : administration, sécurité, configuration,
               documentaire, et la validation de la paie (écran nommé). */
            M1: { editer: false, annuler: false },
            M2: { editer: false, annuler: false },
            M3: { editer: false, annuler: false },
            M4: { editer: false, annuler: false },
            M5: { editer: false, annuler: false },
            M6: { editer: false, annuler: false },
            M7: { editer: false, annuler: false },
            M8: { editer: false, annuler: false },
            M9: { editer: false, annuler: false },
            M10: { editer: false, annuler: false },
            M11: { editer: false, annuler: false },
            M12: { editer: false, annuler: false },
            MECEF: { editer: false, annuler: false },
            M13: { editer: true, annuler: true },
            M14: { editer: true, annuler: true },
            CFG: { editer: true, annuler: false },
            GED: { editer: true, annuler: false },
            RAP: { editer: true, annuler: false },
            /* PIL ne se déclare pas : le pilotage est fait de STATISTIQUES,
               qui n'ont rien à modifier — le déclarer en lecture créerait un
               état « lecture seule » sans objet, que l'audit relèverait. */
          },
          droitsEcrans: {
            /* LA VALIDATION DE LA PAIE EST SON GESTE — l'écran s'accorde
               nommément, le module M11 restant en lecture. */
            'm11-validation': { voir: true, editer: true, annuler: false },
            /* LE BADGE ENGAGE L'ÉTABLISSEMENT : il atteste devant un tiers
               qu'un agent est bien des nôtres. La Direction l'émet et le
               retire au même titre que la RH — accordé PAR ÉCRAN, M10
               restant en lecture, comme pour la validation de la paie. */
            'm10-badges': { voir: true, editer: true, annuler: true },
            'm10-badges-modeles': { voir: true, editer: true, annuler: true },
            'm10-badges-impression': { voir: true, editer: true, annuler: false },
            'm10-badges-verification': { voir: true, editer: false, annuler: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'La Direction lit tout et décide : administration, sécurité, configuration, '
            + 'documentaire, validation de la paie. Elle ne saisit ni actes ni caisse — signer '
            + 'n’est pas saisir.',
        },
        {
          id: 'RBAC22', role: 'comptable', libelleOrigine: 'Comptable', statut: 'actif',
          droits: {
            M12: { editer: true, annuler: true },
            /* L'avoir est SON canal de correction (phase 5). */
            M8: { editer: true, annuler: true },
            M9: { editer: true, annuler: false },
            MECEF: { editer: true, annuler: false },
            M11: { editer: true, annuler: false },
            /* Les achats et le stock se LISENT depuis la comptabilité —
               les tenir depuis le même poste romprait la séparation des
               tâches ; la facture fournisseur, elle, est SA pièce. */
            M7: { editer: false, annuler: false },
            M6: { editer: false, annuler: false },
            M13: { editer: false, annuler: false },
            GED: { editer: true, annuler: false },
            RAP: { editer: true, annuler: false },
            /* PIL ne se déclare pas : le pilotage est fait de STATISTIQUES,
               qui n'ont rien à modifier — le déclarer en lecture créerait un
               état « lecture seule » sans objet, que l'audit relèverait. */
            M1: { editer: false, annuler: false },
          },
          droitsEcrans: {
            /* Identifier un patient pour une pièce, jamais lire son dossier. */
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },
            'm1-pieces': { voir: false },
            /* La facture fournisseur est une pièce COMPTABLE. */
            'm7-factures-fournisseurs': { voir: true, editer: true, annuler: false },
            /* La configuration fiscale engage la clinique devant la DGI :
               elle se décide, elle ne se retouche pas au fil des saisies. */
            'mecef-config': { voir: true, editer: false, annuler: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'La comptabilité, la caisse (avoirs compris), les créances, la paie et le fiscal. '
            + 'Les achats et le stock se lisent ; la facture fournisseur s’y saisit car c’est une '
            + 'pièce comptable. Aucun accès clinique (RG-13).',
        },
        {
          id: 'RBAC23', role: 'agentadmin', libelleOrigine: 'Agent Administratif', statut: 'actif',
          droits: {
            M13: { editer: true, annuler: true },
            GED: { editer: true, annuler: false },
            RAP: { editer: true, annuler: false },
            M1: { editer: false, annuler: false },
          },
          droitsEcrans: {
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: true, editer: false, annuler: false },
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },
            'm1-pieces': { voir: false },
            'm1-certificats-externes': { voir: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'Courriers, réunions, événements, ambulance, documentaire et états — le secrétariat '
            + 'de l’établissement. Il identifie un patient pour un courrier, il ne lit pas son '
            + 'dossier (RG-13).',
        },
        {
          id: 'RBAC24', role: 'ambulancier', libelleOrigine: 'Ambulancier', statut: 'actif',
          droits: {
            M13: { editer: true, annuler: false },
            RAP: { editer: false, annuler: false },
            M1: { editer: false, annuler: false },
          },
          droitsEcrans: {
            /* SON poste : les interventions et le répertoire d'urgence. Le
               reste de M13 est le secrétariat — fermé NOMMÉMENT, pour que la
               matrice se vérifie sans raisonner sur le module. */
            'm13-ambulance': { voir: true, editer: true, annuler: false },
            'm13-repertoire-ambulances': { voir: true, editer: false, annuler: false },
            'm13-courriers': { voir: false },
            'm13-reunions': { voir: false },
            'm13-evenements': { voir: false },
            'm13-plan-annuel': { voir: false },
            'm13-notes-service': { voir: false },
            'm13-maintenance': { voir: false },
            'adm-validations': { voir: false },
            'adm-enquetes': { voir: false },
            'adm-satisfaction': { voir: false },
            /* Identifier le patient transporté, rien de plus. */
            'm1-patients': { voir: true, editer: false, annuler: false },
            'm1-patient-profil': { voir: false },
            'm1-dossier-medical': { voir: false },
            'm1-antecedents': { voir: false },
            'm1-dossier-etendu': { voir: false },
            'm1-constantes': { voir: false },
            'm1-reference': { voir: false },
            'm1-contre-reference': { voir: false },
            'm1-documents': { voir: false },
            'm1-numerisation': { voir: false },
            'm1-pieces': { voir: false },
            'm1-certificats-externes': { voir: false },
            'm1-externe': { voir: false },
            'm1-assures': { voir: false },
          },
          definiLe: '2026-09-02', definiPar: 'Direction',
          motif: 'Les interventions d’ambulance et le répertoire d’urgence — rien du secrétariat, '
            + 'rien du dossier au-delà de l’identité du patient transporté.',
        },
      ],
      /* Emplacements de rangement — rayons et casiers. Amorcés depuis ce que
         les produits portent déjà : le référentiel ne part pas de zéro, il
         régularise l'existant. Lu par le référentiel produits ET par
         l'étiquetage, donc amorcé ici. */
      emplacements: (function () {
        var vus = {}, out = [];
        produits.forEach(function (p) {
          var e = (p.emplacement || '').trim();
          if (!e || vus[e]) return;
          vus[e] = true;
          out.push({
            id: 'EMP' + C.pad(out.length + 1, 3),
            code: e, libelle: e,
            zone: /frigo|froid|2.*8/i.test(e) ? 'Chaîne du froid' : 'Rayonnage sec',
            temperature: /frigo|froid|2.*8/i.test(e) ? '2 à 8 °C' : 'Ambiante',
            capacite: null, statut: 'actif',
            source: 'Repris des emplacements saisis sur les fiches produits',
          });
        });
        return out;
      })(),
      /* Barème d'évaluation NS 131 — lu par les évaluations ET par la paie
         (la retenue en découle), donc amorcé ici. Chaque critère porte sa
         date d'effet : c'est elle qui permet de ne pas réécrire une
         évaluation déjà prononcée. */
      baremeNS131: D.NS131.criteres.map(function (c, i) {
        return {
          id: 'BAR' + C.pad(i + 1, 2), critereId: c.id, num: c.num, label: c.label,
          criteres: (c.criteres || []).slice(),
          sanctions: Object.assign({}, c.sanctions),
          dateEffet: D.NS131.dateEffet, version: D.NS131.version,
          source: D.NS131.reference, statut: 'actif',
        };
      }),
      historiqueBareme: [],
      /* Notifications de poste — amorcées vides, alimentées par le parcours. */
      notifications: [],
      modulesActifs: [
        /* ================================================================
         * DEUX POSTES QUI N'EXISTENT PAS — fermés le 27/08/2026
         * ----------------------------------------------------------------
         * L'INGÉNIEUR BIOMÉDICAL n'existe pas à la clinique : le rôle avait
         * été créé sur une lecture erronée de la liste des comptes, et la
         * Direction a rectifié — KINNOU A. Ganiou est biologiste médical.
         * Le PARC TECHNIQUE reste ouvert : c'est un besoin réel, tenu par
         * l'administration.
         *
         * LE PHARMACIEN est un compte archivé depuis le 24/08/2026 : la
         * pharmacie est tenue par la Caissière-Dispensatrice. Son tableau de
         * bord n'a plus de titulaire.
         *
         * Rien n'est supprimé : rouvrir l'activité rend les écrans en l'état.
         * ============================================================== */

        {
          id: 'MOD01', code: 'M5-BANQUE', libelle: 'Banque de sang', module: 'M5',
          ecrans: ['m5-banque-sang'], actif: false,
          motif: 'La clinique ne pratique pas la banque de sang.',
          fermeLe: '2026-08-21', fermePar: 'Direction',
        },
        {
          id: 'MOD02', code: 'M5-DONNEURS', libelle: 'Donneurs & transfusions', module: 'M5',
          ecrans: ['m5-donneurs'], actif: false,
          motif: 'La clinique ne pratique pas la transfusion.',
          fermeLe: '2026-08-21', fermePar: 'Direction',
        },
      ],
      /* --- Paramétrage du laboratoire ---------------------------------------
         Trois collections lues par plusieurs écrans, donc amorcées ici :
         le catalogue du bulletin, les unités et les variables de résultat.
         Le biologiste doit pouvoir les corriger — « en fonction des réactifs
         les valeurs peuvent changer » — d'où leur passage par le magasin. */
      /* Pathologies — lues par la consultation, le dossier patient et les
         statistiques de morbidité, donc amorcées ici. */
      /* VALIDATIONS ÉCRITES DU 01/09/2026 (vague 51) — les professionnels
         nommés ont tranché : les pathologies par les médecins (tableau de
         morbidité), les bornes suppléées par le biologiste médical. La
         SEMENCE (D.PATHOLOGIES, L.VARIABLES) garde son marquage : elle
         documente ce qui venait d'un document et ce qui a été suppléé. */
      pathologies: D.PATHOLOGIES.map(function (x) {
        var rec = Object.assign({}, x);
        if (rec.aValider) {
          rec.aValider = false;
          rec.valideLe = '2026-09-01';
          rec.validePar = 'Médecins — tableau de morbidité';
        }
        return rec;
      }),
      examensLabo: L.EXAMENS.map(function (e) { return Object.assign({}, e); }),
      unitesLabo: L.UNITES.map(function (u, i) {
        return Object.assign({ id: 'UNI' + C.pad(i + 1, 2), statut: 'actif' }, u);
      }),
      variablesLabo: L.VARIABLES.map(function (v) {
        var rec = Object.assign({}, v);
        if (rec.aValider) {
          rec.aValider = false;
          rec.valideLe = '2026-09-01';
          rec.validePar = 'Biologiste médical';
          rec.source = 'Valeur usuelle, validée par le biologiste médical le 01/09/2026';
        }
        return rec;
      }),
      /* --- Paramétrage de l'IMAGERIE (phase 8) ------------------------------
         Le catalogue et les variables quittent le code pour le magasin — la
         doctrine du laboratoire, appliquée à l'imagerie : l'échographiste
         doit pouvoir corriger ses listes sans toucher au code. Lu par les
         écrans M2 ET par cfg-imagerie-catalogue (module CFG), donc au socle.
         D.IMAGERIE n'est que la semence. */
      examensImagerie: ((D.IMAGERIE && D.IMAGERIE.EXAMENS) || []).map(function (e, i) {
        return Object.assign({ id: 'EXI' + C.pad(i + 1, 2), statut: 'actif' }, e);
      }),
      variablesImagerie: ((D.IMAGERIE && D.IMAGERIE.VARIABLES) || []).map(function (v, i) {
        return Object.assign({ id: 'VIM' + C.pad(i + 1, 3), statut: 'actif', actif: true }, v);
      }),
      /* Les demandes d'imagerie (mêmes états que le labo : demandée → payée →
         exécutée → validée) et la galerie de clichés — remplies par le
         parcours et par le poste, jamais pré-inventées. */
      demandesImagerie: [],
      clichesImagerie: [],
      /* Événements du personnel et participations — amorcés par leur écran
         (un seul les crée), mais LUS par la paie : la collection doit exister.  */
      evenements: [],
      /* Les événements de l'ÉTABLISSEMENT — distincts de ceux du PERSONNEL.
         Les deux partageaient une seule collection, ce que le peuplement a
         révélé en mêlant les mariages d'agents aux journées portes ouvertes. */
      evenementsEtablissement: [],
      participations: [],
      /* Régimes de travail par catégorie — lus par le planning ET par les
         statistiques de garde, donc amorcés ici et non par un écran. */
      /* Le registre des présences — amorcé ICI et non par son écran : trois
         écrans le lisent (registre, statistiques, tableau du Surveillant), et
         une page ne charge que le module de son écran. */
      presences: genPresences(rnd, personnel),

      regimesTravail: D.REGLES_PLANNING.map(function (r, i) {
        return Object.assign({ id: 'REG' + C.pad(i + 1, 2), statut: 'actif' }, r, {
          fonctions: r.fonctions.slice(), vacations: r.vacations.slice(),
        });
      }),
      comptes: D.PLAN_COMPTABLE.map(function (c, i) {
        return Object.assign({ id: 'CPT' + C.pad(i + 1, 3), statut: 'actif' }, c);
      }),
    };
  }

  /* --------------------------------------------------------------------------
   * PERSONNEL SOIGNÉ SUR PLACE
   * --------------------------------------------------------------------------
   * La clinique prend ses agents en charge à 100 %. Encore faut-il savoir, au
   * guichet, que le patient est un agent : c'est ce que porte `personnelId`.
   *
   * Le rattachement ne se devine pas d'un nom — deux personnes peuvent le
   * partager, et un agent peut être enregistré sous un nom d'usage. On crée
   * donc un DOSSIER PATIENT explicite pour une partie du personnel, portant
   * son matricule. C'est ce que fait l'accueil dans la réalité.
   * ----------------------------------------------------------------------- */
  function rattacherPersonnelPatients(rnd, patients, personnel) {
    var eligibles = personnel.slice(0, 18);
    eligibles.forEach(function (e, i) {
      var morceaux = String(e.nomComplet).split(' ');
      var nom = morceaux[0];
      var prenom = morceaux.slice(1).join(' ') || nom;
      patients.push({
        id: 'PAT-AG' + C.pad(i + 1, 3),
        code: 'CNT' + (900 + i) + '/25',
        nom: nom, prenom: prenom,
        sexe: e.sexe || (i % 2 ? 'F' : 'M'),
        dateNaissance: e.dateNaissance || '1988-01-01',
        telephone: e.telephone || null,
        adresse: 'Natitingou',
        statut: 'actif',
        /* Le lien qui vaut prise en charge. */
        personnelId: e.id, matricule: e.matricule, fonctionAgent: e.fonction,
        assure: false, souscripteurId: null,
        priseEnChargePersonnel: true,
        dateCreation: C.iso(C.addDays(new Date(2026, 7, 16), -C.between(rnd, 200, 900))),
      });
    });
  }

  /* --------------------------------------------------------------------------
   * SOUSCRIPTEURS — le niveau intermédiaire que les pièces réelles imposent
   * --------------------------------------------------------------------------
   * Le relevé mensuel de la clinique et la facture récapitulative sont组 organisés
   * « par souscripteur, avec n° de police », sous une même compagnie : PIB Bénin
   * et GIZ Bénin sous Africaine des Assurances, par exemple. C'est le contrat de
   * l'employeur — et non la compagnie — qui porte la grille de garanties.
   * ----------------------------------------------------------------------- */
  var EMPLOYEURS = [
    ['PIB Bénin', 'entreprise'], ['GIZ Bénin', 'entreprise'], ['SBEE', 'entreprise'],
    ['SONEB', 'entreprise'], ['Mairie de Natitingou', 'entreprise'],
    ['CNSS Atacora', 'entreprise'], ['Université de Parakou', 'entreprise'],
    ['Souscripteurs particuliers', 'particulier'],
    ['Personnel Clinique NASSIERA TOO', 'personnel'],
  ];

  function genSouscripteurs(rnd) {
    var out = [];
    EMPLOYEURS.forEach(function (e, i) {
      var comp = D.ASSUREURS[i % D.ASSUREURS.length];
      out.push({
        id: 'SOU' + C.pad(i + 1, 3), statut: 'actif',
        nom: e[0], categorie: e[1],
        assureur: comp.code, assureurNom: comp.nom,
        police: comp.code + '/' + (2024 + (i % 3)) + '/' + C.pad(100 + i, 4),
        effectif: e[1] === 'particulier' ? null : C.between(rnd, 12, 240),
        contact: e[1] === 'entreprise' ? 'Chef Service Santé au Travail' : null,
        dateDebut: C.iso(new Date(2024 + (i % 3), C.between(rnd, 0, 11), 1)),
        dateFin: null,
        /* Aucune grille n'est présumée : tant que la convention n'est pas
           saisie, la facturation reste intégralement à la charge du patient
           et le dit. Les barèmes des compagnies restent à collecter. */
        grilleSaisie: false,
        actesExclus: [], produitsExclus: [], accordPrealable: [],
        source: 'Relevé des prestations et facture mensuelle par souscripteur',
      });
    });
    return out;
  }

  /* Un assuré appartient à un souscripteur de sa compagnie. */
  function rattacherSouscripteurs(rnd, patients, souscripteurs) {
    patients.forEach(function (p) {
      if (!p.assureur) return;
      var possibles = souscripteurs.filter(function (s) { return s.assureur === p.assureur; });
      var s = possibles.length ? C.pick(rnd, possibles) : C.pick(rnd, souscripteurs);
      p.souscripteurId = s.id;
      p.souscripteur = s.nom;
      p.numeroPolice = s.police;
      p.categorieAssurance = s.categorie;
    });
  }

  /* ==========================================================================
   * PERSISTANCE
   * ======================================================================== */
  /* --- Compression du magasin ----------------------------------------------
     ~4 Mo de JSON approchaient le quota localStorage (10 Mo en UTF-16) : la
     vague maternité l'aurait franchi en silence. lz-string (vendoré, comme
     Chart.js) ramène le magasin sous le mégaoctet. Le préfixe U+0002 distingue
     une valeur compressée d'un JSON hérité — les deux se relisent, et un poste
     dont la page n'aurait pas chargé lz-string retombe sur le JSON nu. */
  var MARQUE_LZ = '\u0002';
  /* LES CHAMPS NULS NE S'ÉCRIVENT PAS (vague 62). Un null d'objet se relit
     `undefined`, et le code les traite de la même façon (`== null`) : aucun
     enregistrement n'est comparé à `=== null` — vérifié. Or le jeu portait
     ~480 000 caractères de `"motifRemise":null`, `"acteCode":null`… : de quoi
     franchir le quota et faire perdre le magasin entier. Les chaînes vides,
     `false` et `0` restent écrits — ils portent une valeur. Dans un TABLEAU,
     un null se conserve (la position compte). */
  function sansNuls(cle, valeur) {
    return valeur === null && this && !Array.isArray(this) ? undefined : valeur;
  }
  function enJSON(objet) { return JSON.stringify(objet, sansNuls); }
  function serialiser(objet) {
    var json = enJSON(objet);
    if (global.LZString && global.LZString.compressToUTF16) {
      try { return MARQUE_LZ + global.LZString.compressToUTF16(json); } catch (e) { /* repli JSON */ }
    }
    return json;
  }
  function deserialiser(raw) {
    if (raw == null) return null;
    if (raw.charAt(0) === MARQUE_LZ) {
      if (!(global.LZString && global.LZString.decompressFromUTF16)) return null;
      raw = global.LZString.decompressFromUTF16(raw.slice(1));
    }
    return JSON.parse(raw);
  }

  function load() {
    if (db && !_provisoire) return db;
    /* Coquille provisoire posée, hydratation toujours en vol : on la garde. */
    if (_provisoire && !SRV.repondu) return db;
    if (_provisoire) { _provisoire = false; db = null; }
    /* LE NAVIGATEUR N'EST PLUS UNE SOURCE. On efface au passage le reliquat
       d'avant la bascule : le laisser ferait croire à une donnée vivante et
       occuperait 5 Mo pour rien. */
    try { if (storage.get(KEY)) storage.remove(KEY); } catch (e) { /* sans effet */ }

    if (!SRV.actif) {
      /* AVANT D'AVOIR SEULEMENT ESSAYÉ, ON N'ACCUSE PERSONNE. L'hydratation est
         asynchrone et `mount()` l'attend ; mais le manifeste lit la matrice
         RBAC dès le chargement des scripts, donc avant elle. Crier à la panne
         à cet instant affichait le bandeau sur l'écran de connexion d'un
         serveur parfaitement debout — et pire, la coquille vide devenait le
         magasin pour le reste de la page. On rend donc une coquille NON
         MÉMORISÉE : le prochain appel, après hydratation, chargera le vrai. */
      if (!SRV.repondu) { db = vide(); _provisoire = true; return db; }
      signalerPanne('Le magasin n’a pas pu être chargé : le serveur n’a pas répondu.');
      db = vide();
      return db;
    }
    /* PAS DE SESSION, PAS DE SEMENCE. L'écran de connexion charge le socle
       comme tous les autres ; s'il semait, il écrirait sans session et le
       serveur refuserait — à raison (RG-12). Il n'a besoin que de
       `api/auth.php`, et une coquille vide lui suffit. */
    if (!session()) {
      db = vide();
      return db;
    }
    /* Serveur joignable, session ouverte, base vide : PREMIER démarrage.
       On sème, puis on pousse — une fois, en lot. */
    db = seed();
    invaliderManifeste();
    ecrire();
    return db;
  }

  /**
   * LE CACHE RBAC DU MANIFESTE DOIT TOMBER QUAND LE MAGASIN CHANGE.
   *
   * `nav.js` lit la matrice des droits dès le chargement des scripts, donc
   * AVANT que l'hydratation ait répondu : il la lisait sur la coquille vide
   * et gardait ce cache pour toute la page. Conséquence mesurée : la fiche du
   * biologiste portait bien « antécédents fermés », et `droitsEcran` répondait
   * pourtant `origine: true` — TOUTE la couche de surcharges était morte, sur
   * chaque écran. Ce n'était pas un défaut de banc : un agent aurait eu les
   * droits d'origine partout.
   */
  function invaliderManifeste() {
    try {
      if (global.SIGH && global.SIGH.nav && global.SIGH.nav.invaliderRbac) {
        global.SIGH.nav.invaliderRbac();
      }
    } catch (e) { /* le manifeste n'est pas encore là : il lira le bon magasin */ }
  }

  /** Une coquille de la bonne forme, pour que les écrans se peignent à vide. */
  function vide() {
    var o = seed();
    Object.keys(o).forEach(function (k) { if (Array.isArray(o[k])) o[k] = []; });
    return o;
  }
  /* ==========================================================================
   * SAUVEGARDE, ET SAUVEGARDE DIFFÉRÉE
   * --------------------------------------------------------------------------
   * save() sérialise le magasin entier. Sur un geste isolé c'est imperceptible ;
   * sur un traitement en lot de plusieurs milliers d'écritures, le coût devient
   * quadratique — la base grossit et on la resérialise à chaque ligne.
   *
   * enLot() suspend les écritures le temps du traitement et n'en fait qu'une à
   * la fin. Le mode se referme dans un `finally` : une exception au milieu
   * d'un lot ne doit pas laisser le magasin durablement sans sauvegarde.
   * ======================================================================== */
  /* LA COMPRESSION EST UNE SOUPAPE, PAS UN RÉGIME PERMANENT. Mesure faite :
     compresser 4 Mo coûte ~2,4 s de fil principal — payé à chaque écriture,
     cela gelait l'interface et faisait dépasser six secondes aux pages qui
     amorcent en rafale. Le magasin s'écrit donc en JSON nu (rapide) tant que
     le quota tient ; le jour où une écriture est REFUSÉE, il bascule en
     compressé (437 Ko au lieu de 4 Mo), réécrit, et l'annonce. */
  /* ==========================================================================
   * LE MAGASIN SUR UN SERVEUR (23/09/2026)
   * --------------------------------------------------------------------------
   * Le `localStorage` plafonne à 5 Mo, ne sort pas du navigateur, et n'est vu
   * que du poste qui l'a écrit. Pour simuler une clinique il faut l'inverse :
   * pas de plafond, des données sauvegardables, et PLUSIEURS POSTES QUI VOIENT
   * LE MÊME MAGASIN.
   *
   * LE MAGASIN RESTE CHARGÉ EN MÉMOIRE ET LU DE FAÇON SYNCHRONE : c'est ce qui
   * permet aux trois cents écrans de continuer à faire
   * `S.collection('patients').active()` sans qu'aucun ne change. Seule la
   * DESTINATION change — là où `ecrire()` déposait sa chaîne.
   *
   * TROIS PRÉCAUTIONS :
   *   — le serveur n'est pas toujours là (ouverture par double-clic, serveurs
   *     Node des bancs d'essai) : on retombe alors sur `localStorage`, sans
   *     rien casser. Les bancs d'essai doivent d'ailleurs partir d'un jeu
   *     PROPRE à chaque exécution — la base leur nuirait ;
   *   — on n'envoie QUE LES COLLECTIONS MODIFIÉES. Réexpédier 4,8 Mo à chaque
   *     geste coûterait plus cher que ce qu'on remplace ;
   *   — une écriture PORTE SON JETON de session : le serveur refuse l'anonyme
   *     (RG-12). Le jeton est délivré par le serveur, jamais choisi ici.
   * ======================================================================== */
  var SRV = {
    actif: false,      /* l'API a répondu : le magasin vit sur le serveur */
    teste: false,
    jeton: null,
    envoye: {},        /* dernière forme envoyée, par collection */
    meta: {},          /* idem, pour les clés hors collections */
    enVol: false,
    erreurDite: false,
    /* TENTÉE n'est pas TERMINÉE. `teste` passe à vrai dès le DÉPART de
       l'hydratation ; toute lecture faite pendant la requête voyait donc
       « tentée, et pas active » et criait à la panne alors que le serveur
       répondait très bien. `repondu` ne vaut vrai qu'une fois la réponse
       reçue — c'est lui, et lui seul, qui autorise à conclure à une panne. */
    repondu: false,
  };
  var CLE_JETON = 'sigh-cnt:jeton';

  function urlApi(fichier) {
    var racine = '';
    try {
      racine = (global.document && global.document.documentElement
        && global.document.documentElement.getAttribute('data-root')) || '';
    } catch (e) { racine = ''; }
    return racine + 'api/' + fichier;
  }

  /** Vrai si l'on peut espérer un serveur : inutile d'essayer sur file://. */
  function serveurPlausible() {
    try {
      return !!(global.fetch && global.location && /^https?:$/.test(global.location.protocol));
    } catch (e) { return false; }
  }

  /**
   * Charge le magasin depuis le serveur. Résout `true` si le magasin vient de
   * la base, `false` si l'on reste sur le stockage du navigateur.
   * Appelé UNE fois, au montage, avant que le moindre écran ne lise.
   */
  function hydraterServeur() {
    if (SRV.teste) return global.Promise.resolve(SRV.actif);
    SRV.teste = true;
    if (!serveurPlausible()) { SRV.repondu = true; return global.Promise.resolve(false); }

    return global.fetch(urlApi('magasin.php'), { headers: { Accept: 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (o) {
        SRV.repondu = true;
        _provisoire = false;          /* la coquille d'attente a fait son temps */
        if (!o || o.erreur) { invaliderManifeste(); return false; }
        SRV.actif = true;
        try { SRV.jeton = storage.get(CLE_JETON) || null; } catch (e) { SRV.jeton = null; }
        if (o._vide) {
          /* LA BASE EST VIDE — ET L'ON NE SÈME PAS ICI. Le peuplement écrit
             aussitôt, or la session du poste n'est pas encore ouverte à cet
             instant : l'envoi partirait sans jeton et le serveur le refuserait
             (RG-12). On laisse donc le magasin NON chargé ; il se sèmera au
             premier accès, après que la session aura été établie. */
          db = null;
          SRV.envoye = {}; SRV.meta = {};
          invaliderManifeste();
          return true;
        }
        /* LE CONTRÔLE DE VERSION VAUT AUSSI POUR LA BASE. Un magasin semé sous
           une forme antérieure ne se rattrape pas : on le ré-amorce, et l'on
           pousse le neuf — sinon la base garderait indéfiniment un jeu que
           plus aucun écran ne sait lire. */
        if (!o._version || o._version !== VERSION) {
          db = null;
          load();
          SRV.envoye = {}; SRV.meta = {};   /* tout est à pousser */
          invaliderManifeste();
          return true;
        }
        db = o;
        /* Ce qui vient d'être lu est, par construction, ce que le serveur a
           déjà : on ne le lui renverra pas au premier geste. */
        marquerEnvoye(db);
        /* APRÈS l'affectation, jamais avant : posée plus haut, l'invalidation
           était suivie d'une reconstruction immédiate du cache sur l'ANCIEN
           magasin — mesuré, la surcharge d'écran restait ignorée. */
        invaliderManifeste();
        fusionnerServiceDirection(db);
        normaliserEtatsResultat(db);
        return true;
      })
      .catch(function () { SRV.repondu = true; return false; });
  }

  /** Mémorise la forme envoyée, pour ne transmettre ensuite que les écarts. */
  function marquerEnvoye(source) {
    SRV.envoye = {};
    SRV.meta = {};
    Object.keys(source || {}).forEach(function (k) {
      if (Array.isArray(source[k])) SRV.envoye[k] = JSON.stringify(source[k]);
      else SRV.meta[k] = JSON.stringify(source[k]);
    });
  }

  /** Les collections et clés qui ont changé depuis le dernier envoi. */
  function delta() {
    var collections = {}, meta = {}, n = 0;
    Object.keys(db || {}).forEach(function (k) {
      var brut = JSON.stringify(db[k]);
      if (Array.isArray(db[k])) {
        if (SRV.envoye[k] !== brut) { collections[k] = db[k]; SRV.envoye[k] = brut; n++; }
      } else if (SRV.meta[k] !== brut) { meta[k] = db[k]; SRV.meta[k] = brut; n++; }
    });
    return n ? { collections: collections, meta: meta } : null;
  }

  /** Ouvre une session de poste et retient le jeton qu'elle rend. */
  function ouvrirSessionServeur(s2) {
    if (!SRV.actif || !s2 || !s2.role) return global.Promise.resolve(null);
    /* La promesse est RETENUE : une écriture refusée faute de jeton doit
       pouvoir attendre CELLE-CI plutôt que d'en ouvrir une seconde — deux
       sessions pour un même poste fausseraient le compte des postes actifs. */
    SRV.promesseSession = global.fetch(urlApi('session.php'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(s2),
    }).then(function (r) { return r.ok ? r.json() : null; })
      .then(function (o) {
        if (o && o.jeton) {
          SRV.jeton = o.jeton;
          try { storage.set(CLE_JETON, o.jeton); } catch (e) { /* sans effet */ }
        }
        return SRV.jeton;
      }).catch(function () { return null; });
    return SRV.promesseSession;
  }

  /** Envoie le delta. Ouvre une session si le serveur la réclame, puis reprend. */
  function pousserServeur(charge, reessai, urgent) {
    SRV.enVol = true;
    /* `keepalive` QUAND LA PAGE S'EN VA. Un `fetch` ordinaire meurt avec la
       page qui l'a lancé : l'envoi déclenché par `pagehide` n'arrivait donc
       jamais, et le drapeau « déjà peuplé » avec lui — le jeu se reconstruisait
       à l'écran suivant, en double. Avant la bascule, cette écriture allait
       dans le `localStorage`, synchrone et sûre ; il faut rendre à la
       requête la même garantie. */
    return global.fetch(urlApi('magasin.php'), {
      method: 'POST', keepalive: !!urgent,
      headers: { 'Content-Type': 'application/json', 'X-Sigh-Jeton': SRV.jeton || '' },
      body: JSON.stringify({ jeton: SRV.jeton, collections: charge.collections, meta: charge.meta }),
    }).then(function (r) {
      if (r.status === 401 && !reessai) {
        /* Pas de session : on ATTEND celle qui s'ouvre — ou l'on en ouvre une
           — puis on RENVOIE la même charge. La perdre reviendrait à jeter le
           geste de l'utilisateur. */
        var attente = SRV.promesseSession || ouvrirSessionServeur(session());
        return attente.then(function (jeton) {
          if (!jeton) throw new Error('401 — aucune session de poste');
          return pousserServeur(charge, true);
        });
      }
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    }).then(function (o) { SRV.enVol = false; return o; })
      .catch(function (e) {
        SRV.enVol = false;
        /* Le delta a été marqué comme envoyé : il ne repartirait jamais. On
           REVIENT donc en arrière, pour que la prochaine écriture le reprenne. */
        Object.keys(charge.collections || {}).forEach(function (k) { delete SRV.envoye[k]; });
        Object.keys(charge.meta || {}).forEach(function (k) { delete SRV.meta[k]; });
        if (!SRV.erreurDite) {
          SRV.erreurDite = true;
          if (global.console && global.console.error) {
            global.console.error('[SIGH] Écriture au serveur refusée : ' + e.message
              + ' — le magasin reste en mémoire, rien n’est perdu, mais rien n’est partagé.');
          }
        }
        /* UNE SEULE NOUVELLE TENTATIVE, puis on s'arrête en le disant. Le
           delta a été remis en attente ; reprogrammer sans fin ferait tourner
           une boucle muette pendant que l'agent continue de saisir dans le
           vide. */
        SRV.echecs = (SRV.echecs || 0) + 1;
        if (SRV.echecs < 2) { save(); return null; }
        signalerPanne('Le serveur a refusé l’enregistrement à deux reprises — ' + e.message);
        return null;
      });
  }

  /* ==========================================================================
   * LA FILE DES ACTIONS
   * --------------------------------------------------------------------------
   * Chaque geste de l'interface — créer, modifier, archiver, restaurer — part
   * en UNE requête nommée. Le serveur y applique RG-12 (l'auteur vient de la
   * session, jamais du client) et RG-14 (aucune suppression physique).
   *
   * POURQUOI UNE FILE plutôt qu'un appel direct : les mutations sont
   * SYNCHRONES pour l'appelant — `insert()` rend sa fiche tout de suite, et
   * trois cents écrans comptent là-dessus. La requête part donc juste après,
   * en bloc avec celles de la même rafale, et dans l'ORDRE : deux écritures
   * sur la même fiche ne doivent pas se croiser.
   *
   * PENDANT L'AMORÇAGE, elle est MUETTE : semer, c'est dix mille fiches, donc
   * dix mille requêtes. Le peuplement passe par l'envoi du magasin entier.
   * ======================================================================== */
  var FILE = { actions: [], enCours: false, minuterie: null };

  function transmettre(action, collection, charge) {
    if (!SRV.actif || _lot > 0 || PANNE.active) return;
    if (!session()) return;   /* avant la connexion, rien n'a d'auteur */
    FILE.actions.push(Object.assign({ action: action, collection: collection }, charge));
    if (FILE.minuterie) clearTimeout(FILE.minuterie);
    FILE.minuterie = setTimeout(viderFile, 40);
  }

  function viderFile() {
    FILE.minuterie = null;
    if (FILE.enCours || !FILE.actions.length || PANNE.active) return;
    FILE.enCours = true;
    var geste = FILE.actions.shift();

    var envoi = function (jeton) {
      return global.fetch(urlApi('crud.php'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Sigh-Jeton': jeton || '' },
        body: JSON.stringify(geste),
      });
    };

    envoi(SRV.jeton)
      .then(function (r) {
        /* Session absente : on l'ouvre (ou l'on attend celle qui s'ouvre) et
           l'on REJOUE le même geste. Le perdre reviendrait à jeter la saisie. */
        if (r.status === 401) {
          var attente = SRV.promesseSession || ouvrirSessionServeur(session());
          return attente.then(function (jeton) {
            if (!jeton) throw new Error('aucune session de poste');
            return envoi(jeton);
          });
        }
        return r;
      })
      .then(function (r) {
        if (!r.ok) {
          return r.json().catch(function () { return {}; }).then(function (o) {
            throw new Error((o && (o.detail || o.erreur)) || ('HTTP ' + r.status));
          });
        }
        FILE.enCours = false;
        if (FILE.actions.length) viderFile();
        return null;
      })
      .catch(function (e) {
        FILE.enCours = false;
        /* ON NE RETOMBE PAS. Le geste est perdu côté serveur : le miroir en
           mémoire ment désormais, et le laisser à l'écran ferait croire la
           saisie enregistrée. On bloque, on le dit, on recharge. */
        FILE.actions.length = 0;
        signalerPanne('Écriture refusée (' + geste.action + ' / ' + geste.collection + ') — '
          + e.message);
      });
  }

  var _lot = 0, _minuterie = null, _compresser = false, _enPartant = false;
  function ecrire() {
    if (_minuterie) { clearTimeout(_minuterie); _minuterie = null; }
    if (!db) return;

    /* LA DESTINATION D'ABORD. Sur le serveur, il n'y a ni quota ni soupape de
       compression à armer : ces deux mécanismes appartiennent au stockage du
       navigateur, et les faire tourner en plus coûterait sans rien apporter. */
    if (SRV.actif) {
      /* Sans session, rien ne part : le serveur refuserait (RG-12) et la
         tentative se reprogrammerait en boucle. Avant la connexion il n'y a
         d'ailleurs aucune donnée d'agent à perdre. */
      if (!session()) return;
      var charge = delta();
      if (charge) pousserServeur(charge, false, _enPartant);
      return;
    }

    /* PAS DE SECONDE DESTINATION. Autrefois le magasin retombait ici sur le
       `localStorage` ; cette branche est retirée. Sans serveur, il n'y a pas
       d'écriture — et on le dit. */
    signalerPanne('Aucun serveur de base de données joignable : écriture impossible.');
  }
  function save() {
    if (_lot > 0) return;
    /* Écriture DIFFÉRÉE : les amorçages d'écran enchaînent des dizaines
       d'insertions qui appellent chacune save() — sérialiser le magasin à
       chaque fois est quadratique. Une rafale n'écrit qu'une fois, 300 ms
       après le dernier geste ; db reste la vérité en mémoire, et pagehide
       vide le tampon avant de quitter la page. */
    if (!_minuterie) _minuterie = setTimeout(ecrire, 300);
  }

  function enLot(fn) {
    _lot++;
    try {
      return fn();
    } finally {
      _lot--;
      if (_lot === 0) ecrire();
    }
  }

  /**
   * Vide la file SANS attendre : chaque geste encore en attente part avec
   * `keepalive`, qui laisse la requête survivre à la page. C'est le seul
   * moyen de ne pas perdre une saisie quand l'agent enregistre puis s'en va.
   */
  function viderFileEnPartant() {
    if (!SRV.actif || !FILE.actions.length) return;
    var restants = FILE.actions.splice(0, FILE.actions.length);
    restants.forEach(function (geste) {
      try {
        global.fetch(urlApi('crud.php'), {
          method: 'POST', keepalive: true,
          headers: { 'Content-Type': 'application/json', 'X-Sigh-Jeton': SRV.jeton || '' },
          body: JSON.stringify(geste),
        });
      } catch (e) { /* la page s'en va : on ne peut rien dire de plus */ }
    });
  }

  if (global.addEventListener) {
    global.addEventListener('pagehide', function () {
      _enPartant = true;
      if (FILE.minuterie) { clearTimeout(FILE.minuterie); FILE.minuterie = null; }
      viderFileEnPartant();
      if (_minuterie) ecrire();
    });
  }
  /* ==========================================================================
   * CE QUI SURVIT À UNE RÉINITIALISATION — la liste vit AU SOCLE (vague 68)
   * --------------------------------------------------------------------------
   * « Réinitialiser » retire les données ENGENDRÉES pour la démonstration —
   * patients, consultations, factures, mouvements, écritures — et garde ce qui
   * fait le logiciel : le paramétrage, les référentiels issus des documents,
   * les comptes, la matrice des droits, les catalogues, les règles datées.
   *
   * La liste vivait dans l'écran des paramètres, et elle était INCOMPLÈTE : la
   * matrice RBAC, les modules actifs, les catalogues du laboratoire et de
   * l'imagerie, le barème et la grille des primes n'y figuraient pas. Vider les
   * jeux de test rouvrait la banque de sang, rendait TOUS les droits à TOUS
   * les rôles (un rôle sans fiche a tout — vague 36) et privait le laboratoire
   * de ses examens. C'est ce que « ça n'a pas marché » voulait dire.
   *
   * Et le vidage ne TENAIT pas : une quinzaine d'écrans ré-amorcent leur
   * collection dès qu'ils la trouvent vide (contrats, budgets, avances, poches,
   * achats…). Ouvrir l'écran suffisait à faire renaître le jeu, écran par
   * écran. D'où le drapeau `_jeuVide`, posé par le vidage et lu par
   * `amorcable()` : un amorçage de DÉMONSTRATION ne repart plus sur un magasin
   * volontairement vidé ; un référentiel DÉRIVÉ d'un document (le calendrier
   * fiscal) reste libre de se reconstruire, il ne porte aucune invention.
   * ======================================================================== */
  var COLLECTIONS_ESSENTIELLES = [
    /* Paramétrage et référentiels administrés par la clinique */
    'actes', 'analyses', 'produits', 'assureurs', 'fournisseurs', 'comptes', 'banques',
    'naturesFacture', 'centresCouts', 'secteurs', 'postes', 'personnel', 'soignants',
    'fichesPoste', 'ressources', 'souscripteurs', 'garanties', 'certificats', 'typesPiece',
    'catalogueTarifs', 'objectifsPilotage', 'valorisationsSage', 'ambulances', 'materiel',
    /* Comptes, droits et activation des modules */
    'utilisateurs', 'rbac', 'modulesActifs',
    /* Règles datées — régimes, primes, barème */
    'regimesTravail', 'grillePrimes', 'historiquePrimes', 'baremeNS131', 'historiqueBareme',
    /* Catalogues du laboratoire et de l'imagerie, bornes par lot, pathologies */
    'examensLabo', 'unitesLabo', 'variablesLabo', 'plagesReactif',
    'examensImagerie', 'variablesImagerie', 'pathologies',
    /* Modèles (badges, messages, questionnaires) et emplacements de rangement */
    'modelesBadge', 'modelesMessage', 'enquetes', 'emplacements',
    /* LE JOURNAL D'AUDIT SE GARDE : il trace les tarifs arrêtés, les droits fermés, la
       grille des primes — tout ce que le vidage CONSERVE. Effacer la trace de ce qu'on
       garde contredirait RG-12 ; le vidage s'inscrit EN TÊTE du journal conservé. */
    'audit',
  ];
  /* Dérivées d'un référentiel : vidées, elles se reconstruisent depuis leur
     document — le vidage ne leur retire rien. */
  var COLLECTIONS_DERIVEES = ['echeancesFiscales'];

  function essentielle(nom) { return COLLECTIONS_ESSENTIELLES.indexOf(nom) >= 0; }
  /** Le magasin a-t-il été volontairement vidé de ses jeux de test ? */
  function jeuVide() { load(); return !!(db && db._jeuVide); }
  /** Un amorçage d'écran a-t-il le droit de peupler cette collection ? */
  function amorcable(nom) {
    if (!jeuVide()) return true;
    return essentielle(nom) || COLLECTIONS_DERIVEES.indexOf(nom) >= 0;
  }
  /** Vide les données d'activité, garde l'essentiel, et le DIT au magasin. */
  function viderActivite(motif) {
    load();
    var tables = 0, lignes = 0, vidées = [];
    Object.keys(db).forEach(function (k) {
      if (k.charAt(0) === '_' || !Array.isArray(db[k]) || essentielle(k)) return;
      lignes += db[k].length; tables++; vidées.push(k);
      db[k] = [];
    });
    /* LE CALENDRIER FISCAL EST DÉRIVÉ D'UN DOCUMENT : il revient aussitôt, SANS règlement
       inventé — un tableau de bord qui lirait un faux zéro jusqu'à l'ouverture de l'écran
       des échéances est le défaut documenté de la vague 31. */
    db.echeancesFiscales = genEcheances().map(function (e) {
      return Object.assign(e, { paye: false, datePaiement: null, reference: null, valideePar: null });
    });
    db._jeuVide = true;
    db._jeuVideLe = new Date().toISOString();
    /* Le peuplement du parcours transactionnel ne doit pas repartir non plus. */
    db._parcoursAmorces = true;
    db.audit = db.audit || [];
    save();
    /* Le vidage s'inscrit en tête du journal conservé (RG-12). */
    log('Réinitialisation des jeux de test', 'CFG', 'Base', 'vidage', null,
      { tables: tables, enregistrements: lignes, motif: motif || '' });
    return { tables: tables, enregistrements: lignes, collections: vidées };
  }

  function reset() {
    try { storage.remove(KEY); } catch (e) { /* reliquat d'avant la bascule */ }
    var ancien = db;
    db = seed();
    /* UNE CLÉ ABSENTE NE PART JAMAIS : le delta n'envoie que ce que le nouveau magasin
       PORTE. Une collection née après un vidage (badges, évaluations, missions) et absente
       de la semence survivrait à la régénération, et `_parcoursAmorces`, posé vrai par le
       vidage, empêcherait le peuplement du parcours de repartir — la base rendait un jeu
       amputé. On pose donc explicitement ce qui doit être vide ou faux. */
    Object.keys(ancien || {}).forEach(function (k) {
      if (Array.isArray(ancien[k]) && !(k in db)) db[k] = [];
    });
    db._jeuVide = false;
    db._jeuVideLe = null;
    db._parcoursAmorces = false;
    db._parcoursAmorcesLe = null;
    SRV.envoye = {}; SRV.meta = {};   /* tout est à repousser */
    ecrire();
    return db;
  }

  /* --- Journal d'audit (RG-12) -------------------------------------------- */
  function log(action, module, entite, reference, avant, apres) {
    load();
    db.audit.unshift({
      id: 'LOG' + Date.now().toString(36),
      dateHeure: new Date().toISOString(),
      utilisateur: currentUser(),
      action: action, module: module, entite: entite, reference: reference,
      /* Extraits volontairement courts : le journal doit dire CE QUI a changé,
         pas rejouer l'enregistrement entier. Deux cent quarante caractères par
         ligne pesaient 430 Ko sur huit cents entrées.
         RAMENÉS DE 140 À 100 LE 22/09/2026, et c'est le NOMBRE D'ENTRÉES qu'on
         protège en le faisant : le plafond reste à 400. Entre garder quatre
         cents gestes journalisés avec un extrait plus court et n'en garder que
         deux cent cinquante avec un extrait long, RG-12 penche du premier côté
         — c'est la trace du geste qui fait preuve, pas la longueur de la
         citation. Mesuré : ~62 Ko rendus au magasin, qui était à sa marge. */
      ancienneValeur: avant ? JSON.stringify(avant).slice(0, 100) : null,
      nouvelleValeur: apres ? JSON.stringify(apres).slice(0, 100) : null,
      poste: 'POSTE-LOCAL', succes: true,
    });
    if (db.audit.length > 400) db.audit.length = 400;
  }

  /* --- Abonnements -------------------------------------------------------- */
  function on(name, fn) { (listeners[name] = listeners[name] || []).push(fn); }
  function emit(name) { (listeners[name] || []).forEach(function (fn) { try { fn(); } catch (e) { console.error(e); } }); }

  /* ==========================================================================
   * API COLLECTION
   * ======================================================================== */
  /* GARDES D'ÉCRITURE — une règle métier posée SUR la collection, pas sur un
     écran : l'exercice clos refuse toute écriture, d'où qu'elle vienne. La garde
     rend un MOTIF (refus nommé) ou rien. */
  var GARDES = {};
  function garder(nom, fn) { GARDES[nom] = fn; }
  function refuse(nom, op, rec) {
    var g = GARDES[nom];
    if (!g) return null;
    var motif = g(op, rec);
    if (!motif) return null;
    try { log('Écriture refusée', '—', nom, (rec && (rec.id || rec.numero)) || '', null, { op: op, motif: motif }); } catch (e) { /* journal indisponible */ }
    try { if (global.SIGH.ui && global.SIGH.ui.toast) global.SIGH.ui.toast('Écriture refusée.', { type: 'error', detail: motif }); } catch (e) { /* sans interface */ }
    return motif;
  }

  function collection(name, meta) {
    load();
    if (!db[name]) db[name] = [];
    var M = meta || {};
    var api = {
      name: name,
      /** Tous les enregistrements, archivés compris. */
      all: function () { return db[name]; },
      /** Enregistrements non archivés (vue par défaut des tableaux). */
      active: function () { return db[name].filter(function (r) { return r.statut !== 'archive'; }); },
      archived: function () { return db[name].filter(function (r) { return r.statut === 'archive'; }); },
      get: function (id) {
        for (var i = 0; i < db[name].length; i++) if (db[name][i].id === id) return db[name][i];
        return null;
      },
      count: function () { return api.active().length; },

      insert: function (obj) {
        if (refuse(name, 'inserer', obj)) return null;
        var rec = Object.assign({
          id: (M.prefix || name.slice(0, 3).toUpperCase()) + C.uid(),
          statut: 'actif',
        }, obj);
        rec._creePar = currentUser();
        rec._creeLe = new Date().toISOString();
        db[name].unshift(rec);
        log('Création', M.module || '—', M.entite || name, rec.id, null, rec);
        transmettre('inserer', name, { fiche: rec });
        save(); emit(name);
        return {
          record: rec,
          /* L'ANNULATION D'UNE CRÉATION ARCHIVE, elle ne supprime pas. La
             fiche est déjà en base, et RG-14 n'admet aucune suppression
             physique : la faire disparaître du serveur serait précisément ce
             que la règle interdit. Elle sort donc de l'écran (retirée du
             miroir) et reste à la corbeille, où le journal la rattache à sa
             création. */
          undo: function () {
            api._remove(rec.id);
            transmettre('archiver', name, { id: rec.id, motif: 'Création annulée' });
            save(); emit(name);
          },
        };
      },

      update: function (id, patch) {
        var rec = api.get(id); if (!rec) return null;
        if (refuse(name, 'modifier', Object.assign({}, rec, patch))) return null;
        var avant = Object.assign({}, rec);
        Object.assign(rec, patch);
        rec._modifiePar = currentUser();
        rec._modifieLe = new Date().toISOString();
        log('Modification', M.module || '—', M.entite || name, id, avant, rec);
        transmettre('modifier', name, { id: id, correctif: patch });
        save(); emit(name);
        return {
          record: rec,
          undo: function () {
            Object.assign(rec, avant);
            /* On renvoie les valeurs d'AVANT, limitées aux champs touchés :
               réexpédier la fiche entière réécrirait ce qu'un autre poste
               aurait modifié entre-temps. */
            var retour = {};
            Object.keys(patch || {}).forEach(function (k) { retour[k] = avant[k]; });
            transmettre('modifier', name, { id: id, correctif: retour });
            save(); emit(name);
          },
        };
      },

      /** RG-14 — archivage logique, jamais de suppression physique. */
      archive: function (id, motif) {
        var rec = api.get(id); if (!rec) return null;
        if (refuse(name, 'archiver', rec)) return null;
        var avant = rec.statut;
        rec.statut = 'archive';
        rec._archivePar = currentUser();
        rec._archiveLe = new Date().toISOString();
        rec._motifArchivage = motif || null;
        log('Archivage', M.module || '—', M.entite || name, id, { statut: avant }, { statut: 'archive' });
        transmettre('archiver', name, { id: id, motif: motif || null });
        save(); emit(name);
        return {
          record: rec,
          undo: function () {
            rec.statut = avant; delete rec._archivePar; delete rec._archiveLe; delete rec._motifArchivage;
            log('Restauration', M.module || '—', M.entite || name, id, { statut: 'archive' }, { statut: avant });
            transmettre('restaurer', name, { id: id });
            save(); emit(name);
          },
        };
      },

      restore: function (id) {
        var rec = api.get(id); if (!rec) return null;
        rec.statut = 'actif'; delete rec._archivePar; delete rec._archiveLe;
        log('Restauration', M.module || '—', M.entite || name, id, { statut: 'archive' }, { statut: 'actif' });
        transmettre('restaurer', name, { id: id });
        save(); emit(name);
        return { record: rec };
      },

      duplicate: function (id) {
        var rec = api.get(id); if (!rec) return null;
        var copie = Object.assign({}, rec);
        delete copie.id; delete copie._creeLe; delete copie._creePar;
        if (copie.reference) copie.reference = copie.reference + '-COPIE';
        if (copie.numero) copie.numero = copie.numero + '-COPIE';
        return api.insert(copie);
      },

      /** Suppression physique — réservée à l'annulation d'une création. */
      _remove: function (id) {
        var i = db[name].findIndex(function (r) { return r.id === id; });
        if (i >= 0) db[name].splice(i, 1);
      },
    };
    return api;
  }

  /* ==========================================================================
   * CORBEILLE — RG-14
   * --------------------------------------------------------------------------
   * L'archivage remplace la suppression dans tous les modules. Encore faut-il
   * pouvoir retrouver ce qui a été archivé sans savoir de quel écran cela
   * venait : cette vue balaie toutes les collections et rend chaque fiche
   * restaurable depuis un seul endroit.
   * ======================================================================== */

  /* Libellé lisible de chaque collection : « module | entité ». Une collection
     absente de cette table reste listée sous son nom technique. */
  var LIBELLES = {
    patients: 'M1|Patients', documentsPatient: 'M1|Documents numérisés du patient',
    documents: 'GED|Bibliothèque documentaire',
    consultations: 'M2|Consultations et rendez-vous', support: 'M2|Registre des appels',
    admissions: 'M3|Admissions', soins: 'M3|Soins', observations: 'M3|Mises en observation', sortiesAvisMedical: 'M3|Sorties contre avis médical',
    suiviMaternite: 'M4|Suivi maternité', accouchements: 'M4|Accouchements',
    dossiersObstetricaux: 'M4|Dossiers obstétricaux',
    naissances: 'M4|Naissances', deces: 'M4|Décès',
    grossesses: 'M4|Suivi CPN & carte maternelle', partogrammes: 'M4|Partogrammes',
    cpon: 'M4|Consultations post-natales', planificationFamiliale: 'M4|Planification familiale',
    registreSONU: 'M4|Registre SONUB / SONUC', ptme: 'M4|Registre PTME',
    soinsCuratifsMaternite: 'M4|Soins curatifs & urgences maternité',
    demandesAnalyses: 'M5|Demandes d’analyses', analyses: 'M5|Catalogue des analyses',
    plagesReactif: 'M5|Plages de référence par lot de réactif',
    actes: 'CFG|Catalogue des actes', ordonnances: 'M2|Ordonnances', taches: 'CFG|Files d’attente',
    certificats: 'CFG|Certificats médicaux', naturesFacture: 'CFG|Natures de facture', centresCouts: 'M12|Centres de coûts',
    objectifsPilotage: 'M12|Objectifs et seuils du pilotage',
    banques: 'M12|Comptes de trésorerie', depenses: 'M12|Dépenses de trésorerie', souscripteurs: 'M9|Souscripteurs', garanties: 'M9|Garanties de prise en charge',
    couverturesAssurance: 'M9|Couvertures d’assurance (historique)',
    avoirs: 'M8|Factures d’avoir', pvReceptions: 'M7|PV de réception',
    secteurs: 'CFG|Secteurs de la clinique', postes: 'CFG|Postes de l’organigramme',
    ressources: 'CFG|Ressources graphiques',
    poches: 'M5|Banque de sang', donneurs: 'M5|Donneurs',
    produits: 'M6|Produits et médicaments', lots: 'M6|Lots', mouvements: 'M6|Mouvements de stock',
    transferts: 'M6|Transferts', inventaires: 'M6|Inventaires', dispensations: 'M6|Dispensations',
    besoins: 'M7|Bons de besoins', commandes: 'M7|Commandes', livraisons: 'M7|Livraisons',
    fournisseurs: 'M7|Fournisseurs', facturesFournisseurs: 'M7|Factures fournisseurs',
    factures: 'M8|Factures', remboursements: 'M8|Remboursements', avoirs: 'M8|Avoirs',
    assureurs: 'M9|Compagnies d’assurance', releves: 'M9|Relevés', relances: 'M9|Relances',
    personnel: 'M10|Personnel', contrats: 'M10|Contrats', planning: 'M10|Planning',
    presences: 'M10|Présences', conges: 'M10|Congés', evaluations: 'M10|Évaluations',
    prestataires: 'M10|Prestataires', assurancesPersonnel: 'M10|Assurances du personnel', missions: 'M10|Ordres de mission',
    bulletins: 'M11|Bulletins de paie', heuresSup: 'M11|Heures supplémentaires', avances: 'M11|Avances',
    comptes: 'M12|Plan comptable', ecritures: 'M12|Écritures', budgets: 'M12|Budgets',
    immobilisations: 'M12|Immobilisations', rapprochements: 'M12|Rapprochements bancaires',
    echeancesFiscales: 'M12|Échéances fiscales',
    regimesTravail: 'M10|Régimes de travail par catégorie',
    modulesActifs: 'CFG|Activité des modules', notifications: 'M14|Notifications',
    emplacements: 'M6|Emplacements de rangement',
    baremeNS131: 'M10|Barème d’évaluation NS 131', historiqueBareme: 'M10|Versions antérieures du barème',
    rbac2: 'M14|Surcharges RBAC',
    pathologies: 'M2|Référentiel des pathologies',
    examensLabo: 'M5|Catalogue des examens', unitesLabo: 'M5|Unités de mesure',
    variablesLabo: 'M5|Variables et valeurs de référence',
    evenements: 'M10|Événements du personnel', participations: 'M10|Participations aux événements',
    grillePrimes: 'M10|Grille des primes NS 132', historiquePrimes: 'M10|Versions antérieures de la grille des primes',
    rbac: 'M14|Rôles et permissions', tentativesConnexion: 'M14|Tentatives de connexion refusées',
    courriers: 'M13|Courriers', reunions: 'M13|Réunions',
    /* Une clé déclarée deux fois dans un littéral écrase la première EN
       SILENCE : « evenements » désignait ici les événements de M13 et effaçait
       l'intitulé de ceux du personnel. Les deux collections sont désormais
       distinctes, et leurs intitulés aussi. */
    evenementsEtablissement: 'M13|Événements de l’établissement',
    planAnnuel: 'M13|Plan annuel', ambulance: 'M13|Ambulance',
    releves: 'M3|Relevés de constantes au lit du patient',
    resultatsImagerie: 'M2|Comptes rendus d’imagerie',
    demandesImagerie: 'M2|Demandes d’imagerie',
    enquetes: 'M13|Modèles d’enquête',
    reponsesEnquetes: 'M13|Réponses d’enquête',
    jetonsEnquete: 'M13|Liens de partage des enquêtes',
    badges: 'M10|Badges du personnel', modelesBadge: 'M10|Modèles de badge',
    clichesImagerie: 'M2|Clichés d’échographie',
    examensImagerie: 'CFG|Catalogue des examens d’imagerie',
    variablesImagerie: 'CFG|Variables des comptes rendus d’imagerie',
    fichesReference: 'M1|Fiches de référence',
    contreReferences: 'M1|Fiches de contre-référence',
    surveillancesTransfusion: 'M3|Surveillances transfusionnelles',
    scoresGlasgow: 'M3|Scores de Glasgow',
    rapportsMedicaux: 'M3|Rapports médicaux',
    fileAttente: 'M2|File d’attente',
    fichesPoste: 'M10|Fiches de poste',
    pretsEtudes: 'M11|Prêts-études et avances',
    facturesMere: 'M9|Factures mères d’assurance',
    ambulances: 'M13|Répertoire des ambulances',
    materiel: 'M13|Parc technique',
    valorisationsSage: 'M6|Valorisations de la reprise SAGE',
    dossiersConsultation: 'M1|Dossiers de consultation',
    modelesMessage: 'CFG|Modèles de message',
    rappels: 'CFG|Rappels',
    soignants: 'M14|Prescripteurs et exécutants de soins',
    prescriptions: 'M2|Prescriptions',
    administrations: 'M3|Administrations de traitement',
    crOperatoires: 'M3|Comptes rendus opératoires',
    checklistsBloc: 'M3|Check-listes du bloc',
    cpa: 'M3|Consultations pré-anesthésiques',
    crAnesthesie: 'M3|Comptes rendus d’anesthésie',
    crMaternite: 'M4|Comptes rendus de maternité',
    catalogueTarifs: 'CFG|Catalogue tarifaire',
    typesPiece: 'CFG|Types de pièces certifiantes',
    pieces: 'M1|Pièces certifiantes délivrées',
    utilisateurs: 'M14|Utilisateurs', audit: 'M14|Journal d’audit',
  };

  function libelleCollection(nom) {
    var t = (LIBELLES[nom] || '—|' + nom).split('|');
    return { module: t[0], entite: t[1] };
  }

  /** Toutes les fiches archivées, tous modules confondus. */
  function corbeille() {
    load();
    var out = [];
    Object.keys(db).forEach(function (k) {
      if (k.charAt(0) === '_' || !Array.isArray(db[k])) return;
      var lib = libelleCollection(k);
      db[k].forEach(function (r) {
        if (!r || r.statut !== 'archive') return;
        out.push({
          id: k + ':' + r.id, refId: r.id, collection: k,
          module: lib.module, entite: lib.entite,
          libelle: r.nom ? (r.nom + ' ' + (r.prenom || '')).trim()
            : (r.libelle || r.designation || r.reference || r.numero || r.intitule || r.code || r.id),
          archiveLe: r._archiveLe || null,
          archivePar: r._archivePar || '—',
          motif: r._motifArchivage || null,
        });
      });
    });
    return out.sort(function (a, b) { return String(b.archiveLe || '').localeCompare(String(a.archiveLe || '')); });
  }

  /* ==========================================================================
   * BASCULES D'EXPLOITATION
   * --------------------------------------------------------------------------
   * Elles vivent dans le SOCLE et non dans un module : chaque page ne charge
   * que le module de son écran, si bien qu'une bascule déclarée dans
   * configuration.js serait invisible partout ailleurs — c'est exactement ce
   * qui est arrivé à celle du barème.
   *
   * Autorisation de modifier le barème NS 131 : condition posée par la
   * Direction — « on doit autoriser le CRUD depuis paramètres de setting ».
   * Un barème de sanctions ne se retouche pas au détour d'un écran
   * d'évaluation. Fermée, la modification est ABSENTE et non grisée.
   * ======================================================================== */
  global.SIGH.baremeModifiable = function () {
    return reglage('baremeModifiable', false) === true;
  };
  /** La porte du barème s'ouvre et se ferme DEPUIS LA BASE : fermée sur un
   *  poste, elle doit l'être sur tous. */
  global.SIGH.setBaremeModifiable = function (ouvert) {
    return setReglage('baremeModifiable', !!ouvert);
  };

  /**
   * Journalise un ACCÈS — une consultation, une recherche — sans passer par
   * collection().insert(), qui journaliserait à son tour et doublerait l'entrée.
   *
   * RG-12 impose de tracer les actions ; la Direction a demandé de tracer aussi
   * les CONSULTATIONS de dossier patient. Un journal qui se double lui-même
   * devient illisible au moment précis où l'on en a besoin.
   */
  function journaliserAcces(o) {
    load();
    var rec = {
      id: 'LOG' + C.uid(),
      dateHeure: new Date().toISOString(),
      utilisateur: o.utilisateur || currentUser(),
      role: o.role || null,
      action: o.action || 'Consultation',
      module: o.module || 'M14',
      entite: o.entite || 'Dossier patient',
      reference: o.reference || null,
      cible: o.cible || null,
      patientId: o.patientId || null,
      ecran: o.ecran || null,
      motif: o.motif || null,
      trouve: o.trouve !== false,
      ancienneValeur: null, nouvelleValeur: null,
      poste: 'POSTE-LOCAL', succes: true,
    };
    db.audit.unshift(rec);
    if (db.audit.length > 400) db.audit.length = 400;
    save();
    return rec;
  }

  global.SIGH.store = {
    enLot: enLot,
    journaliserAcces: journaliserAcces,
    load: load, save: save, reset: reset, collection: collection,
    COLLECTIONS_ESSENTIELLES: COLLECTIONS_ESSENTIELLES, viderActivite: viderActivite,
    jeuVide: jeuVide, amorcable: amorcable,
    hydraterServeur: hydraterServeur,
    surServeur: function () { return SRV.actif; },
    /** LE MAGASIN EN MAIN FAIT-IL AUTORITÉ ? Tant que l'hydratation est en
     *  vol, `collection()` rend une coquille PROVISOIRE ET VIDE : lire dedans
     *  ne renvoie pas « aucune fiche », cela renvoie « PAS ENCORE » — et les
     *  deux se ressemblent en tout point. Rien ne permettait de le savoir du
     *  dehors, si bien que les bancs d'essai attendaient un délai calibré à
     *  la main ; depuis la bascule ces délais tombent au milieu de
     *  l'hydratation, et la sonde conclut à une donnée absente. */
    faitAutorite: function () { return SRV.repondu === true && !_provisoire; },
    enPanne: function () { return PANNE.active; },
    motifPanne: function () { return PANNE.motif; },
    /** CE QUI N'A PAS ENCORE ATTEINT LA BASE — les DEUX chemins.
     *  Il y en a deux et il faut les compter tous : la file des actions
     *  nommées (créer, modifier, archiver) ET l'envoi global du magasin, qui
     *  porte les amorçages et les écritures en lot. N'attendre que la
     *  première laissait partir une page avant que la seconde ne soit
     *  arrivée — le banc retrouvait alors une fiche RBAC qu'il venait
     *  pourtant d'écrire. */
    fileEnAttente: function () {
      return FILE.actions.length + (FILE.enCours ? 1 : 0)
        + (_minuterie ? 1 : 0) + (SRV.enVol ? 1 : 0);
    },
    /** Force le départ immédiat de tout ce qui attend, sur les deux chemins. */
    pousserMaintenant: function () {
      if (FILE.minuterie) { clearTimeout(FILE.minuterie); FILE.minuterie = null; }
      if (_minuterie) { clearTimeout(_minuterie); _minuterie = null; ecrire(); }
      viderFile();
    },
    jetonServeur: function () { return SRV.jeton; },
    log: log, on: on, emit: emit,
    session: session, setSession: setSession, currentUser: currentUser, garder: garder,
    valorisationSortie: valorisationSortie, setValorisationSortie: setValorisationSortie,
    reglage: reglage, setReglage: setReglage,
    valeurUnitaire: valeurUnitaire,
    storage: storage,
    corbeille: corbeille, libelleCollection: libelleCollection,
    raw: function () { return load(); },
  };
})(window);
