/* =============================================================================
 * PARCOURS — chaîne transactionnelle inter-modules
 * -----------------------------------------------------------------------------
 * draf1 §24-25 : le prototype ne se juge pas au nombre d'écrans mais à sa
 * capacité à faire traverser plusieurs modules à une même opération. Ce fichier
 * porte cette traversée, décrite par la Direction :
 *
 *   le médecin prescrit  →  le gestionnaire de stock est informé des médicaments
 *                        →  le laborantin est informé des analyses, la demande
 *                           est établie d'office (la saisie manuelle reste
 *                           possible pour les patients venus de l'extérieur)
 *                        →  la caisse est informée, le patient règle, la caisse
 *                           valide  →  les médicaments sont délivrés et le
 *                           prélèvement est autorisé.
 *
 * Il est chargé sur toutes les pages, juste après `store` : la chaîne doit
 * fonctionner depuis la consultation comme depuis la caisse ou la pharmacie,
 * alors que chaque page ne charge que le module de son écran.
 *
 * Règles de gestion appliquées ici :
 *   RG-02  médicaments facturés au prix d'achat, sans marge ;
 *   RG-03  toute sortie porte un justificatif, le stock ne devient jamais négatif ;
 *   RG-12  chaque étape est journalisée, aucune action anonyme ;
 *   RG-14  rien n'est supprimé, tout est archivé.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, S = global.SIGH.store, D = global.SIGH.data;

  /* --- Files d'attente : à qui l'information est adressée ------------------ */
  var TACHES = {
    encaissement: {
      role: 'caissier', module: 'M8', ecran: 'm8-caisse',
      titre: 'Encaisser la prescription', icon: 'coins',
    },
    dispensation: {
      role: 'pharmacien', module: 'M6', ecran: 'm6-dispensation',
      titre: 'Délivrer les médicaments', icon: 'pill',
    },
    prelevement: {
      role: 'laborantin', module: 'M5', ecran: 'm5-demandes',
      titre: 'Prélever et analyser', icon: 'flask-conical',
    },
    acte: {
      role: 'infirmier', module: 'M3', ecran: 'm3-soins',
      titre: 'Exécuter les actes prescrits', icon: 'stethoscope',
    },
    /* Refonte Zone 2 : l'imagerie prescrite depuis la fiche de consultation
       entre dans la même chaîne que le prélèvement — informée tout de suite,
       exécutable après encaissement. */
    imagerie: {
      role: 'echographiste', module: 'M2', ecran: 'm2-dashboard-imagerie',
      titre: 'Réaliser l’examen d’imagerie', icon: 'scan-line',
    },
  };

  function col(nom) { return S.collection(nom, META[nom] || {}); }
  var META = {
    ordonnances: { module: 'M2', entite: 'ordonnance', prefix: 'ORD' },
    taches: { module: 'M14', entite: 'tâche', prefix: 'TCH' },
    demandesAnalyses: { module: 'M5', entite: 'demande d’analyse', prefix: 'DEM' },
    factures: { module: 'M8', entite: 'facture', prefix: 'FAC' },
    mouvements: { module: 'M6', entite: 'mouvement de stock', prefix: 'MVT' },
    prescriptions: { module: 'M2', entite: 'prescription', prefix: 'PRS' },
    administrations: { module: 'M3', entite: 'administration de traitement', prefix: 'ADM' },
    soignants: { module: 'M14', entite: 'soignant', prefix: 'SOI' },
  };

  /* ==========================================================================
   * RÉFÉRENTIELS DE TRAVAIL
   * ======================================================================== */
  function patients() { return S.collection('patients').active(); }
  function produits() { return S.collection('produits').active(); }

  function patientParCode(code) {
    var t = patients().filter(function (p) { return p.code === code; });
    return t[0] || null;
  }
  function produitParId(id) {
    var t = produits().filter(function (p) { return p.id === id; });
    return t[0] || null;
  }
  function analyseParCode(code) {
    var t = D.ANALYSES.filter(function (a) { return a.code === code; });
    return t[0] || null;
  }
  function acteParCode(code) {
    /* Le catalogue des actes vit dans le MAGASIN (administrable depuis
       cfg-tarifs) ; D.ACTES n'en est que la semence. Lire la constante ici,
       c'était facturer un tarif que l'écran de configuration ne pouvait plus
       corriger. */
    var t = S.collection('actes').active().filter(function (a) { return a.code === code; });
    return t[0] || null;
  }

  /* ==========================================================================
   * LE PRIX D'UNE PRESTATION À UNE DATE (PRD-TARIFS, lot T1)
   * --------------------------------------------------------------------------
   * UN SEUL accesseur pour toutes les voies de tarification : le prix est celui de la version EN VIGUEUR à la date de la PIÈCE (jamais l'horloge au moment
   * du calcul : une pièce saisie après coup avec une date passée prend le prix de sa date), sur la colonne que décide la validité de la carte à cette même
   * date (RG-09). Une prestation sans version valide à la date rend « absent » avec son motif : la ligne ne se facture pas, jamais un zéro.
   * La date se compare au JOUR (écart E4).
   * ======================================================================== */
  function colTarifs() { return S.collection('tarifs', { module: 'CFG', entite: 'prestation tarifée', prefix: 'TRF' }); }
  function colVersionsTarif() { return S.collection('versionsTarif', { module: 'CFG', entite: 'version de prix', prefix: 'VTR' }); }
  /* Les trois collections de LECTURE gardent leur module au schéma relationnel (le générateur lit la déclaration dans les sources) : leurs écrans d'édition ont quitté
     le code, la déclaration reste ici. */
  function colActes() { return S.collection('actes', { module: 'CFG', entite: 'acte', prefix: 'ACT' }); }
  function colAnalyses() { return S.collection('analyses', { module: 'M5', entite: 'analyse', prefix: 'ANA' }); }
  function colCatalogueTarifs() { return S.collection('catalogueTarifs', { module: 'CFG', entite: 'tarif', prefix: 'TAR' }); }
  function tarifALaDate(code, date, assure) {
    var TA = D.TARIFS, h = TA && TA.lire();
    if (!h) return { absent: true, montant: null, code: code, motif: 'Le référentiel de prix n’est pas chargé.' };
    var p = h.parCode[code];
    if (!p) return { absent: true, montant: null, code: code, motif: 'Prestation absente du référentiel de prix : « ' + code + ' ».' };
    var r = TA.resoudre(h, p, date, !!assure);
    r.libelle = p.libelle; r.famille = p.famille; r.espaces = { acte: p.codeActe || null, grille: p.codeGrille || null, analyse: p.codeAnalyse || null };
    return r;
  }
  /** LOT TARIF-FIX : le prix d'une ligne de prescription (`voie` 'acte' ou 'analyse') à la date de la pièce, ou « prix à définir » avec sa cause, son motif et son geste
      (`D.TARIFS.prixDeLigne`, moteur pur, vecteurs `tarifs.json`, section `ligne`). Jamais un zéro. */
  function prixLignePrescription(code, date, assure, voie) {
    var TA = D.TARIFS, h = TA.lire();
    if (!h) {
      /* Sans référentiel (semence en cours, page sans socle), les lecteurs retombent sur les constantes, comme avant (PRD-TARIFS, T1) ; une constante absente ou nulle
         reste « prix à définir ». */
      var x = voie === 'analyse' ? analyseParCode(code) : acteParCode(code);
      var m = !x ? null : (voie === 'analyse' ? x.prix : ((assure && x.assurable === true && !x.nonCouvert && x.prixAssure != null) ? x.prixAssure : x.prix));
      if (Number(m) > 0) return { ok: true, montant: Number(m), tarif: assure ? 'assuré' : 'non assuré', motif: null, prestation: code, libelle: x.libelle || x.designation || code, semence: true };
    }
    return TA.prixDeLigne(h, code, date, !!assure, voie);
  }
  /** Le prix d'un ACTE (espace des codes d'acte) selon la règle historique de la prescription : la colonne assurée ne s'applique que si l'acte est
      assurable ET porte un montant assuré ; sinon le prix non assuré. `undefined` : l'acte n'est pas au référentiel (repli sur la collection). */
  function prixActeALaDate(code, date, assure) {
    var TA = D.TARIFS, h = TA && TA.lire(), p = h && h.parActe[code];
    if (!p) return undefined;
    var s = TA.instantane(h, p, date);
    if (!s) return null;
    return (assure && p.assurable === true && s.etatAssure === 'montant') ? s.pa : s.na;
  }
  /** Le prix d'une ANALYSE (espace des codes d'analyse) : la colonne assurée vaut le prix unique tant qu'aucune version ne porte un montant assuré. */
  function prixAnalyseALaDate(code, date, assure) {
    var TA = D.TARIFS, h = TA && TA.lire(), p = h && h.parAnalyse[code];
    if (!p) return undefined;
    var s = TA.instantane(h, p, date);
    if (!s) return null;
    return (assure && s.etatAssure === 'montant') ? s.pa : s.na;
  }

  /** LOT TFIN (T7) : le tarif de la JOURNÉE d'un type de chambre (la prestation `HO01` à `HO03` du référentiel, dans l'ordre de `D.TYPES_CHAMBRE`) à la date dite (vide : aujourd'hui). `undefined`
      quand le type n'est pas une prestation du référentiel, `null` quand aucun prix n'est en vigueur. C'est la SEULE lecture du prix d'une chambre : `D.TYPES_CHAMBRE[i].tarif` n'est plus que la semence. */
  function prixChambreALaDate(typeId, date) {
    var types = D.TYPES_CHAMBRE || [], i = -1;
    types.forEach(function (t, k) { if (t.id === typeId) i = k; });
    if (i < 0) return undefined;
    return prixActeALaDate('HO' + (i < 9 ? '0' : '') + (i + 1), date, false);
  }

  /* --------------------------------------------------------------------------
   * LE PRIX D'UN PRODUIT À UNE DATE (PRD-TARIFS, lot T5) : le MÊME moteur de version que les prestations, famille `PRODUIT`.
   * Le prix d'achat est celui de la version EN VIGUEUR à la date de la PIÈCE (jamais la fiche, jamais l'horloge au moment du calcul) ; le prix de vente se DÉRIVE de la
   * catégorie (RG-02 : un médicament se vend à son prix d'achat) et de la version. Un prix d'achat absent est un `manquant` : l'accesseur rend « absent » avec son motif, et
   * l'article ne se facture JAMAIS à zéro. Un produit que personne n'a encore doté de sa prestation de prix (fiche posée par un outil) reçoit sa version 1 « reprise » ici.
   * -------------------------------------------------------------------------- */
  function produitDeCode(code) {
    return S.collection('produits').all().filter(function (p) { return p.code === code && p.statut !== 'archive'; })[0] || null;
  }
  function prixProduitALaDate(produit, date) {
    var TA = D.TARIFS, h = TA && TA.lire();
    if (!produit || !produit.code) return { absent: true, achat: null, vente: null, motif: 'Produit inconnu.' };
    if (!h) return { absent: true, achat: null, vente: null, motif: 'Le référentiel de prix n’est pas chargé.' };
    var p = h.parProduit[produit.code];
    if (!p && S.assurerTarifProduit && S.assurerTarifProduit(produit)) { h = TA.lire(); p = h && h.parProduit[produit.code]; }
    if (!p) return { absent: true, achat: null, vente: null, motif: 'Produit absent du référentiel de prix : « ' + produit.code + ' ».' };
    var jour = TA.jourDe(date), v = TA.enVigueur(h, p.code, jour);
    if (!v) return { absent: true, achat: null, vente: null, motif: 'Aucune version de prix d’achat valide à la date du ' + jour + ' pour « ' + (produit.designation || produit.code) + ' ».' };
    var achat = TA.prixAchatDe(v);
    if (achat == null) return { absent: true, achat: null, vente: null, version: v.version, dateEffet: v.dateEffet || null,
      motif: 'Le prix d’achat de « ' + (produit.designation || produit.code) + ' » n’est pas renseigné (à valider) : l’article ne se facture jamais à zéro.' };
    return { absent: false, achat: achat, vente: TA.prixVenteProduit(produit.categorie, v), version: v.version, dateEffet: v.dateEffet || null, code: produit.code };
  }
  /** LES PRODUITS « À VALORISER » (lot T5b, décision de la Direction du 12/11/2026) : les articles actifs dont AUCUN prix d'achat n'est en vigueur aujourd'hui (version 1 `manquant`,
      créée par la reprise du Grand Stock dont le stock existe déjà : RG-03). Source UNIQUE de la liste (« Tarifs et prix », onglet Produits ; « Référentiel produits »), de l'indicateur
      et de l'alerte de la Directrice Administrative : trois lectures d'une même population ne se recomptent pas à part. Une fiche posée sans identité de prix n'en fait pas partie
      (elle reçoit la sienne à l'ouverture d'un écran) ; une proposition en attente ne la sort PAS de la liste : seul le Oui, qui met un prix en vigueur, le fait. */
  function produitsAValoriser(date) {
    var TA = D.TARIFS, h = TA && TA.lire();
    if (!h) return [];
    var jour = TA.jourDe(date || C.aujourdhui()), out = [];
    S.collection('produits').all().forEach(function (pr) {
      if (pr.statut === 'archive') return;
      var p = h.parProduit[pr.code];
      if (!p) return;
      var v = TA.enVigueur(h, p.code, jour);
      if (v && TA.prixAchatDe(v) != null) return;
      var attente = (h.vers[p.code] || []).filter(function (x) { return x.statut === 'propose'; }).length;
      out.push({ produit: pr, code: pr.code, designation: pr.designation, raison: 'prix d’achat non renseigné', enAttente: attente > 0 });
    });
    return out;
  }
  /** UNE RÉCEPTION À UN AUTRE PRIX (lot T5b, décision de la Direction du 12/11/2026). Le prix de réception est celui de la ligne reçue (prix unitaire du bon de commande) ; quand il diffère du
      prix d'achat en vigueur à la DATE DE RÉCEPTION, une PROPOSITION de changement du prix d'achat s'ouvre par `proposerTarif` (famille PRODUIT, date d'effet = date de réception, motif « prix
      constaté à la réception n° … »), soumise à l'alerte et au Oui ou Non du circuit existant. Elle NE BLOQUE JAMAIS la réception : le CUMP, le stock et le mouvement sont écrits avant, par le
      geste de l'écran, et un refus du moteur (date antérieure réservée, pièce déjà émise depuis cette date, droit) se dit sans rien défaire. UNE SEULE proposition ouverte par produit : si l'une
      attend déjà son Oui ou son Non, la réception le dit et n'en ouvre pas une seconde. Un prix identique ne propose rien. Le prix en vigueur, le prix de vente dérivé d'un médicament (RG-02)
      et les pièces émises ne bougent QU'AU OUI : une proposition ne change rien. Rend `{ etat: 'ouverte' | 'identique' | 'deja_ouverte' | 'refusee' | 'sans_objet', ... }`. */
  function proposerPrixReception(o) {
    o = o || {};
    var pr = o.produit, prix = Number(o.prixRecu);
    if (!pr || !pr.code || !entierPositif(prix)) return { etat: 'sans_objet', motif: 'prix de réception non renseigné' };
    var TA = D.TARIFS, jour = TA.jourDe(o.date || C.aujourdhui());
    var en = prixProduitALaDate(pr, jour);
    if (!en.absent && en.achat === prix) return { etat: 'identique', code: pr.code, prix: prix };
    var h = TA.lire(), p = h && h.parProduit[pr.code];
    if (!p) return { etat: 'sans_objet', code: pr.code, motif: 'produit sans prix versionné' };
    var attente = (h.vers[p.code] || []).filter(function (x) { return x.statut === 'propose'; })[0];
    if (attente) return { etat: 'deja_ouverte', code: pr.code, version: attente.version, prix: attente.prixNonAssure };
    var ref = String(o.reference || '').trim();
    var passee = jour < jourTarif(null);
    var r = proposerTarif({ code: pr.code, prixNonAssure: prix, dateEffet: jour, datePassee: passee ? true : undefined,
      motif: 'prix constaté à la réception n° ' + ref, source: 'Réception ' + ref, reception: { reference: ref } });
    if (!r.ok) return { etat: 'refusee', code: pr.code, refus: { code: r.code, motif: r.motif, geste: r.geste } };
    return { etat: 'ouverte', code: pr.code, ancien: en.absent ? null : en.achat, prix: prix, dateEffet: jour, version: r.version };
  }
  /** Le refus d'un article créé sans prix d'achat (lot T5b) : code, motif, geste. Un tiret n'est pas un zéro, et zéro n'est pas un prix : l'article ne se crée pas. Le seul cas où un article
      naît sans prix est la reprise du Grand Stock (le stock existe déjà), qui le marque « à valoriser » et le rend non facturable. */
  function refusPrixAchatAbsent(code, designation) {
    return refusTarif('PRIX_ACHAT_ABSENT',
      'le prix d’achat de l’article « ' + [code, designation].filter(Boolean).join(' : ') + ' » n’est pas renseigné (absent, tiret ou nul) : un article sans prix d’achat ne se crée pas',
      'Renseignez son prix d’achat en FCFA. Si le stock existe déjà, passez par « Importation Grand Stock » : l’article y est créé « à valoriser », sans prix facturable, jusqu’à la décision d’un premier prix.');
  }
  /** Le prix d'achat (RG-02) d'un produit à la date de la pièce : un nombre, ou `null` quand il est absent. */
  function prixAchatALaDate(produit, date) { var r = prixProduitALaDate(produit, date); return r.absent ? null : r.achat; }
  /** Le prix de vente DÉRIVÉ d'un produit à la date de la pièce : un nombre, ou `null`. */
  function prixVenteALaDate(produit, date) { var r = prixProduitALaDate(produit, date); return r.absent ? null : r.vente; }

  /* ==========================================================================
   * PROPOSER UN PRIX, DÉCIDER OUI OU NON (PRD-TARIFS, lot T2 : le noyau ; le lot T3 y ajoute le contrôle d'usage, l'alerte, la notification et l'import)
   * --------------------------------------------------------------------------
   * Deux droits DISTINCTS. PROPOSER est le droit d'éditer l'écran « Tarifs et prix » ; DÉCIDER (Oui ou Non) est porté par la LISTE DE RÔLES de la famille,
   * jamais par `editer` : un `editer` sur l'écran ne vaut pas décision. Le moteur refuse aussi : masquer un bouton ne protège rien.
   * Une proposition ne change RIEN : le prix en vigueur ne bouge qu'au Oui, à la date d'effet. Le Non exige son motif et reste lisible à l'historique.
   * Un refus se nomme : code, motif, geste.
   * ======================================================================== */
  var ROLES_VALIDATION_TARIFS = ['admin', 'da', 'direction'];
  /* T6 (Direction, 11/11/2026) : la date d'effet PASSÉE est une autorité de la Directrice Administrative et de la Direction, avec un motif. */
  var ROLES_DATE_PASSEE = ['da', 'direction'];
  function refusTarif(code, motif, geste) { return { ok: false, code: code, motif: motif, geste: geste }; }
  function roleDeLaSession() { var s = S.session(); return s && s.role; }
  function peutDeciderTarif() { return ROLES_VALIDATION_TARIFS.indexOf(roleDeLaSession()) >= 0; }
  function peutDatePasseeTarif() { return ROLES_DATE_PASSEE.indexOf(roleDeLaSession()) >= 0; }
  function profilsDatePassee() { return ROLES_DATE_PASSEE.map(function (r) { return libelleRole(r); }).join(' et '); }
  function peutProposerTarif() {
    var N = global.SIGH.nav, r = roleDeLaSession();
    if (!N || !N.droitsEcran) return ROLES_VALIDATION_TARIFS.indexOf(r) >= 0;
    var d = N.droitsEcran(r, 'cfg-tarifs', 'CFG');
    return !!(d && d.editer);
  }
  /** PROPOSER PAR L'IMPORT (lot IMP-A, I4) : le droit est celui d'IMPORTER le jeu `tarifs`, non celui d'éditer l'écran « Tarifs et prix » : le gestionnaire de stock importe des prix sans
      pouvoir éditer cet écran (CFG lui est fermé). Ce que l'import peut devenir (proposition ou, avec le droit de décider, version validée) reste réglé par la MÊME fonction. */
  function peutProposerParImport() {
    var N = global.SIGH.nav;
    return !!(N && N.droitImport && N.droitImport(roleDeLaSession(), 'tarifs').importer);
  }
  /** PROPOSER LE PRIX D'ACHAT D'UN PRODUIT (lot T5) : le droit est celui de MODIFIER « Référentiel produits » (M6), ou celui d'IMPORTER le jeu `tarifs-produits` : jamais celui d'éditer
      « Tarifs et prix », que le gestionnaire de stock n'a pas. La CRÉATION d'une fiche produit (sa version 1) n'a pas d'autorité propre : l'acte est l'insertion de la fiche, que son écran
      ou son import a déjà contrôlée. Ce que la proposition peut devenir (proposition, ou version validée par un profil qui décide) reste réglé par les MÊMES fonctions. */
  function peutProposerProduit(o) {
    var N = global.SIGH.nav, r = roleDeLaSession();
    if (o && o.import && o.import.jeu) return !!(N && N.droitImport && N.droitImport(r, o.import.jeu).importer);
    /* LA RÉCEPTION D'UN ACHAT (lot T5b) : la proposition naît du geste de réceptionner, dont l'autorité est celle de MODIFIER l'écran des réceptions (M7), comme la création d'une fiche
       n'a pas d'autorité propre. Ce que la proposition peut devenir (Oui ou Non d'un profil qui décide) reste réglé par les MÊMES fonctions. */
    if (o && o.reception) { var dr = N && N.droitsEcran ? N.droitsEcran(r, 'm7-receptions', 'M7') : null; return !!(dr && dr.editer); }
    var d = N && N.droitsEcran ? N.droitsEcran(r, 'm6-produits', 'M6') : null;
    return !!(d && d.editer);
  }
  function auteurDeLaSession() { var s = S.session(); return (s && (s.nomComplet || s.nom)) || '(inconnu)'; }
  function versionsDe(code) {
    return colVersionsTarif().all().filter(function (v) { return v.code === code; })
      .sort(function (a, b) { return a.version - b.version; });
  }
  function jourTarif(d) { return D.TARIFS.jourDe(d); }
  function entierPositif(x) { return typeof x === 'number' && isFinite(x) && x > 0 && Math.floor(x) === x; }

  /* --- Le contrôle d'usage `tarif_deja_utilise` (PRD-TARIFS 4.4 et 5.6) -------------------------------------------------------------------------------- */
  /** Les pièces de VENTE non archivées qui portent déjà une ligne de cette prestation à la date d'effet ou après : un prix qui prendrait effet à cette date changerait
      après coup la réponse à « quel prix s'appliquait », alors que la ligne dit autre chose. Le contrôle se lit SUR LES LIGNES (acte, demande d'analyse, demande
      d'imagerie), sans collection d'usages. Une pro-forma n'est pas une pièce émise : elle se tient par sa durée de validité (T5). */
  function usagesTarif(p, dateEffet) {
    var codes = {};
    [p.code, p.codeActe, p.codeGrille, p.codeAnalyse].concat(p.codesAlias || []).forEach(function (c) { if (c) codes[c] = true; });
    var analyses = {}, imageries = {}, produits = {};
    S.collection('demandesAnalyses').all().forEach(function (d) { if (d.analyseCode) analyses[d.id] = d.analyseCode; });
    S.collection('demandesImagerie').all().forEach(function (d) { if (d.examenCode) imageries[d.id] = d.examenCode; });
    /* Une ligne de PRODUIT porte `produitId` : le contrôle d'usage d'un prix d'achat lit les mêmes lignes (lot T5). */
    if (p.famille === 'PRODUIT') S.collection('produits').all().forEach(function (x) { if (x.code === p.code) produits[x.id] = true; });
    var out = [];
    S.collection('factures').all().forEach(function (f) {
      if (!f || f.statut === 'archive' || f.proforma) return;
      var jour = f.date ? D.TARIFS.jourDe(f.date) : null;
      if (!jour || jour < dateEffet) return;
      var porte = (f.lignes || []).some(function (l) {
        return (l.acteCode && codes[l.acteCode]) || (l.demandeId && codes[analyses[l.demandeId]]) || (l.demandeImagerieId && codes[imageries[l.demandeImagerieId]]) || (l.produitId && produits[l.produitId]);
      });
      if (porte) out.push({ id: f.id, numero: f.numero, date: jour });
    });
    return out.sort(function (a, b) { return a.date < b.date ? -1 : (a.date > b.date ? 1 : String(a.numero).localeCompare(String(b.numero))); });
  }
  function refusUsage(code, dateEffet, usages, decision) {
    var u = usages[0];
    var r = refusTarif('TARIF_DEJA_UTILISE',
      'La facture ' + u.numero + ' du ' + C.dateFR(u.date) + ' porte déjà « ' + code + ' »' + (usages.length > 1 ? ' (et ' + (usages.length - 1) + ' autre(s) pièce(s) depuis cette date)' : '')
        + ' : un prix qui prendrait effet le ' + C.dateFR(dateEffet) + ' changerait après coup ce que la pièce dit.',
      decision
        ? 'Refuser cette proposition (Non), puis la reproposer avec une date d’effet postérieure à la dernière pièce, ou émettre un avoir pour corriger la pièce.'
        : 'Choisir une date d’effet postérieure à la dernière pièce, ou émettre un avoir pour corriger la pièce.');
    r.usages = usages.slice(0, 5); r.nbPieces = usages.length;
    return r;
  }
  /** Les pièces de vente portant la prestation sur les N derniers jours : l'information utile de l'alerte (ce que le changement touchera). */
  function piecesRecentesTarif(p, jours) {
    var fin = jourTarif(null), debut = C.iso(new Date(new Date(fin + 'T12:00:00').getTime() - jours * 86400000));
    return usagesTarif(p, debut).filter(function (u) { return u.date <= fin; }).length;
  }
  /** Une ligne de journal PAR TRANSITION (RG-12) : le journal est plafonné, l'historique d'un prix vit dans `versionsTarif`. Écrite AVANT l'écriture qui sauvegarde. */
  function journalPrix(action, v, extra) {
    var e = Object.assign({}, extra || {});
    if (e.motif) e.motif = String(e.motif).slice(0, 36);
    S.log('Changement de prix : ' + action, 'CFG', 'prix', v.code, null, Object.assign(e, { v: v.version, na: v.prixNonAssure, pa: v.prixAssure, du: v.dateEffet || null }));
  }
  /** La décision d'une version LÈVE le marquage « tarif d'attente » (E2366) : sur la fiche de lecture de l'acte ou de l'analyse (famille du centre des validations) et sur
      les versions marquées provisoires de la prestation. */
  function leverProvisoireDe(code) {
    var maj = 0, qui = auteurDeLaSession(), jour = C.iso(C.aujourdhui());
    versionsDe(code).forEach(function (x) {
      if (x.provisoire === true && x.statut === 'valide') { colVersionsTarif().update(x.id, { provisoire: false, arreteLe: jour, arretePar: qui }); maj++; }
    });
    return maj;
  }
  function leverMarquageTarif(code) {
    var h = D.TARIFS.lire(), p = h && h.parCode[code];
    if (!p) return;
    var V = global.SIGH.validations;
    [['actes', p.codeActe], ['analyses', p.codeAnalyse]].forEach(function (x) {
      if (!x[1]) return;
      var fiche = S.collection(x[0]).all().filter(function (f) { return f.code === x[1] && f.statut !== 'archive'; })[0];
      var e = fiche && V && V.etatValidation(x[0], fiche.id);
      if (e && e.enAttente) V.validerReferentiel(x[0], fiche.id);
    });
    leverProvisoireDe(code);
  }

  /** Valide les champs d'une version proposée. Rend un refus nommé, ou null. */
  function controleProposition(o) {
    var etatA = o.etatAssure || 'montant';
    if (o.prixNonAssure === null || o.prixNonAssure === undefined || o.prixNonAssure === '') {
      return refusTarif('PRIX_ABSENT', 'Le prix non assuré est absent : un prix vide n’est pas un tarif, la ligne ne se facturerait pas.', 'Saisir le prix non assuré.');
    }
    var na = Number(o.prixNonAssure);
    if (na === 0) return refusTarif('PRIX_ZERO', 'Un zéro n’est pas un tarif (arbitrage « plus aucun montant nul »).', 'Saisir un prix strictement positif ; la gratuité passe par la remise motivée ou la prise en charge du personnel.');
    if (!entierPositif(na)) return refusTarif('PRIX_INVALIDE', 'Le prix non assuré doit être un nombre entier de francs, strictement positif (le boîtier fiscal n’accepte que des montants entiers).', 'Corriger le prix non assuré.');
    if (['montant', 'nc', 'manquant', 'unique'].indexOf(etatA) < 0) return refusTarif('ETAT_ASSURE_INCONNU', 'La colonne assurée est un montant, NON COUVERT, non renseignée ou sans objet.', 'Choisir l’un de ces états.');
    if (etatA === 'montant') {
      var pa = Number(o.prixAssure);
      if (o.prixAssure === null || o.prixAssure === undefined || o.prixAssure === '') return refusTarif('PRIX_ABSENT', 'La colonne assurée annonce un montant, mais il est absent.', 'Saisir le prix assuré, ou choisir un autre état.');
      if (pa === 0) return refusTarif('PRIX_ZERO', 'Un zéro n’est pas un tarif (arbitrage « plus aucun montant nul »).', 'Saisir un prix strictement positif.');
      if (!entierPositif(pa)) return refusTarif('PRIX_INVALIDE', 'Le prix assuré doit être un nombre entier de francs, strictement positif.', 'Corriger le prix assuré.');
    }
    if (!String(o.motif || '').trim()) return refusTarif('MOTIF_REQUIS', 'Un changement de prix se motive : sans motif, la Direction ne peut pas décider.', 'Saisir le motif du changement.');
    return null;
  }

  /** La date d'effet d'une proposition : obligatoire ; antérieure à aujourd'hui seulement avec la case, par un profil qui en a l'autorité (T6). Rend `{ refus }` ou `{ passee }`. */
  function controleDateEffetTarif(o) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(o.dateEffet || ''))) return { refus: refusTarif('DATE_EFFET_REQUISE', 'Un changement de prix prend effet à une date : sans date d’effet, on ne sait pas à partir de quand il s’applique.', 'Saisir la date d’effet.') };
    var aujourdhui = jourTarif(null);
    var passee = o.dateEffet < aujourdhui;
    if (passee) {
      /* T6 : la date passée est PERMISE à la DAF et à la Direction, avec une case explicite (jamais silencieuse) et le motif déjà exigé ; refusée aux autres. */
      if (o.datePassee !== true) return { refus: refusTarif('DATE_PASSEE', 'La date d’effet (' + o.dateEffet + ') est antérieure à aujourd’hui (' + aujourdhui + ') : un prix ne se change pas dans le passé sans une décision expresse.',
        peutDatePasseeTarif() ? 'Cocher « Date antérieure à aujourd’hui » et motiver, ou choisir aujourd’hui ou une date future.' : 'Choisir aujourd’hui ou une date future : une date antérieure est une autorité de ' + profilsDatePassee() + '.') };
      if (!peutDatePasseeTarif()) return { refus: refusTarif('DATE_PASSEE_RESERVEE', 'Une date d’effet antérieure à aujourd’hui est une autorité de ' + profilsDatePassee() + '.', 'Choisir aujourd’hui ou une date future, ou demander cette date à l’un de ces profils.') };
    }
    return { passee: passee };
  }

  /** LES CONTRÔLES D'UNE PROPOSITION DE PRIX D'ACHAT (lot T5), sans rien écrire : le même gabarit que celui d'une prestation, avec ses règles propres. Le prix d'achat est la colonne
      « non assuré » de la version ; un produit n'a pas de colonne assurée (`unique`) ; RG-02 interdit au MÉDICAMENT un prix de vente libre ; un prix d'achat absent est refusé en changement
      (« un tiret n'est pas un zéro ») et accepté en CRÉATION de la fiche, où il se dit `manquant` : l'article ne se facture pas tant que personne ne l'a renseigné. */
  function evaluerPropositionProduit(o, h, p, viaImport) {
    var creation = !!o.creation, code = creation ? String(o.code || '').trim() : o.code;
    if (creation) {
      if (!code) return refusTarif('IDENTITE_INCOMPLETE', 'Un produit porte un code.', 'Renseigner le code de l’article.');
      if (p && p.famille !== 'PRODUIT') return refusTarif('CODE_EXISTANT', 'Le code « ' + code + ' » est déjà celui d’une prestation tarifée (' + (p.libelle || p.code) + ') : un article ne peut pas reprendre le code d’une prestation.', 'Choisir un autre code d’article.');
      if (p) return refusTarif('PRIX_DEJA_VERSIONNE', 'Le code « ' + code + ' » porte déjà un prix d’achat versionné : la création de la fiche ne pose pas une seconde version 1.', 'Changer le prix d’achat par « Changer le prix d’achat » (date d’effet, motif, Oui ou Non).');
    } else if (!p) return refusTarif('PRESTATION_INTROUVABLE', 'Aucun produit ne porte le code « ' + o.code + ' » au référentiel de prix.', 'Choisir un produit de la liste.');
    var pr = produitDeCode(code);
    if (!pr) return refusTarif('PRODUIT_INTROUVABLE', 'Aucun produit actif ne porte le code « ' + code + ' ».', 'Choisir un produit du Référentiel produits.');
    var brut = o.prixNonAssure, absent = brut === null || brut === undefined || brut === '', achat = absent ? null : Number(brut);
    if (absent && !creation) return refusTarif('PRIX_ABSENT', 'Le prix d’achat est absent : un prix vide n’est pas un tarif, l’article ne se facturerait pas.', 'Saisir le prix d’achat.');
    if (!absent && achat === 0) return refusTarif('PRIX_ZERO', 'Un zéro n’est pas un tarif (arbitrage « plus aucun montant nul ») : un article ne se facture jamais à zéro.', 'Saisir un prix d’achat strictement positif, ou laisser l’article « à valoriser » (sans prix).');
    if (!absent && !entierPositif(achat)) return refusTarif('PRIX_INVALIDE', 'Le prix d’achat doit être un nombre entier de francs, strictement positif (le boîtier fiscal n’accepte que des montants entiers).', 'Corriger le prix d’achat.');
    var venteBrute = o.prixVente, vente = (venteBrute === null || venteBrute === undefined || venteBrute === '') ? null : Number(venteBrute);
    if (vente != null && !entierPositif(vente)) return refusTarif('PRIX_INVALIDE', 'Le prix de vente doit être un nombre entier de francs, strictement positif.', 'Corriger le prix de vente, ou le laisser vide (il vaut alors le prix d’achat).');
    var med = pr.categorie === D.TARIFS.CATEGORIE_SANS_MARGE;
    var sActuel = !creation && p ? D.TARIFS.instantane(h, p, o.dateEffet) : null;
    if (med && vente != null && (absent || vente !== achat)) return refusTarif('RG02_MARGE', 'RG-02 : un médicament se facture au prix d’achat, sans marge : son prix de vente (' + C.num(vente) + ') ne peut pas différer de son prix d’achat' + (absent ? ' (absent)' : ' (' + C.num(achat) + ')') + '.',
      'Laisser le prix de vente vide : le prix de vente d’un médicament est son prix d’achat, il se dérive. Une exception se valide par la Direction.');
    if (!creation && !String(o.motif || '').trim()) return refusTarif('MOTIF_REQUIS', 'Un changement de prix se motive : sans motif, la Direction ne peut pas décider.', 'Saisir le motif du changement.');
    /* La CRÉATION n'a pas de date d'effet : la version 1 vaut « depuis l'origine » (aucun prix antérieur à protéger ; une pièce saisie après coup, ou une reprise de stock, se tarife à partir d'elle). */
    var cd = creation ? { passee: false } : controleDateEffetTarif(o);
    if (cd.refus) return cd.refus;
    var existantes = versionsDe(code);
    if (!creation) {
      var enAttente = existantes.filter(function (v) { return v.statut === 'propose'; })[0];
      if (enAttente) return refusTarif('CHANGEMENT_EN_ATTENTE', 'Une proposition est déjà en attente de décision pour « ' + code + ' » (version ' + enAttente.version + ').', 'La décider (Oui ou Non) ou la retirer avant d’en proposer une autre.');
      var s = sActuel;
      /* Hors médicament, un prix de vente NON renseigné est CONSERVÉ (le prix d'achat change, la décision commerciale du prix de vente n'est pas prise ici) ; pour l'égaler au prix d'achat, on le saisit. */
      if (!med && vente == null && s && s.vrs && s.vrs.prixVente != null) vente = s.vrs.prixVente;
      var venteNouvelle = med ? achat : (vente != null ? vente : achat), venteActuelle = s ? D.TARIFS.prixVenteProduit(pr.categorie, s.vrs) : null;
      if (s && s.na === achat && venteActuelle === venteNouvelle) return refusTarif('PRIX_INCHANGE', 'Ce prix d’achat est déjà celui en vigueur à cette date : rien à proposer.', 'Modifier le prix d’achat, ou ne rien changer.');
      var us = usagesTarif(p, o.dateEffet);
      if (us.length) return refusUsage(code, o.dateEffet, us, false);
    }
    var rang = existantes.reduce(function (m, v) { return Math.max(m, v.version || 0); }, 0) + 1;
    return { ok: true, plan: { code: code, p: p, h: h, rang: rang, etatA: 'unique', passee: cd.passee, viaImport: viaImport, enUnGeste: o.valider === true, produit: pr, achat: achat, absent: absent,
      venteLibre: (!med && vente != null && vente !== achat) ? vente : null } };
  }

  /** TOUS LES CONTRÔLES d'une proposition, SANS RIEN ÉCRIRE : la saisie à l'écran, l'import (vérification d'une ligne) et l'écriture passent par ELLE, jamais par un second chemin.
      Rend un refus nommé, ou `{ ok: true, plan }`. `o.import = { jeu: 'tarifs', lot }` change l'autorité de proposer (droit d'importer au lieu du droit d'éditer l'écran). */
  function evaluerProposition(o) {
    o = o || {};
    var viaImport = !!(o.import && (o.import.jeu === 'tarifs' || o.import.jeu === 'tarifs-produits'));
    /* LA FAMILLE `PRODUIT` (lot T5) suit le MÊME chemin, avec sa propre autorité et ses propres contrôles (prix d'achat, RG-02). */
    var h0 = D.TARIFS.lire(), p0 = h0 && h0.parCode[o.code];
    var estProduit = !!((p0 && p0.famille === 'PRODUIT') || (o.creation && o.creation.famille === 'PRODUIT'));
    if (estProduit && !o.creation && !peutProposerProduit(o)) {
      return viaImport
        ? refusTarif('PROPOSITION_RESERVEE', 'Proposer un prix d’achat par un fichier revient aux profils qui détiennent le droit d’importer le jeu « Importation des prix d’achat ».', 'Demander ce droit à l’administrateur (« Rôles & permissions », section Importation).')
        : refusTarif('PROPOSITION_RESERVEE', 'Changer le prix d’achat d’un produit se fait au « Référentiel produits », par un profil qui peut modifier cet écran.', 'Demander le changement au gestionnaire de stock, à la Directrice Administrative ou à l’administrateur.');
    }
    if (!estProduit && (viaImport ? !peutProposerParImport() : !peutProposerTarif())) {
      return viaImport
        ? refusTarif('PROPOSITION_RESERVEE', 'Proposer un prix par un fichier revient aux profils qui détiennent le droit d’importer le jeu « Importation des tarifs et prix ».', 'Demander ce droit à l’administrateur (« Rôles & permissions », section Importation).')
        : refusTarif('PROPOSITION_RESERVEE', 'Proposer un prix se fait depuis « Tarifs et prix », par un profil qui peut modifier cet écran.', 'Demander la modification à la Directrice Administrative ou à la Direction.');
    }
    /* VALIDER EN UN GESTE (PRD 5.4, Q3) : la liste de rôles de la famille décide, jamais le simple droit d'éditer ; le moteur refuse en nommant, il ne dégrade pas
       silencieusement une demande de validation en proposition. */
    if (o.valider === true && !peutDeciderTarif()) return refusTarif('VALIDATION_RESERVEE', 'Valider un changement de prix revient à la Direction, à la Directrice Administrative et à l’administrateur : valider n’est pas modifier la fiche.', 'Enregistrer le changement comme proposition : la décision revient à l’un de ces profils.');
    if (o.valider === true) { var gm = refusFileulValidation(familleAValider('prix')); if (gm) return gm; }
    var h = D.TARIFS.lire();
    if (!h) return refusTarif('REFERENTIEL_ABSENT', 'Le référentiel de prix n’est pas chargé.', 'Recharger la page.');
    var p = h.parCode[o.code];
    if (estProduit) return evaluerPropositionProduit(o, h, p, viaImport);
    if (o.creation) {
      if (p) return refusTarif('CODE_EXISTANT', 'Le code « ' + o.code + ' » existe déjà au référentiel (code ou alias) : un code ne se réutilise pas.', 'Choisir un autre code, ou proposer un changement de prix à la prestation existante.');
      /* LOT TARIF-FIX : le doublon CERT-APT ne doit pas renaître. Le code se compare NORMALISÉ (espaces aux bords, casse), dans les trois espaces, les alias et les
         prestations archivées : « cert-apt » ou « CERT-APT  » est le même code que CERT-APT. */
      var pris = D.TARIFS.codePris(h.tarifs, o.code);
      if (pris) return refusTarif('CODE_EXISTANT', 'Le code « ' + String(o.code).trim() + ' » est déjà pris au référentiel par « ' + pris.code + ' » (' + (pris.libelle || pris.code) + (pris.statut === 'archive' ? ', archivée' : '') + ') : un code ne se réutilise pas, même écrit autrement (casse, espaces).',
        'Choisir un autre code (pour un certificat : CERT- suivi du sigle de la pièce), ou proposer un changement de prix à la prestation existante.');
      if (!String(o.code || '').trim() || !String(o.creation.libelle || '').trim()) return refusTarif('IDENTITE_INCOMPLETE', 'Une prestation porte un code et un libellé.', 'Renseigner le code et le libellé.');
    } else if (!p) {
      return refusTarif('PRESTATION_INTROUVABLE', 'Aucune prestation ne porte le code « ' + o.code + ' ».', 'Choisir une prestation de la liste.');
    }
    var refus = controleProposition(o);
    if (refus) return refus;
    var cd = controleDateEffetTarif(o);
    if (cd.refus) return cd.refus;
    var passee = cd.passee;
    var code = o.creation ? String(o.code).trim() : p.code;
    var existantes = versionsDe(code);
    var enAttente = existantes.filter(function (v) { return v.statut === 'propose'; })[0];
    if (enAttente) return refusTarif('CHANGEMENT_EN_ATTENTE', 'Une proposition est déjà en attente de décision pour « ' + code + ' » (version ' + enAttente.version + ').', 'La décider (Oui ou Non) ou la retirer avant d’en proposer une autre.');
    var etatA = o.etatAssure || 'montant';
    if (p) {
      var s = D.TARIFS.instantane(h, p, o.dateEffet);
      if (s && s.na === Number(o.prixNonAssure) && s.etatAssure === etatA && (etatA !== 'montant' || s.pa === Number(o.prixAssure))) {
        return refusTarif('PRIX_INCHANGE', 'Ce prix est déjà celui en vigueur à cette date : rien à proposer.', 'Modifier au moins un des prix, ou ne rien changer.');
      }
      var us = usagesTarif(p, o.dateEffet);
      if (us.length) return refusUsage(code, o.dateEffet, us, false);
    }
    var rang = existantes.reduce(function (m, v) { return Math.max(m, v.version || 0); }, 0) + 1;
    return { ok: true, plan: { code: code, p: p, h: h, rang: rang, etatA: etatA, passee: passee, viaImport: viaImport, enUnGeste: o.valider === true } };
  }

  /** L'ÉCRITURE d'une proposition de prix d'achat (lot T5), après `evaluerPropositionProduit`. Une version est une fiche IMMUABLE : le prix d'achat est la colonne « non assuré », la colonne
      assurée vaut `unique`. La CRÉATION de la fiche produit pose la version 1 VALIDE d'emblée (aucun prix antérieur à changer : ce n'est pas un changement de prix), tracée avec le rôle de
      l'auteur ; tout CHANGEMENT d'un produit existant naît `propose` (alerte Oui ou Non), ou `valide` en un geste pour un profil qui décide (Q3). */
  function ecrireVersionProduit(o, plan) {
    var code = plan.code, pr = plan.produit, creation = !!o.creation, identite = null;
    if (creation) {
      identite = colTarifs().insert({ id: code, code: code, libelle: String(o.creation.libelle || pr.designation || code).trim(), famille: 'PRODUIT', statut: 'actif' });
      if (!identite) return refusTarif('ECRITURE_REFUSEE', 'Le magasin a refusé l’écriture de la prestation de prix du produit.', 'Réessayer ; le refus est au journal.');
    }
    var v = {
      id: code + '@' + (creation ? 'origine' : o.dateEffet) + '@' + plan.rang, code: code, version: plan.rang,
      prixNonAssure: plan.absent ? null : plan.achat, prixAssure: null, etatAssure: 'unique',
      motif: String(o.motif || '').trim(), origine: (plan.viaImport || o.import) ? 'import' : (creation ? 'creation' : 'ecran'), statut: 'propose',
      proposePar: auteurDeLaSession(), proposeLe: C.iso(C.aujourdhui()), proposeRole: roleDeLaSession(),
    };
    if (!creation) v.dateEffet = o.dateEffet;
    if (plan.absent) v.etatNonAssure = 'manquant';
    if (plan.venteLibre != null) v.prixVente = plan.venteLibre;
    if (plan.viaImport && o.import.lot) v.lot = o.import.lot;
    if (o.import && !plan.viaImport && o.import.lot) v.lot = o.import.lot;
    if (o.source) v.source = String(o.source).trim();
    if (plan.passee) v.datePassee = true;
    var valide = creation || o.valider === true;
    if (valide) {
      v.statut = 'valide'; v.decidePar = v.proposePar; v.decideLe = v.proposeLe; v.roleDecision = v.proposeRole;
      v.motifDecision = creation ? 'Première version du prix d’achat, posée à la création de l’article' + (o.import && o.import.lot ? ' (import ' + o.import.lot + ')' : '') : (plan.viaImport ? 'Validée à l’import ' + (o.import.lot || '') : 'Validée en un geste à la saisie');
    }
    journalPrix(creation ? 'création du prix d’achat' : (plan.viaImport ? (valide ? 'validation à l’import' : 'proposition à l’import') : (valide ? 'validation en un geste' : 'proposition')), v, { motif: v.motif, role: v.proposeRole, produit: code });
    var rec = colVersionsTarif().insert(v);
    if (!rec) return refusTarif('ECRITURE_REFUSEE', 'Le magasin a refusé l’écriture de la version.', 'Réessayer ; le refus est au journal.');
    D.TARIFS.invalider();
    /* Une création n'a rien à projeter (la fiche porte déjà ce prix) ; une validation en un geste met la fiche au pas. */
    if (!creation && valide) { leverMarquageTarif(code); S.projeterTarifs(); }
    return { ok: true, version: rec.record, identite: identite ? identite.record : null, creation: creation, valideeEnUnGeste: !creation && valide };
  }

  /** LA CRÉATION D'UNE FICHE PRODUIT pose la version 1 de son prix d'achat par la MÊME voie que tout changement de prix (`proposerTarif`, mode `creation`), jamais « à plat sur la
      fiche » : les écrans de création (Référentiel produits, nouvel article des achats) et les jeux d'import l'appellent juste après l'insertion de la fiche. Un prix d'achat absent ou nul
      pose un `manquant` : l'article se crée « à valoriser » et ne se facture pas tant que personne n'a renseigné son prix. `ctx` : { import: { jeu, lot }, source, motif }.
      Si la prestation de prix existe déjà (fiche recréée après une annulation, reprise), aucune seconde version 1 n'est posée : l'écart éventuel avec la fiche est rendu. */
  function creerPrixProduit(produit, ctx) {
    ctx = ctx || {};
    if (!produit || !produit.code) return refusTarif('PRODUIT_INTROUVABLE', 'Aucune fiche produit à doter d’un prix d’achat.', 'Créer la fiche produit d’abord.');
    var h = D.TARIFS.lire(), existant = h && h.parProduit[produit.code];
    if (existant) {
      var s = D.TARIFS.instantane(h, existant, null);
      var achatFiche = typeof produit.prixAchat === 'number' && produit.prixAchat > 0 ? produit.prixAchat : null;
      return { ok: true, reutilise: true, ecart: (s && s.na != null && achatFiche != null && s.na !== achatFiche) ? { fiche: achatFiche, enVigueur: s.na } : null };
    }
    var achat = typeof produit.prixAchat === 'number' && produit.prixAchat > 0 ? produit.prixAchat : null;
    var o = { code: produit.code, prixNonAssure: achat, creation: { famille: 'PRODUIT', libelle: produit.designation },
      motif: ctx.motif || (achat == null ? 'Article créé sans prix d’achat : à valoriser' : 'Création de l’article'), source: ctx.source || null };
    if (ctx.import) o.import = ctx.import;
    if (achat != null && produit.categorie !== D.TARIFS.CATEGORIE_SANS_MARGE && typeof produit.prixVente === 'number' && produit.prixVente > 0 && produit.prixVente !== achat) o.prixVente = produit.prixVente;
    return proposerTarif(o);
  }

  /** Propose une version de prix pour une prestation existante (ou, avec `creation`, crée la prestation et sa première version). `o.essai` : tous les contrôles, aucune écriture. */
  function proposerTarif(o) {
    o = o || {};
    var ev = evaluerProposition(o);
    if (!ev.ok) return ev;
    if (o.essai === true) return { ok: true, essai: true, creation: !!o.creation, valideeEnUnGeste: o.valider === true, rang: ev.plan.rang };
    if (ev.plan.produit) return ecrireVersionProduit(o, ev.plan);
    var code = ev.plan.code, rang = ev.plan.rang, etatA = ev.plan.etatA, passee = ev.plan.passee, viaImport = ev.plan.viaImport, identite = null;
    if (o.creation) {
      var c = o.creation, famille = c.famille;
      var ident = { id: code, code: code, libelle: String(c.libelle).trim(), famille: famille, statut: 'actif' };
      if (c.secteur) ident.secteur = c.secteur;
      if (c.source) ident.source = c.source;
      if (famille === 'ACTE' || famille === 'HOSPITALISATION') ident.codeActe = code;
      else if (famille === 'LABO') ident.codeAnalyse = code;
      else ident.codeGrille = code;
      if (o.assurable !== undefined) ident.assurable = o.assurable;
      identite = colTarifs().insert(ident);
    }
    var v = {
      id: code + '@' + o.dateEffet + '@' + rang, code: code, version: rang, dateEffet: o.dateEffet,
      prixNonAssure: Number(o.prixNonAssure), prixAssure: etatA === 'montant' ? Number(o.prixAssure) : null, etatAssure: etatA,
      motif: String(o.motif).trim(), origine: viaImport ? 'import' : 'ecran', statut: 'propose',
      proposePar: auteurDeLaSession(), proposeLe: C.iso(C.aujourdhui()), proposeRole: roleDeLaSession(),
    };
    if (viaImport && o.import.lot) v.lot = o.import.lot;
    if (o.source) v.source = String(o.source).trim();
    if (passee) v.datePassee = true;
    var enUnGeste = o.valider === true;
    if (enUnGeste) {
      /* Née VALIDE en un geste, avec le rôle de l'auteur tracé : la correction de la DAF n'attend pas la Direction. */
      v.statut = 'valide'; v.decidePar = v.proposePar; v.decideLe = v.proposeLe; v.roleDecision = v.proposeRole;
      v.motifDecision = viaImport ? 'Validée à l’import ' + (o.import.lot || '') : 'Validée en un geste à la saisie';
    }
    journalPrix(viaImport ? (enUnGeste ? 'validation à l’import' : 'proposition à l’import') : (enUnGeste ? 'validation en un geste' : 'proposition'), v, { motif: v.motif, role: v.proposeRole });
    var rec = colVersionsTarif().insert(v);
    if (!rec) return refusTarif('ECRITURE_REFUSEE', 'Le magasin a refusé l’écriture de la version.', 'Réessayer ; le refus est au journal.');
    D.TARIFS.invalider();
    if (enUnGeste) { leverMarquageTarif(code); S.projeterTarifs(); }
    return { ok: true, version: rec.record, identite: identite ? identite.record : null, creation: !!o.creation, valideeEnUnGeste: enUnGeste };
  }

  /** Décide une proposition : Oui (elle devient la version en vigueur à sa date d'effet) ou Non (refusée, motif obligatoire). */
  function deciderTarif(versionId, decision, o) {
    o = o || {};
    if (!peutDeciderTarif()) return refusTarif('VALIDATION_RESERVEE', 'Décider d’un changement de prix revient à la Direction, à la Directrice Administrative et à l’administrateur : valider n’est pas modifier la fiche.', 'Demander la décision à l’un de ces profils.');
    /* DAF = la mère (T11, 11/11/2026) : la décision est une écriture de configuration, tenue par la mère. Un fileul la refuse en nommant (même code que les validations de
       référentiels) ; la décision d'un fileul comme pièce de famille B appliquée par la mère est du lot du poste. */
    var gardeMere = refusFileulValidation(familleAValider('prix'));
    if (gardeMere) return gardeMere;
    if (decision !== 'oui' && decision !== 'non') return refusTarif('DECISION_INCONNUE', 'La décision est Oui ou Non.', 'Choisir Oui ou Non.');
    var col = colVersionsTarif(), v = col.get(versionId);
    if (!v) return refusTarif('VERSION_INTROUVABLE', 'Aucune version ne porte l’identifiant « ' + versionId + ' ».', 'Actualiser la liste des alertes.');
    if (v.statut !== 'propose') return refusTarif('DEJA_DECIDEE', 'Cette version est déjà « ' + v.statut + ' » : une décision ne se rejoue pas.', 'Proposer une nouvelle version si le prix doit encore changer.');
    var motif = String(o.motif || '').trim();
    var patch = { decidePar: auteurDeLaSession(), decideLe: C.iso(C.aujourdhui()), roleDecision: roleDeLaSession() };
    if (motif) patch.motifDecision = motif;
    if (decision === 'non') {
      if (!motif) return refusTarif('MOTIF_REQUIS', 'Un refus se motive : le service doit pouvoir lire pourquoi le changement n’est pas appliqué.', 'Saisir le motif du refus.');
      patch.statut = 'refuse';
    } else {
      if (v.prixNonAssure === null || v.prixNonAssure === undefined || v.etatNonAssure === 'manquant') return refusTarif('TARIF_ABSENT', 'Cette version ne porte pas de prix non assuré : elle ne se valide pas.', 'La refuser, puis proposer une version chiffrée.');
      var date = v.dateEffet || o.dateEffet;
      if (!/^\d{4}-\d{2}-\d{2}$/.test(String(date || ''))) return refusTarif('DATE_EFFET_REQUISE', 'Cette proposition n’a pas de date d’effet : la décision la fixe.', 'Saisir la date d’effet avec le Oui.');
      if (date < jourTarif(null)) {
        /* La date a été dépassée PENDANT l'attente, ou la proposition était datée du passé : aucun décalage automatique (PRD 5.6). Une date passée proposée
           expressément par la DAF ou la Direction se décide par elles seules. */
        if (!v.datePassee) return refusTarif('DATE_PASSEE', 'La date d’effet (' + date + ') est antérieure à aujourd’hui : la proposition a attendu au-delà de sa date, et un prix ne se change pas dans le passé.', 'Refuser cette proposition (Non), puis la reproposer avec une date d’effet d’aujourd’hui.');
        if (!peutDatePasseeTarif()) return refusTarif('DATE_PASSEE_RESERVEE', 'Une date d’effet antérieure à aujourd’hui se décide par ' + profilsDatePassee() + '.', 'Demander la décision à l’un de ces profils.');
      }
      /* Le contrôle d'usage est REJOUÉ au Oui : une pièce a pu être émise pendant l'attente. */
      var hh = D.TARIFS.lire(), pp = hh && hh.parCode[v.code];
      if (pp) { var us = usagesTarif(pp, date); if (us.length) return refusUsage(v.code, date, us, true); }
      patch.statut = 'valide';
      if (!v.dateEffet) patch.dateEffet = date;
    }
    journalPrix(decision === 'oui' ? 'validation' : 'refus', v, { motif: motif || null, role: roleDeLaSession() });
    var maj = col.update(versionId, patch);
    if (!maj) return refusTarif('ECRITURE_REFUSEE', 'Le magasin a refusé la décision.', 'Réessayer ; le refus est au journal.');
    D.TARIFS.invalider();
    if (decision === 'oui') { leverMarquageTarif(v.code); S.projeterTarifs(); }
    /* LE RETOUR À L'AUTEUR : « votre changement de prix a été accepté ou refusé, motif ». Une alerte dérivée ne peut pas porter un retour, la notification de poste le fait. */
    if (v.proposeRole && v.proposePar && v.proposePar !== auteurDeLaSession()) {
      notifier({ type: 'prix_decide', poste: v.proposeRole, destinataire: v.proposePar, reference: v.code, ecran: 'cfg-tarifs',
        priorite: decision === 'non' ? 'haute' : 'normale',
        libelle: 'Votre changement de prix ' + v.code + ' a été ' + (decision === 'oui' ? 'accepté' : 'refusé'),
        detail: (decision === 'oui' ? 'Il prend effet le ' + C.dateFR(patch.dateEffet || v.dateEffet) + '.' : 'Motif : ' + motif + '.') + ' Décidé par ' + auteurDeLaSession() + '.' });
    }
    return { ok: true, decision: decision, version: maj.record };
  }
  function retirerProposition(versionId, motif) {
    var col = colVersionsTarif(), v = col.get(versionId);
    if (!v) return refusTarif('VERSION_INTROUVABLE', 'Aucune version ne porte l’identifiant « ' + versionId + ' ».', 'Actualiser la liste.');
    if (v.statut !== 'propose') return refusTarif('DEJA_DECIDEE', 'Seule une proposition en attente se retire.', 'Une version décidée se remplace par une nouvelle version.');
    if (v.proposePar !== auteurDeLaSession() && !peutDeciderTarif()) return refusTarif('RETRAIT_RESERVE', 'Une proposition se retire par son auteur, ou par un profil qui décide.', 'Demander le retrait à son auteur.');
    journalPrix('retrait', v, { motif: motif || null, role: roleDeLaSession() });
    var maj = col.update(versionId, { statut: 'retire', decidePar: auteurDeLaSession(), decideLe: C.iso(C.aujourdhui()), roleDecision: roleDeLaSession(), motifDecision: String(motif || 'Retirée par son auteur') });
    D.TARIFS.invalider();
    return maj ? { ok: true, version: maj.record } : refusTarif('ECRITURE_REFUSEE', 'Le magasin a refusé le retrait.', 'Réessayer.');
  }

  /* --- « Oui à tout », ENCADRÉ (PRD 5.3, Q8) -------------------------------------------------------------------------------------------------------------- */
  /** Le seuil de variation que la Direction décide de SIGNALER : AUCUNE valeur proposée (aucun document ne la fixe), vide par défaut. Au-delà, la ligne n'est jamais
      acceptée en bloc : elle se décide seule. */
  function seuilVariationAlerte() {
    var x = S.reglage('tarifsVariationAlertePct', null);
    return typeof x === 'number' && isFinite(x) && x > 0 ? x : null;
  }
  function variationPropositionPct(v) {
    var h = D.TARIFS.lire(), p = h && h.parCode[v.code];
    var s = p ? D.TARIFS.instantane(h, p, v.dateEffet || jourTarif(null)) : null;
    return s && s.na && v.prixNonAssure != null && v.etatNonAssure !== 'manquant' ? Math.round((v.prixNonAssure - s.na) / s.na * 1000) / 10 : null;
  }
  /** Décide Oui chaque proposition de la liste (toutes celles en attente par défaut), JAMAIS sans que la comparaison ligne à ligne ait été affichée (`comparaisonAffichee`).
      Chaque ligne passe par la décision ordinaire (contrôle d'usage, date, droit) : celles qui ne passent pas sont NOMMÉES avec leur refus, les autres sont acceptées. */
  function deciderTousTarifs(o) {
    o = o || {};
    if (!peutDeciderTarif()) return refusTarif('VALIDATION_RESERVEE', 'Décider d’un changement de prix revient à la Direction, à la Directrice Administrative et à l’administrateur : valider n’est pas modifier la fiche.', 'Demander la décision à l’un de ces profils.');
    var gardeMereT = refusFileulValidation(familleAValider('prix'));
    if (gardeMereT) return gardeMereT;
    if (o.comparaisonAffichee !== true) return refusTarif('COMPARAISON_REQUISE', 'Un « Oui à tout » ne se donne qu’après l’affichage de la comparaison ligne à ligne (ancien prix, nouveau prix, variation).', 'Ouvrir la comparaison, la lire, puis confirmer.');
    var enAttente = colVersionsTarif().all().filter(function (v) { return v.statut === 'propose'; });
    var ids = o.ids || enAttente.map(function (v) { return v.id; });
    var seuil = seuilVariationAlerte();
    var acceptees = [], refusees = [], exclues = [];
    ids.forEach(function (id) {
      var v = colVersionsTarif().get(id);
      if (!v || v.statut !== 'propose') { refusees.push({ id: id, code: v ? v.code : null, refus: 'DEJA_DECIDEE', motif: 'Cette version n’est plus en attente.' }); return; }
      var pct = variationPropositionPct(v);
      if (seuil != null && pct != null && Math.abs(pct) > seuil) { exclues.push({ id: id, code: v.code, variation: pct, motif: 'Variation de ' + pct + ' % au-delà du seuil signalé (' + seuil + ' %) : à décider seule.' }); return; }
      var r = deciderTarif(id, 'oui', { dateEffet: o.dateEffet || null });
      if (r.ok) acceptees.push({ id: id, code: v.code }); else refusees.push({ id: id, code: v.code, refus: r.code, motif: r.motif, geste: r.geste });
    });
    S.log('Changement de prix : Oui à tout', 'CFG', 'prix', 'lot', null, { oui: acceptees.length, refus: refusees.length, exclus: exclues.length, role: roleDeLaSession() });
    S.save();
    return { ok: true, acceptees: acceptees, refusees: refusees, exclues: exclues };
  }

  /* ==========================================================================
   * LA PRO-FORMA À LA CONVERSION (T5, Direction, 11/11/2026)
   * --------------------------------------------------------------------------
   * Une pro-forma est une estimation non fiscale. Convertie en vente, elle se facture AU PRIX DU JOUR, avec l'ÉCART affiché, sauf pendant une durée réglable
   * (30 jours proposés, « à valider », réglage en base) : dans ce délai, le prix de la pro-forma est tenu. Ce moteur dit, ligne par ligne, quel prix s'applique et de
   * combien il s'écarte ; il n'écrit aucune pièce. La maquette n'a pas de geste « convertir » : émettre la vente passe par l'écran d'émission, qui prend le prix du jour.
   * ======================================================================== */
  var VALIDITE_PROFORMA_DEFAUT = 30, VALIDITE_PROFORMA_BORNES = [0, 365];
  function validiteProformaJours() {
    var x = Number(S.reglage('tarifsValiditeProformaJours', VALIDITE_PROFORMA_DEFAUT));
    return isFinite(x) && x === Math.floor(x) && x >= VALIDITE_PROFORMA_BORNES[0] && x <= VALIDITE_PROFORMA_BORNES[1] ? x : VALIDITE_PROFORMA_DEFAUT;
  }
  function definirValiditeProforma(o) {
    o = o || {};
    if (!peutDeciderTarif()) return refusTarif('REGLAGE_RESERVE', 'La durée de validité d’une pro-forma se règle par la Direction, la Directrice Administrative ou l’administrateur.', 'Demander le réglage à l’un de ces profils.');
    var j = Number(o.jours);
    if (o.jours === '' || o.jours === null || o.jours === undefined || !isFinite(j) || j !== Math.floor(j) || j < VALIDITE_PROFORMA_BORNES[0] || j > VALIDITE_PROFORMA_BORNES[1]) {
      return refusTarif('DUREE_INVALIDE', 'La durée de validité est un nombre entier de jours, de ' + VALIDITE_PROFORMA_BORNES[0] + ' à ' + VALIDITE_PROFORMA_BORNES[1] + '.', 'Saisir un nombre entier de jours.');
    }
    var avant = validiteProformaJours();
    S.log('Validité d’une pro-forma', 'CFG', 'reglage', 'tarifsValiditeProformaJours', { jours: avant }, { jours: j, motif: o.motif || null });
    S.setReglage('tarifsValiditeProformaJours', j);
    return { ok: true, jours: j, avant: avant };
  }
  function ecartProforma(factureId, dateConversion) {
    var f = S.collection('factures').all().filter(function (x) { return x.id === factureId; })[0];
    if (!f) return refusTarif('FACTURE_INTROUVABLE', 'Aucune facture ne porte l’identifiant « ' + factureId + ' ».', 'Choisir une pro-forma de la liste.');
    if (!f.proforma) return refusTarif('PAS_UNE_PROFORMA', 'La pièce ' + f.numero + ' est une vente : elle garde son prix (une pièce émise ne se réécrit pas).', 'Choisir une pro-forma.');
    var conv = dateConversion ? D.TARIFS.jourDe(dateConversion) : jourTarif(null);
    var jourPro = D.TARIFS.jourDe(f.date), age = C.daysBetween(jourPro, conv), validite = validiteProformaJours();
    var regle = age <= validite ? 'prix_de_la_proforma' : 'prix_du_jour';
    var patient = patientParCode(f.patientCode), assure = patient ? carteValide(patient, conv) : false;
    var analyses = {}, imageries = {};
    S.collection('demandesAnalyses').all().forEach(function (d) { if (d.analyseCode) analyses[d.id] = d.analyseCode; });
    S.collection('demandesImagerie').all().forEach(function (d) { if (d.examenCode) imageries[d.id] = d.examenCode; });
    var ecartTotal = 0;
    var lignes = (f.lignes || []).map(function (l) {
      var code = l.acteCode || (l.demandeId && analyses[l.demandeId]) || (l.demandeImagerieId && imageries[l.demandeImagerieId]) || null;
      var ancien = l.prixUnitaire, q = l.quantite != null ? l.quantite : 1;
      var t = code ? tarifALaDate(code, conv, assure) : null;
      var nouveau = t && !t.absent && t.montant != null ? t.montant : null;
      var retenu = regle === 'prix_du_jour' && nouveau != null ? nouveau : ancien;
      var ecart = nouveau != null ? (nouveau - ancien) * q : 0;
      ecartTotal += ecart;
      return { id: l.id, designation: l.designation, code: code, quantite: q, ancien: ancien, nouveau: nouveau, retenu: retenu, ecart: ecart,
        sansTarif: nouveau == null ? (code ? 'prix du jour absent du référentiel' : 'ligne sans prestation tarifée (médicament au prix d’achat, RG-02)') : null };
    });
    return { ok: true, factureId: f.id, numero: f.numero, jourProforma: jourPro, jourConversion: conv, ageJours: age, validiteJours: validite, regle: regle, assure: assure, lignes: lignes, ecartTotal: ecartTotal };
  }

  /* ==========================================================================
   * 1. LE MÉDECIN PRESCRIT
   * --------------------------------------------------------------------------
   * Un seul geste engendre l'ordonnance, les demandes d'analyses, la facture et
   * les trois files d'attente. Rien n'est laissé à une ressaisie.
   * ======================================================================== */
  /** Rang suivant d'une SÉRIE ANNUELLE de pièces de caisse (`FN-2026-`, `PRO-2026-`, `FP-2026-`) : le plus grand rang déjà porté
      par les factures du même préfixe, plus un. Les deux volets d'une même émission (-A, -B) portent deux rangs consécutifs. Les archivées comptent
      (une pièce archivée garde son numéro, RG-14). Écart E6, corrigé le 31/10/2026 : le rang était le nombre TOTAL de factures. */
  function rangSerieFactures(prefixe) {
    var max = 0;
    col('factures').all().forEach(function (f) {
      var n = String(f.numero || '');
      if (n.indexOf(prefixe) !== 0) return;
      var r = parseInt(n.slice(prefixe.length), 10);
      if (r > max) max = r;
    });
    return max + 1;
  }
  function numeroSerieFacture(prefixe) { return prefixe + C.pad(rangSerieFactures(prefixe), 5); }

  function prescrire(v) {
    var p = patientParCode(v.patientCode);
    if (!p) throw new Error('Patient introuvable : ' + v.patientCode);

    var date = v.date || new Date().toISOString();
    var numero = 'ORD-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('ordonnances').all().length + 1, 5);

    /* --- Lignes ----------------------------------------------------------- */
    var sansPrixAchat = [];
    var medicaments = (v.medicaments || []).map(function (l) {
      var prod = produitParId(l.produitId) || {};
      /* RG-02 — prix d'achat, sans marge : celui de la version EN VIGUEUR à la date de la PIÈCE (lot T5), jamais la fiche, jamais un zéro. Un prix d'achat absent refuse la prescription
         en nommant l'article, avant toute écriture. */
      var px = prod.code ? prixProduitALaDate(prod, date) : { absent: true };
      var pu = px.absent ? 0 : px.achat;
      var q = Number(l.quantite) || 0;
      if (px.absent && q > 0) sansPrixAchat.push(prod.designation || l.produit || l.produitId);
      return {
        produitId: l.produitId, produit: prod.designation || l.produit || '—',
        unite: prod.unite || '', quantite: q,
        posologie: l.posologie || '', duree: l.duree || '',
        prix: pu, total: pu * q,
      };
    }).filter(function (l) { return l.quantite > 0; });

    if (sansPrixAchat.length) {
      throw new Error('Prix d’achat absent pour : ' + sansPrixAchat.join(', ') + '. Un article sans prix d’achat ne se facture jamais à zéro : renseigner son prix d’achat au Référentiel produits (« Changer le prix d’achat ») avant de prescrire.');
    }
    /* RG-09 : la colonne se décide à la date de la pièce, comme pour les actes. Le prix est celui de la version en vigueur à CETTE date (PRD-TARIFS). */
    var assureAnalyses = !!(p.assureur && carteValide(p, date));
    /* LOT TARIF-FIX : « non calculable n'est pas zéro ». Chaque ligne d'analyse et d'acte lit le référentiel de prix à la date de la PIÈCE par `prixLignePrescription` ; une
       ligne sans prix strictement positif est « prix à définir », jamais 0 : elle est NOMMÉE (cause, motif, geste) et la prescription est refusée avant toute écriture,
       comme un médicament sans prix d'achat et un examen d'imagerie sans tarif. */
    var aDefinir = [];
    var analyses = (v.analyses || []).map(function (code) {
      var a = analyseParCode(code) || {};
      var pr = prixLignePrescription(code, date, assureAnalyses, 'analyse');
      if (!pr.ok) aDefinir.push(pr);
      return { code: code, designation: a.designation || pr.libelle || code, categorie: a.categorie || '',
        echantillon: a.echantillon || '', delai: a.delai || '', prix: pr.ok ? pr.montant : null };
    });

    /* C3 (corrigé le 31/10/2026) : le tarif ASSURÉ d'un acte (pansement : 6 000 contre 9 000, colonnes inversées, décision du
       26/08) s'applique réellement. Il était ANNONCÉ par l'écran des bons de pansement mais jamais appliqué : l'acte se facturait
       au prix du catalogue (non assuré) et la garantie s'y appliquait. RG-09 décide, comme pour l'imagerie et les analyses :
       carte valide à la date de la prescription => colonne assurée de la grille ; sinon colonne non assuré. */
    var assureActes = !!(p.assureur && carteValide(p, date));
    var actes = (v.actes || []).map(function (code) {
      var a = acteParCode(code) || {};
      /* Seule la colonne ASSURÉE change le prix d'un acte assurable (SO09 : 6 000 contre 9 000) ; sans carte valide, NON COUVERT ou certificat `sos`, le prix non
         assuré. PRD-TARIFS (T1) puis TARIF-FIX : le prix vient du RÉFÉRENTIEL UNIQUE à la date de la prescription (espace des actes, puis le code ou l'alias de toute
         prestation : un certificat ou une consultation ne tombe plus à 0 parce qu'il n'est pas dans l'espace des actes). La collection `actes` n'est qu'une projection. */
      var pr = prixLignePrescription(code, date, assureActes, 'acte');
      if (!pr.ok) aDefinir.push(pr);
      return { code: code, libelle: a.libelle || pr.libelle || code, secteur: a.secteur || '', prix: pr.ok ? pr.montant : null,
        tarifValide: pr.ok };
    });
    if (aDefinir.length) {
      var refusPrix = new Error('Prix à définir : ' + aDefinir.map(function (x) { return x.motif; }).join(' ; ') + '. ' + aDefinir[0].geste
        + ' Une ligne sans prix ne se facture jamais à zéro.');
      refusPrix.code = 'PRIX_A_DEFINIR'; refusPrix.lignes = aDefinir; refusPrix.geste = aDefinir[0].geste;
      throw refusPrix;
    }

    var mMed = C.sum(medicaments, 'total');
    var mAna = C.sum(analyses, 'prix');
    var mAct = C.sum(actes, function (a) { return a.prix || 0; });

    /* --- L'imagerie médicale (refonte Zone 2, 14/09/2026) -------------------
       La fiche de consultation prescrit l'imagerie DANS LE MÊME GESTE que les
       médicaments et les analyses, et la caisse doit recevoir UNE facture
       globale (METHODOLOGIE §1.5) — deux factures pour une même consultation
       feraient passer le patient deux fois au guichet et laisseraient la part
       assureur coupée en deux pièces. Les demandes sont créées AVANT
       l'ordonnance : un examen sans tarif est refusé en le nommant, et le
       refus ne doit laisser derrière lui ni ordonnance ni facture orpheline. */
    var imagerieCree = (v.imagerie || []).length
      ? creerDemandesImagerie(p, v.imagerie, date, {
        prescripteur: v.medecin, indication: v.indication || v.diagnostic || '',
        urgent: !!v.urgent, secteurDemandeur: v.secteurDemandeur,
        origine: v.origine || 'consultation',
        dossierConsultationId: v.dossierConsultationId || null,
      })
      : { demandes: [], lignes: [] };
    var demandesImagerie = imagerieCree.demandes;
    var imagerie = demandesImagerie.map(function (d) {
      return { code: d.examenCode, examen: d.examen, modalite: d.modalite, prix: d.prix, demandeImagerieId: d.id };
    });
    var mImg = C.sum(imagerie, 'prix');

    /* --- L'ordonnance ------------------------------------------------------ */
    var ord = col('ordonnances').insert({
      numero: numero, date: date,
      patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
      medecin: v.medecin, diagnostic: v.diagnostic || '', consultationId: v.consultationId || null,
      dossierConsultationId: v.dossierConsultationId || null,
      medicaments: medicaments, analyses: analyses, actes: actes, imagerie: imagerie,
      montantMedicaments: mMed, montantAnalyses: mAna, montantActes: mAct, montantImagerie: mImg,
      montant: mMed + mAna + mAct + mImg,
      urgent: !!v.urgent,
      statutPaiement: 'impayee',
      statutDispensation: medicaments.length ? 'en_attente' : 'sans_objet',
      statutAnalyses: analyses.length ? 'en_attente' : 'sans_objet',
      statutActes: actes.length ? 'en_attente' : 'sans_objet',
      statutImagerie: imagerie.length ? 'en_attente' : 'sans_objet',
    }).record;
    demandesImagerie.forEach(function (d) {
      S.collection('demandesImagerie').update(d.id, { ordonnanceId: ord.id, ordonnanceNumero: numero });
    });

    /* --- Le laboratoire : demandes établies d'office ----------------------- */
    var demandes = analyses.map(function (a) {
      return col('demandesAnalyses').insert({
        reference: C.referenceSuivante('LAB-', 5, S.collection('demandesAnalyses').all()),
        codeAnalyse: codeAnalyse(date),
        patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
        analyseCode: a.code, analyse: a.designation, categorie: a.categorie,
        echantillon: a.echantillon, delai: a.delai, prix: a.prix,
        dateHeure: date, prescripteur: v.medecin, laborantin: null,
        urgent: !!v.urgent, etatAnalyse: 'en_attente',
        /* Origine tracée : la demande automatique se distingue de la saisie
           manuelle du laboratoire, qui reste ouverte pour les patients
           adressés par l'extérieur. */
        origine: 'ordonnance', ordonnanceId: ord.id, ordonnanceNumero: numero,
        dossierConsultationId: v.dossierConsultationId || null,
        /* Le secteur prescripteur commande la visibilité du résultat : une
           sage-femme voit ceux de la maternité, pas ceux de la chirurgie. */
        secteurDemandeur: v.secteurDemandeur || (secteurCourant() ? secteurCourant().libelle : null),
        /* Le prélèvement n'est autorisé qu'une fois la caisse passée. */
        bloqueParPaiement: true,
      }).record;
    });

    /* --- La caisse : facture en attente de règlement ------------------------ */
    /* RG-09 — la prise en charge ne s'applique que si la carte est valide À LA DATE de la prescription (écart E340 : le taux du
       dossier s'appliquait même carte expirée, alors que l'imagerie de la même pièce était déjà tarifée « non assuré »). */
    var taux = (p.assureur && carteValide(p, date)) ? (p.tauxPriseEnCharge || 0) : 0;
    var montant = mMed + mAna + mAct + mImg;
    var partAssurance = Math.round(montant * taux / 100);

    /* Les LIGNES PAYABLES. Chacune sait ce qu'elle couvre — une demande
       d'analyse, un produit, un acte, un examen d'imagerie — pour que le
       règlement de cette ligne débloque exactement ce qu'elle a payé, et rien
       d'autre. */
    var lignesFacture = construireLignes({
      medicaments: medicaments, analyses: analyses, actes: actes,
      autres: imagerieCree.lignes,
      demandes: demandes, taux: taux,
      /* L'agent de la clinique est pris en charge à 100 % par l'établissement.
         Le lien vient du dossier, il ne se saisit pas au guichet. */
      personnelId: p.personnelId || null,
    });

    /* LE TOTAL EST LA SOMME DES LIGNES, jamais un montant calculé à côté.
       C'est le défaut déjà corrigé sur les états imprimés : deux façons de
       compter la même chose divergent au premier correctif. */
    var totalLignes = C.sum(lignesFacture, 'montant');
    var totalAssureur = C.sum(lignesFacture, 'partAssureur');
    var totalPersonnel = C.sum(lignesFacture, 'partPersonnel');
    var totalRemise = C.sum(lignesFacture, 'remise');
    var duPatient = totalLignes - totalAssureur - totalPersonnel;

    var facture = col('factures').insert({
      lignes: lignesFacture,
      numero: numeroSerieFacture('FP-' + String(new Date(date).getFullYear()) + '-'),   /* E6 : rang de la série de l'année */
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Prescription',
      montantHT: totalLignes, montantTTC: totalLignes,
      montantBrut: C.sum(lignesFacture, 'montantBrut'), totalRemise: totalRemise,
      partPersonnel: totalPersonnel,
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: totalAssureur, partPatient: duPatient,
      montantPaye: 0, reliquat: duPatient,
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
      ordonnanceId: ord.id, ordonnanceNumero: numero,
      dossierConsultationId: v.dossierConsultationId || null,
    }).record;

    col('ordonnances').update(ord.id, { factureId: facture.id, factureNumero: facture.numero });
    demandesImagerie.forEach(function (d) {
      S.collection('demandesImagerie').update(d.id, { factureId: facture.id, factureNumero: facture.numero });
    });

    /* --- Les files d'attente ---------------------------------------------- */
    var taches = [];
    taches.push(creerTache('encaissement', ord, facture, {
      detail: resumeLignes(medicaments, analyses, actes, imagerie), montant: montant, statut: 'en_attente',
    }));
    if (imagerie.length) {
      /* Le poste d'imagerie est informé tout de suite, exécutable après
         encaissement — la même règle que le prélèvement. */
      taches.push(creerTache('imagerie', ord, facture, {
        poste: 'imagerie',
        detail: imagerie.map(function (i) { return i.examen; }).join(', '),
        montant: mImg, statut: 'bloque',
      }));
      notifier({
        type: 'demande_imagerie', poste: 'imagerie',
        libelle: 'Nouvelle demande d’imagerie — ' + p.nom + ' ' + p.prenom,
        detail: imagerie.map(function (i) { return i.examen; }).join(', ')
          + ' — exécutable après passage en caisse',
        priorite: v.urgent ? 'haute' : 'normale',
        patientId: p.id, reference: facture.numero, ordonnanceId: ord.id,
      });
    }
    if (medicaments.length) {
      taches.push(creerTache('dispensation', ord, facture, {
        detail: medicaments.length + ' médicament(s) — ' + C.money(mMed, false),
        montant: mMed,
        /* Informé tout de suite, exécutable après encaissement. */
        statut: 'bloque',
      }));
    }
    if (analyses.length) {
      taches.push(creerTache('prelevement', ord, facture, {
        detail: analyses.length + ' analyse(s) — ' + analyses.map(function (a) { return a.designation; }).join(', '),
        montant: mAna, statut: 'bloque',
      }));
    }
    if (actes.length) {
      taches.push(creerTache('acte', ord, facture, {
        detail: actes.map(function (a) { return a.libelle; }).join(', '),
        montant: mAct, statut: 'bloque',
      }));
    }

    S.log('Prescription', 'M2', 'ordonnance', numero, null, {
      medicaments: medicaments.length, analyses: analyses.length, actes: actes.length,
      imagerie: imagerie.length, montant: montant,
    });

    /* L ordonnance entre au REGISTRE UNIFIÉ des prescriptions. Sans cela,
       « les prescriptions du jour » n en montreraient que la moitié : les soins
       y figureraient, les médicaments non. */
    if (medicaments.length) {
      try { inscrireOrdonnance(col('ordonnances').get(ord.id), v.origine || 'consultation'); }
      catch (e) { /* le registre est secondaire, il ne doit pas casser la prescription */ }
    }

    return {
      ordonnance: col('ordonnances').get(ord.id), demandes: demandes,
      demandesImagerie: demandesImagerie.map(function (d) { return S.collection('demandesImagerie').get(d.id); }),
      facture: facture, taches: taches,
    };
  }

  /* ==========================================================================
   * LA TRANSCRIPTION D'UNE PRESCRIPTION DU MOBILE (E1559, E1561, 01/11/2026)
   * --------------------------------------------------------------------------
   * Le téléphone d'un soignant écrit une PIÈCE `prescriptions` (famille C, émise, immuable) que la mère accepte et distribue ; elle ne devient une
   * ordonnance, une facture de caisse et des files d'aval que lorsqu'un POSTE de la clinique la TRANSCRIT. La transcription passe par `PR.prescrire`
   * (le même moteur que la fiche de consultation du poste) : rien n'est recalculé à côté. Ce qu'elle ajoute, ce sont les REFUS, nommés, parce qu'une
   * pièce reçue du terrain n'a pas été saisie devant le catalogue de la clinique :
   *   - le prix ne vient jamais du téléphone : prix d'achat du catalogue, sans marge (RG-02) ;
   *   - la quantité sortie ne dépasse pas le stock de la pharmacie (RG-03) : refus nommé, jamais un stock négatif ;
   *   - la carte d'assurance se lit À LA DATE de la prescription (RG-09), pas à celle de la transcription ;
   *   - une pièce transcriptible est transcrite UNE FOIS (`pieceMobileId` sur l'ordonnance) ;
   *   - une pièce qui ne l'est pas (patient inconnu, médicament hors catalogue, examen sans correspondance) est REFUSÉE EN LE DISANT : elle n'est ni
   *     perdue ni transcrite à moitié.
   * La phrase « Prescrire génère l'ordonnance et la facture de la caisse » du simulateur n'est donc vraie qu'APRÈS cette transcription.
   * ======================================================================== */

  /** Les six examens du simulateur mobile et l'analyse du catalogue du laboratoire qui les porte. PROPOSITION à valider par le biologiste : le
      simulateur nomme des examens courants, le catalogue de la clinique les nomme autrement (« NFS COMPLETE (HEMOGRAMME) »). « Goutte épaisse / TDR
      paludisme » est rapprochée de « GE-DP / FROTTIS SANGUIN » : le test de diagnostic rapide n'a pas de ligne propre au catalogue. */
  var CORRESPONDANCE_EXAMENS_MOBILE = {
    'NFS': 'L24',
    'Glycémie': 'L14',
    'Goutte épaisse / TDR paludisme': 'L16',
    'CRP': 'L10',
    'Test de grossesse (TBG)': 'L35',
    'Créatininémie': 'L09',
  };

  function refusMobile(code, motif, geste) {
    var e = new Error(motif); e.code = code; e.motif = motif; e.geste = geste; return e;
  }

  /** `transcrireMobile(piece, { note, session })` : transcrit une pièce `prescriptions` émise par un mobile (médicaments ou analyses). Lève un refus nommé
      (`code`, `motif`, `geste`) sans rien écrire ; rend `{ deja, ordonnance, facture, taches, demandes }` sinon. */
  function transcrireMobile(piece, opts) {
    opts = opts || {};
    var pieceId = piece.id || piece.pieceId;
    /* Idempotence : une pièce n'est transcrite qu'une fois. */
    var deja = col('ordonnances').active().filter(function (o) { return o.pieceMobileId && o.pieceMobileId === pieceId; })[0];
    if (deja) return { deja: true, ordonnance: deja, facture: col('factures').get(deja.factureId), taches: [], demandes: [] };

    var nature = String(piece.nature || '');
    if (nature !== 'medicament' && nature !== 'analyse') {
      throw refusMobile('NATURE_NON_PORTEE', 'Le mobile ne prescrit pas « ' + nature + ' ».', 'Prescrire depuis un poste de la clinique');
    }
    var fonction = String(piece.fonction || '');
    if (!peutPrescrire(nature, { fonction: fonction })) {
      /* Formulation de la maquette (`prescrireSoins` : « X n’est pas habilité à prescrire. »), complétée de la nature refusée. */
      var libFonction = (D.CAPACITES[fonction] || {}).label || fonction;
      var libNature = (D.NATURES_PRESCRIPTION.filter(function (n) { return n.id === nature; })[0] || {}).label || nature;
      throw refusMobile('FONCTION_NON_HABILITEE', libFonction + ' n’est pas habilité à prescrire « ' + libNature + ' ».', 'Demander la prescription à un médecin');
    }
    var p = patientParCode(piece.patientCode);
    if (!p) {
      throw refusMobile('PATIENT_INTROUVABLE', 'Le dossier « ' + (piece.patientCode || 'sans code') + ' » n’existe pas à la clinique : la prescription ne peut pas être facturée.', 'Rapprocher le dossier du patient avant de transcrire');
    }

    var medicaments = [], analyses = [];
    if (nature === 'medicament') {
      var lignes = piece.lignes || [];
      if (!lignes.length) throw refusMobile('ORDONNANCE_VIDE', 'L’ordonnance ne porte aucune ligne.', 'Refaire la prescription depuis le téléphone');
      var demande = {};
      lignes.forEach(function (l) {
        var prod = l.produitId ? produitParId(l.produitId) : null;
        if (!prod) {
          throw refusMobile('PRODUIT_INCONNU', 'Médicament absent du catalogue de la clinique : « ' + (l.medicament || 'sans nom') + ' ».', 'Choisir le médicament dans la liste du lot et refaire la prescription');
        }
        var q = Number(l.quantite);
        if (!(q >= 1) || q !== Math.floor(q)) {
          throw refusMobile('QUANTITE_INVALIDE', 'Quantité invalide pour « ' + prod.designation + ' » : un entier d’au moins 1 est attendu.', 'Refaire la prescription depuis le téléphone');
        }
        demande[prod.id] = (demande[prod.id] || 0) + q;
        var dispo = prod.stockDetail != null ? prod.stockDetail : prod.stock;
        if (demande[prod.id] > dispo) {
          throw refusMobile('STOCK_INSUFFISANT', 'Stock insuffisant pour « ' + prod.designation + ' » : disponible : ' + dispo + ' ; demandé : ' + demande[prod.id] + ' (RG-03).', 'Corriger la quantité ou demander un transfert du gros.');
        }
        medicaments.push({ produitId: prod.id, quantite: q, posologie: l.posologie || '', duree: l.dureeJours != null ? l.dureeJours + (Number(l.dureeJours) > 1 ? ' jours' : ' jour') : '' });
      });
    } else {
      var examens = piece.examens || [];
      if (!examens.length) throw refusMobile('ORDONNANCE_VIDE', 'La demande ne porte aucun examen.', 'Refaire la demande depuis le téléphone');
      examens.forEach(function (nom) {
        var code = CORRESPONDANCE_EXAMENS_MOBILE[nom];
        if (!code || !analyseParCode(code)) {
          throw refusMobile('EXAMEN_INCONNU', 'Examen sans correspondance au catalogue du laboratoire : ' + nom + '.', 'Demander l’examen depuis un poste de la clinique');
        }
        analyses.push(code);
      });
    }

    var date = new Date(String(piece.date || '').indexOf('T') > 0 ? piece.date : Date.now()).toISOString();
    var res = prescrire({
      patientCode: p.code, medecin: piece.prescripteur || '', diagnostic: (opts.note && opts.note.diagnostic) || '',
      date: date, urgent: nature === 'analyse' && String(piece.urgence || 'Non urgent') !== 'Non urgent',
      medicaments: medicaments, analyses: analyses, actes: [], origine: 'mobile',
      secteurDemandeur: (capacites({ fonction: fonction }).secteurs || [])[0] || 'Consultation',
    });
    col('ordonnances').update(res.ordonnance.id, { origine: 'mobile', pieceMobileId: pieceId, fonctionPrescripteur: fonction });
    return { deja: false, ordonnance: col('ordonnances').get(res.ordonnance.id), facture: res.facture, taches: res.taches, demandes: res.demandes };
  }

  function resumeLignes(med, ana, act, img) {
    var t = [];
    if (med.length) t.push(med.length + ' médicament(s)');
    if (ana.length) t.push(ana.length + ' analyse(s)');
    if (act.length) t.push(act.length + ' acte(s)');
    if (img && img.length) t.push(img.length + ' examen(s) d’imagerie');
    return t.join(' · ') || 'Prescription sans ligne';
  }

  function creerTache(type, ord, facture, extra) {
    var def = TACHES[type];
    return col('taches').insert(Object.assign({
      type: type, role: def.role, module: def.module, ecran: def.ecran,
      titre: def.titre, icon: def.icon,
      reference: ord.numero, ordonnanceId: ord.id,
      factureId: facture ? facture.id : null, factureNumero: facture ? facture.numero : null,
      patient: ord.patient, patientCode: ord.patientCode,
      date: ord.date, urgent: !!ord.urgent,
      statut: 'en_attente', faitLe: null, faitPar: null,
    }, extra || {})).record;
  }

  /* ==========================================================================
   * 2. LA CAISSE ENCAISSE ET VALIDE
   * --------------------------------------------------------------------------
   * Le règlement débloque tout l'aval : sans lui, ni délivrance ni prélèvement.
   * ======================================================================== */
  /* ==========================================================================
   * LES DEUX VALIDATIONS D'UN RÉSULTAT
   * --------------------------------------------------------------------------
   * « Une première validation technique, puis une validation biologique. Dès
   * que nous faisons la validation biologique, le médecin a le résultat. »
   *
   * Entre les deux, le résultat existe mais reste invisible du prescripteur :
   * c'est la fenêtre de relecture. Elle n'a de sens que si personne ne lit
   * par-dessus l'épaule du laboratoire — d'où le verrou posé dans
   * peutVoirResultat().
   *
   * QUI VALIDE BIOLOGIQUEMENT : le biologiste médical. Le TSL le peut EN SON
   * ABSENCE, et l'intérim est alors tracé sur la pièce. Une clinique de trente
   * agents ne peut pas suspendre ses rendus pendant un congé ; masquer
   * l'intérim reviendrait à faire signer quelqu'un d'autre.
   * ======================================================================== */
  function validerTechnique(demandeId, opts) {
    opts = opts || {};
    var col_ = S.collection('demandesAnalyses');
    var d = col_.get(demandeId);
    if (!d) throw new Error('Demande introuvable.');
    if (!d.valeurs || !Object.keys(d.valeurs).length) {
      throw new Error('Aucun résultat saisi : il n’y a rien à valider.');
    }
    var res = col_.update(demandeId, {
      etatAnalyse: 'valide_technique',
      valideTechniqueLe: new Date().toISOString(),
      valideTechniquePar: opts.utilisateur || S.currentUser(),
    });
    S.log('Validation technique', 'M5', 'ResultatAnalyse', d.reference,
      { etat: d.etatAnalyse }, { etat: 'valide_technique' });
    return { demande: col_.get(demandeId), undo: res.undo };
  }

  /**
   * La validation biologique rend le résultat OPPOSABLE : le prescripteur le
   * voit, la clinique le remet au patient externe. C'est le point de
   * non-retour — au-delà, une correction devient une RECTIFICATION.
   */
  function validerBiologique(demandeId, opts) {
    opts = opts || {};
    var col_ = S.collection('demandesAnalyses');
    var d = col_.get(demandeId);
    if (!d) throw new Error('Demande introuvable.');
    if (d.etatAnalyse !== 'valide_technique') {
      throw new Error('La validation technique doit précéder la validation biologique.');
    }
    var cap = capacites(opts.session);
    if (!cap.validerBiologique) {
      throw new Error(cap.label + ' n’est pas habilité à porter la validation biologique.');
    }
    var interim = cap.validerBiologique === 'interim';

    var res = col_.update(demandeId, {
      etatAnalyse: 'valide',
      valideLe: new Date().toISOString(),
      valideBiologiquePar: opts.utilisateur || S.currentUser(),
      /* L'intérim est PORTÉ SUR LA PIÈCE : le compte rendu dira qui a signé
         et à quel titre. */
      validationInterim: interim,
      qualiteValidateur: interim
        ? cap.label + ' — par intérim du biologiste médical'
        : cap.label,
      version: d.version || 1,
    });
    S.log('Validation biologique', 'M5', 'ResultatAnalyse', d.reference,
      { etat: 'valide_technique' }, { etat: 'valide', interim: interim });

    /* Le prescripteur est informé que son résultat est disponible. */
    notifier({
      type: 'resultat_disponible', poste: 'prescripteur',
      destinataire: d.prescripteur,
      libelle: 'Résultat disponible — ' + d.analyse,
      detail: d.patient + ' (' + d.patientCode + ')',
      demandeId: demandeId, reference: d.reference,
      patientId: d.patientId,
    });

    return { demande: col_.get(demandeId), interim: interim, undo: res.undo };
  }

  /**
   * RECTIFIER un résultat déjà validé biologiquement.
   *
   * « Même si après on vient corriger, peut-être qu'il a déjà lu le premier,
   * et c'est pas cool. » — Exactement. La version précédente est CONSERVÉE,
   * la nouvelle est numérotée, et le prescripteur est notifié que ce qu'il a
   * lu a changé. Écraser en silence laisserait le médecin avec une valeur qui
   * n'existe plus nulle part.
   */
  function rectifierResultat(demandeId, valeurs, opts) {
    opts = opts || {};
    if (!opts.motif) throw new Error('Une rectification doit être motivée.');
    var col_ = S.collection('demandesAnalyses');
    var d = col_.get(demandeId);
    if (!d) throw new Error('Demande introuvable.');
    if (!D.resultatRendu(d.etatAnalyse)) {
      throw new Error('Ce résultat n’a pas été validé biologiquement : le corriger ne demande pas de rectification.');
    }

    var versions = (d.versions || []).slice();
    var numero = (d.version || 1);
    /* On fige la version sortante AVANT de la remplacer : c'est elle que le
       médecin a lue, et elle doit rester consultable. */
    versions.push({
      numero: numero,
      valeurs: Object.assign({}, d.valeurs),
      commentaireGeneral: d.commentaireGeneral || null,
      conclusion: d.conclusion || null,
      valideLe: d.valideLe,
      valideBiologiquePar: d.valideBiologiquePar,
      remplaceeLe: new Date().toISOString(),
      motifRemplacement: opts.motif,
    });

    var res = col_.update(demandeId, {
      valeurs: valeurs,
      versions: versions,
      version: numero + 1,
      etatAnalyse: 'rectifie',
      rectifieLe: new Date().toISOString(),
      rectifiePar: opts.utilisateur || S.currentUser(),
      motifRectification: opts.motif,
      commentaireGeneral: opts.commentaireGeneral != null ? opts.commentaireGeneral : d.commentaireGeneral,
    });

    S.log('Rectification de résultat', 'M5', 'ResultatAnalyse', d.reference,
      { version: numero, valeurs: d.valeurs }, { version: numero + 1, motif: opts.motif });

    /* LA NOTIFICATION EST LE CŒUR DU DISPOSITIF : sans elle, la rectification
       ne vaut pas mieux qu'un écrasement silencieux. */
    notifier({
      type: 'resultat_rectifie', poste: 'prescripteur',
      destinataire: d.prescripteur,
      priorite: 'haute',
      libelle: 'RÉSULTAT RECTIFIÉ — ' + d.analyse,
      detail: d.patient + ' (' + d.patientCode + ') — version ' + (numero + 1)
        + '. Motif : ' + opts.motif + '. Le résultat que vous avez consulté a changé.',
      demandeId: demandeId, reference: d.reference,
      patientId: d.patientId,
    });

    return { demande: col_.get(demandeId), version: numero + 1, undo: res.undo };
  }

  /* ==========================================================================
   * NOTIFICATIONS DE POSTE
   * --------------------------------------------------------------------------
   * Une notification s'adresse à un POSTE, pas à une personne : le
   * prescripteur peut être en congé, c'est le service qui doit voir passer
   * l'information. Elle vit dans sa propre collection pour survivre au
   * rechargement de la page.
   * ======================================================================== */
  function notifier(o) {
    return S.collection('notifications', { module: 'M14', entite: 'notification', prefix: 'NOT' }).insert({
      type: o.type, poste: o.poste || 'tous',
      destinataire: o.destinataire || null,
      libelle: o.libelle, detail: o.detail || null,
      priorite: o.priorite || 'normale',
      demandeId: o.demandeId || null, factureId: o.factureId || null,
      ordonnanceId: o.ordonnanceId || null, patientId: o.patientId || null,
      reference: o.reference || null,
      lue: false, creeLe: new Date().toISOString(),
    }).record;
  }

  /** Les notifications d'un poste, non lues d'abord. */
  function notifications(poste, opts) {
    opts = opts || {};
    var rows = S.collection('notifications', { module: 'M14', entite: 'notification', prefix: 'NOT' })
      .active()
      .filter(function (n) { return !poste || n.poste === poste || n.poste === 'tous'; });
    if (opts.nonLues) rows = rows.filter(function (n) { return !n.lue; });
    return rows.sort(function (a, b) { return String(b.creeLe).localeCompare(String(a.creeLe)); });
  }

  function marquerLue(id) {
    return S.collection('notifications', { module: 'M14', entite: 'notification', prefix: 'NOT' })
      .update(id, { lue: true, lueLe: new Date().toISOString(), luePar: S.currentUser() });
  }

  /* ==========================================================================
   * LE PATIENT EXTERNE
   * --------------------------------------------------------------------------
   * Il arrive avec une ordonnance d'un médecin extérieur. L'accueil TRANSCRIT
   * cette ordonnance — il ne prescrit pas — en cochant les examens dans le
   * catalogue, puis l'envoie à la caisse avec sa facture.
   *
   * Deux règles que ce circuit doit tenir :
   *   — les examens viennent du CATALOGUE, jamais d'un montant libre : sans
   *     lignes, la facture ne peut pas être réglée examen par examen ;
   *   — l'IDENTITÉ est obligatoire. Sans nom, âge, sexe et téléphone, le
   *     résultat ne peut être ni remis ni retrouvé — et c'est au patient
   *     externe qu'on le remet directement.
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * LE DOSSIER D'UN PATIENT ADRESSÉ DE L'EXTÉRIEUR — UNE SEULE FABRIQUE
   * --------------------------------------------------------------------------
   * Le laboratoire et l'imagerie reçoivent tous deux des patients venus avec
   * une prescription extérieure. Écrire la création du dossier deux fois
   * aurait donné deux formes de patient externe dans la même collection —
   * c'est le défaut déjà payé sur le code patient, qui vivait à deux endroits.
   *
   * Le patient externe reçoit un DOSSIER : sans lui, on ne peut ni lui
   * remettre son résultat, ni le retrouver s'il revient. Il est marqué
   * `externe`, ce qui le distingue de la file de consultation.
   *
   * Le code suit `C.codePatient()` — la fabrique unique du format `CNT/n/AA`.
   * Ce site en construisait un À LA MAIN, à l'ancien format « CNT905/26 » :
   * la règle qui existe en deux exemplaires diverge au premier correctif, et
   * celle-ci avait déjà divergé.
   * ------------------------------------------------------------------------ */
  function dossierExterne(v, date) {
    var patients = S.collection('patients', { module: 'M1', entite: 'Patient' });
    var existant = v.patientId ? patients.get(v.patientId)
      : (v.patientCode ? patientParCode(v.patientCode) : null);
    if (v.patientId && !existant) throw new Error('Patient introuvable au répertoire.');
    if (existant) return existant;
    if (!String(v.nom || '').trim() || !String(v.prenom || '').trim()) {
      throw new Error('Nom et prénoms du patient obligatoires.');
    }
    return patients.insert({
      code: C.codePatient(900 + patients.all().length, new Date(date).getFullYear()),
      nom: String(v.nom).toUpperCase(), prenom: v.prenom,
      sexe: v.sexe || 'M', dateNaissance: v.dateNaissance || null,
      /* Âge DÉCLARÉ, et daté du jour de la déclaration : sans cette date il
         se figerait, et le dossier vieillirait sans que le patient vieillisse. */
      age: (!v.dateNaissance && v.age != null && v.age !== '') ? v.age : null,
      ageReferenceLe: (!v.dateNaissance && v.age != null && v.age !== '') ? C.iso(new Date(date)) : null,
      telephone: v.telephone || null, adresse: v.residence || null,
      quartier: v.residence || null,
      /* La date de création manquait : le répertoire la montre, le KPI
         « créés dans l'année » la compte, et la traçabilité du dossier la
         date — un dossier externe sans elle n'était compté nulle part. */
      dateCreation: C.iso(new Date(date)),
      externe: true, origineDossier: v.origineDossier || 'Patient externe — accueil',
      prescripteurExterieur: v.prescripteur || null,
      assure: !!v.assureur, assureur: v.assureur || null,
      tauxPriseEnCharge: v.assureur ? (Number(v.taux) || 0) : 0,
    }).record;
  }

  function ouvrirDemandeExterne(v) {
    /* L'identité est obligatoire — mais un patient DU RÉPERTOIRE (fiche du
       service, phase 7) la porte déjà : exiger sa ressaisie créerait deux
       vérités. La règle vaut pour l'externe dont on crée le dossier. */
    if (!v || (!v.patientId && (!v.nom || !v.prenom))) {
      throw new Error('Nom et prénoms du patient obligatoires.');
    }
    if (!v.analyses || !v.analyses.length) throw new Error('Cocher au moins un examen au catalogue.');

    var date = v.date || new Date().toISOString();

    /* Le patient externe reçoit un DOSSIER : sans lui, on ne peut ni lui
       remettre son résultat, ni le retrouver s'il revient. Il est marqué
       comme externe, ce qui le distingue de la file de consultation. */
    var p = dossierExterne(v, date);

    /* Les examens, pris au catalogue. */
    var assureExterne = !!(p.assureur && carteValide(p, date));
    var analyses = (v.analyses || []).map(function (code) {
      var a = analyseParCode(code) || {};
      var pr = prixAnalyseALaDate(code, date, assureExterne);
      return {
        code: code, designation: a.designation || code, categorie: a.categorie || '',
        echantillon: a.echantillon || '', delai: a.delai || '', prix: (pr === undefined ? a.prix : pr) || 0,
      };
    });
    var montant = C.sum(analyses, 'prix');

    /* Les demandes, marquées EXTERNE : le résultat se remet au patient. */
    var demandes = analyses.map(function (a) {
      return S.collection('demandesAnalyses').insert({
        reference: C.referenceSuivante('LAB-', 5, S.collection('demandesAnalyses').all()),
        codeAnalyse: codeAnalyse(date),
        patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
        analyseCode: a.code, analyse: a.designation, categorie: a.categorie,
        echantillon: a.echantillon, delai: a.delai, prix: a.prix,
        dateHeure: date,
        prescripteur: v.prescripteur || 'Médecin extérieur',
        laborantin: null,
        urgent: v.urgence === 'bilan' || (v.urgence === 'examen' && v.examenUrgent === a.code),
        etatAnalyse: 'en_attente',
        /* Trois voies désormais : la transcription à l'accueil, la saisie du
           laboratoire, et — phase 7 — la fiche de demande d'examen d'un
           SERVICE (m3-demande-examen, le formulaire papier de reunions/).
           origineDemande 'externe' dit que le résultat se remet au patient ;
           'service' le renvoie au prescripteur, sous le RBAC métier. */
        origine: v.origineFiche || 'accueil-externe',
        origineDemande: v.origineDemande || 'externe',
        serviceDemandeur: v.serviceDemandeur || null,
        secteurDemandeur: v.secteurDemandeur || null,
        indication: v.indication || null,
        hospitalise: !!v.hospitalise,
        /* La résidence saisie sur la fiche papier est portée par la demande : sans cela elle ne vivait que le temps de l'impression.
           Le dossier du patient (Zone 1) n'est pas modifié : c'est une donnée de la demande. */
        residence: v.residence || null,
        bloqueParPaiement: true,
      }).record;
    });

    /* La facture, avec ses lignes payables. */
    var taux = p.assureur ? (p.tauxPriseEnCharge || 0) : 0;
    var partAssurance = Math.round(montant * taux / 100);
    var lignes = construireLignes({
      analyses: analyses, demandes: demandes, taux: taux,
      personnelId: p.personnelId || null,
    });

    var facture = col('factures').insert({
      lignes: lignes,
      numero: 'FE-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Analyses — patient externe',
      /* Le total est la somme des lignes, comme sur la facture de
         prescription : deux façons de compter divergeraient. */
      montantHT: C.sum(lignes, 'montant'), montantTTC: C.sum(lignes, 'montant'),
      montantBrut: C.sum(lignes, 'montantBrut'), totalRemise: C.sum(lignes, 'remise'),
      partPersonnel: C.sum(lignes, 'partPersonnel'),
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: C.sum(lignes, 'partAssureur'),
      partPatient: C.sum(lignes, 'partPatient'),
      montantPaye: 0, reliquat: C.sum(lignes, 'partPatient'),
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
      origineDemande: 'externe',
      prescripteurExterieur: v.prescripteur || null,
    }).record;

    demandes.forEach(function (d) {
      S.collection('demandesAnalyses').update(d.id, { factureId: facture.id, factureNumero: facture.numero });
    });

    /* La caisse est saisie, le prélèvement attend le règlement. */
    var taches = [];
    taches.push(col('taches').insert({
      type: 'encaissement', poste: 'caisse',
      libelle: 'Patient externe — ' + p.nom + ' ' + p.prenom,
      detail: C.num(analyses.length) + ' examen(s) — ' + C.money(montant, false),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      montant: montant, statut: 'en_attente', creeLe: date,
    }).record);
    taches.push(col('taches').insert({
      type: 'prelevement', poste: 'laboratoire',
      libelle: 'Patient externe — ' + p.nom + ' ' + p.prenom,
      detail: C.num(analyses.length) + ' examen(s)',
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      statut: 'bloque', creeLe: date,
    }).record);

    S.log('Demande externe ouverte', 'M1', 'DemandeAnalyse', facture.numero, null,
      { patient: p.code, examens: analyses.length, montant: montant });

    return { patient: p, demandes: demandes, facture: facture, taches: taches, montant: montant };
  }

  /* ==========================================================================
   * LA DEMANDE D'IMAGERIE (phase 8, cible Instructions)
   * --------------------------------------------------------------------------
   * L'imagerie suit LES MÊMES ÉTATS que le laboratoire : demandée → payée →
   * exécutée → validée. La demande naît bloquée par le paiement ; c'est
   * l'encaissement de SA ligne qui la libère — la ligne payable porte
   * `demandeImagerieId`, comme la ligne d'analyse porte `demandeId`.
   * UNE fabrique pour toutes les voies (consultation, service, saisie du
   * poste) : deux fabriques divergeraient.
   * ======================================================================== */
  /* --------------------------------------------------------------------------
   * LES DEMANDES D'IMAGERIE — UNE SEULE FABRIQUE, DEUX PORTES (14/09/2026)
   * --------------------------------------------------------------------------
   * La demande d'imagerie naît désormais aussi de la FICHE DE CONSULTATION,
   * dans la même facture que les médicaments et les analyses (METHODOLOGIE
   * §1.5 : UNE facture globale). Recopier ici la création des demandes aurait
   * donné deux formes de demande dès le premier correctif — c'est la leçon du
   * code patient, qui vivait à deux endroits. `prescrire` et
   * `ouvrirDemandeImagerie` appellent donc la MÊME fonction, qui crée les
   * demandes bloquées, applique RG-09 au tarif et REFUSE en nommant l'examen
   * sans prix, puis rend les lignes payables à poser sur la facture.
   *
   * Le catalogue est lu AU MAGASIN (`examensImagerie`, administrable par
   * cfg-imagerie-catalogue), la semence D.IMAGERIE n'étant qu'un repli : lire
   * la constante, c'était ignorer ce que l'écran de configuration corrige.
   * ------------------------------------------------------------------------ */
  function examenImagerieParCode(code) {
    var c = S.collection('examensImagerie').active().filter(function (x) { return x.code === code; })[0];
    if (c) return c;
    return ((D.IMAGERIE && D.IMAGERIE.EXAMENS) || []).filter(function (x) { return x.code === code; })[0] || null;
  }

  function creerDemandesImagerie(p, codes, date, v) {
    var assure = carteValide(p, date);
    var col_ = S.collection('demandesImagerie', { module: 'M2', entite: 'demande d’imagerie', prefix: 'IME' });

    var demandes = codes.map(function (code) {
      var ex = examenImagerieParCode(code);
      /* RG-09 : la validité de la carte À LA DATE décide du tarif. */
      var pr = D.tarifPrix ? D.tarifPrix((ex && ex.tarifCode) || code, assure, date) : { montant: null };
      return col_.insert({
        /* Lue sur les demandes EXISTANTES (écart E100) : le compteur de page de nextRef repartait à 1 à chaque chargement. */
        reference: C.referenceSuivante('IME-', 5, col_.all()),
        dateHeure: date,
        patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
        examenCode: code, examen: ex ? ex.label : code,
        /* Copie de lecture : la modalité fait foi au catalogue (vague 61). */
        modalite: D.IMAGERIE && D.IMAGERIE.modaliteDeExamen ? D.IMAGERIE.modaliteDeExamen(ex) : 'echographie',
        prescripteur: v.prescripteur || '—',
        indication: v.indication || '',
        urgent: !!v.urgent,
        secteurDemandeur: v.secteurDemandeur || (secteurCourant() ? secteurCourant().libelle : null),
        origine: v.origine || 'consultation',
        ordonnanceId: v.ordonnanceId || null, ordonnanceNumero: v.ordonnanceNumero || null,
        dossierConsultationId: v.dossierConsultationId || null,
        prix: pr.montant, motifTarif: pr.motif || null,
        statut: 'demandee',
        bloqueParPaiement: true,
      }).record;
    });

    var sansPrix = demandes.filter(function (d) { return d.prix == null; });
    if (sansPrix.length) {
      /* Un tiret n'est pas un zéro : une demande sans tarif validé ne se
         facture pas — elle est refusée EN NOMMANT l'examen. */
      demandes.forEach(function (d) { col_.archive(d.id); });
      throw new Error('Tarif non renseigné pour : '
        + sansPrix.map(function (d) { return d.examen; }).join(', ')
        + '. Le renseigner au référentiel tarifaire avant de facturer.');
    }

    return {
      demandes: demandes,
      /* Les lignes payables : chacune porte `demandeImagerieId`, et c'est ce
         lien que `encaisser` lit pour libérer l'examen NOMMÉ. */
      lignes: demandes.map(function (d) {
        return { categorie: 'imagerie', designation: d.examen,
          quantite: 1, prixUnitaire: d.prix, montant: d.prix,
          demandeImagerieId: d.id };
      }),
    };
  }

  function ouvrirDemandeImagerie(v) {
    if (!v.examens || !v.examens.length) throw new Error('Cocher au moins un examen d’imagerie.');

    var date = v.date || new Date().toISOString();
    /* PATIENT DU RÉPERTOIRE **OU** ADRESSÉ DE L'EXTÉRIEUR (06/09/2026) : une
       échographie prescrite ailleurs se pratique ici comme une analyse
       prescrite ailleurs. La MÊME fabrique que le laboratoire ouvre le
       dossier — le patient externe n'a pas deux formes selon la porte par
       laquelle il entre. */
    var p = (v.patientId || v.patientCode) ? dossierExterne(v, date)
      : dossierExterne(Object.assign({}, v, { origineDossier: 'Patient externe — imagerie' }), date);
    if (!p) throw new Error('Patient introuvable au répertoire.');
    var col_ = S.collection('demandesImagerie', { module: 'M2', entite: 'demande d’imagerie', prefix: 'IME' });

    var cree = creerDemandesImagerie(p, v.examens, date, v);
    var demandes = cree.demandes;

    /* RG-09 (écart E101) : la part de l'assureur ne se calcule QUE si la carte est valide à la date — le tarif non assuré était bien
       appliqué sur carte expirée, mais 80 % de la pièce partaient quand même à l'assureur. */
    var taux = (p.assureur && carteValide(p, date)) ? (p.tauxPriseEnCharge || 0) : 0;
    var lignes = construireLignes({
      taux: taux, personnelId: p.personnelId || null,
      autres: cree.lignes,
    });

    var facture = col('factures').insert({
      lignes: lignes,
      numero: 'FI-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Imagerie',
      montantHT: C.sum(lignes, 'montant'), montantTTC: C.sum(lignes, 'montant'),
      montantBrut: C.sum(lignes, 'montantBrut'), totalRemise: C.sum(lignes, 'remise'),
      partPersonnel: C.sum(lignes, 'partPersonnel'),
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: C.sum(lignes, 'partAssureur'),
      partPatient: C.sum(lignes, 'partPatient'),
      montantPaye: 0, reliquat: C.sum(lignes, 'partPatient'),
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
    }).record;

    demandes.forEach(function (d) {
      col_.update(d.id, { factureId: facture.id, factureNumero: facture.numero });
    });

    var taches = [];
    taches.push(col('taches').insert({
      type: 'encaissement', poste: 'caisse',
      libelle: 'Imagerie — ' + p.nom + ' ' + p.prenom,
      detail: C.num(demandes.length) + ' examen(s) — ' + C.money(facture.montantTTC, false),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      montant: facture.montantTTC, statut: 'en_attente', creeLe: date,
    }).record);
    taches.push(col('taches').insert({
      type: 'imagerie', poste: 'imagerie',
      libelle: 'Examen d’imagerie — ' + p.nom + ' ' + p.prenom,
      detail: demandes.map(function (d) { return d.examen; }).join(', '),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      statut: 'bloque', creeLe: date,
    }).record);

    notifier({
      type: 'demande_imagerie', poste: 'imagerie',
      libelle: 'Nouvelle demande d’imagerie — ' + p.nom + ' ' + p.prenom,
      detail: demandes.map(function (d) { return d.examen; }).join(', ')
        + ' — exécutable après passage en caisse',
      priorite: v.urgent ? 'haute' : 'normale',
      patientId: p.id, reference: facture.numero,
    });

    S.log('Demande d’imagerie ouverte', 'M2', 'DemandeImagerie', facture.numero, null,
      { patient: p.code, examens: demandes.length, montant: facture.montantTTC });

    return { patient: p, demandes: demandes.map(function (d) { return col_.get(d.id); }), facture: facture, taches: taches };
  }

  /* ==========================================================================
   * LE CODE D'ANALYSE UNIQUE — NNNNN-AAAA (phase 6, cible Instructions)
   * --------------------------------------------------------------------------
   * Série ANNUELLE, comme les pièces certifiantes : le registre papier du
   * laboratoire repart à 1 chaque année. UNE SEULE fabrique pour toutes les
   * voies — ordonnance, transcription à l'accueil, saisie du laboratoire,
   * jeu de démonstration : deux fabriques divergeraient au premier correctif
   * (c'est le défaut déjà rencontré sur le code patient, qui vivait à deux
   * endroits). La référence LAB-NNNNN reste : elle identifie la DEMANDE dans
   * le logiciel, le code d'analyse identifie le DOSSIER au registre annuel.
   * ======================================================================== */
  function codeAnalyse(date) {
    var d = date ? new Date(date) : new Date();
    var annee = String(isNaN(d.getTime()) ? new Date().getFullYear() : d.getFullYear());
    var max = 0;
    S.collection('demandesAnalyses').all().forEach(function (x) {
      var m = /^(\d{5})-(\d{4})$/.exec(x.codeAnalyse || '');
      if (m && m[2] === annee && +m[1] > max) max = +m[1];
    });
    return C.pad(max + 1, 5) + '-' + annee;
  }

  /* ==========================================================================
   * LE BADGE DU PERSONNEL — numéro de série et charge utile du QR
   * --------------------------------------------------------------------------
   * UNE SEULE fabrique, comme pour le code d'analyse : le numéro est posé à
   * l'émission, relu à la vérification, imprimé sur la carte et scanné au
   * contrôle. Le format retenu — BDG-NNNNN-AAAA — reprend la SÉRIE ANNUELLE
   * des pièces certifiantes, mais reste marqué à VALIDER par la Direction :
   * rien dans les documents de cadrage ne fixe la numérotation des badges, et
   * la clinique tient peut-être déjà un registre papier avec le sien.
   *
   * LA CHARGE UTILE DU QR EST LE POINT LE PLUS IMPORTANT DU MODULE.
   * Elle ne porte QUE le matricule de l'agent et le numéro de série du badge.
   * Ni nom, ni fonction, ni téléphone, ni adresse d'un service extérieur.
   * Trois raisons, et la troisième commande les deux autres :
   *   - un badge se photographie dans un couloir : ce qu'il porte en clair
   *     est lisible par quiconque le croise ;
   *   - le logiciel fonctionne HORS LIGNE — une URL ne mènerait nulle part ;
   *   - la vérification doit passer par le LOGICIEL, seul à savoir si le
   *     badge est encore valide. Un QR qui porterait le nom remplacerait un
   *     contrôle par une simple lecture, et c'est exactement ce qu'un faux
   *     badge cherche à obtenir.
   * ======================================================================== */
  function numeroBadge(date) {
    var d = date ? new Date(date) : new Date();
    var annee = String(isNaN(d.getTime()) ? new Date().getFullYear() : d.getFullYear());
    var max = 0;
    S.collection('badges').all().forEach(function (b) {
      var m = /^BDG-(\d{5})-(\d{4})$/.exec(b.numero || '');
      if (m && m[2] === annee && +m[1] > max) max = +m[1];
    });
    return 'BDG-' + C.pad(max + 1, 5) + '-' + annee;
  }

  /** La charge utile du code QR d'un badge — matricule et n° de série, rien d'autre. */
  function badgeQR(badge) {
    return 'CNT-BDG|MAT:' + (badge.matricule || '') + '|SER:' + (badge.numero || '');
  }

  /**
   * Lecture d'un code présenté au contrôle. On accepte aussi bien la charge
   * utile complète (badge scanné) que le seul numéro de série (saisi à la
   * main quand le QR est abîmé) : refuser la saisie manuelle rendrait le
   * contrôle impossible le jour où il sert le plus.
   */
  function lireBadgeQR(texte) {
    var t = String(texte || '').trim();
    if (!t) return null;
    var m = /^CNT-BDG\|MAT:([^|]*)\|SER:(.+)$/.exec(t);
    if (m) return { matricule: m[1] || null, numero: m[2].trim(), source: 'qr' };
    return { matricule: null, numero: t, source: 'saisie' };
  }

  /* ==========================================================================
   * LE JETON D'UNE FICHE D'ENQUÊTE PARTAGÉE
   * --------------------------------------------------------------------------
   * L'adresse porte un JETON, jamais l'identifiant de l'enquête : sans cela,
   * on énumère les enquêtes en changeant un numéro. Le jeton est long, tiré
   * au hasard, et c'est la fiche du magasin — pas le jeton — qui porte sa
   * date d'expiration et sa révocation : un lien qui vit indéfiniment
   * collecte des réponses des mois après la clôture, et personne ne s'en
   * aperçoit.
   * ======================================================================== */
  function jetonEnquete() {
    var alphabet = 'abcdefghijkmnopqrstuvwxyz23456789'; /* ni l ni 1, ni o ni 0 */
    var out = '';
    for (var i = 0; i < 24; i++) out += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
    return out;
  }

  /* ==========================================================================
   * LES LIGNES PAYABLES D'UNE FACTURE
   * --------------------------------------------------------------------------
   * Une ligne par prestation, et le lien vers ce qu'elle couvre. Sans ce lien,
   * régler « trois examens sur cinq » ne pourrait pas désigner LESQUELS trois
   * passent au laboratoire.
   *
   * Chaque ligne porte sa part patient et sa part assureur : c'est la part
   * PATIENT qui se règle à la caisse, la part assureur suit son propre
   * circuit de recouvrement.
   * ======================================================================== */
  function construireLignes(v) {
    var lignes = [];
    var taux = Number(v.taux) || 0;
    /* La prise en charge de l'établissement se DÉDUIT du dossier : un agent
       n'a pas à la réclamer au guichet, et la lui faire demander reviendrait à
       l'oublier le jour où il est pressé. Ce n'est pas une assurance — aucun
       tiers ne rembourse, aucune créance ne naît. */
    var estAgent = !!v.personnelId;
    var n = 0;

    function ajouter(o) {
      n++;
      var brut = Math.round(Number(o.montant) || 0);
      var remise = Math.round(Number(o.remise) || 0);
      /* RG-02 — pas de remise sur un médicament : il se facture au prix
         d'achat, une remise le vendrait à perte. */
      if (o.categorie === 'medicament') remise = 0;
      var montant = brut - remise;

      var partAssureur = estAgent ? 0 : Math.round(montant * taux / 100);
      var partPersonnel = estAgent ? montant : 0;

      lignes.push({
        id: 'L' + C.pad(n, 3),
        categorie: o.categorie, designation: o.designation,
        quantite: o.quantite != null ? o.quantite : 1,
        prixUnitaire: o.prixUnitaire != null ? o.prixUnitaire : brut,
        prixUnitaireNet: (o.quantite || 1) ? Math.round(montant / (o.quantite || 1)) : montant,
        montantBrut: brut,
        remise: remise,
        motifRemise: remise ? (o.motifRemise || 'Remise accordée') : null,
        montant: montant,
        partAssureur: partAssureur,
        partPersonnel: partPersonnel,
        partPatient: montant - partAssureur - partPersonnel,
        /* Le lien vers ce que la ligne couvre. */
        demandeId: o.demandeId || null,
        produitId: o.produitId || null,
        acteCode: o.acteCode || null,
        demandeImagerieId: o.demandeImagerieId || null,
        /* L'état de règlement, ligne par ligne. */
        statutPaiement: 'du',
        montantRegle: 0, payeLe: null, payePar: null,
      });
    }

    (v.medicaments || []).forEach(function (m) {
      ajouter({
        categorie: 'medicament', designation: m.produit,
        quantite: m.quantite, prixUnitaire: m.prix, montant: m.total,
        produitId: m.produitId,
      });
    });

    (v.analyses || []).forEach(function (a, i) {
      var dem = (v.demandes || [])[i];
      ajouter({
        categorie: 'analyse', designation: a.designation,
        quantite: 1, prixUnitaire: a.prix, montant: a.prix,
        demandeId: dem ? dem.id : null,
      });
    });

    (v.actes || []).forEach(function (a) {
      ajouter({
        categorie: 'acte', designation: a.libelle,
        quantite: 1, prixUnitaire: a.prix || 0, montant: a.prix || 0,
        acteCode: a.code,
      });
    });

    (v.autres || []).forEach(function (o) { ajouter(o); });
    return lignes;
  }

  /* ==========================================================================
   * LA PIÈCE CERTIFIANTE PASSE PAR LA CAISSE (22/09/2026)
   * --------------------------------------------------------------------------
   * Un certificat est une PRESTATION TARIFÉE : la grille lui donne un prix, et
   * la clinique l'encaisse. Il se délivrait pourtant sans qu'aucune pièce de
   * caisse ne naisse — le montant figurait sur la fiche, personne ne savait
   * s'il avait été réglé, et le total des « recettes des certificats » comptait
   * des sommes jamais entrées.
   *
   * L'ÉTAT DE RÈGLEMENT N'EST PAS STOCKÉ SUR LA PIÈCE : il se LIT sur la ligne
   * de facture, comme le laboratoire lit le règlement d'un examen sur la
   * sienne. Le porter en double donnerait deux vérités, et c'est toujours la
   * mauvaise qu'on afficherait.
   *
   * TROIS RÉPONSES, PAS DEUX — la troisième est celle qui manque toujours :
   *   réglé · à encaisser · SANS PIÈCE LIÉE, pour les certificats délivrés
   *   avant que la caisse ne soit dans le circuit. Les dire impayés serait
   *   aussi faux que les dire réglés.
   *
   * L'ASSURANCE NE COUVRE RIEN ICI, SAUF SOS : la répartition suit donc la
   * grille (`assurable === 'sos'`), et non le taux du dossier — un assuré NSIA
   * règle son certificat intégralement.
   * ======================================================================== */
  function facturerPiece(v) {
    var p = v.patient;
    if (!p) throw new Error('Aucun patient : la pièce ne peut pas être facturée.');
    var montant = Math.round(Number(v.montant) || 0);
    if (!(montant > 0)) return null; /* pièce non tarifée : rien à encaisser */

    var date = v.date || new Date().toISOString();
    /* Seul SOS couvre un certificat (mention manuscrite de la grille). */
    var couvert = v.assurable === 'sos' && String(p.assureur || '') === 'SOS' && carteValide(p, date);
    var taux = couvert ? (p.tauxPriseEnCharge || 0) : 0;

    var lignes = construireLignes({
      actes: [{ libelle: v.libelle || 'Pièce certifiante', prix: montant, code: v.acteCode || null }],
      taux: taux, personnelId: p.personnelId || null,
    });
    /* La ligne porte CE QU'ELLE COUVRE : sans ce lien, un règlement partiel ne
       saurait pas désigner la pièce qu'il solde.
       C'est la RÉFÉRENCE qui fait le lien, et non l'identifiant : la facture
       naît AVANT la pièce — on la numérote pour pouvoir la facturer, et elle
       n'est écrite au registre qu'ensuite. Attendre l'identifiant obligerait
       à repasser sur la facture après coup, donc à écrire deux fois. */
    lignes.forEach(function (l) {
      l.pieceRef = v.reference || null;
      if (v.pieceId) l.pieceId = v.pieceId;
    });

    var facture = col('factures').insert({
      lignes: lignes,
      numero: 'FC-' + String(new Date(date).getFullYear()) + '-' + C.pad(col('factures').all().length + 1, 5),
      numeroMecef: null,
      patientId: p.id, patient: p.nom + ' ' + p.prenom, patientCode: p.code,
      date: C.iso(new Date(date)), type: 'Certificat & attestation',
      montantHT: C.sum(lignes, 'montant'), montantTTC: C.sum(lignes, 'montant'),
      montantBrut: C.sum(lignes, 'montantBrut'), totalRemise: C.sum(lignes, 'remise'),
      partPersonnel: C.sum(lignes, 'partPersonnel'),
      priseEnChargePersonnel: !!p.personnelId, personnelId: p.personnelId || null,
      assureur: p.assureur || null, tauxPriseEnCharge: taux,
      partAssurance: C.sum(lignes, 'partAssureur'),
      partPatient: C.sum(lignes, 'partPatient'),
      montantPaye: 0, reliquat: C.sum(lignes, 'partPatient'),
      modePaiement: null,
      statutPaiement: 'impayee', statutMecef: 'en_attente',
      pieceId: v.pieceId || null,
      pieceRef: v.reference || null,
      motifCouverture: couvert
        ? 'Certificat couvert par SOS — seule compagnie conventionnée sur ces pièces'
        : 'Certificat non couvert par les assurances (mention de la grille tarifaire)',
    }).record;

    col('taches').insert({
      type: 'encaissement', poste: 'caisse',
      libelle: (v.libelle || 'Pièce certifiante') + ' — ' + p.nom + ' ' + p.prenom,
      detail: (v.reference || '') + ' — ' + C.money(montant, false),
      reference: facture.numero, factureId: facture.id,
      patientId: p.id, patient: p.nom + ' ' + p.prenom,
      montant: facture.partPatient, statut: 'en_attente', creeLe: date,
    });

    return facture;
  }

  /**
   * L'état de règlement d'une pièce certifiante, LU sur sa facture.
   * @returns {{code:string,label:string,ton:string,detail:string,facture:Object}}
   */
  function statutPiece(piece) {
    if (!piece) return { code: 'inconnu', label: '—', ton: 'neutral', detail: '', facture: null };
    if (!piece.montant) {
      return { code: 'non_tarife', label: 'Non tarifée', ton: 'neutral',
        detail: 'Aucun tarif à la grille : rien à encaisser.', facture: null };
    }
    var f = piece.factureId ? col('factures').get(piece.factureId) : null;
    if (!f) {
      return { code: 'sans_piece', label: 'En attente', ton: 'warning',
        detail: 'Aucune pièce de caisse liée — certificat délivré avant que la caisse ne soit '
          + 'dans le circuit. Ni réglé, ni impayé : on ne sait pas.', facture: null };
    }
    var due = lignesDues(f).length;
    if (!due) {
      return { code: 'regle', label: 'Réglé', ton: 'success',
        detail: 'Réglé à la caisse — pièce ' + f.numero + '.', facture: f };
    }
    return { code: 'a_encaisser', label: 'À encaisser', ton: 'danger',
      detail: 'Le patient doit se présenter à la caisse avec la pièce ' + f.numero
        + ' — reste dû ' + C.money(f.reliquat || f.partPatient, false) + '.', facture: f };
  }

  /** Les lignes encore dues d'une facture, dans l'ordre de la pièce. */
  function lignesDues(facture) {
    return (facture.lignes || []).filter(function (l) { return l.statutPaiement !== 'paye'; });
  }

  /** Les lignes réglées d'une facture. */
  function lignesReglees(facture) {
    return (facture.lignes || []).filter(function (l) { return l.statutPaiement === 'paye'; });
  }

  /* ==========================================================================
   * LE COMPTABLE EST INFORMÉ
   * --------------------------------------------------------------------------
   * « La caisse valide → le comptable est informé. » Informer ne suffit pas :
   * un encaissement qui ne produit pas d'écriture oblige à ressaisir la
   * recette à la main, et c'est exactement ce que la clinique fait aujourd'hui
   * entre PERFECTO et la caisse.
   *
   * L'écriture est EQUILIBRÉE (RG-10) et double quand le patient est assuré :
   *   — débit  571 Caisse            de la part réglée par le patient ;
   *   — débit  411 Clients assurance de la part restant due par l'assureur ;
   *   — crédit 706 Prestations       du total facturé.
   *
   * Elle naît en BROUILLON : la validation comptable reste un geste humain.
   * ======================================================================== */
  var COMPTES_CAISSE = {
    caisse: { num: '571000', libelle: 'Caisse' },
    clientsAssurance: { num: '411110', libelle: 'Clients compagnie d’assurance' },
    prestations: { num: '706000', libelle: 'Services vendus — prestations de soins' },
  };

  /* LA PART ASSUREUR SE CONSTATE UNE SEULE FOIS (correction du 30/10/2026, écart E1 de ECARTS-MAQUETTE.md).
     Elle était ré-inscrite à CHAQUE versement partiel : une facture assurée réglée en deux fois par le patient posait
     deux fois la créance sur la compagnie (411) et deux fois le produit correspondant (706). Désormais le PREMIER
     versement constate la créance assureur ; les suivants ne constatent que ce que le patient verse.
     Au total, sur la vie de la facture : 706 = montant facturé, 411 = part assureur, 571 = part patient. */
  function creanceAssureurDejaConstatee(facture) {
    return col('ecritures').all().some(function (e) {
      return e.pieceId === facture.id && e.compte === COMPTES_CAISSE.clientsAssurance.num && e.statut !== 'archive';
    });
  }

  /* LE NUMÉRO DE PIÈCE EST UNE SÉRIE ANNUELLE (correction du 30/10/2026, écart E3). Il prenait les cinq derniers chiffres
     du numéro de facture — deux factures de deux années pouvaient se heurter, une facture sans chiffres donnait « CAI-2026-8 »
     — et le millésime était écrit en dur. Désormais : le millésime est celui de la date de l'écriture, le rang est le
     suivant de la série de l'année, et les versements d'une même facture REPRENNENT le numéro de sa première écriture. */
  function numeroPieceCaisse(facture, date) {
    var existante = col('ecritures').all().filter(function (e) {
      return e.pieceId === facture.id && e.journal === 'CAI' && e.numero;
    })[0];
    if (existante) return existante.numero;
    var annee = String(date).slice(0, 4);
    var prefixe = 'CAI-' + annee + '-';
    var max = 0;
    col('ecritures').all().forEach(function (e) {
      if (typeof e.numero === 'string' && e.numero.indexOf(prefixe) === 0) {
        var n = parseInt(e.numero.slice(prefixe.length), 10);
        if (n > max) max = n;
      }
    });
    return prefixe + C.pad(max + 1, 5);
  }

  function ecrireEncaissement(facture, montantRegle) {
    var lignes = [];
    var constatee = creanceAssureurDejaConstatee(facture);
    /* L'EN-TÊTE d'une facture porte `partAssurance` ; `partAssureur` n'existe que sur les LIGNES (correction du 06/11/2026, E2260) :
       lire ce dernier champ sur l'en-tête donnait toujours zéro, et la créance de l'assureur (débit 411, crédit 706) n'entrait jamais au journal. */
    var partAssureur = constatee ? 0 : (Number(facture.partAssurance != null ? facture.partAssurance : facture.partAssureur) || 0);
    var total = montantRegle + partAssureur;
    if (total <= 0) return [];

    var date = C.iso(new Date());
    var numero = numeroPieceCaisse(facture, date);
    var base = {
      numero: numero, date: date,
      journal: 'CAI', journalLibelle: 'Journal de caisse-dépenses',
      libelle: 'Encaissement facture ' + (facture.numero || facture.id)
        + ' — ' + (facture.patient || ''),
      pieceId: facture.id, pieceNumero: facture.numero,
      origine: 'Automatique — Caisse',
      statut: 'brouillon',
    };

    if (montantRegle > 0) {
      lignes.push(Object.assign({}, base, {
        compte: COMPTES_CAISSE.caisse.num, compteLibelle: COMPTES_CAISSE.caisse.libelle,
        debit: montantRegle, credit: 0,
      }));
    }
    if (partAssureur > 0) {
      lignes.push(Object.assign({}, base, {
        compte: COMPTES_CAISSE.clientsAssurance.num,
        compteLibelle: COMPTES_CAISSE.clientsAssurance.libelle,
        debit: partAssureur, credit: 0,
        libelle: base.libelle + ' — part ' + (facture.assureur || 'assureur'),
      }));
    }
    lignes.push(Object.assign({}, base, {
      compte: COMPTES_CAISSE.prestations.num, compteLibelle: COMPTES_CAISSE.prestations.libelle,
      debit: 0, credit: total,
    }));

    /* Contrôle RG-10 avant écriture : un déséquilibre ne doit pas entrer au
       journal, fût-il en brouillon. */
    var debit = lignes.reduce(function (n, l) { return n + l.debit; }, 0);
    var credit = lignes.reduce(function (n, l) { return n + l.credit; }, 0);
    if (debit !== credit) {
      S.log('Écriture d’encaissement refusée — déséquilibre', 'M12', 'Ecriture', numero,
        null, { debit: debit, credit: credit });
      return [];
    }

    var posees = lignes.map(function (l) { return col('ecritures').insert(l).record; });
    S.log('Écriture d’encaissement', 'M12', 'Ecriture', numero, null,
      { debit: debit, credit: credit, lignes: posees.length });
    return posees;
  }

  /* ==========================================================================
   * LE STOCK EST INFORMÉ
   * --------------------------------------------------------------------------
   * « Le stock est informé des stocks épuisés et de l'approvisionnement. »
   * Une délivrance qui fait passer un article sous son seuil doit le dire au
   * gestionnaire — au moment où elle a lieu, et non le jour de l'inventaire.
   *
   * Le seuil est celui que la clinique a fixé (il est absent du document
   * SAGE) : sans seuil, aucune alerte n'est possible, et l'article est
   * signalé comme tel plutôt que passé sous silence.
   * ======================================================================== */
  function alerterStock(produitIds, justificatif) {
    var alertes = [];
    (produitIds || []).forEach(function (id) {
      var prod = produitParId(id);
      if (!prod) return;
      var dispo = prod.stockDetail != null ? prod.stockDetail : prod.stock;
      var seuil = prod.seuilAlerte;
      var niveau = null;
      if (dispo <= 0) niveau = 'rupture';
      else if (seuil != null && seuil !== '' && dispo <= seuil) niveau = 'alerte';
      else if (seuil == null || seuil === '') niveau = 'sansSeuil';
      if (!niveau || niveau === 'sansSeuil') {
        if (niveau === 'sansSeuil') {
          alertes.push({ produit: prod, niveau: niveau, dispo: dispo, seuil: null });
        }
        return;
      }
      /* Une seule tâche ouverte par article : réalerter à chaque sortie
         noierait le gestionnaire sous les doublons. */
      var deja = taches().filter(function (t) {
        return t.type === 'reapprovisionnement' && t.produitId === id
          && t.statut !== 'termine';
      })[0];
      if (deja) {
        col('taches').update(deja.id, {
          stockRestant: dispo,
          libelle: (niveau === 'rupture' ? 'RUPTURE — ' : 'Sous le seuil — ') + prod.designation,
        });
      } else {
        col('taches').insert({
          type: 'reapprovisionnement', poste: 'stock',
          libelle: (niveau === 'rupture' ? 'RUPTURE — ' : 'Sous le seuil — ') + prod.designation,
          produitId: id, produitCode: prod.code,
          stockRestant: dispo, seuil: seuil,
          justificatif: justificatif || null,
          statut: 'en_attente', priorite: niveau === 'rupture' ? 'haute' : 'normale',
          creeLe: new Date().toISOString(),
        });
      }
      alertes.push({ produit: prod, niveau: niveau, dispo: dispo, seuil: seuil });
    });
    return alertes;
  }

  /**
   * encaisser(factureId, opts)
   *
   * opts.lignes   — identifiants des lignes réglées. C'est la forme JUSTE :
   *                 la caisse encaisse des prestations nommées.
   * opts.montant  — forme héritée. Le montant est alors ALLOUÉ aux lignes
   *                 encore dues, dans l'ordre de la pièce, jusqu'à épuisement.
   *                 Une ligne n'est réglée que si elle l'est entièrement :
   *                 un demi-examen ne se prélève pas.
   *
   * Dans les deux cas le résultat est le même — des lignes réglées, nommées,
   * et un déblocage qui ne porte que sur elles.
   */
  function encaisser(factureId, opts) {
    opts = opts || {};
    var fac = col('factures').get(factureId);
    if (!fac) throw new Error('Facture introuvable.');
    if (fac.statutPaiement === 'soldee') return { facture: fac, deja: true, lignesReglees: [] };

    /* La fenêtre « Facture normalisée » (IFU de l'acheteur, nom, AIB) se contrôle AVANT toute écriture : un refus nommé n'écrit rien. */
    var acheteurSaisi = null;
    if (opts.acheteur) {
      acheteurSaisi = validerAcheteurMecef(opts.acheteur);
      if (!acheteurSaisi.ok) {
        return {
          facture: fac, refus: acheteurSaisi.code + ' : ' + acheteurSaisi.motif + ' ' + acheteurSaisi.geste, refusNomme: acheteurSaisi,
          debloquees: [], ecritures: [], lignesReglees: [], montantRegle: 0,
          restantDu: (fac.lignes || []).filter(function (l) { return l.statutPaiement !== 'paye'; }).reduce(function (n, l) { return n + l.partPatient; }, 0),
          demandesLiberees: [],
        };
      }
    }

    var toutes = fac.lignes || [];
    var duTotal = fac.partPatient != null ? fac.partPatient : fac.montantTTC;

    /* --- Quelles lignes sont réglées par ce versement ? ------------------ */
    var reglees = [];
    var paye = 0;

    if (opts.lignes && opts.lignes.length) {
      var vises = {};
      opts.lignes.forEach(function (id) { vises[id] = true; });
      toutes.forEach(function (l) {
        if (l.statutPaiement === 'paye' || !vises[l.id]) return;
        reglees.push(l); paye += l.partPatient;
      });
    } else if (toutes.length) {
      /* Allocation d'un montant global : les lignes dues, dans l'ordre, tant
         que la somme versée les couvre ENTIÈREMENT. */
      var reste = opts.montant != null ? Number(opts.montant) : duTotal;
      toutes.forEach(function (l) {
        if (l.statutPaiement === 'paye') return;
        if (l.partPatient <= reste) { reglees.push(l); reste -= l.partPatient; paye += l.partPatient; }
      });
    } else {
      /* Facture sans lignes — pièce antérieure au modèle. On conserve le
         comportement par montant plutôt que de la rendre inencaissable, mais JAMAIS au-delà du dû
         (écart E2, corrigé le 31/10/2026) : sans ligne pour borner le versement, 99 999 sur 5 000 dus
         faisaient dépasser le TTC à `montantPaye` et à la base MECeF. Le refus NOMME le défaut. */
      var restantPiece = Math.max(0, duTotal - (fac.montantPaye || 0));
      var voulu = opts.montant != null ? Number(opts.montant) : restantPiece;
      if (!(voulu >= 0) || voulu > restantPiece) {
        return {
          facture: fac, refus: 'Versement de ' + C.money(voulu) + ' refusé : la pièce ' + (fac.numero || fac.id)
            + ' ne porte aucune ligne et ne doit plus que ' + C.money(restantPiece) + '. Un versement ne dépasse jamais le dû.',
          debloquees: [], ecritures: [], lignesReglees: [], montantRegle: 0, restantDu: restantPiece,
          demandesLiberees: [],
        };
      }
      paye = voulu;
    }

    /* --- Report sur la facture ------------------------------------------- */
    var lignesMaj = toutes.map(function (l) {
      if (reglees.indexOf(l) === -1) return l;
      return Object.assign({}, l, {
        statutPaiement: 'paye', montantRegle: l.partPatient,
        payeLe: new Date().toISOString(),
        payePar: opts.utilisateur || S.currentUser(),
      });
    });
    var totalPaye = (fac.montantPaye || 0) + paye;
    var restantDu = lignesMaj.length
      ? lignesMaj.filter(function (l) { return l.statutPaiement !== 'paye'; })
        .reduce(function (n, l) { return n + l.partPatient; }, 0)
      : Math.max(0, duTotal - totalPaye);
    var solde = restantDu <= 0;

    /* LA BASE MECeF NAÎT DE LA FONCTION UNIQUE DES MONTANTS : seule la part PATIENT des lignes réglées par ce versement s'ajoute (ni part
       assureur, ni remise). Les montants des pièces ne changent pas : la fonction retrouve exactement ce qui a été alloué. Une ligne que la
       fonction refuse (prix décimal d'une pièce ancienne) ne bloque pas l'encaissement : la base reste le total réglé, et c'est la
       NORMALISATION qui refuse en nommant la ligne. */
    var baseVersement = null;
    if (reglees.length) {
      var mv = mecefMontants({ lignes: reglees.map(ligneVersMecef) });
      if (mv.ok) baseVersement = mv.base;
    }
    var baseMecef = baseVersement != null ? (fac.montantPaye || 0) + baseVersement : totalPaye;

    col('factures').update(factureId, Object.assign({
      lignes: lignesMaj,
      montantPaye: totalPaye,
      reliquat: restantDu,
      modePaiement: opts.mode || 'especes',
      statutPaiement: solde ? 'soldee' : (totalPaye > 0 ? 'partielle' : 'impayee'),
      /* TOUTE VENTE EST NORMALISÉE (Direction, 07/11/2026) : l'état se décide plus bas, par la normalisation de la vente soldée. */
      statutMecef: 'en_attente',
      /* Le point fiscal du dossier : seule la part réglée est normalisée. */
      baseMecef: baseMecef,
      dernierReglement: {
        date: new Date().toISOString(), montant: paye, mode: opts.mode || 'especes',
        lignes: reglees.map(function (l) { return l.id; }),
        encaissePar: opts.utilisateur || S.currentUser(),
      },
    }, acheteurSaisi ? Object.assign({ ifuClient: acheteurSaisi.acheteur.ifu, acheteurNom: acheteurSaisi.acheteur.nom }, traceAibAcheteur(acheteurSaisi.acheteur)) : {}));
    fac = col('factures').get(factureId);

    /* La vente SOLDÉE passe par la normalisation (faux boîtier) ; un règlement partiel attend le solde. Le refus de la normalisation ne défait
       pas l'encaissement (l'argent est reçu) : la pièce devient « refusée » ou « à vérifier », nommément, et se retransmet ensuite. */
    var normalisation = solde ? normaliserVente(factureId, { acheteur: opts.acheteur, utilisateur: opts.utilisateur }) : null;
    if (normalisation) fac = col('factures').get(factureId);

    /* --- Le laboratoire : SEULES les analyses réglées passent ------------- */
    var demandesLiberees = [];
    reglees.forEach(function (l) {
      if (l.categorie !== 'analyse' || !l.demandeId) return;
      var d = S.collection('demandesAnalyses').get(l.demandeId);
      if (!d) return;
      S.collection('demandesAnalyses').update(l.demandeId, {
        bloqueParPaiement: false, statutPaiement: 'soldee',
        etatAnalyse: d.etatAnalyse === 'valide' ? 'valide' : 'attente_prelevement',
        regleLe: new Date().toISOString(),
      });
      demandesLiberees.push(d.reference || d.id);
    });

    /* --- L'imagerie suit la même règle : la séance réglée passe ----------- */
    reglees.forEach(function (l) {
      if (l.categorie !== 'imagerie' || !l.demandeImagerieId) return;
      var di = S.collection('demandesImagerie').get(l.demandeImagerieId);
      if (!di) return;
      S.collection('demandesImagerie').update(l.demandeImagerieId, {
        bloqueParPaiement: false,
        statut: di.statut === 'demandee' ? 'payee' : di.statut,
        regleLe: new Date().toISOString(),
      });
      demandesLiberees.push(di.reference || di.id);
    });

    var debloquees = [];
    if (fac.statutPaiement === 'soldee') {
      /* La tâche de caisse est faite ; celles d'aval s'ouvrent. */
      taches().filter(function (t) { return t.factureId === factureId; }).forEach(function (t) {
        if (t.type === 'encaissement') { terminer(t.id, opts.utilisateur); return; }
        if (t.statut === 'bloque') {
          col('taches').update(t.id, { statut: 'en_attente' });
          debloquees.push(t.type);
        }
      });
      /* Facture soldée : ce qui resterait bloqué faute de ligne — les pièces
         antérieures au modèle par lignes — est libéré ici. Les analyses déjà
         libérées ligne par ligne ne sont pas retouchées. */
      S.collection('demandesAnalyses').all().forEach(function (d) {
        if (!d.bloqueParPaiement) return;
        if (d.factureId === factureId || (fac.ordonnanceId && d.ordonnanceId === fac.ordonnanceId)) {
          S.collection('demandesAnalyses').update(d.id, {
            bloqueParPaiement: false,
            statutPaiement: 'soldee',
            etatAnalyse: d.etatAnalyse === 'valide' ? 'valide' : 'attente_prelevement',
            regleLe: new Date().toISOString(),
          });
          demandesLiberees.push(d.reference || d.id);
        }
      });
      S.collection('demandesImagerie').all().forEach(function (di) {
        if (!di.bloqueParPaiement || di.factureId !== factureId) return;
        S.collection('demandesImagerie').update(di.id, {
          bloqueParPaiement: false,
          statut: di.statut === 'demandee' ? 'payee' : di.statut,
          regleLe: new Date().toISOString(),
        });
        demandesLiberees.push(di.reference || di.id);
      });
      if (fac.ordonnanceId) col('ordonnances').update(fac.ordonnanceId, { statutPaiement: 'soldee' });
    }

    /* Le comptable est informé — par une écriture, pas par un message.
       Elle est posée à CHAQUE versement, y compris partiel : attendre le
       solde laisserait la caisse et la comptabilité divergentes entre-temps. */
    var ecritures = paye > 0 ? ecrireEncaissement(fac, paye) : [];

    S.log('Encaissement', 'M8', 'facture', fac.numero, { statutPaiement: 'impayee' },
      {
        statutPaiement: fac.statutPaiement, montantPaye: totalPaye,
        verse: paye, lignes: reglees.length, restantDu: restantDu,
      });

    return {
      facture: fac, debloquees: debloquees, ecritures: ecritures,
      lignesReglees: reglees, montantRegle: paye,
      restantDu: restantDu, demandesLiberees: demandesLiberees,
      normalisation: normalisation,
    };
  }

  /* ==========================================================================
   * LE CANAL UNIQUE DE L'AVOIR (décision de la Direction du 31/10/2026, B10)
   * --------------------------------------------------------------------------
   * Une pièce émise ne se réécrit jamais : un seul mécanisme la corrige. Il vivait dans m8-facturation.js ; il vit AU SOCLE
   * depuis le 31/10/2026 parce que l'écran de facturation (nature « Facture avoir »), l'avoir MECeF et l'écran des avoirs
   * l'APPELLENT tous, et qu'une page ne charge que le module de son écran. Trois canaux (E12, E15) n'en font plus qu'un :
   * la collection `avoirs`, plafond CUMULÉ partout, montant strictement positif, lignes nommées, contre-passation plate en
   * brouillon (RG-10). La DATE d'une pièce est un JOUR ; l'instant d'émission est porté à part (`horodatage`, E4).
   * ======================================================================== */
  META.avoirs = { module: 'M8', entite: 'facture d’avoir', prefix: 'AVR' };
  META.ecritures = { module: 'M12', entite: 'écriture' };

  /** Référence d'un avoir : série annuelle lue sur les avoirs déjà émis (millésime de la DATE de l'avoir, rang de l'année). */
  function referenceAvoir(date) {
    return C.referenceSuivante('AV-' + String(date).slice(0, 4) + '-', 4, col('avoirs').all());
  }

  /** Émet un avoir. Retourne { record, ecritureIds } ou { erreur } : un refus se lit, il ne se devine pas.
      params : { lignes:[{designation, montant}], motif, remboursement:'creance'|'especes', observations, date, origine }. */
  function emettreAvoir(factureId, params) {
    params = params || {};
    var fac = col('factures').get(factureId);
    if (!fac) return { erreur: 'Facture introuvable.' };
    if (fac.type === 'Avoir' || (fac.montantTTC || 0) < 0) {
      return { erreur: 'La pièce ' + fac.numero + ' est elle-même un avoir : on ne rectifie pas un avoir.' };
    }

    /* UNE FILLE CONSOLIDÉE EST FIGÉE : la mère émise porte son numéro, et la compagnie détient la pièce. */
    var mere = S.collection('facturesMere').active().filter(function (m) {
      return (m.piecesFilles || []).indexOf(fac.numero) !== -1;
    })[0];
    if (mere) {
      return { erreur: 'La facture ' + fac.numero + ' est consolidée dans la facture mère '
        + mere.numero + ' (' + (mere.compagnie || '') + '), déjà émise : la corriger passerait '
        + 'derrière le dos de la compagnie. Émettre l’avoir au niveau de la mère, par avenant.' };
    }

    var lignes = params.lignes || [];
    if (!lignes.length) return { erreur: 'Un avoir se rapporte à des LIGNES nommées — en cocher au moins une.' };
    var montant = C.sum(lignes, 'montant');
    if (!(montant > 0)) return { erreur: 'Le montant de l’avoir doit être strictement supérieur à 0 FCFA.' };

    var dejaMontant = C.sum(col('avoirs').active().filter(function (a) { return a.factureId === fac.id; }), 'montant');
    if (montant + dejaMontant > (fac.montantTTC || 0)) {
      return { erreur: 'Le cumul des avoirs (' + C.money(montant + dejaMontant)
        + ') excéderait la facture (' + C.money(fac.montantTTC) + ').' };
    }

    var date = jourDe(params.date || new Date());
    var rec = col('avoirs').insert({
      reference: referenceAvoir(date),
      date: date,
      horodatage: new Date().toISOString(),
      factureId: fac.id, factureNumero: fac.numero,
      patientId: fac.patientId, patient: fac.patient, patientCode: fac.patientCode,
      montant: montant,
      motif: params.motif,
      observations: params.observations || '',
      lignesAnnulees: lignes,
      remboursement: params.remboursement || 'creance',
      origine: params.origine || 'caisse',
      /* Le registre fiscal : une facture normalisée validée exige la régularisation MECeF ; une pièce non transmise n'en relève pas. */
      statutMecef: fac.statutMecef === 'valide' ? 'en_attente' : 'sans_objet',
      emisPar: S.currentUser(),
    }).record;

    /* LA CONTRE-PASSATION : écritures PLATES en brouillon, débit 706 (la recette diminue), crédit 571 si l'on rembourse en
       espèces, crédit 411 sinon (la créance diminue). */
    var base = {
      numero: rec.reference, date: rec.date,
      journal: 'CAI', journalLibelle: 'Journal de caisse-dépenses',
      pieceId: rec.id, pieceNumero: rec.reference,
      origine: 'Facture d’avoir',
      statut: 'brouillon',
    };
    var contre = rec.remboursement === 'especes'
      ? { compte: '571000', libelle: 'Remboursement en espèces — avoir ' + rec.reference }
      : { compte: '411000', libelle: 'Créance réduite — avoir ' + rec.reference };
    var ecritures = [
      Object.assign({}, base, {
        compte: '706000', compteLibelle: 'Prestations de services',
        libelle: 'Contre-passation — ' + fac.numero + ' (' + params.motif + ')',
        debit: montant, credit: 0,
      }),
      Object.assign({}, base, {
        compte: contre.compte, compteLibelle: contre.compte === '571000' ? 'Caisse' : 'Clients',
        libelle: contre.libelle,
        debit: 0, credit: montant,
      }),
    ];
    var debit = C.sum(ecritures, 'debit'), credit = C.sum(ecritures, 'credit');
    if (debit !== credit) {
      col('avoirs').archive(rec.id);
      return { erreur: 'RG-10 — contre-passation déséquilibrée (débit ' + C.money(debit)
        + ', crédit ' + C.money(credit) + ') : rien n’est écrit.' };
    }
    var ids = ecritures.map(function (l) { return col('ecritures').insert(l).record.id; });
    col('avoirs').update(rec.id, { ecritureIds: ids });

    /* La facture PORTE ses avoirs, elle n'est jamais réécrite : la pièce d'origine et sa correction se lisent côte à côte. */
    col('factures').update(fac.id, {
      avoirIds: (fac.avoirIds || []).concat([rec.id]),
      montantAvoirs: (fac.montantAvoirs || 0) + montant,
    });

    S.log('Facture d’avoir émise', 'M8', 'Avoir', rec.reference, null,
      { facture: fac.numero, montant: montant, motif: params.motif, origine: rec.origine });
    return { record: col('avoirs').get(rec.id), ecritureIds: ids };
  }

  /** Retire un avoir qu'on vient d'émettre (annulation visible d'un geste) : archivé avec ses écritures, jamais supprimé (RG-14),
      et la facture rend le montant du plafond cumulé. */
  function retirerAvoir(avoirId) {
    var a = col('avoirs').get(avoirId);
    if (!a) return false;
    (a.ecritureIds || []).forEach(function (id) { col('ecritures').archive(id); });
    col('avoirs').archive(a.id);
    var fac = col('factures').get(a.factureId);
    if (fac) {
      col('factures').update(fac.id, {
        avoirIds: (fac.avoirIds || []).filter(function (x) { return x !== a.id; }),
        montantAvoirs: Math.max(0, (fac.montantAvoirs || 0) - (a.montant || 0)),
      });
    }
    S.log('Facture d’avoir retirée', 'M8', 'Avoir', a.reference, null, { montant: a.montant });
    return true;
  }

  /* ==========================================================================
   * 3. LA PHARMACIE DÉLIVRE
   * --------------------------------------------------------------------------
   * RG-03 : chaque sortie porte son justificatif — le numéro d'ordonnance — et
   * le stock ne peut pas passer sous zéro. Une ligne insuffisante bloque la
   * délivrance entière plutôt que de servir à moitié sans le dire.
   * ======================================================================== */
  function verifierStock(ordonnanceId) {
    var ord = col('ordonnances').get(ordonnanceId);
    if (!ord) throw new Error('Ordonnance introuvable.');
    /* RG-03 : le CUMUL des lignes d'un même produit est contrôlé — deux lignes de 5 sur un stock de 8 passaient chacune seule et laissaient
       un stock NÉGATIF (écart E42, corrigé le 30/10/2026). `disponible` est ce qui reste APRÈS les lignes précédentes du même produit. */
    var prises = {};
    return (ord.medicaments || []).map(function (l) {
      var prod = produitParId(l.produitId);
      var total = prod ? (prod.stockDetail != null ? prod.stockDetail : prod.stock) : 0;
      var dispo = total - (prises[l.produitId] || 0);
      if (prod) prises[l.produitId] = (prises[l.produitId] || 0) + l.quantite;
      return { ligne: l, produit: prod, disponible: dispo, suffisant: prod && dispo >= l.quantite };
    });
  }

  /* Valorisation d'une sortie de stock — paramétrable (annotation manuscrite
     de la réunion du 30/12/2024). Le mouvement porte LES DEUX valeurs : sans
     cela, changer de méthode rendrait l'historique incomparable. */
  function valoriserSortie(produit, quantite) {
    var pv = (produit.prixVente != null ? produit.prixVente : produit.prixAchat) || 0;
    var cump = produit.cump != null ? produit.cump : pv;
    var methode = S.valorisationSortie();
    var retenu = methode === 'cump' ? cump : pv;
    return {
      methode: methode,
      valeur: Math.round(retenu * quantite),
      valeurPrixVente: Math.round(pv * quantite),
      valeurCump: Math.round(cump * quantite),
      ecart: Math.round((pv - cump) * quantite),
    };
  }

  /** Alerte le gestionnaire de stock après une sortie. Voir alerterStock(). */
  function delivrer(ordonnanceId, opts) {
    opts = opts || {};
    var ord = col('ordonnances').get(ordonnanceId);
    if (!ord) throw new Error('Ordonnance introuvable.');
    if (ord.statutPaiement !== 'soldee') throw new Error('Facture non réglée — la délivrance est bloquée.');
    if (ord.statutDispensation === 'servie') return { ordonnance: ord, deja: true };

    var etat = verifierStock(ordonnanceId);
    var manquants = etat.filter(function (e) { return !e.suffisant; });
    if (manquants.length) {
      /* RG-03 — jamais de stock négatif : on refuse et on dit lequel. */
      var e = new Error('Stock insuffisant : ' + manquants.map(function (m) {
        return m.ligne.produit + ' (' + m.disponible + ' pour ' + m.ligne.quantite + ' demandés)';
      }).join(', '));
      e.manquants = manquants;
      throw e;
    }

    var mouvements = etat.map(function (x) {
      var prod = x.produit;
      var reste = (prod.stockDetail != null ? prod.stockDetail : prod.stock) - x.ligne.quantite;
      S.collection('produits').update(prod.id, {
        stockDetail: prod.stockDetail != null ? reste : prod.stockDetail,
        stock: Math.max(0, (prod.stock || 0) - x.ligne.quantite),
      });
      var val = valoriserSortie(prod, x.ligne.quantite);
      return col('mouvements').insert({
        /* Série lue sur les mouvements EXISTANTS, jamais sur un compteur de page qui repart à 1 à chaque chargement (écart E41b, cf. E8). */
        reference: C.referenceSuivante('M', 6, col('mouvements').all()),
        date: new Date().toISOString(),
        produitId: prod.id, produit: prod.designation,
        type: 'sortie', typeLabel: 'Sortie',
        quantite: x.ligne.quantite,
        stockType: 'detail',
        justificatif: 'Ordonnance ' + ord.numero,
        ordonnanceId: ord.id,
        /* Valorisation : méthode retenue et les deux valeurs, pour comparaison. */
        valorisation: val.methode, valeur: val.valeur,
        valeurPrixVente: val.valeurPrixVente, valeurCump: val.valeurCump,
        utilisateur: opts.utilisateur || S.currentUser(),
      }).record;
    });

    col('ordonnances').update(ordonnanceId, {
      statutDispensation: 'servie',
      dispenseLe: new Date().toISOString(),
      dispensePar: opts.utilisateur || S.currentUser(),
    });
    taches().filter(function (t) { return t.ordonnanceId === ordonnanceId && t.type === 'dispensation'; })
      .forEach(function (t) { terminer(t.id, opts.utilisateur); });

    S.log('Dispensation', 'M6', 'ordonnance', ord.numero, { statutDispensation: 'en_attente' },
      { statutDispensation: 'servie', lignes: mouvements.length });

    /* Le gestionnaire de stock est informé au moment où la sortie a lieu, et
       non le jour de l’inventaire : c’est la sortie qui fait passer sous le
       seuil, c’est elle qui doit le dire. */
    var alertes = alerterStock(etat.map(function (x) { return x.produit ? x.produit.id : null; })
      .filter(Boolean), ord.numero);

    return { ordonnance: col('ordonnances').get(ordonnanceId), mouvements: mouvements, alertes: alertes };
  }

  /* ==========================================================================
   * 4. FILES D'ATTENTE
   * ======================================================================== */
  function taches() { return col('taches').active(); }

  /** Ce qui attend un poste de travail : d'abord l'urgent, puis le plus ancien. */
  function aFaire(role, type) {
    return taches().filter(function (t) {
      if (t.statut === 'fait') return false;
      if (role && t.role !== role) return false;
      if (type && t.type !== type) return false;
      return true;
    }).sort(function (a, b) {
      if (!!b.urgent !== !!a.urgent) return b.urgent ? 1 : -1;
      return String(a.date).localeCompare(String(b.date));
    });
  }

  function terminer(tacheId, utilisateur) {
    return col('taches').update(tacheId, {
      statut: 'fait', faitLe: new Date().toISOString(), faitPar: utilisateur || S.currentUser(),
    });
  }

  /** Compteurs d'attente, pour les badges des tableaux de bord. */
  function compteurs(role) {
    var out = { total: 0 };
    aFaire(role).forEach(function (t) {
      out[t.type] = (out[t.type] || 0) + 1;
      if (t.statut === 'en_attente') out.total++;
    });
    return out;
  }

  /** Toutes les pièces attachées à une ordonnance — vue de bout en bout. */
  function dossier(ordonnanceId) {
    var ord = col('ordonnances').get(ordonnanceId);
    if (!ord) return null;
    return {
      ordonnance: ord,
      facture: ord.factureId ? col('factures').get(ord.factureId) : null,
      demandes: S.collection('demandesAnalyses').all().filter(function (d) { return d.ordonnanceId === ordonnanceId; }),
      demandesImagerie: S.collection('demandesImagerie').all().filter(function (d) { return d.ordonnanceId === ordonnanceId; }),
      mouvements: S.collection('mouvements').all().filter(function (m) { return m.ordonnanceId === ordonnanceId; }),
      taches: taches().filter(function (t) { return t.ordonnanceId === ordonnanceId; }),
    };
  }

  /* ==========================================================================
   * PRISE EN CHARGE — répartition ligne par ligne
   * --------------------------------------------------------------------------
   * Le cahier de charge du 30/12/2024 l'exige : « appliquer des pourcentages
   * par article et par prestation », le taux variant « d'une assurance à
   * l'autre et, pour un même assuré, selon la nature de l'article ». Un taux
   * unique par patient ne peut pas exprimer cela.
   *
   * La répartition suit donc quatre questions, dans cet ordre :
   *   1. la carte est-elle valide à la date de facturation ?      (RG-09)
   *   2. la ligne est-elle exclue par la convention ?
   *   3. exige-t-elle un accord préalable, et l'a-t-on ?
   *   4. quelle garantie couvre sa catégorie, à quel taux, sous quel plafond ?
   *
   * Chaque ligne repart avec son MOTIF : une part patient à 100 % doit toujours
   * pouvoir s'expliquer au guichet.
   * ======================================================================== */
  /* Le souscripteur suit la couverture de la DATE : c’est l’employeur qui
     porte la grille, et un assuré qui change d’employeur change de grille. */
  function souscripteurDe(patient, date) {
    if (!patient) return null;
    var id = patient.souscripteurId;
    if (date) {
      var c = couvertureALaDate(patient, date);
      if (c) id = c.souscripteurId || null;
      else return null;
    }
    if (!id) return null;
    return S.collection('souscripteurs').get(id);
  }

  /** Garanties applicables : celles du souscripteur, sinon celles de la compagnie, chacune dans sa VERSION EN VIGUEUR à la date. */
  function garantiesDe(patient, date) {
    /* La grille est celle du souscripteur DE LA DATE : un assuré qui a changé
       d’employeur en cours d’année n’avait pas le même barème en janvier. */
    var sous = souscripteurDe(patient, date);
    if (!sous) return [];
    var jour = jourDe(date || new Date());
    var toutes = S.collection('garanties').active();
    var propres = toutes.filter(function (g) { return g.souscripteurId === sous.id; });
    /* Un souscripteur qui porte sa propre grille la porte seule, même si aucune de ses versions n'est encore en vigueur à cette date : pas de repli sur la compagnie. */
    if (propres.length) return garantiesEnVigueur(propres, jour);
    return garantiesEnVigueur(toutes.filter(function (g) { return !g.souscripteurId && g.assureur === sous.assureur; }), jour);
  }

  /* ==========================================================================
   * LES GARANTIES SONT DATÉES (lot IMP-B2, 12/11/2026)
   * --------------------------------------------------------------------------
   * Même mécanisme que les prix, la grille des primes et les couvertures : quand une donnée de référence change alors que des pièces ont été émises sous l'ancienne, on
   * VERSIONNE par date, on n'écrase jamais. Une garantie est une SÉRIE (souscripteur, catégorie, libellé) ; chaque changement de taux ou de plafond est une nouvelle ligne de la série,
   * portant sa `dateEffet` et son rang `version`. Une ligne sans `dateEffet` vaut « depuis l'origine » (les grilles saisies avant ce mécanisme restent lues telles quelles, aucune
   * date n'est inventée). `repartir` lit la version EN VIGUEUR à la date de la pièce ; l'écran « Conventions & garanties » et l'importation écrivent par la MÊME fabrique
   * (`poserGarantie`) : il n'y a pas de second chemin qui écraserait une version.
   * ======================================================================== */
  function colGaranties() { return S.collection('garanties', { module: 'M9', entite: 'garantie', prefix: 'GAR' }); }
  function cleSerieGarantie(g) { return [g.souscripteurId || ('~' + (g.assureur || '')), g.categorie || '', C.norm(g.libelle || '').trim()].join('|'); }
  /** UNE version par série : la plus récente dont la date d'effet est atteinte au jour dit (une ligne sans date vaut « depuis l'origine ») ; l'ordre d'origine est conservé. */
  function garantiesEnVigueur(rows, jour) {
    var parSerie = {};
    (rows || []).forEach(function (g, i) {
      if (g.dateEffet && g.dateEffet > jour) return;
      var k = cleSerieGarantie(g), cur = parSerie[k], d = g.dateEffet || '';
      if (!cur || d > (cur.g.dateEffet || '') || (d === (cur.g.dateEffet || '') && i > cur.i)) parSerie[k] = { g: g, i: i };
    });
    return Object.keys(parSerie).map(function (k) { return parSerie[k]; }).sort(function (a, b) { return a.i - b.i; }).map(function (x) { return x.g; });
  }
  /** Les versions d'une série, de la plus ancienne à la plus récente. */
  function versionsGarantie(souscripteurId, categorie, libelle) {
    var cle = cleSerieGarantie({ souscripteurId: souscripteurId, categorie: categorie, libelle: libelle });
    return colGaranties().active().filter(function (g) { return cleSerieGarantie(g) === cle; })
      .sort(function (a, b) { return String(a.dateEffet || '').localeCompare(String(b.dateEffet || '')); });
  }
  /** La première facture non archivée d'un assuré de ce souscripteur datée du jour dit ou après : ce qu'une version ne peut pas rattraper (la pièce émise garde son taux). */
  function factureSousGrille(sous, jour) {
    var patients = {};
    return S.collection('factures').active().filter(function (f) {
      if (!f.assureur || f.assureur !== sous.assureur || !f.date || String(f.date).slice(0, 10) < jour) return false;
      var p = patients[f.patientId] || (patients[f.patientId] = S.collection('patients').get(f.patientId) || false);
      var sd = p && souscripteurDe(p, f.date);
      return !!(sd && sd.id === sous.id);
    }).sort(function (a, b) { return String(a.date).localeCompare(String(b.date)); })[0] || null;
  }
  /**
   * poserGarantie(spec) : une VERSION de garantie, jamais un écrasement. Un refus se NOMME (code, motif, geste) ; `essai: true` contrôle sans écrire.
   * spec : { souscripteurId, categorie, libelle, taux, plafond, unitePlafond, dateEffet, sansDate?, source?, motif?, champs? }. `sansDate` n'est admis que pour la PREMIÈRE ligne d'une série
   * (la grille d'une convention saisie d'un bloc : « depuis l'origine », aucune date n'est inventée). `champs` : traces posées sur la fiche (lot d'import).
   */
  function poserGarantie(spec) {
    spec = spec || {};
    function refus(code, motif, geste) { return { ok: false, code: code, motif: motif, geste: geste }; }
    var sous = spec.souscripteurId ? S.collection('souscripteurs').get(spec.souscripteurId) : null;
    if (!sous || sous.statut === 'archive') return refus('SOUSCRIPTEUR_INCONNU', 'aucun souscripteur actif ne porte cette identité', 'Choisissez un souscripteur connu (écran « Souscripteurs ») ou importez-le d’abord.');
    var cat = D.CATEGORIES_GARANTIE.filter(function (x) { return x.id === spec.categorie; })[0];
    if (!cat) return refus('CATEGORIE_INCONNUE', 'la catégorie « ' + spec.categorie + ' » n’est pas une catégorie de garantie', 'Choisissez une catégorie de la liste.');
    var libelle = String(spec.libelle == null ? '' : spec.libelle).trim();
    if (!libelle) return refus('GARANTIE_SANS_LIBELLE', 'la garantie n’a pas de libellé : la série ne se distinguerait pas des autres garanties de la catégorie', 'Saisissez le libellé de la garantie.');
    var taux = spec.taux === '' || spec.taux == null ? NaN : Number(spec.taux);
    if (!isFinite(taux) || taux < 0 || taux > 100) return refus('TAUX_INVALIDE', 'le taux doit être un nombre de 0 à 100', 'Saisissez un pourcentage entre 0 et 100.');
    var plafond = spec.plafond === '' || spec.plafond == null ? null : Number(spec.plafond);
    if (plafond != null && (!isFinite(plafond) || plafond < 0 || Math.floor(plafond) !== plafond)) return refus('PLAFOND_INVALIDE', 'le plafond doit être un montant entier de francs, zéro ou plus', 'Saisissez un montant entier, ou laissez vide pour « sans plafond ».');
    var unite = plafond == null ? null : (spec.unitePlafond || null);
    if (plafond != null && !D.UNITES_PLAFOND.some(function (u) { return u.id === unite; })) return refus('UNITE_PLAFOND_REQUISE', 'un plafond se dit toujours « par quoi » (acte, jour, an…)', 'Choisissez l’unité du plafond.');
    var jour = spec.sansDate ? null : (spec.dateEffet ? (/^\d{4}-\d{2}-\d{2}$/.test(spec.dateEffet) ? spec.dateEffet : C.iso(spec.dateEffet)) : '');
    if (!spec.sansDate && !jour) return refus('DATE_EFFET_REQUISE', 'la date d’effet est obligatoire : sans elle, la nouvelle version ne se distinguerait pas de l’ancienne sur les pièces déjà émises', 'Saisissez la date à laquelle la garantie change.');
    var rows = versionsGarantie(sous.id, spec.categorie, libelle);
    if (spec.sansDate) {
      if (rows.length) return refus('SERIE_EXISTANTE', 'la garantie « ' + libelle + ' » existe déjà pour ce souscripteur : elle ne se redéfinit pas « depuis l’origine »', 'Posez une nouvelle version avec sa date d’effet.');
    } else {
      var meme = rows.filter(function (g) { return (g.dateEffet || '') === jour; })[0];
      var enForce = garantiesEnVigueur(rows, jour)[0];
      var identique = enForce && Number(enForce.taux) === taux && (enForce.plafond == null ? null : Number(enForce.plafond)) === plafond && (plafond == null || enForce.unitePlafond === unite);
      if (identique) return refus('GARANTIE_INCHANGEE', 'la garantie « ' + libelle + ' » porte déjà ce taux et ce plafond à cette date', 'Rien à faire : aucune version n’est créée.');
      if (meme) return refus('VERSION_MEME_DATE', 'une version de « ' + libelle + ' » prend déjà effet le ' + C.dateFR(jour) + ' avec d’autres valeurs : une version ne se réécrit pas', 'Choisissez une autre date d’effet.');
      var plusRecente = rows.filter(function (g) { return (g.dateEffet || '') > jour; })[0];
      if (plusRecente) return refus('VERSION_ANTERIEURE', 'une version plus récente de « ' + libelle + ' » prend effet le ' + C.dateFR(plusRecente.dateEffet) + ' : on ne glisse pas une version dans le passé d’une série', 'Choisissez une date d’effet postérieure à la dernière version.');
      var fac = factureSousGrille(sous, jour);
      if (fac) return refus('FACTURE_DEJA_EMISE', 'la facture ' + fac.numero + ' du ' + C.dateFR(fac.date) + ' a été émise sous la grille de ce souscripteur : une pièce émise garde son taux', 'Choisissez une date d’effet postérieure à la dernière facture émise (' + C.dateFR(fac.date) + ').');
    }
    var ancienne = rows.length ? garantiesEnVigueur(rows, jour || '9999-12-31')[0] || rows[rows.length - 1] : null;
    if (spec.essai) return { ok: true, essai: true, ancienne: ancienne, version: rows.length + 1 };
    var res = colGaranties().insert(Object.assign({
      souscripteurId: sous.id, assureur: sous.assureur,
      code: spec.code || (rows[0] && rows[0].code) || null, libelle: libelle, categorie: spec.categorie,
      taux: taux, plafond: plafond, unitePlafond: unite, zone: (rows[0] && rows[0].zone) || 'Bénin',
      dateEffet: spec.sansDate ? null : jour, version: rows.length + 1,
      motif: spec.motif || null, source: spec.source || null,
    }, spec.champs || {}));
    if (!res) return refus('ECRITURE_REFUSEE', 'le magasin a refusé d’écrire la garantie', 'Réessayez ; si le refus se répète, prévenez l’administrateur.');
    return { ok: true, garantie: res.record, ancienne: ancienne, version: rows.length + 1 };
  }

  /* ==========================================================================
   * LA COUVERTURE EST DATÉE — un assuré change d’assureur
   * --------------------------------------------------------------------------
   * Un employé change d’employeur, une convention n’est pas reconduite, un
   * particulier passe d’une compagnie à une autre : la couverture d’un même
   * patient n’est pas la même en janvier et en octobre. Le dossier ne portait
   * qu’un ÉTAT — une compagnie, une police, un taux, une expiration — et le
   * mettre à jour effaçait ce qui l’avait précédé. Conséquence : une facture
   * de mars, relue en novembre, se serait rapportée à la MAUVAISE compagnie,
   * et la créance de l’ancienne serait devenue injustifiable.
   *
   * Le mécanisme est celui de la grille des primes (NS 132) et des plages par
   * lot de réactif, et ce n’est pas un hasard : à chaque fois qu’une donnée
   * de référence change alors que des pièces ont déjà été émises sous
   * l’ancienne, c’est la MÊME réponse — versionner par date, jamais écraser.
   *
   * `debut: null` signifie « depuis l’ouverture du dossier » : la première
   * fiche d’historique est écrite au moment du PREMIER changement, et elle
   * ne peut pas inventer une date d’effet que personne n’a saisie.
   * `fin: null` signifie « en cours ».
   * ======================================================================== */
  function colCouvertures() {
    return S.collection('couverturesAssurance', {
      module: 'M9', entite: 'couverture d’assurance', prefix: 'COU' });
  }

  /** L’historique d’un patient, de la plus récente à la plus ancienne. */
  function historiqueCouverture(patient) {
    if (!patient) return [];
    return colCouvertures().active()
      .filter(function (c) { return c.patientId === patient.id; })
      .sort(function (a, b) {
        return String(b.debut || '0000-00-00').localeCompare(String(a.debut || '0000-00-00'));
      });
  }

  /**
   * La couverture EN FORCE à une date. Sans historique, la fiche du dossier
   * fait foi — c’est la situation des dossiers antérieurs à ce mécanisme, et
   * les traiter comme non couverts inventerait une rupture de droits.
   */
  function couvertureALaDate(patient, date) {
    if (!patient) return null;
    var d = C.iso(date || new Date());
    var hist = historiqueCouverture(patient);
    var enForce = hist.filter(function (c) {
      if (c.debut && d < c.debut) return false;
      if (c.fin && d > c.fin) return false;
      return true;
    })[0];
    if (enForce) return enForce;
    if (hist.length) return null; /* historique connu, et la date est hors de toute période */
    if (!patient.assureur) return null;
    return {
      origine: 'fiche', patientId: patient.id, assureur: patient.assureur,
      assureurNom: patient.assureurNom, numeroPolice: patient.numeroPolice,
      categorieAssurance: patient.categorieAssurance,
      tauxPriseEnCharge: patient.tauxPriseEnCharge,
      carteExpiration: patient.carteExpiration,
      souscripteurId: patient.souscripteurId,
      debut: null, fin: null,
    };
  }

  /**
   * changerCouverture(patient, v) — ferme la couverture en cours à la veille
   * de la date d’effet et en ouvre une nouvelle. RIEN N’EST ÉCRASÉ.
   * Retourne { ok, motif } : un refus se NOMME.
   */
  function changerCouverture(patient, v) {
    if (!patient) return { ok: false, motif: 'Aucun patient désigné.' };
    if (!v || !v.dateEffet) {
      return { ok: false, motif: 'La date d’effet est obligatoire : sans elle, la nouvelle couverture ne pourrait pas se distinguer de l’ancienne sur les pièces déjà émises.' };
    }
    if (!v.motif) {
      return { ok: false, motif: 'Le motif du changement est obligatoire (RG-12) — c’est lui qu’on relit quand une compagnie conteste une prise en charge.' };
    }
    var col = colCouvertures();
    var hist = historiqueCouverture(patient);
    var courante = hist.filter(function (c) { return !c.fin; })[0];

    /* Première mise à jour d’un dossier ancien : la couverture qui s’achève
       n’a jamais été écrite. On l’inscrit AVANT de la clore, faute de quoi
       tout ce qui précède la bascule deviendrait sans couverture connue. */
    if (!courante && patient.assureur) {
      courante = col.insert({
        patientId: patient.id, patientCode: patient.code,
        patient: patient.nom + ' ' + patient.prenom,
        assureur: patient.assureur, assureurNom: patient.assureurNom,
        numeroPolice: patient.numeroPolice, categorieAssurance: patient.categorieAssurance,
        tauxPriseEnCharge: patient.tauxPriseEnCharge, carteExpiration: patient.carteExpiration,
        souscripteurId: patient.souscripteurId,
        debut: null, fin: null, motif: 'Couverture reprise du dossier à la première mise à jour',
      }).record;
    }
    if (courante && courante.debut && v.dateEffet <= courante.debut) {
      return { ok: false, motif: 'La date d’effet (' + C.dateFR(v.dateEffet) + ') doit être postérieure au début de la couverture en cours (' + C.dateFR(courante.debut) + ').' };
    }
    if (courante) col.update(courante.id, { fin: C.iso(C.addDays(v.dateEffet, -1)) });

    var neuve = col.insert({
      patientId: patient.id, patientCode: patient.code,
      patient: patient.nom + ' ' + patient.prenom,
      assureur: v.assureur || null, assureurNom: v.assureurNom || null,
      numeroPolice: v.numeroPolice || null, categorieAssurance: v.categorieAssurance || null,
      tauxPriseEnCharge: Number(v.tauxPriseEnCharge) || 0,
      carteExpiration: v.carteExpiration || null,
      souscripteurId: v.souscripteurId || null,
      debut: C.iso(v.dateEffet), fin: null, motif: v.motif,
    }).record;

    /* La fiche du dossier reflète TOUJOURS la couverture en force AUJOURD’HUI.
       Une bascule datée du mois prochain ne doit pas changer ce que la caisse
       applique ce matin. */
    var auj = couvertureALaDate(patient, new Date()) || {};
    S.collection('patients').update(patient.id, {
      assureur: auj.assureur || null, assureurNom: auj.assureurNom || null,
      numeroPolice: auj.numeroPolice || null, categorieAssurance: auj.categorieAssurance || null,
      tauxPriseEnCharge: auj.tauxPriseEnCharge || 0,
      carteExpiration: auj.carteExpiration || null,
      souscripteurId: auj.souscripteurId || null,
      /* Le NOM du souscripteur suit son identifiant (lot IMP-B2) : un changement de police par l'importation change aussi le souscripteur, et le répertoire des assurés lit le nom sur la fiche. */
      souscripteur: (function () { var sc = auj.souscripteurId ? S.collection('souscripteurs').get(auj.souscripteurId) : null; return sc ? sc.nom : (auj.souscripteurId ? (patient.souscripteur || null) : null); })(),
    });
    return { ok: true, couverture: neuve };
  }

  /* RG-09 SE LIT À LA DATE, et la couverture aussi : une facture de mars se
     règle sur la compagnie de mars, pas sur celle d’aujourd’hui. */
  function carteValide(patient, date) {
    if (!patient) return false;
    var c = couvertureALaDate(patient, date);
    if (!c || !c.assureur || !c.carteExpiration) return false;
    /* E4 (corrigé le 31/10/2026) : une date de pièce est un JOUR. Comparer des millisecondes rendait la même carte valide le
       dernier jour pour une date « 2026-08-16 » et invalide pour l'instant « 2026-08-16T12:00:00Z » : les deux jours se comparent. */
    return jourDe(c.carteExpiration) >= jourDe(date || new Date());
  }
  /** Le JOUR (AAAA-MM-JJ) d'une date : celui qui est ÉCRIT quand la valeur commence par une date, sinon le jour local. */
  function jourDe(d) {
    var m = typeof d === 'string' ? /^(\d{4}-\d{2}-\d{2})/.exec(d) : null;
    return m ? m[1] : C.iso(d);
  }

  /* Nombre de mots significatifs partagés par deux libellés : « consultation
     généraliste » colle à « Consultation généraliste » (2) et non à
     « Consultation spécialiste ou professeur » (1). */
  function mots(t) {
    var s = String(t || '').toLowerCase();
    if (s.normalize) s = s.normalize('NFD').replace(/[̀-ͯ]/g, '');
    return s.split(/[^a-z0-9]+/);
  }
  function proximite(a, b) {
    var ma = mots(a).filter(function (m) { return m.length > 3; });
    var mb = mots(b).filter(function (m) { return m.length > 3; });
    var n = 0;
    ma.forEach(function (m) { if (mb.indexOf(m) >= 0) n++; });
    return n;
  }

  function contient(liste, texte) {
    if (!liste || !liste.length || !texte) return null;
    var t = String(texte).toLowerCase();
    for (var i = 0; i < liste.length; i++) {
      var e = String(liste[i]).toLowerCase();
      if (t.indexOf(e) >= 0 || e.indexOf(t) >= 0) return liste[i];
    }
    return null;
  }

  /**
   * repartir(patient, lignes, opts) — lignes : [{libelle, categorie, montant, accordObtenu}]
   * Retourne chaque ligne enrichie de partAssureur, partPatient et motif,
   * plus les totaux de la facture.
   */
  function repartir(patient, lignes, opts) {
    opts = opts || {};
    var date = opts.date || new Date().toISOString();
    var sous = souscripteurDe(patient, date);
    var grille = garantiesDe(patient, date);
    var valide = carteValide(patient, date);

    var detail = (lignes || []).map(function (l) {
      var montant = Number(l.montant) || 0;
      var base = {
        libelle: l.libelle, categorie: l.categorie || 'autre', montant: montant,
        partAssureur: 0, partPatient: montant, taux: 0, plafond: null, garantie: null,
      };

      if (!patient || !patient.assureur) {
        return Object.assign(base, { motif: 'Patient non assuré' });
      }
      if (!valide) {
        /* RG-09 — carte invalide à la date de facturation : facturation intégrale. */
        return Object.assign(base, { motif: 'Carte non valide à la date de facturation (RG-09)' });
      }
      if (!sous) {
        return Object.assign(base, { motif: 'Assuré non rattaché à un souscripteur' });
      }
      if (!grille.length) {
        return Object.assign(base, { motif: 'Convention non saisie pour ' + sous.nom });
      }

      var exclu = contient(sous.actesExclus, l.libelle) || contient(sous.produitsExclus, l.libelle);
      if (exclu) {
        return Object.assign(base, { motif: 'Exclu de la convention : ' + exclu, exclu: true });
      }

      var accord = contient(sous.accordPrealable, l.libelle);
      if (accord && !l.accordObtenu) {
        return Object.assign(base, {
          motif: 'Accord préalable requis et non obtenu : ' + accord,
          accordRequis: accord,
        });
      }

      /* Une catégorie porte souvent plusieurs garanties — le barème distingue
         la consultation généraliste de la consultation spécialiste, plafonnées
         à 5 000 et 10 000 FCFA. Prendre la première venue appliquerait le mauvais
         plafond : on retient celle dont le libellé colle le mieux à la ligne. */
      var candidates = grille.filter(function (x) { return x.categorie === base.categorie; });
      if (!candidates.length) {
        return Object.assign(base, { motif: 'Aucune garantie pour la catégorie « ' + base.categorie + ' »' });
      }
      var g = candidates[0], meilleur = -1;
      candidates.forEach(function (x) {
        var s = proximite(x.libelle, l.libelle);
        if (s > meilleur) { meilleur = s; g = x; }
      });

      var couvert = Math.round(montant * (g.taux || 0) / 100);
      var motif = 'Garantie ' + g.libelle + ' — ' + g.taux + ' %';
      if (g.plafond != null && couvert > g.plafond) {
        couvert = g.plafond;
        motif += ', plafonnée à ' + C.money(g.plafond, false)
          + (g.unitePlafond ? ' ' + libelleUnite(g.unitePlafond) : '');
      }
      return Object.assign(base, {
        partAssureur: couvert, partPatient: montant - couvert,
        taux: g.taux, plafond: g.plafond, garantie: g.libelle, motif: motif,
      });
    });

    return {
      lignes: detail,
      souscripteur: sous, carteValide: valide, grilleSaisie: grille.length > 0,
      total: C.sum(detail, 'montant'),
      partAssureur: C.sum(detail, 'partAssureur'),
      partPatient: C.sum(detail, 'partPatient'),
    };
  }

  function libelleUnite(id) {
    var u = D.UNITES_PLAFOND.filter(function (x) { return x.id === id; })[0];
    return u ? u.label : id;
  }

  /** Catégorie de garantie d'une ligne, déduite de sa nature. */
  function categoriser(ligne) {
    if (ligne.analyseCode || ligne.type === 'analyse') return 'analyse';
    if (ligne.produitId || ligne.type === 'medicament') {
      return /vitamin|fortifiant/i.test(ligne.libelle || ligne.produit || '') ? 'vitamine' : 'medicament';
    }
    var acte = (ligne.code && acteParCode(ligne.code)) || null;
    var secteur = acte ? acte.secteur : (ligne.secteur || '');
    if (/Imagerie/i.test(secteur)) return 'imagerie';
    if (/Maternité/i.test(secteur)) return 'maternite';
    if (/Chirurgie/i.test(secteur)) return 'chirurgie';
    if (/Hospitalisation/i.test(secteur)) return 'hospitalisation';
    if (/Médecine générale/i.test(secteur)) return /[Cc]ertificat/.test(ligne.libelle || '') ? 'certificat' : 'consultation';
    if (/Soins/i.test(secteur)) return 'soin';
    return 'autre';
  }

  /* ==========================================================================
   * HABILITATIONS MÉTIER — ce que l'agent peut VOIR, pas seulement ouvrir
   * --------------------------------------------------------------------------
   * Le manifeste `nav.js` décide des écrans par rôle. Il ne suffit pas : deux
   * agents peuvent ouvrir le même écran et ne devoir y voir ni les mêmes
   * lignes ni les mêmes colonnes. La Direction l'a dit sans ambiguïté — le
   * médecin voit tous les résultats, la sage-femme ceux de la maternité,
   * l'infirmier aucun, l'aide-soignant pas davantage.
   *
   * Trois axes, et non un seul :
   *   RÔLE       → les écrans          (nav.js)
   *   FONCTION   → les capacités       (D.CAPACITES)
   *   SECTEUR    → le périmètre        (collection `secteurs`, NS 145)
   * ======================================================================== */

  /** Fonction déduite d'une session — le rôle sert de repli. */
  var ROLE_VERS_FONCTION = {
    medecin: 'medecin', dm: 'medecin', direction: 'direction', da: 'direction',
    infirmier: 'infirmier', pharmacien: 'dispensatrice', laborantin: 'tsl',
    caissier: 'caissiere', reception: 'accueil', stock: 'stock',
    comptable: 'comptable', rh: 'direction', admin: 'direction',
    agentadmin: 'entretien', ambulancier: 'chauffeur',
  };

  function capacites(session) {
    var s = session || S.session() || {};
    var demandee = s.fonction || null;
    var duRole = ROLE_VERS_FONCTION[s.role] || null;

    /* UNE FONCTION INCONNUE NE FERME PAS L'ÉCRAN EN SILENCE. Elle retombe sur
       la fonction déduite du RÔLE — donnée sûre, venue du manifeste et non
       d'une saisie — et la substitution est signalée. Retomber sur « accueil »,
       le profil le plus restrictif, faisait qu'un agent parfaitement habilité
       ouvrait son poste, ne voyait rien, et lisait qu'il n'avait pas accès. */
    var inconnue = !!(demandee && !D.CAPACITES[demandee]);
    var f = (demandee && D.CAPACITES[demandee]) ? demandee : (duRole || 'accueil');

    return Object.assign({
      fonction: f,
      fonctionInconnue: inconnue ? demandee : null,
    }, D.CAPACITES[f] || D.CAPACITES.accueil);
  }

  /** Secteur d'affectation de l'agent connecté (NS 145). */
  function secteurCourant(session) {
    var s = session || S.session() || {};
    if (!s.secteur) return null;
    var t = S.collection('secteurs').active().filter(function (x) {
      return x.code === s.secteur || x.id === s.secteur;
    });
    return t[0] || null;
  }

  /**
   * peutVoirResultat(demande, session) — décide, et dit pourquoi.
   * Retourne { autorise, motif }. Le motif est destiné à l'écran : un refus
   * muet laisse croire à une donnée manquante plutôt qu'à une restriction.
   */
  function peutVoirResultat(demande, session) {
    var cap = capacites(session);

    /* LE PREMIER VERROU, avant toute question d'habilitation : un résultat
       non validé biologiquement n'existe pas pour le prescripteur. C'est
       toute la raison d'être des deux validations — entre la saisie et la
       validation biologique, le laboratoire relit, et personne d'autre ne
       lit par-dessus son épaule. Le laboratoire, lui, voit son propre
       travail en cours, sans quoi il ne pourrait pas le relire. */
    var duLabo = cap.voirResultats === 'produits' || cap.validerTechnique;
    if (demande && demande.etatAnalyse && !duLabo
      && !D.resultatRendu(demande.etatAnalyse)) {
      return {
        autorise: false,
        motif: 'Résultat non encore validé biologiquement — '
          + D.etatResultat(demande.etatAnalyse).label.toLowerCase()
          + '. Le laboratoire le relit avant de le rendre.',
        enAttenteValidation: true,
      };
    }

    if (cap.voirResultats === 'tous') {
      return { autorise: true, motif: cap.label + ' — accès à tous les résultats' };
    }
    if (cap.voirResultats === 'aucun') {
      return { autorise: false, motif: cap.label + ' — les résultats d’analyses ne lui sont pas accessibles' };
    }
    if (cap.voirResultats === 'produits') {
      /* Le laboratoire voit ce qu'il produit, et le remet aux patients externes. */
      return { autorise: true, motif: 'Laboratoire — résultat produit par le service' };
    }
    if (cap.voirResultats === 'secteur') {
      var sect = secteurCourant(session);
      var demandeur = demande && (demande.secteurDemandeur || demande.secteur);
      var mien = (sect && sect.libelle) || (cap.secteurs || [])[0] || '';
      var ok = demandeur && mien && String(demandeur).toUpperCase().indexOf(String(mien).toUpperCase()) >= 0;
      return {
        autorise: !!ok,
        motif: ok
          ? cap.label + ' — résultat demandé par son secteur (' + demandeur + ')'
          : cap.label + ' — résultat demandé par ' + (demandeur || 'un autre secteur') + ', hors de son périmètre',
      };
    }
    return { autorise: false, motif: 'Périmètre non défini' };
  }

  /**
   * peutVoirDocument(type, session) : décide, et dit pourquoi, si le profil lit (ou dépose) un document numérisé du dossier patient de ce TYPE (lot DOCS-1, D3).
   * Deux zones (D.DOCUMENTS.TYPES_PATIENT) : la zone 1 (pièce d'identité, carte d'assurance) est administrative et se lit de tout profil qui ouvre l'écran ; la zone 2, médicale, ne se lit
   * que des profils de `D.DOCUMENTS.ROLES_ZONE_2` (RG-13). La MÊME règle est écrite par `build/gen-regles-fichiers.js` pour le serveur : une règle en deux exemplaires diverge au premier correctif.
   * Retourne { autorise, zone, motif }.
   */
  function peutVoirDocument(type, session) {
    var s = session || S.session() || {};
    var zone = D.DOCUMENTS.zoneDe(type);
    if (zone < 2) return { autorise: true, zone: zone, motif: 'Pièce administrative (zone 1) : lisible de tout profil qui ouvre l’écran' };
    if (D.DOCUMENTS.ROLES_ZONE_2.indexOf(s.role) >= 0) return { autorise: true, zone: zone, motif: 'Profil clinique : les pièces médicales (zone 2) lui sont ouvertes' };
    return { autorise: false, zone: zone, motif: 'Pièce médicale (zone 2) : seuls les profils cliniques la lisent (RG-13)' };
  }

  function peutPrescrire(nature, session) {
    var cap = capacites(session);
    return (cap.prescrire || []).indexOf(nature) >= 0;
  }

  function peutExecuterSoin(session) { return !!capacites(session).executerSoins; }

  /** Filtre une liste de demandes/résultats selon l'habilitation. */
  function filtrerResultats(liste, session) {
    return (liste || []).filter(function (d) { return peutVoirResultat(d, session).autorise; });
  }

  /* ==========================================================================
   * PRISE EN CHARGE DU PERSONNEL
   * --------------------------------------------------------------------------
   * La clinique soigne ses agents à 100 %. Ce n'est PAS une assurance au sens
   * de M9 : aucun tiers ne rembourse, aucune créance ne naît, et la prestation
   * ne constitue ni une recette ni une charge à comptabiliser — c'est un
   * avantage consenti par l'employeur, dont on veut connaître le VOLUME.
   *
   * D'où trois règles que le reste du logiciel doit respecter :
   *   — la part patient est nulle, mais il n'y a pas de part assureur ;
   *   — la ligne ne remonte pas aux recettes ni au relevé assureur ;
   *   — la valeur reste calculée, pour que la Direction sache ce que
   *     l'avantage représente.
   * ======================================================================== */

  /** Le dossier personnel derrière un patient, ou null. */
  function agentDe(patient) {
    if (!patient) return null;
    var id = patient.personnelId || (typeof patient === 'string' ? null : null);
    if (!id) return null;
    return S.collection('personnel').all().filter(function (e) { return e.id === id; })[0] || null;
  }

  /** Le patient est-il un agent de la clinique ? */
  function estPersonnel(patient) {
    return !!(patient && patient.personnelId);
  }

  /**
   * Prise en charge d'une ligne pour un agent : 100 %, sans tiers payeur.
   * Renvoie le même contrat que PR.repartir pour que la facturation n'ait
   * pas à distinguer deux formes de résultat.
   */
  function prendreEnChargePersonnel(patient, lignes) {
    var agent = agentDe(patient);
    return (lignes || []).map(function (l) {
      var base = Number(l.montant) || 0;
      return {
        ligne: l, base: base,
        partAssureur: 0,
        partPatient: 0,
        priseEnChargePersonnel: base,
        taux: 100,
        agent: agent ? agent.nomComplet : (patient && patient.nom),
        matricule: agent ? agent.matricule : (patient && patient.matricule),
        motif: 'Prise en charge du personnel — 100 %, sans contrepartie d’un tiers payeur. '
          + 'Ni recette ni créance : avantage consenti par l’employeur.',
        horsRecettes: true,
      };
    });
  }

  /* ==========================================================================
   * PRESCRIPTION DE SOINS
   * --------------------------------------------------------------------------
   * La clinique distingue deux prescriptions : celle de l'ORDONNANCE, qui
   * porte des médicaments, et celle des SOINS, qui porte des actes. Les
   * confondre rendait invisible tout le travail infirmier — sept infirmiers et
   * trois sages-femmes exécutent des actes que rien ne traçait.
   *
   * Un soin est ADRESSÉ à un secteur : salle de soins, hospitalisation ou
   * maternité. Sans destinataire, il n'apparaîtrait sur aucun poste et ne
   * serait jamais exécuté.
   *
   * Il est facturé au catalogue AMI — donc au bon prix selon que le patient
   * est assuré ou non (voir D.tarifPrix).
   * ======================================================================== */
  function prescrireSoins(v) {
    var p = patientParCode(v.patientCode);
    if (!p) throw new Error('Patient introuvable : ' + v.patientCode);

    var soignant = (col('soignants').active().filter(function (x) {
      return x.id === v.prescripteurId;
    })[0]) || null;
    /* Un infirmier ne prescrit pas. Le contrôle est ici, au moteur : le poser
       dans l'écran laisserait passer toute prescription venue d'ailleurs. */
    if (soignant && !soignant.prescrit) {
      throw new Error(soignant.nomComplet + ' (' + soignant.poste + ') n’est pas habilité à prescrire.');
    }

    var date = v.date || new Date().toISOString();
    /* RG-09 : c’est la validité de la carte À LA DATE qui décide du tarif,
       et non le fait que le patient possède une carte. Une carte expirée
       facture au tarif non assuré, et la ligne le dit. */
    var assure = carteValide(p, date);

    var lignes = (v.actes || []).map(function (a) {
      var code = typeof a === 'string' ? a : a.code;
      var t = D.tarif ? D.tarif(code) : null;
      var pr = D.tarifPrix ? D.tarifPrix(code, assure, date) : { montant: null, motif: null };
      return {
        acteCode: code,
        libelle: t ? t.libelle : code,
        famille: t ? t.famille : null,
        quantite: Number((typeof a === 'object' && a.quantite) || 1),
        frequence: (typeof a === 'object' && a.frequence) || '',
        duree: (typeof a === 'object' && a.duree) || '',
        /* Le nombre d'administrations attendues : c'est lui qui fait vivre le
           relais. Une seule administration ne quitte jamais la salle de soins. */
        nbAdministrations: Number((typeof a === 'object' && a.nbAdministrations) || 1),
        prix: pr.montant,
        tarif: pr.tarif || null,
        motifTarif: pr.motif || null,
        prixAValider: pr.montant == null,
      };
    });

    var modalite = v.modalite || 'ambulatoire';
    var pres = col('prescriptions').insert({
      reference: C.nextRef('PRS-', 5),
      type: 'soins',
      origine: v.origine || 'consultation',
      date: date,
      patientId: p.id, patientCode: p.code, patient: p.nom + ' ' + p.prenom,
      prescripteurId: v.prescripteurId || null,
      prescripteur: soignant ? soignant.nomComplet : (v.prescripteur || '—'),
      secteurDestinataire: v.secteurDestinataire || 'salle_soins',
      modalite: modalite,
      /* Le secteur qui recevra la PREMIÈRE administration, annoncé d'avance :
         l'écran le dit au prescripteur au moment où il prescrit. */
      premierAdministrateur: D.secteurAdministrateur(modalite, 1).secteur,
      admissionId: v.admissionId || null,
      indication: v.indication || '',
      lignes: lignes,
      montant: lignes.reduce(function (t, l) { return t + (l.prix || 0) * l.quantite; }, 0),
      assure: assure,
      statut: 'en_cours',
      statutPaiement: 'impayee',
    }).record;

    /* La notification s'adresse à un POSTE et non à une personne : l'infirmier
       de garde change, le secteur reste. */
    notifier({
      type: 'prescription_soins',
      poste: v.secteurDestinataire || 'salle_soins',
      libelle: 'Nouvelle prescription de soins — ' + pres.patient,
      detail: pres.reference + ' — ' + lignes.length + ' acte(s) — ' + pres.prescripteur,
      priorite: v.urgent ? 'haute' : 'normale',
      patientId: p.id, reference: pres.reference,
    });

    return pres;
  }

  /* --------------------------------------------------------------------------
   * L'ORDONNANCE ENTRE AU MÊME REGISTRE
   * ------------------------------------------------------------------------
   * Pour que le registre des prescriptions dise la vérité, l'ordonnance doit y
   * figurer aussi. Sans cela, « les prescriptions du jour » n'en montreraient
   * que la moitié.
   * ---------------------------------------------------------------------- */
  function inscrireOrdonnance(ord, origine) {
    return col('prescriptions').insert({
      reference: ord.numero,
      type: 'ordonnance',
      origine: origine || 'consultation',
      date: ord.date,
      patientId: ord.patientId, patientCode: ord.patientCode, patient: ord.patient,
      prescripteurId: ord.prescripteurId || null,
      prescripteur: ord.medecin,
      secteurDestinataire: 'pharmacie',
      modalite: ord.modalite || 'ambulatoire',
      premierAdministrateur: D.secteurAdministrateur(ord.modalite || 'ambulatoire', 1).secteur,
      ordonnanceId: ord.id,
      lignes: (ord.medicaments || []).map(function (m) {
        return {
          produitId: m.produitId, libelle: m.produit, quantite: m.quantite,
          posologie: m.posologie, duree: m.duree, prix: m.prix,
          nbAdministrations: Number(m.nbAdministrations || 1),
        };
      }),
      montant: ord.montantMedicaments || 0,
      statut: 'en_cours',
      statutPaiement: ord.statutPaiement || 'impayee',
    }).record;
  }

  /* ==========================================================================
   * ADMINISTRATION D'UN TRAITEMENT — LA RÈGLE DE RELAIS
   * --------------------------------------------------------------------------
   * Le rang décide du secteur, pas l'inverse. Un poste qui tente d'administrer
   * ce qui ne lui revient pas est refusé EN LE NOMMANT : « cette administration
   * revient à la salle de soins ». Un refus muet ferait croire à une panne.
   * ======================================================================== */
  function rangSuivant(prescriptionId, ligneIndex) {
    return col('administrations').active().filter(function (a) {
      return a.prescriptionId === prescriptionId && a.ligneIndex === ligneIndex;
    }).length + 1;
  }

  function administrer(prescriptionId, opts) {
    opts = opts || {};
    var pres = col('prescriptions').get(prescriptionId);
    if (!pres) throw new Error('Prescription introuvable.');

    var ligneIndex = Number(opts.ligneIndex || 0);
    var ligne = (pres.lignes || [])[ligneIndex];
    if (!ligne) throw new Error('Ligne de prescription introuvable.');

    /* Une prescription non réglée ne s'administre pas : c'est la même règle
       que pour la délivrance et le laboratoire. */
    if (pres.statutPaiement !== 'payee' && !opts.forcer) {
      return { ok: false, motif: 'Prescription non réglée — l’administration reste bloquée jusqu’à l’encaissement.' };
    }

    var rang = rangSuivant(prescriptionId, ligneIndex);
    var attendu = D.secteurAdministrateur(pres.modalite, rang);

    if (opts.secteur && opts.secteur !== attendu.secteur) {
      return {
        ok: false, rang: rang, secteurAttendu: attendu.secteur,
        motif: attendu.motif,
      };
    }

    var exec = (col('soignants').active().filter(function (x) {
      return x.id === opts.executantId;
    })[0]) || null;
    /* Le médecin prescrit, il n'exécute pas les soins ; l'infirmier et la
       sage-femme exécutent. Le contrôle vit au moteur. */
    if (exec && !exec.execute) {
      return {
        ok: false, rang: rang,
        motif: exec.nomComplet + ' (' + exec.poste + ') n’exécute pas les soins.',
      };
    }

    var rec = col('administrations').insert({
      reference: C.referenceSuivante('ADM-', 5, col('administrations').all()),   /* E363 : série lue sur le registre, jamais un compteur de page */
      prescriptionId: prescriptionId, prescriptionRef: pres.reference,
      ligneIndex: ligneIndex, libelle: ligne.libelle,
      patientId: pres.patientId, patientCode: pres.patientCode, patient: pres.patient,
      dateHeure: opts.dateHeure || new Date().toISOString(),
      rang: rang, total: ligne.nbAdministrations || 1,
      secteur: attendu.secteur, motifSecteur: attendu.motif,
      executantId: opts.executantId || null,
      executant: exec ? exec.nomComplet : (opts.executant || '—'),
      observation: opts.observation || '',
      modalite: pres.modalite,
    }).record;

    /* La prescription se termine quand toutes ses lignes sont servies. */
    var reste = (pres.lignes || []).some(function (l, i) {
      return rangSuivant(prescriptionId, i) <= (l.nbAdministrations || 1);
    });
    if (!reste) col('prescriptions').update(prescriptionId, { statut: 'termine' });

    return { ok: true, administration: rec, rang: rang, secteur: attendu.secteur };
  }

  /* --------------------------------------------------------------------------
   * CE QUI REVIENT À UN POSTE, MAINTENANT
   * ------------------------------------------------------------------------
   * Trois écrans posent la même question — la salle de soins, l'hospitalisation
   * et la maternité. Y répondre une fois évite trois filtres divergents.
   * ---------------------------------------------------------------------- */
  function soinsDuSecteur(secteur) {
    return col('prescriptions').active().filter(function (pres) {
      return pres.statut === 'en_cours';
    }).map(function (pres) {
      var lignes = (pres.lignes || []).map(function (l, i) {
        var rang = rangSuivant(pres.id, i);
        var att = D.secteurAdministrateur(pres.modalite, rang);
        return {
          index: i, ligne: l, rang: rang,
          total: l.nbAdministrations || 1,
          secteur: att.secteur, motif: att.motif,
          du: rang <= (l.nbAdministrations || 1) && att.secteur === secteur,
          bloque: pres.statutPaiement !== 'payee',
        };
      }).filter(function (x) { return x.du; });
      return lignes.length ? { prescription: pres, lignes: lignes } : null;
    }).filter(Boolean);
  }

  /* ==========================================================================
   * CLOISONNEMENT DE L'ACCUEIL
   * --------------------------------------------------------------------------
   * L'accueil a besoin de l'identité, des coordonnées, de la couverture
   * d'assurance et des constantes qu'il relève lui-même. Il n'a aucun besoin
   * du diagnostic, des antécédents, des résultats d'analyse ni du traitement —
   * et RG-13 le lui interdit.
   *
   * DEUX PRINCIPES :
   *   1. Une restriction S'ANNONCE. Un filtre muet fait croire à une donnée
   *      manquante ; l'écran dit qui il est, ce qu'il ne voit pas et pourquoi.
   *   2. TOUTE recherche de dossier par l'accueil est JOURNALISÉE. C'est une
   *      demande expresse de la Direction : le dossier d'un voisin, d'un
   *      notable ou d'un employé se consulte trop facilement quand rien ne
   *      trace qui a regardé quoi.
   * ======================================================================== */
  var CHAMPS_ADMINISTRATIFS = ['code', 'nip', 'nom', 'prenom', 'sexe', 'dateNaissance', 'age',
    'telephone', 'quartier', 'adresse', 'profession', 'ethnie', 'personneContact',
    'assureur', 'assureurNom', 'numeroCarte', 'carteExpiration', 'tauxPriseEnCharge',
    'souscripteur', 'creeLe', 'heureArrivee', 'statut'];

  var CHAMPS_CLINIQUES = ['diagnostic', 'antecedents', 'allergies', 'traitement',
    'groupeSanguin', 'gsRh', 'te', 'hb', 'observations', 'motifConsultation'];

  /** L'accueil voit-il ce champ ? RG-13. */
  function accueilVoitChamp(nom) {
    return CHAMPS_ADMINISTRATIFS.indexOf(nom) !== -1;
  }

  /**
   * Le dossier tel que l'accueil a le droit de le voir. Renvoie la fiche
   * expurgée ET le motif — parce qu'une restriction s'annonce.
   */
  function dossierPourAccueil(patient) {
    if (!patient) return { fiche: null, motif: 'Dossier introuvable.' };
    var out = {};
    Object.keys(patient).forEach(function (k) {
      if (accueilVoitChamp(k) || k === 'id') out[k] = patient[k];
    });
    var masques = Object.keys(patient).filter(function (k) {
      return CHAMPS_CLINIQUES.indexOf(k) !== -1;
    });
    return {
      fiche: out,
      masques: masques,
      motif: 'RG-13 — l’accueil accède aux données administratives et à la couverture d’assurance. '
        + 'Les données cliniques (diagnostic, antécédents, résultats, traitement) lui sont fermées.',
    };
  }

  /**
   * Journalise une recherche de dossier. Demande expresse de la Direction :
   * le dossier d'un voisin ou d'un notable se consulte trop facilement quand
   * rien ne trace qui a regardé quoi.
   *
   * On journalise la CONSULTATION, pas seulement la modification : c'est le
   * regard qui pose problème ici, pas l'écriture.
   */
  function journaliserRecherche(patient, opts) {
    opts = opts || {};
    var s = S.session() || {};
    /* On passe par le mécanisme du magasin et NON par collection().insert() :
       insert() journalise à son tour, et une recherche produisait deux
       entrées — la sienne, plus une entrée fantôme décrivant son écriture. */
    return S.journaliserAcces({
      utilisateur: s.nom || S.currentUser(),
      role: s.role || null,
      action: opts.action || 'Consultation de dossier',
      module: 'M1', entite: 'Dossier patient',
      reference: patient ? patient.code : (opts.terme || null),
      cible: patient ? (patient.code + ' — ' + patient.nom + ' ' + patient.prenom) : (opts.terme || '—'),
      patientId: patient ? patient.id : null,
      ecran: opts.ecran || null,
      motif: opts.motif || null,
      /* Une recherche infructueuse se journalise aussi : chercher le dossier
         de quelqu'un qui n'est pas patient est en soi une information. */
      trouve: !!patient,
    });
  }

  /* ==========================================================================
   * CONTINUITÉ DU PRÉLÈVEMENT ET DE LA VALIDATION
   * --------------------------------------------------------------------------
   * Celui qui a fait le prélèvement est celui qui valide. Règle de PREUVE et
   * non d'organisation : le validateur atteste d'un échantillon, et s'il ne l'a
   * pas vu arriver il atteste de ce qu'un collègue lui a dit.
   *
   * La clinique compte DEUX biologistes médicaux ; la règle a donc un effet
   * réel — elle interdit que l'un valide le prélèvement de l'autre.
   * ======================================================================== */
  function continuiteRespectee(demande, agent) {
    if (!demande) return { ok: false, motif: 'Demande introuvable.' };
    var preleveur = demande.preleveParId || demande.prelevePar || null;
    /* Un prélèvement non encore fait ne peut pas être validé : c'est déjà la
       règle du circuit, on ne la redouble pas ici. */
    if (!preleveur) {
      return { ok: true, motif: 'Aucun prélèvement enregistré — la continuité ne s’applique pas encore.' };
    }
    var memeAgent = preleveur === (agent && (agent.id || agent))
      || preleveur === (agent && agent.nomComplet);
    if (memeAgent) return { ok: true, motif: null };
    return {
      ok: false,
      preleveur: demande.prelevePar || preleveur,
      motif: 'Le prélèvement a été fait par ' + (demande.prelevePar || preleveur)
        + '. C’est à lui de valider : un validateur qui n’a pas vu arriver l’échantillon '
        + 'atteste de ce qu’un collègue lui a dit, et la signature perd sa valeur.',
    };
  }

  /* ==========================================================================
   * BESOIN EN FONDS DE ROULEMENT ET PILOTAGE (BFR_TABLEAU.txt, 22/09/2026)
   * --------------------------------------------------------------------------
   * LE MOTEUR VIT AU SOCLE, ET C'EST LA SEULE PLACE POSSIBLE : le BFR se lit
   * depuis la comptabilité (M12), depuis le pilotage (PIL), depuis les deux
   * tableaux de bord de la Direction et depuis le moteur d'alertes, qui
   * n'appartient à aucun écran. Une page ne charge que le module du sien :
   * poser le calcul dans un module l'aurait rendu invisible aux quatre
   * autres, et quatre copies auraient divergé au premier correctif.
   *
   * IL NE FABRIQUE AUCUNE DONNÉE — il en agrège trois, déjà tenues ailleurs :
   *
   *   créances    ← M9, la MÊME définition que la balance âgée (part assureur
   *                 des factures assurées) + les restes à charge patients ;
   *   stocks      ← M6, valorisés par `S.valeurUnitaire`, donc selon la
   *                 méthode que la Direction a choisie (prix de vente ou
   *                 CUMP) — recalculer ici ferait diverger deux valorisations ;
   *   dettes      ← M7, les factures fournisseurs non réglées.
   *
   *   BFR = créances + stocks − dettes fournisseurs.
   *
   * UN COMPOSANT QUI MANQUE SE DIT. Si une collection n'est pas amorcée, on
   * ne la compte pas pour zéro : `incomplet` porte son nom, et les écrans
   * l'affichent. Un BFR amputé de ses dettes est SURESTIMÉ, et un chiffre
   * faux qui a l'air juste est ce que ce prototype refuse partout ailleurs.
   * ======================================================================== */

  function objectifsPilotage() {
    var col = S.collection('objectifsPilotage', { module: 'M12', entite: 'ObjectifPilotage' });
    var vivants = col.active();
    if (vivants.length) return vivants;
    /* Repli sur la semence : un poste dont la collection a été vidée doit
       encore pouvoir lire ses indicateurs, sans cible arrêtée. */
    return (D.OBJECTIFS_PILOTAGE || []).slice();
  }

  function objectifPilotage(id) {
    return objectifsPilotage().filter(function (o) { return o.id === id; })[0] || null;
  }

  /** La fenêtre d'observation : 90 jours glissants par défaut, bornes nommées. */
  function fenetrePilotage(opts) {
    var o = opts || {};
    var fin = o.fin ? C.toDate(o.fin) : C.aujourdhui();   /* la fenêtre glissante suit l'horloge (vague 68) */
    var debut = o.debut ? C.toDate(o.debut) : C.addDays(fin, -(o.jours || 90));
    return { debut: C.iso(debut), fin: C.iso(fin), jours: Math.max(1, C.daysBetween(debut, fin)) };
  }

  function dansFenetre(d, f) {
    var x = String(d || '').slice(0, 10);
    return !!x && x >= f.debut && x <= f.fin;
  }

  function facturesPilotage() { return S.collection('factures').active(); }

  /**
   * Les trois composantes et leur somme algébrique.
   * @param {Object} [opts] {fin, jours} — la fenêtre sert au CA, pas aux encours :
   *   un encours se lit À UNE DATE, un flux SUR UNE PÉRIODE. Les confondre
   *   ferait croire que le stock détenu dépend de la fenêtre qu'on regarde.
   */
  function bfr(opts) {
    var f = fenetrePilotage(opts);
    var manquants = [];
    var factures = facturesPilotage();

    /* 1 — EN-COURS CLIENTS. La part assureur suit la définition de la balance
       âgée de M9, au mot près : deux définitions du même encours se seraient
       contredites en réunion. */
    var assurees = factures.filter(function (x) { return !!x.assureur; });
    var creancesAssureurs = C.sum(assurees, 'partAssurance');
    var restesACharge = C.sum(factures.filter(function (x) {
      return x.statutPaiement !== 'soldee';
    }), function (x) { return Math.max(0, x.reliquat || 0); });

    /* 2 — STOCKS. La valorisation passe par le magasin, qui connaît la
       méthode en vigueur. */
    var produits = S.collection('produits').active();
    if (!produits.length) manquants.push('les produits du stock');
    var stocks = C.sum(produits, function (p) {
      return (p.stock || 0) * S.valeurUnitaire(p);
    });

    /* 3 — DETTES FOURNISSEURS. « payée » et « soldée » désignent la même
       chose selon l'écran par lequel la pièce est passée : on accepte les
       deux plutôt que d'en compter une comme impayée. */
    var ff = S.collection('facturesFournisseurs').active();
    if (!ff.length) manquants.push('les factures fournisseurs');
    var dettes = C.sum(ff.filter(function (x) {
      return ['payee', 'soldee'].indexOf(String(x.statutPaiement || '')) === -1;
    }), function (x) { return x.montantFacture || 0; });

    var caPeriode = C.sum(factures.filter(function (x) { return dansFenetre(x.date, f); }), 'montantTTC');
    var creances = creancesAssureurs + restesACharge;

    return {
      arrete: f.fin, fenetre: f,
      creancesAssureurs: creancesAssureurs,
      restesACharge: restesACharge,
      creances: creances,
      stocks: stocks,
      dettes: dettes,
      bfr: creances + stocks - dettes,
      caPeriode: caPeriode,
      /* Le BFR ramené en jours d'activité : c'est sous cette forme qu'il se
         compare d'un exercice à l'autre, une valeur absolue ne disant rien
         sans le chiffre d'affaires qui la porte. */
      bfrJours: caPeriode > 0 ? Math.round((creances + stocks - dettes) / (caPeriode / f.jours)) : null,
      nbFacturesAssurees: assurees.length,
      nbDettes: ff.filter(function (x) {
        return ['payee', 'soldee'].indexOf(String(x.statutPaiement || '')) === -1;
      }).length,
      incomplet: manquants,
    };
  }

  /** Les sorties valorisées de la période — le dénominateur de la rotation. */
  function sortiesValorisees(f) {
    var prods = {};
    S.collection('produits').active().forEach(function (p) { prods[p.id] = p; });
    var sortantes = ['sortie', 'perte', 'casse', 'peremption'];
    return C.sum(S.collection('mouvements').active().filter(function (m) {
      return sortantes.indexOf(m.type) !== -1 && dansFenetre(m.date, f);
    }), function (m) {
      var p = prods[m.produitId];
      return (m.quantite || 0) * (p ? S.valeurUnitaire(p) : 0);
    });
  }

  /** Le délai moyen de transmission des pièces assureur, en jours. */
  function delaiTransmission() {
    var meres = S.collection('facturesMere').active().filter(function (m) {
      return m.dateEmission && m.fin;
    });
    if (!meres.length) return null;
    return Math.round(C.sum(meres, function (m) {
      return Math.max(0, C.daysBetween(m.fin, m.dateEmission));
    }) / meres.length);
  }

  /**
   * La grille « objectif fixé / réel atteint ».
   * Chaque ligne porte son état : atteint · vigilance · alerte · indisponible.
   * INDISPONIBLE N'EST PAS ZÉRO — un indicateur qu'on ne sait pas calculer se
   * dit tel quel, faute de quoi la Direction lirait un échec là où il n'y a
   * qu'une donnée manquante.
   */
  function indicateursPilotage(opts) {
    var f = fenetrePilotage(opts);
    var b = bfr(opts);
    var reels = {};

    reels.dso = b.caPeriode > 0 ? Math.round(b.creances / (b.caPeriode / f.jours)) : null;
    reels.bfr_jours = b.bfrJours;

    /* L'ancienneté de la créance la plus vieille encore ouverte : c'est elle
       qui déclenche la relance, pas la moyenne — une moyenne rassurante peut
       cacher une pièce de huit mois. */
    var assurees = facturesPilotage().filter(function (x) { return !!x.assureur && (x.partAssurance || 0) > 0; });
    reels.creance_agee = assurees.length
      ? Math.max.apply(null, assurees.map(function (x) { return C.daysBetween(x.date, f.fin); }))
      : null;

    var lits = (D.CHAMBRES || []).reduce(function (n, ch) { return n + ch.lits.length; }, 0);
    var occupes = S.collection('admissions').active().filter(function (a) { return a.statut === 'en_cours'; }).length;
    reels.occupation_lits = lits ? Math.round(occupes / lits * 1000) / 10 : null;

    var sorties = sortiesValorisees(f);
    reels.rotation_stock = b.stocks > 0 && sorties > 0
      ? Math.round(sorties * (365 / f.jours) / b.stocks * 10) / 10 : null;
    reels.couverture_stock = sorties > 0 ? Math.round(b.stocks / (sorties / f.jours)) : null;

    reels.delai_transmission = delaiTransmission();

    var normalisables = facturesPilotage().filter(function (x) { return !!x.numeroMecef; });
    reels.facturation_normalisee = normalisables.length
      ? Math.round(normalisables.filter(function (x) { return x.statutMecef === 'valide'; }).length
        / normalisables.length * 1000) / 10
      : null;

    return objectifsPilotage().map(function (o) {
      var reel = reels[o.id];
      var etat = 'indisponible';
      if (reel != null) {
        var bas = o.sens !== 'haut';
        var atteint = bas ? reel <= o.cible : reel >= o.cible;
        var franchi = bas ? reel > o.alerte : reel < o.alerte;
        etat = atteint ? 'atteint' : (franchi ? 'alerte' : 'vigilance');
      }
      return {
        id: o.id, axe: o.axe, label: o.label, unite: o.unite,
        cible: o.cible, alerte: o.alerte, sens: o.sens,
        aValider: !!o.aValider, source: o.source, aide: o.aide,
        reel: reel, etat: etat,
        /* L'écart n'a de sens que rapporté au bon côté : un DSO de 30 jours
           pour une cible de 45 est une AVANCE, pas un retard. */
        ecart: reel == null ? null : (o.sens === 'haut' ? reel - o.cible : o.cible - reel),
      };
    });
  }

  /**
   * Les compagnies dont la créance dépasse le seuil d'ancienneté retenu.
   * Consommé par le moteur de notifications : il route, il ne décide pas du
   * seuil — celui-ci vit dans `objectifsPilotage`, où la Direction le règle.
   */
  function alertesRecouvrement(opts) {
    var f = fenetrePilotage(opts);
    var o = objectifPilotage('creance_agee');
    var seuil = o ? o.cible : 60;
    var parCompagnie = {};
    facturesPilotage().forEach(function (x) {
      if (!x.assureur || !(x.partAssurance > 0)) return;
      var jours = C.daysBetween(x.date, f.fin);
      if (jours <= seuil) return;
      var e = parCompagnie[x.assureur] || (parCompagnie[x.assureur] = {
        assureur: x.assureur, montant: 0, nb: 0, jours: 0,
      });
      e.montant += x.partAssurance;
      e.nb += 1;
      e.jours = Math.max(e.jours, jours);
    });
    return Object.keys(parCompagnie).map(function (k) { return parCompagnie[k]; })
      .sort(function (a, b2) { return b2.montant - a.montant; })
      .map(function (e) { return Object.assign({ seuil: seuil }, e); });
  }

  global.SIGH.parcours = {
    continuiteRespectee: continuiteRespectee,
    bfr: bfr, indicateursPilotage: indicateursPilotage,
    alertesRecouvrement: alertesRecouvrement, objectifsPilotage: objectifsPilotage,
    objectifPilotage: objectifPilotage, fenetrePilotage: fenetrePilotage,
    sortiesValorisees: sortiesValorisees, delaiTransmission: delaiTransmission,
    accueilVoitChamp: accueilVoitChamp,
    dossierPourAccueil: dossierPourAccueil,
    journaliserRecherche: journaliserRecherche,
    CHAMPS_CLINIQUES: CHAMPS_CLINIQUES,
    prescrireSoins: prescrireSoins, inscrireOrdonnance: inscrireOrdonnance,
    administrer: administrer, soinsDuSecteur: soinsDuSecteur,
    rangSuivant: rangSuivant,
    ecrireEncaissement: ecrireEncaissement, alerterStock: alerterStock,
    emettreAvoir: emettreAvoir, retirerAvoir: retirerAvoir, referenceAvoir: referenceAvoir,
    rangSerieFactures: rangSerieFactures,
    construireLignes: construireLignes, lignesDues: lignesDues, lignesReglees: lignesReglees,
    facturerPiece: facturerPiece, statutPiece: statutPiece,
    ouvrirDemandeExterne: ouvrirDemandeExterne,
    dossierExterne: dossierExterne,
    ouvrirDemandeImagerie: ouvrirDemandeImagerie,
    examenImagerieParCode: examenImagerieParCode,
    codeAnalyse: codeAnalyse,
    numeroBadge: numeroBadge, badgeQR: badgeQR, lireBadgeQR: lireBadgeQR,
    jetonEnquete: jetonEnquete,
    validerTechnique: validerTechnique, validerBiologique: validerBiologique,
    rectifierResultat: rectifierResultat,
    notifier: notifier, notifications: notifications, marquerLue: marquerLue,
    estPersonnel: estPersonnel, agentDe: agentDe,
    prendreEnChargePersonnel: prendreEnChargePersonnel,
    capacites: capacites, secteurCourant: secteurCourant, valoriserSortie: valoriserSortie,
    peutVoirResultat: peutVoirResultat, peutVoirDocument: peutVoirDocument, peutPrescrire: peutPrescrire,
    peutExecuterSoin: peutExecuterSoin, filtrerResultats: filtrerResultats,
    repartir: repartir, garantiesDe: garantiesDe, souscripteurDe: souscripteurDe,
    poserGarantie: poserGarantie, factureSousGrille: factureSousGrille, garantiesEnVigueur: garantiesEnVigueur, versionsGarantie: versionsGarantie, cleSerieGarantie: cleSerieGarantie,
    carteValide: carteValide, categoriser: categoriser, libelleUnite: libelleUnite,
    colTarifs: colTarifs, colVersionsTarif: colVersionsTarif,
    colActes: colActes, colAnalyses: colAnalyses, colCatalogueTarifs: colCatalogueTarifs,
    ROLES_VALIDATION_TARIFS: ROLES_VALIDATION_TARIFS, peutDeciderTarif: peutDeciderTarif, peutProposerTarif: peutProposerTarif,
    ROLES_DATE_PASSEE: ROLES_DATE_PASSEE, peutDatePasseeTarif: peutDatePasseeTarif, profilsDatePassee: profilsDatePassee, usagesTarif: usagesTarif, piecesRecentesTarif: piecesRecentesTarif,
    deciderTousTarifs: deciderTousTarifs, variationPropositionPct: variationPropositionPct, seuilVariationAlerte: seuilVariationAlerte,
    ecartProforma: ecartProforma, validiteProformaJours: validiteProformaJours, definirValiditeProforma: definirValiditeProforma, VALIDITE_PROFORMA_DEFAUT: VALIDITE_PROFORMA_DEFAUT,
    proposerTarif: proposerTarif, evaluerProposition: evaluerProposition, peutProposerParImport: peutProposerParImport, deciderTarif: deciderTarif, retirerProposition: retirerProposition, versionsTarifDe: versionsDe,
    tarifALaDate: tarifALaDate, prixLignePrescription: prixLignePrescription, prixActeALaDate: prixActeALaDate, prixAnalyseALaDate: prixAnalyseALaDate, prixChambreALaDate: prixChambreALaDate,
    produitsAValoriser: produitsAValoriser, refusPrixAchatAbsent: refusPrixAchatAbsent, proposerPrixReception: proposerPrixReception,
    prixProduitALaDate: prixProduitALaDate, prixAchatALaDate: prixAchatALaDate, prixVenteALaDate: prixVenteALaDate, produitDeCode: produitDeCode, peutProposerProduit: peutProposerProduit, creerPrixProduit: creerPrixProduit,
    couvertureALaDate: couvertureALaDate, historiqueCouverture: historiqueCouverture,
    changerCouverture: changerCouverture,
    TACHES: TACHES,
    prescrire: prescrire, encaisser: encaisser, delivrer: delivrer,
    transcrireMobile: transcrireMobile, CORRESPONDANCE_EXAMENS_MOBILE: CORRESPONDANCE_EXAMENS_MOBILE,
    verifierStock: verifierStock,
    taches: taches, aFaire: aFaire, terminer: terminer, compteurs: compteurs,
    dossier: dossier,
  };


  /* ==========================================================================
   * EXERCICES COMPTABLES — sélecteur, lecture seule au moteur, clôture en deux
   * gestes (PRD-M12-cloture-exercice).
   * --------------------------------------------------------------------------
   * LE MOTEUR VIT AU SOCLE : le sélecteur d'exercice est lu par tous les écrans
   * de M12, de M9 et des tableaux de bord, et une page ne charge que le module
   * de son écran. Une clôture est un acte DÉFINITIF : un exercice clos ne se
   * rouvre pas (obligation légale), il se corrige par une écriture de l'exercice
   * suivant. La garde de lecture seule est posée sur la COLLECTION, pas sur
   * l'écran — un champ désactivé dans le navigateur ne protège rien.
   * ======================================================================== */
  var CLE_EXERCICE = 'sigh-cnt:exercice';
  var LETTRABLES = ['40', '41', '42', '43', '44', '47'];

  function anneeDe(date) { var d = C.toDate(date); return d && !isNaN(d) ? d.getFullYear() : null; }
  function anneeCourante() { return C.aujourdhui().getFullYear(); }

  /* Les exercices sont DÉRIVÉS : une fiche par année portée par les écritures,
     plus l'année courante, plus celle de la liasse déposée (close d'office —
     c'est un fait déposé à la DGI, non un exercice du logiciel). */
  function exercices() {
    var col = S.collection('exercices', { module: 'M12', entite: 'Exercice' });
    var annees = {};
    S.collection('ecritures').all().forEach(function (e) { var a = anneeDe(e.date); if (a) annees[a] = true; });
    var aDesEcritures = {}; Object.keys(annees).forEach(function (a) { aDesEcritures[a] = true; });
    annees[anneeCourante()] = true;
    /* LOT CLO C4 : à partir du mois réglé du circuit (défaut semé : décembre), l'exercice de l'année SUIVANTE s'ouvre aussi. Aucune pièce n'est écrite. */
    var moisOuv = circuitALaDate('moisOuvertureSuivant');
    if (moisOuv.ok && C.aujourdhui().getMonth() + 1 >= Number(moisOuv.valeur)) annees[anneeCourante() + 1] = true;
    if (global.SIGH.liasse && global.SIGH.liasse.DEPOT) {
      annees[global.SIGH.liasse.DEPOT.exerciceN] = true;
      annees[global.SIGH.liasse.DEPOT.exerciceN1] = true;
    }
    var ajoute = false, nouveaux = [];
    Object.keys(annees).forEach(function (a) {
      a = Number(a);
      if (col.all().some(function (x) { return x.annee === a; })) return;
      var deposee = !!(global.SIGH.liasse && global.SIGH.liasse.DEPOT && (global.SIGH.liasse.DEPOT.exerciceN === a || global.SIGH.liasse.DEPOT.exerciceN1 === a));
      col.all().unshift({
        id: 'EXO-' + a, annee: a, debut: a + '-01-01', fin: a + '-12-31', statut: 'actif',
        etat: deposee ? 'clos' : 'ouvert',
        source: deposee ? 'liasse' : 'journal',
        valideLe: deposee ? global.SIGH.liasse.DEPOT.dateDepot : null,
        validePar: deposee ? 'Liasse déposée à la DGI' : null,
        motif: deposee ? 'Exercice antérieur à la mise en service : fait par la liasse déposée.' : null,
      });
      ajoute = true;
      if (!deposee) {
        nouveaux.push(a);
        /* TOUTE OUVERTURE EST TRACÉE (RG-12), avec sa cause ; elle n'écrit aucune pièce. */
        S.log('Ouverture d’exercice', 'M12', 'Exercice', String(a), null,
          { etat: 'ouvert', origine: aDesEcritures[a] ? 'ecriture' : (a === anneeCourante() ? 'annee_en_cours' : 'ouverture_anticipee') });
      }
    });
    /* Le 05/11/2026 l'état « en attente de clôture » devient « en clôture » (la demande verrouille les modules) : les fiches d'avant sont reprises. */
    col.all().forEach(function (x) { if (x.etat === 'en_attente_cloture') { x.etat = 'en_cloture'; ajoute = true; } });
    if (ajoute) S.save();
    /* UN EXERCICE QUI S'OUVRE ENGENDRE SON ÉCHÉANCIER (lot A3b, E-A3-09) : additif, sans toucher une échéance existante ni une quittance. */
    nouveaux.forEach(function (a) { if (S.assurerEcheances) S.assurerEcheances(a); });
    return col.all().filter(function (x) { return x.statut !== 'archive'; })
      .sort(function (a, b) { return b.annee - a.annee; });
  }
  function exercice(annee) { return exercices().filter(function (x) { return x.annee === Number(annee); })[0] || null; }
  /* LA TÂCHE QUOTIDIENNE D'OUVERTURE DES EXERCICES (lot CLO C4, EF-CLO-1) : ouvre l'année en cours et, à partir du mois réglé du circuit, l'année suivante. Idempotente, tracée au
     journal d'audit, n'écrit AUCUNE pièce (ni à-nouveau ni écriture). Rend { date, ouverts: [années], existants: [années] }. Le poste la joue à son ouverture ; le serveur
     (api/cron.php, tâche `exercices_ouverture`) vérifie chaque jour que ce qui doit être ouvert l'est, et le dit au rôle qui démarre la clôture sinon. */
  function ouvrirExercicesDuJour() {
    var avant = {}; S.collection('exercices', { module: 'M12', entite: 'Exercice' }).all().forEach(function (x) { avant[x.annee] = true; });
    var nbEcritures = S.collection('ecritures').all().length;
    var liste = exercices();
    var ouverts = liste.filter(function (x) { return !avant[x.annee]; }).map(function (x) { return x.annee; }).sort();
    return { date: aujIso(), ouverts: ouverts, existants: liste.map(function (x) { return x.annee; }).sort(), pieceEcrite: S.collection('ecritures').all().length !== nbEcritures };
  }
  function etatExercice(annee) { var x = exercice(annee); return x ? x.etat : 'ouvert'; }

  /* LE CHOIX DE L'EXERCICE VIT DANS LA SESSION DE L'UTILISATEUR, en un seul endroit : cette fonction. Tous les écrans la lisent, aucun ne garde de copie.
     Il ne fait que CHOISIR CE QUE L'ON LIT : il n'écrit rien, ne donne aucun droit, et une pièce s'enregistre toujours dans l'exercice de SA date.
     Par défaut : l'exercice ouvert le plus récent, sinon le plus récent tout court. */
  function exerciceParDefaut() {
    var liste = exercices();
    var ouverts = liste.filter(function (x) { return x.etat === 'ouvert'; });
    return (ouverts[0] || liste[0] || { annee: anneeCourante() }).annee;
  }
  function exerciceChoisi() {
    var v = null;
    try { v = Number(global.sessionStorage.getItem(CLE_EXERCICE)); } catch (e) { /* stockage refusé */ }
    return v && exercice(v) ? v : exerciceParDefaut();
  }
  function choisirExercice(annee) {
    try { global.sessionStorage.setItem(CLE_EXERCICE, String(annee)); } catch (e) { /* sans effet */ }
    if (S.assurerEcheances && exercice(annee)) S.assurerEcheances(annee);
    return Number(annee);
  }
  /* « Ce mois », « ce trimestre » : calculés depuis aujourd'hui si l'exercice consulté le contient, sinon depuis son dernier jour. Consulter 2025 en 2026,
     c'est voir décembre 2025 sous « ce mois ». */
  function dateReference() {
    var a = exerciceChoisi(), auj = C.aujourdhui();
    return anneeDe(auj) === a ? auj : new Date(a, 11, 31);
  }
  function exerciceVoisin(sens) {
    var cible = exerciceChoisi() + sens;
    return exercice(cible) ? cible : null;
  }

  /* La garde de lecture seule : posée sur la collection, refusée AVANT l'écriture. */
  /* Drapeau posé par lettrer/delettrer : poser un lettrage est le geste attendu d'un exercice en clôture, quelle que soit l'origine. */
  var lettrageEnCours = false;
  S.garder('ecritures', function (op, rec) {
    /* EF-CLO-6 : les journaux CL et AN ne se saisissent pas à la main, quel que soit l'état de l'exercice (le moteur refuse aussi : masquer une option ne protège rien). */
    if (op !== 'archiver' && rec && rec.origine === 'Saisie manuelle') {
      var jr = (D.JOURNAUX_RESERVES || []).filter(function (j) { return j.code === rec.journal; })[0];
      if (jr) return 'JOURNAL_RESERVE : le journal ' + jr.code + ' (' + jr.libelle + ') n’est alimenté que par ' + jr.alimente + ' ; il ne se saisit pas à la main. Saisir l’écriture au journal des opérations diverses (OD).';
    }
    var a = anneeDe(rec && rec.date);
    if (!a) return null;
    /* Les pièces de la clôture elle-même (CL, AN, contre-passations) passent : c'est elles qui font l'état. */
    if (rec && rec.origineCloture && op === 'inserer') return null;
    var etat = etatExercice(a);
    if (etat === 'clos') {
      var x = exercice(a);
      return 'Exercice ' + a + ' clôturé' + (x && x.valideLe ? ' le ' + C.dateFR(x.valideLe) : '')
        + ' : lecture seule. La correction passe par la réouverture par le comptable (motif obligatoire), ou par une écriture de l’exercice en cours.';
    }
    if (etat === 'en_cloture') {
      if (lettrageEnCours && op === 'modifier') return null;
      /* En clôture : les modules n'écrivent plus ; seul le comptable passe ses écritures d'inventaire (saisie manuelle). */
      var inv = circuitALaDate('rolesInventaire');
      if ((rec && rec.origine === 'Saisie manuelle') && inv.ok && inv.valeur.indexOf(roleCourant()) >= 0) return null;
      return 'Exercice ' + a + ' en clôture : les modules n’y écrivent plus. Seuls ' + (inv.ok ? nomsRoles(inv.valeur) : 'les rôles du circuit de clôture (non arrêté)') + ' y passent leurs écritures d’inventaire (saisie manuelle) ; sinon dater la pièce de l’exercice ouvert.';
    }
    return null;
  });

  /* LE BUDGET D'UN EXERCICE CLOS EST EN LECTURE SEULE (lot IMP-B2), d'où que l'écriture vienne (écran, importation) : un budget prévisionnel n'est pas une écriture comptable, mais un exercice
     clos est un exercice arrêté, et lui ajouter une ligne prévue le contredit. Seul `clos` est refusé ici ; l'importation, elle, n'admet que les exercices OUVERTS. Limite connue : la garde lit
     l'exercice de la fiche telle qu'elle sera ; un budget que l'on ferait passer d'un exercice clos à un exercice ouvert en changeant son année échappe à la garde de modification. */
  S.garder('budgets', function (op, rec) {
    var a = Number(rec && rec.exercice);
    if (!a || etatExercice(a) !== 'clos') return null;
    return 'Exercice ' + a + ' clôturé : le budget d’un exercice clos ne s’écrit plus. La correction passe par la réouverture de l’exercice par le comptable (motif obligatoire), ou par un budget de l’exercice ouvert.';
  });

  function sensLettrable(compte) {
    return LETTRABLES.some(function (p) { return String(compte).indexOf(p) === 0; });
  }

  /* Écritures VALIDÉES d'un exercice (un brouillon n'est pas un fait comptable). */
  function ecrituresDe(annee, inclureBrouillons, avecCL) {
    /* Le journal CL (clôture) est EXCLU par défaut : les états de N restent ceux d'avant la clôture, le compte de résultat montre le résultat de l'année et non zéro. */
    return S.collection('ecritures').active().filter(function (e) {
      return anneeDe(e.date) === Number(annee) && (inclureBrouillons || e.statut === 'validee') && (avecCL || e.journal !== 'CL');
    });
  }

  function soldesParCompte(lignes) {
    var m = {};
    lignes.forEach(function (e) {
      var k = String(e.compte);
      if (!m[k]) m[k] = { compte: k, libelle: e.compteLibelle || k, debit: 0, credit: 0 };
      m[k].debit += Number(e.debit) || 0; m[k].credit += Number(e.credit) || 0;
    });
    return Object.keys(m).sort().map(function (k) { m[k].solde = m[k].debit - m[k].credit; return m[k]; });
  }

  /* Le résultat : classes 7 (+) moins 6 (−), HAO (8) compris. Positif = bénéfice. */
  function resultatDe(lignes) {
    var r = 0;
    lignes.forEach(function (e) {
      var cl = String(e.compte).charAt(0);
      if (cl === '6' || cl === '7' || cl === '8') r += (Number(e.credit) || 0) - (Number(e.debit) || 0);
    });
    return r;
  }

  /* Lignes de report (classes 1 à 5) vers N+1. Comptes NON lettrables : un solde
     global. Comptes de TIERS : ligne par ligne, uniquement les lignes NON lettrées —
     c'est ce qui permet de suivre sur le nouvel exercice les factures en attente. */
  function lignesDeReport(lignes) {
    var out = [];
    var bilan = lignes.filter(function (e) { return '12345'.indexOf(String(e.compte).charAt(0)) >= 0; });
    var tiers = bilan.filter(function (e) { return sensLettrable(e.compte); });
    var autres = bilan.filter(function (e) { return !sensLettrable(e.compte); });
    soldesParCompte(autres).forEach(function (s) {
      if (Math.abs(s.solde) < 1) return;
      out.push({ compte: s.compte, compteLibelle: s.libelle, debit: s.solde > 0 ? s.solde : 0, credit: s.solde < 0 ? -s.solde : 0, lettrable: false });
    });
    tiers.filter(function (e) { return !e.lettrage; }).forEach(function (e) {
      var net = (Number(e.debit) || 0) - (Number(e.credit) || 0);
      if (Math.abs(net) < 1) return;
      out.push({ compte: String(e.compte), compteLibelle: e.compteLibelle, debit: net > 0 ? net : 0, credit: net < 0 ? -net : 0,
        lettrable: true, pieceOrigine: e.numero, libelle: 'Report — ' + (e.libelle || e.numero) });
    });
    return out;
  }

  /* À-NOUVEAUX PROVISOIRES : tant que N n'est pas clos, N+1 voit un report calculé
     des soldes validés de N, RECALCULÉ à chaque lecture et jamais stocké. Le
     résultat de N (non encore soldé) est porté au compte 131 / 139. */
  function aNouveauxProvisoires(annee) {
    var prec = Number(annee) - 1;
    var ex = exercice(prec);
    if (!ex || ex.etat === 'clos' || ex.source === 'liasse') return [];
    var base = ecrituresDe(prec);
    var lignes = lignesDeReport(base);
    var res = resultatDe(base);
    if (Math.abs(res) >= 1) {
      var cr = compteResultat(res);
      lignes.push({ compte: cr.compte, compteLibelle: cr.libelle,
        debit: res < 0 ? -res : 0, credit: res > 0 ? res : 0, lettrable: false });
    }
    return lignes.map(function (l) {
      return Object.assign({ id: 'PROV-' + annee + '-' + l.compte + '-' + (l.pieceOrigine || 'S'), numero: 'AN-PROV-' + annee,
        date: annee + '-01-01', journal: 'AN', journalLibelle: 'Journal des à-nouveaux (provisoire)',
        libelle: l.libelle || 'À-nouveau provisoire', statut: 'validee', provisoire: true, origine: 'Provisoire — calculé' }, l);
    });
  }

  /* LES SOLDES D'UN COMPTE AU GRAND LIVRE (lot CLO C3, EF-CLO-4) : solde d'OUVERTURE et solde de CLÔTURE d'un exercice, jamais un zéro inventé.
     OUVERTURE d'un compte de bilan (classes 1 à 5) : (a) le report ÉCRIT (journal AN, hors contre-passations) quand l'exercice en porte ; (b) sinon le report PROVISOIRE de
     l'exercice précédent s'il n'est pas clos (calculé, dit tel, jamais stocké) ; (c) sinon, l'exercice précédent est clos (ou celui de la liasse) SANS à-nouveau : l'ouverture est
     INCONNUE, ce n'est pas zéro ; (d) sans exercice précédent : premier exercice, pas de report (0, dit tel). Un compte de GESTION (6, 7, 8) ne se reporte jamais : ouverture 0.
     CLÔTURE : ouverture + mouvements de l'exercice (ou INCONNUE quand l'ouverture l'est). Dans un exercice CLOS par le moteur la pièce de clôture CL compte : un compte de gestion y
     est à zéro. Même population de lignes que l'écran du grand livre (écritures de l'exercice, brouillons compris), pour que le solde progressif aboutisse au solde de clôture. */
  function soldesGrandLivre(compte, annee) {
    compte = String(compte); annee = Number(annee);
    var classe = compte.charAt(0), gestion = '678'.indexOf(classe) >= 0;
    var x = exercice(annee), prec = exercice(annee - 1);
    var toutes = S.collection('ecritures').active();
    var contrePassees = {};
    toutes.forEach(function (e) { if (e.contrePasseDe) contrePassees[e.contrePasseDe] = true; });
    var delAnnee = toutes.filter(function (e) { return anneeDe(e.date) === annee && String(e.compte) === compte; });
    var estAN = function (e) { return e.journal === 'AN' && !e.contrePasseDe && !contrePassees[e.numero]; };
    var anAnnee = toutes.some(function (e) { return anneeDe(e.date) === annee && estAN(e); });
    var somme = function (l) { return l.reduce(function (n, e) { return n + (Number(e.debit) || 0) - (Number(e.credit) || 0); }, 0); };
    var ouv = { valeur: null, etat: 'inconnue', source: null };
    var opening = delAnnee.filter(estAN);
    if (gestion) ouv = { valeur: 0, etat: 'gestion', source: 'Un compte de gestion ne se reporte jamais : il est soldé par le résultat.' };
    else if (anAnnee) ouv = { valeur: somme(opening), etat: 'ecrit', source: opening.length ? 'À-nouveaux écrits (' + opening[0].numero + ')' : 'À-nouveaux écrits : ce compte n’y figure pas' };
    else if (prec && prec.etat !== 'clos' && prec.source !== 'liasse') {
      var prov = aNouveauxProvisoires(annee).filter(function (l) { return String(l.compte) === compte; });
      ouv = { valeur: somme(prov), etat: 'provisoire', source: 'À-nouveaux provisoires de ' + (annee - 1) + ' (calculés, l’exercice n’est pas clos)' };
    } else if (prec) ouv = { valeur: null, etat: 'inconnue', source: 'L’exercice ' + (annee - 1) + ' est clos sans à-nouveau écrit : l’ouverture est inconnue, ce n’est pas zéro.' };
    else ouv = { valeur: 0, etat: 'premier', source: 'Premier exercice : aucun report.' };
    var clos = x && x.etat === 'clos' && x.source !== 'liasse';
    var mvts = delAnnee.filter(function (e) { return (clos || e.journal !== 'CL') && !(!gestion && anAnnee && estAN(e)) && !(e.provisoire); });
    var d = mvts.reduce(function (n, e) { return n + (Number(e.debit) || 0); }, 0), c = mvts.reduce(function (n, e) { return n + (Number(e.credit) || 0); }, 0);
    var clot = ouv.valeur == null ? { valeur: null, etat: 'inconnue' } : { valeur: ouv.valeur + d - c, etat: clos ? 'clos' : (x && x.etat === 'en_cloture' ? 'en_cloture' : 'courant') };
    return { compte: compte, annee: annee, gestion: gestion, ouverture: ouv, mouvements: { debit: d, credit: c, nb: mvts.length }, cloture: clot, apresCL: !!clos };
  }

  /* PRÉ-CLÔTURE : contrôles nommés, chacun avec les pièces en cause et l'écran où corriger. */
  function preCloture(annee) {
    annee = Number(annee);
    var tous = ecrituresDe(annee, true);
    var validees = tous.filter(function (e) { return e.statut === 'validee'; });
    var brouillons = tous.filter(function (e) { return e.statut === 'brouillon'; });
    var controles = [];
    controles.push({ id: 'brouillons', bloquant: true, ok: brouillons.length === 0,
      libelle: 'Aucune écriture en brouillon', ecran: 'm12-ecritures',
      detail: brouillons.length ? brouillons.length + ' ligne(s) en brouillon, dont ' + brouillons.slice(0, 4).map(function (e) { return e.numero; })
        .filter(function (v, i, a) { return a.indexOf(v) === i; }).join(', ') + '.' : '' });
    var d = C.sum(validees, 'debit'), c = C.sum(validees, 'credit');
    controles.push({ id: 'equilibre', bloquant: true, ok: Math.abs(d - c) < 1,
      libelle: 'Journal équilibré (RG-10)', ecran: 'm12-balance',
      detail: Math.abs(d - c) < 1 ? '' : 'Écart de ' + C.money(Math.abs(d - c)) + ' entre débit et crédit.' });
    var pieces = {};
    validees.forEach(function (e) { var p = pieces[e.numero] || (pieces[e.numero] = { d: 0, c: 0 }); p.d += Number(e.debit) || 0; p.c += Number(e.credit) || 0; });
    var boiteuses = Object.keys(pieces).filter(function (k) { return Math.abs(pieces[k].d - pieces[k].c) >= 1; });
    controles.push({ id: 'pieces', bloquant: true, ok: boiteuses.length === 0,
      libelle: 'Chaque pièce validée est équilibrée', ecran: 'm12-ecritures',
      detail: boiteuses.length ? boiteuses.length + ' pièce(s) déséquilibrée(s) : ' + boiteuses.slice(0, 4).join(', ') + '.' : '' });
    var prec = exercice(annee - 1), suiv = exercice(annee + 1);
    controles.push({ id: 'precedent-clos', bloquant: true, ok: !prec || prec.etat === 'clos',
      libelle: 'Exercice ' + (annee - 1) + ' déjà clôturé', ecran: 'm12-cloture',
      detail: prec && prec.etat !== 'clos' ? 'L’exercice ' + (annee - 1) + ' est ' + (prec.etat === 'en_cloture' ? 'en clôture' : 'ouvert') + ' : le clôturer d’abord.' : '' });
    controles.push({ id: 'suivant-non-clos', bloquant: true, ok: !suiv || suiv.etat !== 'clos',
      libelle: 'Exercice ' + (annee + 1) + ' non clôturé', ecran: 'm12-cloture',
      detail: suiv && suiv.etat === 'clos' ? 'L’exercice ' + (annee + 1) + ' est déjà clôturé : impossible de clôturer ' + annee + ' après lui.' : '' });
    var enAttente = (S.fileEnAttente && S.fileEnAttente()) || 0;
    controles.push({ id: 'postes-a-envoyer', bloquant: false, ok: enAttente === 0,
      libelle: 'Aucune opération en attente d’envoi sur ce poste', ecran: 'm12-cloture',
      detail: enAttente ? enAttente + ' opération(s) à envoyer : synchroniser d’abord, car une fois ' + annee + ' en clôture la mère refuse les pièces datées de ' + annee + '. Les autres postes sont à vérifier de la même façon.' : '' });
    var contrePassees = {};
    S.collection('ecritures').active().forEach(function (e) { if (e.contrePasseDe) contrePassees[e.contrePasseDe] = true; });
    var an = S.collection('ecritures').active().filter(function (e) { return anneeDe(e.date) === annee + 1 && e.journal === 'AN' && !e.contrePasseDe && !contrePassees[e.numero] && !e.provisoire; });
    controles.push({ id: 'an-existants', bloquant: true, ok: an.length === 0,
      libelle: 'Aucun à-nouveau déjà écrit sur ' + (annee + 1), ecran: 'm12-ouverture',
      detail: an.length ? 'Des à-nouveaux existent (' + an[0].numero + ') : les archiver avant de clôturer, la clôture écrit les définitifs.' : '' });
    var attente = validees.filter(function (e) { return String(e.compte).indexOf('47') === 0; });
    var solde47 = C.sum(attente, 'debit') - C.sum(attente, 'credit');
    controles.push({ id: 'compte-47', bloquant: false, ok: Math.abs(solde47) < 1,
      libelle: 'Comptes d’attente (47x) soldés', ecran: 'm12-grand-livre',
      detail: Math.abs(solde47) < 1 ? '' : 'Solde de ' + C.money(Math.abs(solde47)) + ' à régulariser.' });
    controles.push({ id: 'ecritures', bloquant: true, ok: validees.length > 0,
      libelle: 'L’exercice porte des écritures validées', ecran: 'm12-ecritures', detail: validees.length ? '' : 'Aucune écriture validée en ' + annee + '.' });
    return { annee: annee, controles: controles, bloquants: controles.filter(function (x) { return x.bloquant && !x.ok; }),
      resultat: resultatDe(validees), nbEcritures: validees.length };
  }

  function acteur() { var s = S.session && S.session(); return (s && (s.nomComplet || s.nom)) || 'Utilisateur'; }
  function roleCourant() { var s = S.session && S.session(); return (s && s.role) || ''; }

  /* LA TABLE DES COMPTES DE RÉSULTAT (131 bénéfice, 139 perte) : un référentiel paramétrable, jamais deux constantes du code. */
  function comptesResultat() {
    var col = S.collection('comptesResultat', { module: 'M12', entite: 'Compte de résultat' });
    if (!col.all().length && S.amorcable('comptesResultat')) {
      col.all().push({ id: 'CR-BEN', statut: 'actif', sens: 'benefice', compte: '131000', libelle: 'Résultat net : bénéfice' });
      col.all().push({ id: 'CR-PER', statut: 'actif', sens: 'perte', compte: '139000', libelle: 'Résultat net : perte' });
      S.save();
    }
    return col;
  }
  /* Contrôle d'une modification de la table : un compte de bénéfice est un 131, un compte de perte un 139 (SYSCOHADA), six chiffres (les comptes 131000 et 139000 d'origine ne figurent pas au plan statique : on ne contrôle donc pas l'appartenance au plan).
     Retourne le motif du refus, ou null. Le motif NOMME ce qui est attendu. */
  function controleCompteResultat(fiche, valeurs) {
    var compte = String(valeurs.compte == null ? '' : valeurs.compte).trim();
    var libelle = String(valeurs.libelle == null ? '' : valeurs.libelle).trim();
    var prefixe = fiche.sens === 'benefice' ? '131' : '139';
    var nom = fiche.sens === 'benefice' ? 'bénéfice' : 'perte';
    if (!/^\d{6}$/.test(compte)) return 'Le compte de ' + nom + ' doit comporter six chiffres (reçu « ' + compte + ' »).';
    if (compte.indexOf(prefixe) !== 0) return 'Le compte de ' + nom + ' doit appartenir au compte ' + prefixe + ' du SYSCOHADA (reçu ' + compte + ').';
    if (libelle.length < 3) return 'Le libellé du compte de ' + nom + ' est obligatoire.';
    return null;
  }
  function compteResultat(res) {
    var sens = res >= 0 ? 'benefice' : 'perte';
    var f = comptesResultat().active().filter(function (x) { return x.sens === sens; })[0];
    return f ? { compte: String(f.compte), libelle: f.libelle } : { compte: sens === 'benefice' ? '131000' : '139000', libelle: sens === 'benefice' ? 'Résultat net : bénéfice' : 'Résultat net : perte' };
  }

  /* Prochain numéro d'une pièce de clôture (CL-2026-00001, AN-2027-00001, …-C00001 pour les contre-passations) : lu du journal, jamais d'un compteur de page. */
  function numeroPiece(prefixe, annee) {
    var motif = new RegExp('^' + prefixe + '-' + annee + '-?[A-Z]?(\\d+)$'), rang = 0;
    S.collection('ecritures').all().forEach(function (e) { var m = motif.exec(String(e.numero || '')); if (m) rang = Math.max(rang, Number(m[1])); });
    return rang + 1;
  }
  function pad5(n) { return ('00000' + n).slice(-5); }

  /* ==========================================================================
   * LE CIRCUIT DE CLÔTURE ANNUELLE (Direction, 11/11/2026 ; lot CLO C1) : AUCUN nom de rôle dans le moteur. Qui démarre, qui passe l'inventaire en clôture, qui clôture
   * définitivement et qui rouvre se LISENT dans la collection `reglagesCloture` (une fiche par version datée, défauts semés), à la date du geste. Un refus nomme la liste
   * LUE (jamais une liste recopiée dans la phrase) et le geste de correction. Régler le circuit est un geste réservé de la fiche RBAC (`regler_circuit_cloture`).
   * Sans version en vigueur, le geste est refusé nommément : rien n'est supposé.
   * ======================================================================== */
  function colReglagesCloture() { return S.collection('reglagesCloture', { module: 'M12', entite: 'réglage de la clôture', prefix: 'RCL' }); }
  function definitionCircuit(cle) { return (D.REGLAGES_CLOTURE || []).filter(function (x) { return x.cle === cle; })[0] || null; }
  function versionsCircuit(cle) {
    return colReglagesCloture().active().filter(function (v) { return v.cle === cle; })
      .sort(function (a, b) { return String(a.dateEffet).localeCompare(String(b.dateEffet)); });
  }
  /** La valeur du réglage à la date : { ok, valeur, dateEffet, versionId, version } ou le refus nommé CIRCUIT_SANS_VERSION (jamais une valeur inventée). */
  function circuitALaDate(cle, date) {
    var d = date ? isoJour(date) : aujIso();
    var def = definitionCircuit(cle);
    if (!def) return refusCfg('CIRCUIT_REGLAGE_INCONNU', 'Le réglage « ' + cle + ' » n’existe pas parmi ceux de la clôture annuelle.', 'Choisir un réglage listé à l’écran « Exercices & clôtures », onglet « Circuit de clôture ».', { cle: cle });
    var toutes = versionsCircuit(cle);
    var couvrantes = toutes.filter(function (v) { return String(v.dateEffet) <= d && (!v.dateFin || String(v.dateFin) >= d); });
    var v = couvrantes[couvrantes.length - 1];
    if (!v || v.valeur == null || (Array.isArray(v.valeur) && !v.valeur.length)) {
      return refusCfg('CIRCUIT_SANS_VERSION', 'Aucune version du réglage « ' + def.libelle + ' » ne couvre le ' + C.dateFR(d) + ' : la valeur n’est pas arrêtée, rien n’est supposé.',
        'Ajouter une version à l’écran « Exercices & clôtures », onglet « Circuit de clôture ».', { cle: cle, date: d });
    }
    return { ok: true, cle: cle, valeur: v.valeur, dateEffet: v.dateEffet, version: toutes.indexOf(v) + 1, versionId: v.id, date: d };
  }
  function nomsRoles(liste) {
    var n = (liste || []).map(function (r) { return libelleRole(r); });
    return n.length > 1 ? n.slice(0, -1).join(', ') + ' ou ' + n[n.length - 1] : (n[0] || 'aucun rôle');
  }
  /** Le rôle de la session figure-t-il dans la liste lue ? null s'il y figure, sinon le refus nommé qui CITE la liste lue. */
  function verifierCircuit(cle, code, quoi, geste) {
    var r = circuitALaDate(cle);
    if (!r.ok) return r;
    if (r.valeur.indexOf(roleCourant()) >= 0) return null;
    return refusCfg(code, quoi + ' : action réservée à : ' + nomsRoles(r.valeur) + '.', geste, { roles: r.valeur.slice(), versionId: r.versionId });
  }
  function peutDansCircuit(cle, role) {
    var r = circuitALaDate(cle);
    return r.ok && r.valeur.indexOf(role == null ? roleCourant() : role) >= 0;
  }
  /** Les rôles du circuit (liste LUE), pour le routage des notifications. */
  function rolesDuCircuit(cle) { var r = circuitALaDate(cle); return r.ok ? r.valeur.slice() : []; }
  function notifierCircuit(cle, o) { rolesDuCircuit(cle).forEach(function (poste) { notifier(Object.assign({}, o, { poste: poste })); }); }

  var GESTE_REGLER_CIRCUIT = 'regler_circuit_cloture';
  function peutRegler(role) { var N = global.SIGH.nav; return !!(N && N.droitGeste && N.droitGeste(role == null ? roleCourant() : role, GESTE_REGLER_CIRCUIT)); }
  /** Poser une NOUVELLE version d'un réglage du circuit : { cle, valeur, dateEffet?, motif }. Jamais une réécriture : la version précédente est fermée à la veille. */
  function definirCircuit(o) {
    o = o || {};
    var def = definitionCircuit(o.cle);
    if (!def) return refusCfg('CIRCUIT_REGLAGE_INCONNU', 'Le réglage « ' + o.cle + ' » n’existe pas parmi ceux de la clôture annuelle.', 'Choisir un réglage listé à l’écran « Exercices & clôtures », onglet « Circuit de clôture ».');
    if (!peutRegler()) return refusCfg('CIRCUIT_REGLAGE_RESERVE', 'Régler le circuit de la clôture annuelle est un droit réservé de la fiche du rôle : « ' + libelleRole(roleCourant()) + ' » ne l’a pas.',
      'Demander à un rôle qui détient le droit « Régler le circuit de la clôture annuelle » (matrice des droits).', { roles: global.SIGH.nav.rolesAvecGeste(GESTE_REGLER_CIRCUIT) });
    var fileul = controleEcritureCfg();
    if (fileul) return fileul;
    if (!o.motif || String(o.motif).trim().length < 3) return refusCfg('CIRCUIT_MOTIF_OBLIGATOIRE', 'Un motif est obligatoire pour changer le circuit de clôture.', 'Saisir le motif du changement.');
    var valeur = o.valeur;
    if (def.type === 'roles') {
      var ROLES = (global.SIGH.nav && global.SIGH.nav.ROLES) || {};
      valeur = (Array.isArray(valeur) ? valeur : String(valeur == null ? '' : valeur).split(',')).map(function (x) { return String(x).trim(); }).filter(Boolean)
        .filter(function (x, i, a) { return a.indexOf(x) === i; });
      if (!valeur.length) return refusCfg('CIRCUIT_LISTE_VIDE', 'La liste « ' + def.libelle + ' » ne peut pas être vide : personne ne pourrait accomplir le geste.', 'Choisir au moins un rôle.');
      var inconnus = valeur.filter(function (x) { return !ROLES[x] || (global.SIGH.nav.roleArchive && global.SIGH.nav.roleArchive(x)); });
      if (inconnus.length) return refusCfg('CIRCUIT_ROLE_INCONNU', 'Rôle inconnu ou archivé : ' + inconnus.join(', ') + '.', 'Choisir des rôles de la matrice des droits.', { inconnus: inconnus });
    } else if (def.type === 'mois') {
      valeur = Number(valeur);
      if (!(valeur >= 1 && valeur <= 12) || Math.floor(valeur) !== valeur) return refusCfg('CIRCUIT_MOIS_INVALIDE', 'Le mois doit être un entier de 1 à 12 (reçu « ' + o.valeur + ' »).', 'Saisir un mois de 1 à 12.');
    }
    var dateEffet = o.dateEffet ? isoJour(o.dateEffet) : aujIso();
    var existantes = versionsCircuit(o.cle), derniere = existantes[existantes.length - 1] || null;
    if (derniere && String(dateEffet) < String(derniere.dateEffet)) {
      return refusCfg('CIRCUIT_DATE_ANTERIEURE', 'La date d’effet ' + C.dateFR(dateEffet) + ' précède celle de la version en vigueur (' + C.dateFR(derniere.dateEffet) + ') : une version ne s’insère pas dans le passé.',
        'Choisir une date d’effet égale ou postérieure.');
    }
    var veillee = veille(dateEffet), ferme = null;
    if (derniere && (!derniere.dateFin || String(derniere.dateFin) > veillee)) {
      ferme = { id: derniere.id, avant: derniere.dateFin || null };
      colReglagesCloture().update(derniere.id, { dateFin: veillee, modifieLe: aujIso(), modifiePar: acteur() });
    }
    var affiche = def.type === 'roles' ? nomsRoles(valeur) : String(valeur);
    var base = { cle: o.cle, valeur: valeur, libelle: def.libelle + ' : ' + affiche, dateEffet: dateEffet, dateFin: null, source: String(o.source || '').trim() || null,
      motif: String(o.motif).trim(), creeLe: aujIso(), creePar: acteur() };
    var res = colReglagesCloture().insert(base, { journal: { action: 'Circuit de clôture : nouvelle version', module: 'M12', entite: 'reglagesCloture',
      avant: { precedente: derniere ? { id: derniere.id, valeur: derniere.valeur } : null },
      apres: { cle: o.cle, valeur: valeur, dateEffet: dateEffet, motif: base.motif, precedenteFermeeLe: ferme ? veillee : null } } });
    if (!res) return refusCfg('CIRCUIT_ECRITURE_REFUSEE', 'Le magasin a refusé l’écriture de la version.', 'Relire le journal.');
    return { ok: true, id: res.record.id, cle: o.cle, valeur: valeur, dateEffet: dateEffet, version: existantes.length + 1, precedente: derniere ? derniere.id : null, undo: res.undo };
  }
  S.garder('reglagesCloture', function (op, rec) {
    if (op !== 'modifier') return null;
    var avant = rec && rec.id ? colReglagesCloture().get(rec.id) : null;
    if (!avant) return null;
    if (JSON.stringify(avant.valeur) !== JSON.stringify(rec.valeur) || avant.cle !== rec.cle || String(avant.dateEffet) !== String(rec.dateEffet)) {
      return 'CIRCUIT_VERSION_FIGEE : une version du circuit de clôture ne se réécrit pas (valeur, réglage, date d’effet). Ajouter une nouvelle version à une date d’effet égale ou postérieure.';
    }
    return null;
  });
  function circuitComplet(date) {
    var out = { ok: true, date: date ? isoJour(date) : aujIso() };
    ['rolesDemarrer', 'rolesInventaire', 'rolesCloturer', 'rolesRouvrir', 'moisOuvertureSuivant'].forEach(function (c) {
      var r = circuitALaDate(c, date);
      if (!r.ok) { out.ok = false; out[c] = null; out.refus = r; } else out[c] = r.valeur;
    });
    return out;
  }


  /* TRANSITION 1 : démarrer la clôture (ouvert → en clôture). Les modules n'écrivent plus dans N ; le comptable passe ses écritures d'inventaire. */
  function demarrerCloture(annee) {
    annee = Number(annee);
    var x = exercice(annee);
    if (!x) return { ok: false, motif: 'Exercice ' + annee + ' inconnu.' };
    if (x.source === 'liasse') return { ok: false, motif: 'L’exercice ' + annee + ' est celui de la liasse déposée : il est clôturé et ne se rouvre pas ici.' };
    if (x.etat === 'clos') return { ok: false, motif: 'Exercice ' + annee + ' déjà clôturé : le rouvrir (comptable, motif obligatoire) pour le corriger.' };
    if (x.etat === 'en_cloture') return { ok: false, motif: 'L’exercice ' + annee + ' est déjà en clôture.' };
    var refusD = verifierCircuit('rolesDemarrer', 'CLOTURE_DEMARRAGE_RESERVE', 'Démarrer la clôture', 'Demander à l’un de ces rôles, ou faire modifier le circuit (écran « Exercices & clôtures », onglet « Circuit de clôture »).');
    if (refusD) return refusD;
    var pre = preCloture(annee);
    S.collection('exercices').update(x.id, { etat: 'en_cloture', demandeLe: new Date().toISOString(), demandePar: acteur(), resultatPrevu: pre.resultat });
    S.log('Démarrage de la clôture', 'M12', 'Exercice', String(annee), { etat: 'ouvert' }, { etat: 'en_cloture', resultat: pre.resultat });
    notifierCircuit('rolesCloturer', { type: 'cloture', libelle: 'Clôture ' + annee + ' à valider', detail: acteur() + ' a démarré la clôture de l’exercice ' + annee + ' : les modules n’y écrivent plus.', priorite: 'haute', reference: String(annee) });
    return { ok: true, pre: pre };
  }
  var demanderCloture = demarrerCloture;   /* ancien nom du geste, conservé pour les appelants et les sondes */

  /* TRANSITION 2 : reprendre la saisie (en clôture → ouvert), tant que rien n'est clôturé. */
  function reprendreSaisie(annee) {
    annee = Number(annee);
    var x = exercice(annee);
    if (!x || x.etat !== 'en_cloture') return { ok: false, motif: 'L’exercice ' + annee + ' n’est pas en clôture : rien à reprendre.' };
    var refusR = verifierCircuit('rolesDemarrer', 'CLOTURE_REPRISE_RESERVEE', 'Reprendre la saisie', 'Demander à l’un de ces rôles, ou faire modifier le circuit (écran « Exercices & clôtures », onglet « Circuit de clôture »).');
    if (refusR) return refusR;
    S.collection('exercices').update(x.id, { etat: 'ouvert', demandeLe: null, demandePar: null, reprisLe: new Date().toISOString(), reprisPar: acteur() });
    S.log('Reprise de la saisie', 'M12', 'Exercice', String(annee), { etat: 'en_cloture' }, { etat: 'ouvert' });
    return { ok: true };
  }

  /* Empreinte SHA-256 synchrone (FIPS 180-4) de l'export d'archive. */
  function sha256(texte) {
    var K = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    var H = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    var b = unescape(encodeURIComponent(texte)), l = b.length, w = [], i, j;
    for (i = 0; i < l; i++) w[i >> 2] |= b.charCodeAt(i) << (24 - (i % 4) * 8);
    w[l >> 2] |= 0x80 << (24 - (l % 4) * 8);
    var n = (((l + 8) >> 6) + 1) * 16; w[n - 1] = l * 8; for (i = 0; i < n; i++) w[i] = w[i] | 0;
    var rotr = function (x, k) { return (x >>> k) | (x << (32 - k)); };
    for (i = 0; i < n; i += 16) {
      var s = w.slice(i, i + 16), a = H.slice();
      for (j = 16; j < 64; j++) {
        var s0 = rotr(s[j - 15], 7) ^ rotr(s[j - 15], 18) ^ (s[j - 15] >>> 3), s1 = rotr(s[j - 2], 17) ^ rotr(s[j - 2], 19) ^ (s[j - 2] >>> 10);
        s[j] = (s[j - 16] + s0 + s[j - 7] + s1) | 0;
      }
      for (j = 0; j < 64; j++) {
        var S1 = rotr(a[4], 6) ^ rotr(a[4], 11) ^ rotr(a[4], 25), ch = (a[4] & a[5]) ^ (~a[4] & a[6]);
        var t1 = (a[7] + S1 + ch + K[j] + s[j]) | 0, S0 = rotr(a[0], 2) ^ rotr(a[0], 13) ^ rotr(a[0], 22);
        var mj = (a[0] & a[1]) ^ (a[0] & a[2]) ^ (a[1] & a[2]), t2 = (S0 + mj) | 0;
        a = [(t1 + t2) | 0, a[0], a[1], a[2], (a[3] + t1) | 0, a[4], a[5], a[6]];
      }
      for (j = 0; j < 8; j++) H[j] = (H[j] + a[j]) | 0;
    }
    return H.map(function (v) { return ('00000000' + (v >>> 0).toString(16)).slice(-8); }).join('');
  }

  /* TRANSITION 3 : clôturer définitivement (en clôture → clôturé). Par la Direction, la DAF ou l'administrateur, une AUTRE personne que celle qui a démarré
     la clôture (« signer n'est pas saisir »). Dans l'ordre et d'un seul tenant : pièce CL au 31/12/N, pièce AN au 01/01/N+1, verrou, archive. Un échec en
     cours de route défait tout ce qui a été posé : l'exercice reste en clôture, rien n'est écrit à moitié. */
  function validerCloture(annee, motif) {
    annee = Number(annee);
    var x = exercice(annee);
    if (!x || x.etat !== 'en_cloture') return { ok: false, motif: 'L’exercice ' + annee + ' n’est pas en clôture : démarrer la clôture d’abord.' };
    var refusV = verifierCircuit('rolesCloturer', 'CLOTURE_DEFINITIVE_RESERVEE', 'La clôture définitive', 'Demander à l’un de ces rôles, ou faire modifier le circuit (écran « Exercices & clôtures », onglet « Circuit de clôture »).');
    if (refusV) return refusV;
    if (!motif || String(motif).trim().length < 3) return { ok: false, motif: 'Un motif est obligatoire pour clôturer un exercice.' };
    if (x.demandePar === acteur()) return refusCfg('CLOTURE_MEME_PERSONNE', 'Signer n’est pas saisir : la clôture définitive doit venir d’une autre personne que celle qui a démarré la clôture (' + x.demandePar + ').', 'Faire prononcer la clôture par une autre personne du circuit.');
    var pre = preCloture(annee);
    if (pre.bloquants.length) return { ok: false, motif: 'Contrôles bloquants en échec : ' + pre.bloquants.map(function (b) { return b.libelle + (b.detail ? ' (' + b.detail + ')' : ''); }).join(' ; '), pre: pre };

    var col = S.collection('ecritures', { module: 'M12', entite: 'Écriture' });
    var base = ecrituresDe(annee);
    var res = resultatDe(base);
    var posees = [];
    function defaire() { posees.slice().reverse().forEach(function (u) { try { u.undo(); } catch (e) { /* déjà retirée */ } }); }
    function poser(l) { var r = col.insert(l); if (!r) throw new Error('Écriture refusée par le journal.'); posees.push(r); return r; }

    try {
      /* (1) PIÈCE DE CLÔTURE, journal CL, au 31/12/N : chaque compte des classes 6, 7 et 8 est soldé CENTRE DE COÛTS par centre de coûts ; la contrepartie de
         chaque centre va en 131 (bénéfice) ou 139 (perte), lus de la table des comptes de résultat. */
      var numCL = 'CL-' + annee + '-' + pad5(numeroPiece('CL', annee));
      var clBase = { numero: numCL, date: annee + '-12-31', journal: 'CL', journalLibelle: 'Journal de clôture',
        libelle: 'Clôture de l’exercice ' + annee + ' : détermination du résultat', origine: 'Clôture : résultat', statut: 'validee', origineCloture: 'cl' };
      var parCentre = {};
      base.filter(function (e) { return '678'.indexOf(String(e.compte).charAt(0)) >= 0; }).forEach(function (e) {
        var k = e.centreCout || ''; (parCentre[k] = parCentre[k] || []).push(e);
      });
      var lignesCL = [];
      Object.keys(parCentre).sort().forEach(function (centre) {
        var resCentre = 0;
        soldesParCompte(parCentre[centre]).forEach(function (sd) {
          if (Math.abs(sd.solde) < 1) return;
          resCentre += -sd.solde;
          lignesCL.push(Object.assign({}, clBase, { compte: sd.compte, compteLibelle: sd.libelle, centreCout: centre || null,
            debit: sd.solde < 0 ? -sd.solde : 0, credit: sd.solde > 0 ? sd.solde : 0 }));
        });
        if (Math.abs(resCentre) >= 1) {
          var cr = compteResultat(resCentre);
          lignesCL.push(Object.assign({}, clBase, { compte: cr.compte, compteLibelle: cr.libelle, centreCout: centre || null,
            debit: resCentre < 0 ? -resCentre : 0, credit: resCentre > 0 ? resCentre : 0 }));
        }
      });
      var dCL = C.sum(lignesCL, 'debit'), cCL = C.sum(lignesCL, 'credit');
      if (Math.abs(dCL - cCL) >= 1) throw new Error('Pièce de clôture déséquilibrée (' + C.money(Math.abs(dCL - cCL)) + ') : clôture refusée (RG-10).');
      lignesCL.forEach(poser);

      /* (2) PIÈCE D'À-NOUVEAUX, journal AN, au 01/01/N+1 : soldes des classes 1 à 5, résultat compris (calculés APRÈS la pièce CL). */
      var report = lignesDeReport(ecrituresDe(annee, false, true));
      var numAN = 'AN-' + (annee + 1) + '-' + pad5(numeroPiece('AN', annee + 1));
      var anBase = { numero: numAN, date: (annee + 1) + '-01-01', journal: 'AN', journalLibelle: 'Journal des à-nouveaux',
        libelle: 'À-nouveaux au 1er janvier ' + (annee + 1), origine: 'Clôture : à-nouveaux', statut: 'validee', origineCloture: 'an', centreCout: null };
      var dAN = C.sum(report, 'debit'), cAN = C.sum(report, 'credit');
      if (Math.abs(dAN - cAN) >= 1) throw new Error('À-nouveaux déséquilibrés (' + C.money(Math.abs(dAN - cAN)) + ') : vérifier les lettrages.');
      report.forEach(function (l) {
        poser(Object.assign({}, anBase, { compte: l.compte, compteLibelle: l.compteLibelle, debit: l.debit, credit: l.credit,
          libelle: l.libelle || anBase.libelle, pieceOrigine: l.pieceOrigine || null }));
      });

      /* (3) VERROU puis (4) ARCHIVE : l'empreinte du journal ARRÊTÉ, puis l'état « clôturé » en dernier. */
      var arret = ecrituresDe(annee, false, true);
      var texte = arret.map(function (e) { return [e.numero, e.date, e.journal, e.compte, e.debit, e.credit].join('|'); }).sort().join('\n');
      var empreinte = sha256(texte);
      S.collection('exercices').update(x.id, { etat: 'clos', valideLe: new Date().toISOString(), validePar: acteur(), motif: String(motif).trim(),
        resultat: res, empreinte: empreinte, nbEcrituresArchivees: arret.length, clNumero: numCL, anNumero: numAN });
      S.collection('clotures', { module: 'M12', entite: 'Clôture' }).insert({ annee: annee, type: 'cloture', clNumero: numCL, anNumero: numAN, resultat: res,
        par: acteur(), le: new Date().toISOString(), motif: String(motif).trim(), empreinte: empreinte });
    } catch (e) {
      defaire();
      return { ok: false, motif: String((e && e.message) || e) + ' L’exercice reste en clôture, rien n’a été écrit.' };
    }
    if (!exercice(annee + 1)) {
      S.collection('exercices').all().unshift({ id: 'EXO-' + (annee + 1), annee: annee + 1, debut: (annee + 1) + '-01-01', fin: (annee + 1) + '-12-31',
        statut: 'actif', etat: 'ouvert', source: 'journal' });
      S.log('Ouverture d’exercice', 'M12', 'Exercice', String(annee + 1), null, { etat: 'ouvert', origine: 'cloture' });
    }
    S.log('Clôture d’exercice', 'M12', 'Exercice', String(annee), { etat: 'en_cloture' }, { etat: 'clos', resultat: res, cl: numCL, an: numAN });
    notifierCircuit('rolesRouvrir', { type: 'cloture', libelle: 'Exercice ' + annee + ' clôturé', detail: 'Résultat ' + C.money(res) + ' ; pièces ' + numCL + ' et ' + numAN + ' écrites.', reference: String(annee) });
    S.save();
    /* L'archive de conservation naît AVEC la clôture, par quelque porte qu'elle soit prononcée. */
    var archive = null;
    try { archive = archiverExercice(annee); } catch (e2) { if (global.console) global.console.error('[SIGH] archive de clôture', e2); }
    return { ok: true, resultat: res, empreinte: empreinte, lignesAN: report.length, lignesCL: lignesCL.length, clNumero: numCL, anNumero: numAN, archive: archive ? archive.reference : null };
  }
  var cloturerDefinitivement = validerCloture;

  /* TRANSITION 4 : rouvrir (clôturé → en clôture). Le COMPTABLE seul, avec un motif d'au moins dix caractères. Rien ne s'efface : la pièce CL et la pièce AN
     sont CONTRE-PASSÉES (mêmes lignes, sens inversé, marquées `contrePasseDe`). Refusée si N+1 n'est plus ouvert (il a déjà consommé l'à-nouveau). */
  function rouvrirExercice(annee, motif) {
    annee = Number(annee);
    var x = exercice(annee);
    if (!x || x.etat !== 'clos') return { ok: false, motif: 'L’exercice ' + annee + ' n’est pas clôturé : rien à rouvrir.' };
    if (x.source === 'liasse') return { ok: false, motif: 'L’exercice ' + annee + ' est celui de la liasse déposée à la DGI : il ne se rouvre pas dans le logiciel.' };
    var refusO = verifierCircuit('rolesRouvrir', 'REOUVERTURE_RESERVEE', 'La réouverture', 'Demander à l’un de ces rôles, ou faire modifier le circuit (écran « Exercices & clôtures », onglet « Circuit de clôture »).');
    if (refusO) return refusO;
    if (!motif || String(motif).trim().length < 10) return { ok: false, motif: 'Le motif de réouverture doit compter au moins dix caractères.' };
    var suiv = exercice(annee + 1);
    if (suiv && suiv.etat !== 'ouvert') return { ok: false, motif: 'L’exercice ' + (annee + 1) + ' est ' + (suiv.etat === 'clos' ? 'clôturé' : 'en clôture') + ' : il a consommé les à-nouveaux de ' + annee + '. Le rouvrir ou le reprendre d’abord.' };
    var col = S.collection('ecritures', { module: 'M12', entite: 'Écriture' });
    var origines = col.active().filter(function (e) { return (e.numero === x.clNumero || e.numero === x.anNumero) && !e.contrePasseDe; });
    if (!origines.length) return { ok: false, motif: 'Les pièces de clôture de ' + annee + ' sont introuvables : réouverture refusée.' };
    var posees = [];
    function defaire() { posees.slice().reverse().forEach(function (u) { try { u.undo(); } catch (e) { /* déjà retirée */ } }); }
    try {
      var nCL = 'CL-' + annee + '-C' + pad5(numeroPiece('CL', annee)), nAN = 'AN-' + (annee + 1) + '-C' + pad5(numeroPiece('AN', annee + 1));
      origines.forEach(function (o) {
        var estCL = o.numero === x.clNumero;
        var r = col.insert({ numero: estCL ? nCL : nAN, date: o.date, journal: o.journal, journalLibelle: o.journalLibelle, compte: o.compte, compteLibelle: o.compteLibelle,
          centreCout: o.centreCout || null, debit: Number(o.credit) || 0, credit: Number(o.debit) || 0, statut: 'validee',
          libelle: 'Contre-passation de ' + o.numero + ' : réouverture de ' + annee, origine: 'Clôture : contre-passation', origineCloture: estCL ? 'cl-contre' : 'an-contre',
          contrePasseDe: o.numero, pieceOrigine: o.pieceOrigine || null });
        if (!r) throw new Error('Contre-passation refusée par le journal.');
        posees.push(r);
      });
      S.collection('exercices').update(x.id, { etat: 'en_cloture', rouvertLe: new Date().toISOString(), rouvertPar: acteur(), motifReouverture: String(motif).trim(),
        valideLe: null, validePar: null, resultat: null });
      S.collection('clotures', { module: 'M12', entite: 'Clôture' }).insert({ annee: annee, type: 'reouverture', clNumero: nCL, anNumero: nAN, contrePasse: [x.clNumero, x.anNumero],
        par: acteur(), le: new Date().toISOString(), motif: String(motif).trim() });
    } catch (e) {
      defaire();
      return { ok: false, motif: String((e && e.message) || e) + ' L’exercice reste clôturé, rien n’a été écrit.' };
    }
    S.log('Réouverture d’exercice', 'M12', 'Exercice', String(annee), { etat: 'clos' }, { etat: 'en_cloture', motif: String(motif).trim(), contrePasse: [x.clNumero, x.anNumero] });
    notifierCircuit('rolesCloturer', { type: 'cloture', libelle: 'Exercice ' + annee + ' rouvert', detail: acteur() + ' a rouvert l’exercice ' + annee + ' : ' + String(motif).trim(), priorite: 'haute', reference: String(annee) });
    S.save();
    return { ok: true, pieces: [nCL, nAN], lignes: posees.length };
  }

  /**
   * L'ARCHIVE DE CLÔTURE DANS LA GED. L'obligation de conservation (dix ans, OHADA) se tient là où la
   * clinique range ses pièces. La fiche porte la balance générale de l'exercice figé et son EMPREINTE
   * SHA-256 : l'exercice étant en lecture seule au moteur, le grand livre se rééditera à l'identique, et
   * l'empreinte le prouve. UNE archive par exercice : en déposer deux créerait deux « vérités » à conserver.
   * Retourne la fiche (existante ou nouvelle) ; `.deja` dit qu'elle existait.
   */
  function archiverExercice(annee) {
    var col = S.collection('documents', { module: 'GED', entite: 'Document' });
    var f = exercice(annee) || { annee: annee };
    /* UNE archive PAR CLÔTURE : une réouverture suivie d'une seconde clôture dépose une seconde archive, sans toucher à la première (piste d'audit). */
    var nbClotures = S.collection('clotures', { module: 'M12', entite: 'Clôture' }).active().filter(function (c) { return c.annee === Number(annee) && c.type === 'cloture'; }).length;
    var version = Math.max(1, nbClotures);
    var code = 'EX' + annee + (version > 1 ? '-V' + version : '');
    var deja = col.active().filter(function (d) { return d.codeRattachement === code; })[0];
    if (deja) return Object.assign({}, deja, { deja: true });
    var esc = function (v) { v = v == null ? '' : String(v); return /[;"\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
    var csv = ['Compte;Intitulé;Débit;Crédit'].concat(soldesParCompte(ecrituresDe(annee)).map(function (l) {
      return [l.compte, l.libelle, l.debit, l.credit].map(esc).join(';');
    })).join('\n');
    var an = String(C.aujourdhui().getFullYear()), rang = 0;
    col.all().forEach(function (d) {
      var m = new RegExp('^DOC-' + an + '-(\\d+)$').exec(String(d.reference || ''));
      if (m) rang = Math.max(rang, Number(m[1]));
    });
    var empBalance = sha256(csv);
    var paquet = deposerArchive(annee, version, f);
    var r = col.insert({
      reference: 'DOC-' + an + '-' + ('00000' + (rang + 1)).slice(-5),
      libelle: 'Clôture de l’exercice ' + annee + (version > 1 ? ' (clôture n° ' + version + ')' : '') + ' : archive légale, ' + paquet.fichiers.length + ' fichiers (empreinte du manifeste ' + paquet.manifesteEmpreinte.slice(0, 12) + '…)',
      categorie: 'cloture_exercice', rattachement: 'Administration', rattacheA: 'Exercice ' + annee, codeRattachement: code,
      format: 'CSV', taille: csv.length, version: version, signe: true, archive: true, etatValidation: 'valide', conservation: 10,
      consultations: 0, date: C.iso(C.aujourdhui()), deposePar: (S.session() || {}).nom || '—',
      empreinte: f.empreinte || empBalance, empreinteBalance: empBalance, resultat: f.resultat == null ? null : f.resultat, contenu: csv,
      archiveExercice: paquet.reference, manifesteEmpreinte: paquet.manifesteEmpreinte,
    });
    return Object.assign({}, r.record, { deja: false });
  }

  /* =========================================================================
   * L'ARCHIVE LÉGALE D'UNE CLÔTURE (arbitrage du 05/11/2026)
   * -------------------------------------------------------------------------
   * Les écritures et la balance en CSV, les états de synthèse imprimables (HTML : « Enregistrer en PDF » se fait à l'impression), et un MANIFESTE portant
   * l'empreinte SHA-256 de chaque fichier. Immuable : la collection `archivesExercice` refuse toute modification, tout archivage et tout second dépôt pour la
   * même clôture ; JAMAIS régénérée. Chaque téléchargement VÉRIFIE l'empreinte avant de livrer : un fichier altéré est un refus nommé, pas un fichier livré.
   *
   * LE FORMAT DU CSV DES ÉCRITURES est isolé ICI, en un seul point (`formatEcrituresCsv`) : colonnes du journal SYSCOHADA révisé, séparateur « ; »,
   * UTF-8 avec BOM, dates JJ/MM/AAAA, montants entiers en FCFA (la monnaie n'a pas de subdivision). Validé par la Direction le 05/11/2026.
   * ======================================================================= */
  var ENTETE_ECRITURES = ['Journal', 'Date', 'N° pièce', 'Compte', 'Intitulé du compte', 'Libellé de l’écriture', 'Centre de coûts', 'Débit', 'Crédit', 'Lettrage', 'Statut'];
  function csvCellule(v) { v = v == null ? '' : String(v); return /[;"\n\r]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; }
  function dateJJMMAAAA(d) { var x = C.toDate(d); return x && !isNaN(x) ? C.pad(x.getDate(), 2) + '/' + C.pad(x.getMonth() + 1, 2) + '/' + x.getFullYear() : ''; }
  function formatEcrituresCsv(lignes) {
    var corps = lignes.slice().sort(function (a, b) {
      return String(a.date).localeCompare(String(b.date)) || String(a.numero).localeCompare(String(b.numero)) || String(a.compte).localeCompare(String(b.compte));
    }).map(function (e) {
      return [e.journal, dateJJMMAAAA(e.date), e.numero, e.compte, e.compteLibelle, e.libelle, e.centreCout, Math.round(Number(e.debit) || 0), Math.round(Number(e.credit) || 0), e.lettrage, e.statut].map(csvCellule).join(';');
    });
    return '﻿' + [ENTETE_ECRITURES.join(';')].concat(corps).join('\r\n') + '\r\n';
  }
  function formatBalanceCsv(soldes) {
    return '﻿' + ['Compte;Intitulé;Débit;Crédit;Solde'].concat(soldes.map(function (l) {
      return [l.compte, l.libelle, Math.round(l.debit), Math.round(l.credit), Math.round(l.solde)].map(csvCellule).join(';');
    })).join('\r\n') + '\r\n';
  }
  function htmlEchappe(v) { return String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  function etatsHtml(annee, f, soldes, lignes) {
    var classe = function (c) { return soldes.filter(function (l) { return String(l.compte).charAt(0) === c; }); };
    var somme = function (l, k) { return l.reduce(function (n, x) { return n + x[k]; }, 0); };
    var bloc = function (titre, l) {
      return '<h2>' + htmlEchappe(titre) + '</h2><table><tr><th>Compte</th><th>Intitulé</th><th>Débit</th><th>Crédit</th><th>Solde</th></tr>'
        + l.map(function (x) { return '<tr><td>' + htmlEchappe(x.compte) + '</td><td>' + htmlEchappe(x.libelle) + '</td><td>' + Math.round(x.debit) + '</td><td>' + Math.round(x.credit) + '</td><td>' + Math.round(x.solde) + '</td></tr>'; }).join('')
        + '<tr><th colspan="2">Total</th><th>' + Math.round(somme(l, 'debit')) + '</th><th>' + Math.round(somme(l, 'credit')) + '</th><th>' + Math.round(somme(l, 'solde')) + '</th></tr></table>';
    };
    return '<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>États de l’exercice ' + annee + '</title><style>body{font-family:Arial,sans-serif;font-size:11pt}table{border-collapse:collapse;width:100%}td,th{border:1px solid #888;padding:3px 6px;text-align:right}td:nth-child(-n+2),th:nth-child(-n+2){text-align:left}h2{margin-top:18pt}</style></head><body>'
      + '<h1>États de synthèse : exercice ' + annee + '</h1><p>Résultat net : <strong>' + Math.round(f.resultat == null ? resultatDe(lignes) : f.resultat) + ' FCFA</strong>. Journal arrêté, clôture ' + htmlEchappe(f.clNumero || '') + '. Les états de la liasse (bilan, compte de résultat, flux) se rééditent à l’identique depuis l’exercice figé ; « Enregistrer en PDF » se fait à l’impression.</p>'
      + bloc('Classes 1 à 5 : bilan (soldes)', soldes.filter(function (l) { return '12345'.indexOf(String(l.compte).charAt(0)) >= 0; }))
      + bloc('Classes 6 et 7 : charges et produits', classe('6').concat(classe('7')))
      + bloc('Classe 8 : hors activités ordinaires', classe('8'))
      + '</body></html>';
  }
  function deposerArchive(annee, version, f) {
    var archives = S.collection('archivesExercice', { module: 'M12', entite: 'Archive de clôture' });
    var ref = 'ARC-' + annee + '-' + ('0' + version).slice(-2);
    var existante = archives.all().filter(function (a) { return a.reference === ref; })[0];
    if (existante) return existante;
    var lignes = ecrituresDe(annee, true, true);
    var soldes = soldesParCompte(ecrituresDe(annee));
    var fichiers = [
      { nom: 'ecritures-' + annee + '.csv', type: 'text/csv;charset=utf-8', contenu: formatEcrituresCsv(lignes) },
      { nom: 'balance-' + annee + '.csv', type: 'text/csv;charset=utf-8', contenu: formatBalanceCsv(soldes) },
      { nom: 'etats-' + annee + '.html', type: 'text/html;charset=utf-8', contenu: etatsHtml(annee, f, soldes, ecrituresDe(annee)) },
    ].map(function (x) { return { nom: x.nom, type: x.type, contenu: x.contenu, taille: x.contenu.length, empreinte: sha256(x.contenu) }; });
    var manifeste = fichiers.map(function (x) { return x.empreinte + '  ' + x.nom; }).join('\n') + '\n';
    var man = { nom: 'manifeste-' + annee + '.txt', type: 'text/plain;charset=utf-8', contenu: manifeste, taille: manifeste.length, empreinte: sha256(manifeste) };
    var r = archives.insert({ reference: ref, annee: Number(annee), version: version, creeLe: new Date().toISOString(), par: acteur(),
      clNumero: f.clNumero || null, anNumero: f.anNumero || null, fichiers: fichiers.concat([man]), manifesteEmpreinte: man.empreinte });
    return r.record;
  }

  /* TÉLÉCHARGEMENT : l'empreinte est RECALCULÉE et comparée à celle du manifeste avant de livrer. Un fichier altéré est refusé en le nommant. */
  function lireArchive(reference, nomFichier) {
    var a = S.collection('archivesExercice').all().filter(function (x) { return x.reference === reference; })[0];
    if (!a) return { ok: false, motif: 'Archive ' + reference + ' introuvable.' };
    var fich = (a.fichiers || []).filter(function (x) { return x.nom === nomFichier; })[0];
    if (!fich) return { ok: false, motif: 'Le fichier « ' + nomFichier + ' » ne figure pas dans l’archive ' + reference + '.' };
    var recalc = sha256(fich.contenu);
    if (recalc !== fich.empreinte) return { ok: false, motif: 'Archive ' + reference + ', fichier ' + nomFichier + ' : l’empreinte ne correspond plus (attendue ' + fich.empreinte.slice(0, 12) + '…, calculée ' + recalc.slice(0, 12) + '…). Le fichier a été altéré : téléchargement refusé.', altere: true };
    var manifeste = (a.fichiers || []).filter(function (x) { return /^manifeste-/.test(x.nom); })[0];
    if (manifeste && nomFichier !== manifeste.nom && manifeste.contenu.indexOf(fich.empreinte + '  ' + fich.nom) < 0) {
      return { ok: false, motif: 'Archive ' + reference + ' : le manifeste ne porte pas l’empreinte de ' + nomFichier + '. Téléchargement refusé.', altere: true };
    }
    return { ok: true, fichier: fich, archive: a };
  }
  S.garder('archivesExercice', function (op, rec) {
    if (op === 'inserer') {
      var deja = S.collection('archivesExercice').all().filter(function (a) { return a.reference === (rec && rec.reference); })[0];
      return deja ? 'L’archive ' + rec.reference + ' existe déjà : une archive de clôture n’est jamais régénérée.' : null;
    }
    return 'Une archive de clôture est immuable : elle ne se modifie ni ne s’archive. Une nouvelle clôture dépose une nouvelle archive.';
  });
  S.garder('clotures', function (op) {
    return op === 'inserer' ? null : 'Le registre des clôtures et réouvertures est une piste d’audit : il ne se modifie ni ne s’archive.';
  });

  /* LETTRAGE : un ensemble de lignes d'UN compte de tiers dont le total s'annule. */
  function lettrer(compte, ids) {
    if (!sensLettrable(compte)) return { ok: false, motif: 'Le compte ' + compte + ' n’est pas lettrable (comptes de tiers seulement).' };
    var col = S.collection('ecritures');
    var lignes = (ids || []).map(function (id) { return col.get(id); });
    if (lignes.length < 2 || lignes.some(function (l) { return !l || String(l.compte) !== String(compte) || l.lettrage; }))
      return { ok: false, motif: 'Sélection invalide : au moins deux lignes, du même compte, non encore lettrées.' };
    var net = C.sum(lignes, 'debit') - C.sum(lignes, 'credit');
    if (Math.abs(net) >= 1) return { ok: false, motif: 'Lettrage refusé — l’ensemble ne s’annule pas (écart ' + C.money(Math.abs(net)) + ').' };
    var code = String.fromCharCode(65 + (col.all().filter(function (e) { return e.lettrage; }).map(function (e) { return e.lettrage; })
      .filter(function (v, i, a) { return a.indexOf(v) === i; }).length % 26));
    /* Le retour de update est lu : un refus de la garde rend null. On défait les lignes déjà posées et on le dit (code, motif, geste). */
    var res = [];
    lettrageEnCours = true;
    try {
      lignes.forEach(function (l) { res.push(col.update(l.id, { lettrage: code, lettreLe: new Date().toISOString(), lettrePar: acteur() })); });
    } finally { lettrageEnCours = false; }
    if (res.some(function (r) { return !r; })) {
      res.forEach(function (r) { if (r) r.undo(); });
      return { ok: false, motif: 'LETTRAGE_REFUSE : une ligne est refusée par la garde de l’exercice (clos). Rouvrir l’exercice par le comptable (motif obligatoire) ; aucun lettrage n’a été posé.' };
    }
    return { ok: true, code: code, lignes: res.length };
  }
  function delettrer(compte, code, motif) {
    if (!motif || String(motif).trim().length < 3) return { ok: false, motif: 'Un motif est obligatoire pour dé-lettrer.' };
    var col = S.collection('ecritures'), n = 0;
    var cibles = col.all().filter(function (e) { return String(e.compte) === String(compte) && e.lettrage === code; });
    var res = [];
    lettrageEnCours = true;
    try {
      cibles.forEach(function (l) { res.push(col.update(l.id, { lettrage: null, delettreLe: new Date().toISOString(), delettreMotif: String(motif).trim() })); });
    } finally { lettrageEnCours = false; }
    if (res.some(function (r) { return !r; })) {
      res.forEach(function (r) { if (r) r.undo(); });
      return { ok: false, motif: 'DELETTRAGE_REFUSE : une ligne est refusée par la garde de l’exercice (clos). Rouvrir l’exercice par le comptable (motif obligatoire) ; aucune ligne n’a été dé-lettrée.' };
    }
    n = res.length;
    return n ? { ok: true, lignes: n } : { ok: false, motif: 'Aucune ligne lettrée « ' + code + ' » sur ce compte.' };
  }

  /** La date tombe-t-elle dans l'exercice choisi ? (écrans de flux : registre fiscal, avoirs…) */
  function dansExerciceChoisi(date) {
    if (!date) return true;
    var n = Number(date);   /* une année seule (bulletins de paie) */
    return (n >= 1900 && n < 3000 && String(date).length === 4 ? n : anneeDe(date)) === exerciceChoisi();
  }
  /** La fenêtre de l'exercice choisi : du 1er janvier au 31 décembre, ou à aujourd'hui pour l'année en cours. */
  function fenetreExercice() {
    var a = exerciceChoisi(), auj = C.aujourdhui(), fin = a >= auj.getFullYear() ? auj : new Date(a, 11, 31);
    return { annee: a, debut: C.iso(new Date(a, 0, 1)), fin: C.iso(fin) };
  }

  /* ==========================================================================
   * SESSIONS DE POSTE : ACTIVES, SUSPENDUES, CLOTURÉES (01/11/2026)
   * --------------------------------------------------------------------------
   * La Direction a demandé que « Clôturer » change le statut d'une session. Le
   * registre vit au magasin (`sessionsUtilisateur`, une fiche par session) :
   * la clôture y est ÉCRITE, avec sa date, son auteur et son motif, et le poste
   * visé la lit au PROCHAIN GESTE (ouverture d'écran, clic) pour retomber sur
   * la connexion.
   *
   * Trois principes, tous nés d'un défaut évité :
   *  - une session clôturée NE ROUVRE PAS : l'agent se reconnecte et obtient
   *    une AUTRE session ; rouvrir la fiche ferait mentir l'heure de clôture ;
   *  - RIEN n'est supprimé (RG-14) : la fiche clôturée reste au registre, avec
   *    qui l'a fermée et quand (RG-12) ;
   *  - un agent qui clôture SA PROPRE session le DIT : refus nommé tant que la
   *    confirmation explicite n'est pas donnée, puis déconnexion immédiate.
   * `etat` et non `statut` : `statut` est le champ d'archivage du magasin.
   * ======================================================================== */
  var ETATS_SESSION = { active: 'Active', suspendue: 'Suspendue', cloturee: 'Clôturée' };
  function colSessions() { return S.collection('sessionsUtilisateur', { module: 'M14', entite: 'session', prefix: 'SES' }); }
  function refusSession(code, motif, geste) { return { ok: false, code: code, motif: motif, geste: geste }; }
  function sessionDuPoste() {
    var s = S.session();
    if (!s || !s.sessionId) return null;
    return colSessions().get(s.sessionId) || null;
  }
  /** La fiche de la session courante, créée à la première occasion (connexion, banc). */
  function assurerSession() {
    var s = S.session();
    if (!s || !s.role) return null;
    var col = colSessions();
    if (s.sessionId && col.get(s.sessionId)) return s.sessionId;
    var poste = (global.location && global.location.hostname) || 'poste';
    var identifiant = s.identifiant || s.role;
    var reprise = s.nouvelleSession ? null : col.all().filter(function (f) {
      return f.source === 'poste' && f.identifiant === identifiant && f.poste === poste && f.etat !== 'cloturee';
    })[0];
    var id = reprise ? reprise.id : null;
    if (!id) {
      /* L'ouverture d'une session n'est pas un geste de l'agent : elle s'écrit au registre SANS entrée de journal (comme un amorçage),
         la connexion étant déjà journalisée par le serveur. Seules la suspension et la clôture, elles, sont des gestes journalisés. */
      var maintenant = new Date().toISOString();
      col.all();
      id = 'SES' + C.uid();
      S.raw().sessionsUtilisateur.unshift({
        id: id, statut: 'actif', identifiant: identifiant, nomComplet: s.nom || identifiant, role: s.role, poste: poste, adresseIp: null,
        source: 'poste', debut: maintenant, derniereActivite: maintenant, inactivite: 0, etat: 'active',
        _creePar: S.currentUser(), _creeLe: maintenant,
      });
      S.save();
    }
    s.sessionId = id; delete s.nouvelleSession;
    S.storage.set('sigh-cnt:session', JSON.stringify(s));
    return id;
  }
  /** La session courante a-t-elle été clôturée depuis un autre écran ou un autre poste ? */
  function clotureeDuPoste() {
    var f = sessionDuPoste();
    return f && f.etat === 'cloturee' ? f : null;
  }
  /** Suspend (verrou d'inactivité) ou reprend la session courante. Une session clôturée n'en change plus. */
  function changerEtatSession(etat) {
    var f = sessionDuPoste();
    if (!f || f.etat === 'cloturee' || f.etat === etat) return false;
    colSessions().update(f.id, { etat: etat, derniereActivite: new Date().toISOString() });
    return true;
  }
  /**
   * CLOTURER. Rend { ok:true, fiche, propre } ou un refus NOMMÉ { ok:false, code, motif, geste }.
   * opts : { confirmePropre, motif }.
   */
  function cloturerSession(id, opts) {
    var o = opts || {}, s = S.session() || {};
    var f = colSessions().get(id);
    if (!f) return refusSession('SESSION_INCONNUE', 'Cette session n’existe pas au registre.', 'Actualiser la liste des sessions.');
    if (f.etat === 'cloturee') {
      return refusSession('DEJA_CLOTUREE', 'Cette session est déjà clôturée (le ' + C.dateHeure(f.clotureLe) + ', par ' + (f.cloturePar || 'un administrateur') + '). Une session clôturée ne se rouvre pas.',
        'L’agent ouvre une nouvelle session en se reconnectant.');
    }
    var d = global.SIGH.nav.droitsEcran(s.role, 'm14-sessions', 'M14');
    if (!d.editer) {
      return refusSession('DROIT_REFUSE', 'Le profil courant ne peut pas clôturer de session.', 'Demander la clôture à l’administrateur système.');
    }
    var propre = !!s.sessionId && s.sessionId === f.id;
    if (propre && !o.confirmePropre) {
      return refusSession('SESSION_PROPRE', 'C’est VOTRE session : la clôturer vous déconnecte aussitôt de ce poste.',
        'Confirmer explicitement la clôture de votre propre session.');
    }
    var patch = {
      etat: 'cloturee', clotureLe: new Date().toISOString(), cloturePar: S.currentUser(),
      clotureParIdentifiant: s.identifiant || s.role, clotureMotif: o.motif || null, cloturePropre: propre,
    };
    var r = colSessions().update(id, patch);
    if (!r) return refusSession('ECRITURE_REFUSEE', 'Le magasin a refusé l’écriture.', 'Réessayer, puis consulter le journal d’audit.');
    return { ok: true, fiche: r.record, propre: propre };
  }

  global.SIGH.sessions = {
    ETATS: ETATS_SESSION, collection: colSessions, courante: sessionDuPoste, assurer: assurerSession,
    cloturee: clotureeDuPoste, changerEtat: changerEtatSession, cloturer: cloturerSession,
  };

  global.SIGH.exercice = {
    dansExercice: dansExerciceChoisi, fenetre: fenetreExercice,
    liste: exercices, ouvrirDuJour: ouvrirExercicesDuJour, de: exercice, etat: etatExercice, choisi: exerciceChoisi, choisir: choisirExercice,
    dateReference: dateReference, voisin: exerciceVoisin, parDefaut: exerciceParDefaut,
    anneeDe: anneeDe, ecrituresDe: ecrituresDe, soldes: soldesParCompte, resultat: resultatDe,
    provisoires: aNouveauxProvisoires, soldesCompte: soldesGrandLivre, preCloture: preCloture, demander: demanderCloture, demarrer: demarrerCloture, reprendre: reprendreSaisie,
    valider: validerCloture, cloturer: validerCloture, comptesResultat: comptesResultat, controleCompteResultat: controleCompteResultat, rouvrir: rouvrirExercice, compteResultat: compteResultat,
    lettrer: lettrer, delettrer: delettrer, lettrable: sensLettrable, sha256: sha256, archiver: archiverExercice, lireArchive: lireArchive,
    formatEcrituresCsv: formatEcrituresCsv,
    /* Le circuit de clôture (lot CLO C1) : lu à la date, réglé par un geste réservé, jamais écrit en dur. */
    circuit: circuitALaDate, circuitComplet: circuitComplet, peut: peutDansCircuit, nomsRoles: nomsRoles, definirCircuit: definirCircuit, peutRegler: peutRegler,
    versionsCircuit: versionsCircuit, definitionsCircuit: function () { return D.REGLAGES_CLOTURE; },
  };

  /* Le moteur du BFR est EXPOSÉ pour être SONDÉ, jamais recopié : le scénario
     l'interroge et compare ses trois composantes à un recompte du magasin. */
  global.SIGH.bfr = {
    calculer: bfr, indicateurs: indicateursPilotage,
    alertes: alertesRecouvrement, objectifs: objectifsPilotage,
  };

  /* ==========================================================================
   * CONFIGURATION FISCALE VALIDÉE ET DATÉE (Direction, 06/11/2026)
   * --------------------------------------------------------------------------
   * L'identité légale (cfg-branding, cfg-fiscalite) et les obligations
   * fiscales (cfg-comptabilite) se VÉRIFIENT et se VALIDENT à la première
   * configuration, puis se modifient par VERSIONS DATÉES avec historique : une
   * pièce émise sous l'ancienne version garde son en-tête, une échéance payée
   * garde sa quittance. Le moteur vit AU SOCLE (lu par CFG, print.js, M8, M11,
   * M12, M13, l'assistant d'installation) et il est EXPOSÉ pour être SONDÉ,
   * jamais recopié. Chaque refus se nomme : code, motif, geste.
   * ======================================================================== */
  var ROLES_VALIDATION = ['direction', 'da', 'admin'];
  function colIdentite() { return S.collection('identiteLegale', { module: 'CFG', entite: 'identité légale', prefix: 'IDL' }); }
  function colObligations() { return S.collection('obligationsFiscales', { module: 'CFG', entite: 'obligation fiscale', prefix: 'OBL' }); }
  function colHistoriqueObligations() { return S.collection('historiqueObligations', { module: 'CFG', entite: 'version antérieure d’obligation fiscale', prefix: 'HOB' }); }

  function refusCfg(code, motif, geste, extra) {
    return Object.assign({ ok: false, code: code, motif: motif, geste: geste || null }, extra || {});
  }
  function aujIso() { return C.iso(C.aujourdhui()); }
  function isoJour(d) { return typeof d === 'string' ? d.slice(0, 10) : C.iso(d); }
  function veille(iso) { return C.iso(C.addDays(isoJour(iso), -1)); }
  function libelleRole(r) {
    var N = global.SIGH.nav;
    return (N && N.ROLES && N.ROLES[r] && N.ROLES[r].label) || r || 'aucun';
  }
  /* La maquette n'a pas de vrai mode fileul : le réglage `posteFileul` tient lieu de drapeau, pour que la règle
     existe et se sonde. Au poste, c'est le mode du poste qui décide (famille R publiée par la mère seule). */
  function posteFileul() { return S.reglage('posteFileul', false) === true; }
  function controleEcritureCfg() {
    if (posteFileul()) {
      return refusCfg('FILEUL_LECTURE_SEULE', 'Cette configuration est tenue par la mère ; modifiez-la sur le poste mère.',
        'Ouvrir le même écran sur le poste mère : la modification arrivera ici par la synchronisation.');
    }
    return null;
  }
  function controleDateEffet(d, minimum, existante) {
    if (!d) return refusCfg('DATE_EFFET_REQUISE', 'La date d’effet est obligatoire.', 'Choisir la date à partir de laquelle la nouvelle version s’applique.');
    var annee = Number(String(d).slice(0, 4));
    var etat = global.SIGH.exercice && global.SIGH.exercice.etat ? global.SIGH.exercice.etat(annee) : 'ouvert';
    if (etat === 'clos') {
      return refusCfg('EXERCICE_CLOS', 'La date d’effet tombe dans un exercice clos (' + annee + ') ; choisissez une date de l’exercice ouvert.',
        'Choisir une date d’effet dans l’exercice ' + C.aujourdhui().getFullYear() + '.');
    }
    if (minimum && d < isoJour(minimum)) {
      /* Une version DÉJÀ PROGRAMMÉE à une date future est la vraie cause : le refus la NOMME et dit le geste (E-A3-03). */
      if (existante && existante.dateEffet && isoJour(existante.dateEffet) > aujIso()) {
        var quoi = existante.libelleVersion || D.libelleEcheance(existante);
        return refusCfg('DATE_EFFET_ANTERIEURE', 'Une version de ' + (existante.code || 'cette fiche') + ' est déjà programmée à compter du ' + C.dateFR(isoJour(existante.dateEffet))
          + ' (' + quoi + ') : la date d’effet (' + C.dateFR(d) + ') lui est antérieure.',
          'Annuler d’abord la version à venir (commande « Annuler la version à venir » de la ligne, avec un motif), puis saisir la correction ; ou choisir une date d’effet au plus tôt le '
          + C.dateFR(isoJour(minimum)) + '.', { versionAVenir: { code: existante.code, dateEffet: isoJour(existante.dateEffet), id: existante.id || null } });
      }
      return refusCfg('DATE_EFFET_ANTERIEURE', 'La date d’effet (' + C.dateFR(d) + ') est antérieure à la version en vigueur (' + C.dateFR(isoJour(minimum)) + ').',
        'Choisir une date d’effet au plus tôt le ' + C.dateFR(isoJour(minimum)) + '.');
    }
    return null;
  }
  function controleValidation() {
    var r = controleEcritureCfg(); if (r) return r;
    var role = roleCourant();
    if (ROLES_VALIDATION.indexOf(role) < 0) {
      return refusCfg('VALIDATION_RESERVEE', 'La validation de la configuration fiscale est réservée à la Direction, à la DAF et à l’administrateur système. Profil : ' + libelleRole(role) + '.',
        'Demander à la Direction ou à la DAF de valider depuis son poste.');
    }
    return null;
  }
  /* Écrit plusieurs fiches d'un coup, UNE ligne de journal : vingt validations ne font pas vingt gestes. */
  function marquerToutes(nom, fiches, patch) {
    var brut = S.raw()[nom] || [];
    fiches.forEach(function (f) {
      var rec = brut.filter(function (x) { return x.id === f.id; })[0];
      if (rec) Object.assign(rec, patch);
    });
    S.save(); S.emit(nom);
  }

  /* --- Identité légale ------------------------------------------------------ */
  function normaliserIdentite(champs) {
    var c = {};
    (C.CHAMPS_IDENTITE || []).forEach(function (k) {
      if (champs[k] === undefined) return;
      var v = champs[k];
      if (k === 'telephones') {
        v = Array.isArray(v) ? v : String(v || '').split(/[\/,;]/);
        v = v.map(function (t) { return String(t).trim(); }).filter(Boolean);
      } else if (typeof v === 'string') v = v.trim();
      c[k] = v;
    });
    return c;
  }
  function controleIdentite(c) {
    if (c.nom !== undefined && !c.nom) return refusCfg('NOM_REQUIS', 'La dénomination sociale est obligatoire.', 'Saisir la dénomination telle qu’elle figure au RCCM.');
    if (c.ifu !== undefined && !/^\d{13}$/.test(String(c.ifu).replace(/\s/g, ''))) return refusCfg('IFU_FORMAT', 'L’IFU compte 13 chiffres.', 'Relever l’IFU sur l’attestation d’immatriculation fiscale.');
    if (c.rccm !== undefined && !c.rccm) return refusCfg('RCCM_REQUIS', 'Le RCCM est obligatoire.', 'Relever le RCCM sur l’extrait du registre du commerce.');
    if (c.telephones !== undefined && !c.telephones.length) return refusCfg('TELEPHONE_REQUIS', 'Au moins un téléphone est requis sur l’en-tête.', 'Saisir le ou les numéros, séparés par « / ».');
    return null;
  }
  function identiteEnForce() { return S.identiteALaDate(aujIso()); }
  function identiteJamaisValidee() { return !colIdentite().all().some(function (v) { return v.valideLe; }); }
  function identiteExigeVersion() { return !identiteJamaisValidee(); }
  function versionsIdentiteAValider() {
    var a = aujIso();
    return colIdentite().active().filter(function (v) { return !v.fin || isoJour(v.fin) >= a; });
  }
  /** AVANT la première validation : « Enregistrer » corrige la version en force (la première configuration est un brouillon). */
  function enregistrerIdentite(champs, opts) {
    opts = opts || {};
    var r = controleEcritureCfg(); if (r) return r;
    var c = normaliserIdentite(champs || {});
    r = controleIdentite(c); if (r) return r;
    var enForce = identiteEnForce();
    if (!enForce) return refusCfg('IDENTITE_ABSENTE', 'Aucune version de l’identité légale au magasin.', 'Réinitialiser le jeu de démonstration (Paramètres système).');
    if (identiteExigeVersion()) {
      return refusCfg('VERSION_REQUISE', 'L’identité légale a déjà été validée : toute modification crée une version datée.',
        'Indiquer la date d’effet et le motif (modale « Portée de la modification »).', { versionRequise: true });
    }
    var res = colIdentite().update(enForce.id, Object.assign({}, c, { modifieLe: new Date().toISOString(), modifiePar: acteur() }));
    if (!res) return refusCfg('ECRITURE_REFUSEE', 'La fiche n’a pas pu être écrite.', 'Voir le journal.');
    S.log('Identité légale enregistrée', 'CFG', 'IdentiteLegale', enForce.id, null, { version: enForce.version, champs: Object.keys(c), origine: opts.origine || null });
    return { ok: true, mode: 'en_place', version: enForce.version, fiche: res.record, aValider: true };
  }
  /** APRÈS une validation : une nouvelle version, datée, motivée ; l'ancienne reçoit sa date de fin et reste. */
  function nouvelleVersionIdentite(champs, opts) {
    opts = opts || {};
    var r = controleEcritureCfg(); if (r) return r;
    var c = normaliserIdentite(champs || {});
    r = controleIdentite(c); if (r) return r;
    if (!opts.motif || !String(opts.motif).trim()) return refusCfg('MOTIF_REQUIS', 'Le motif est obligatoire dès la version 2.', 'Dire pourquoi l’identité change (changement de RCCM, nouvelle adresse…).');
    var d = isoJour(opts.dateEffet || aujIso());
    var col = colIdentite();
    var toutes = col.active();
    var couverte = S.identiteALaDate(d);
    r = controleDateEffet(d, couverte && couverte.debut); if (r) return r;
    if (toutes.some(function (v) { return v.debut && isoJour(v.debut) === d; })) {
      return refusCfg('VERSION_EXISTANTE', 'Une version prend déjà effet le ' + C.dateFR(d) + '.', 'Choisir une autre date d’effet.');
    }
    var suivante = toutes.filter(function (v) { return v.debut && isoJour(v.debut) > d; })
      .sort(function (a, b) { return String(a.debut).localeCompare(String(b.debut)); })[0] || null;
    var numero = Math.max.apply(null, col.all().map(function (v) { return v.version || 0; }).concat([0])) + 1;
    var fiche = Object.assign({}, C.champsIdentite(couverte || C.BRAND_ORIGINE), c, {
      version: numero, debut: d, fin: suivante ? veille(suivante.debut) : null,
      creeLe: new Date().toISOString(), creePar: acteur(), motif: String(opts.motif).trim(),
      valideLe: null, validePar: null,
      source: 'Saisie à l’écran (' + (opts.origine || 'cfg-fiscalite') + ')',
    });
    if (couverte) col.update(couverte.id, { fin: veille(d) });
    var res = col.insert(fiche);
    S.log('Nouvelle version de l’identité légale', 'CFG', 'IdentiteLegale', res.record.id,
      { version: couverte ? couverte.version : null }, { version: numero, debut: d, motif: fiche.motif });
    return { ok: true, mode: 'version', version: numero, fiche: res.record, precedente: couverte || null, enForceAujourdhui: d <= aujIso() };
  }
  function validerIdentite() {
    var r = controleValidation(); if (r) return r;
    var cibles = versionsIdentiteAValider();
    if (!cibles.length) return refusCfg('IDENTITE_ABSENTE', 'Aucune version de l’identité légale à valider.', 'Réinitialiser le jeu de démonstration (Paramètres système).');
    var quand = new Date().toISOString(), qui = acteur();
    marquerToutes('identiteLegale', cibles, { valideLe: quand, validePar: qui });
    S.log('Validation', 'CFG', 'IdentiteLegale', cibles.map(function (v) { return v.id; }).join(','), null, { valideLe: quand, validePar: qui });
    return { ok: true, valideLe: quand, validePar: qui, versions: cibles.map(function (v) { return v.version; }) };
  }

  /* --- Obligations fiscales et paramètres ORTB ------------------------------ */
  function obligationActive(ref) {
    var col = colObligations();
    var f = ref && ref.id ? col.get(ref.id) : null;
    if (!f && ref && ref.code) f = col.active().filter(function (x) { return x.code === ref.code && x.type !== 'parametres'; })[0] || null;
    return f && f.statut !== 'archive' ? f : null;
  }
  function ficheOrtb() {
    return colObligations().active().filter(function (x) { return x.type === 'parametres' && x.code === 'ORTB-PARAMETRES'; })[0] || null;
  }
  function controleValeursObligation(v) {
    if (!v.libelle || !String(v.libelle).trim()) return refusCfg('LIBELLE_REQUIS', 'L’intitulé de l’obligation est obligatoire.', 'Nommer l’obligation comme la déclaration la nomme.');
    if (['mensuelle', 'annuelle'].indexOf(v.periodicite) < 0) return refusCfg('PERIODICITE_INVALIDE', 'La périodicité est mensuelle ou annuelle.', 'Choisir l’une des deux.');
    var jour = Number(v.jour);
    if (!(jour >= 1 && jour <= 31 && jour === Math.floor(jour))) return refusCfg('JOUR_INVALIDE', 'Le jour de l’échéance est compris entre 1 et 31.', 'Saisir le jour du mois.');
    if (v.periodicite === 'annuelle') {
      var mois = Number(v.mois);
      if (v.mois === null || v.mois === undefined || v.mois === '' || !(mois >= 0 && mois <= 11)) return refusCfg('MOIS_INVALIDE', 'Une obligation annuelle porte son mois (janvier à décembre).', 'Choisir le mois de l’échéance.');
    }
    if (v.part !== null && v.part !== undefined && v.part !== '') {
      var part = Number(v.part);
      if (!(part >= 1 && part <= 100)) return refusCfg('PART_INVALIDE', 'La part est un pourcentage entre 1 et 100, ou vide.', 'Saisir la fraction réglée à cette échéance.');
    }
    return null;
  }
  function valeursObligation(v) {
    var annuelle = v.periodicite === 'annuelle';
    return {
      libelle: String(v.libelle).trim(), periodicite: v.periodicite, jour: Number(v.jour),
      mois: annuelle ? Number(v.mois) : null,
      part: v.part === null || v.part === undefined || v.part === '' ? null : Number(v.part),
      declaration: v.declaration ? String(v.declaration).trim() : null,
      note: v.note ? String(v.note).trim() : null,
    };
  }
  function copieHistorique(fiche, d, motif, retiree) {
    var copie = Object.assign({}, fiche);
    /* Rétablir À LA MÊME date d'effet ne peut pas écrire une version dont la fin précède le début (E-A3-04) : la version sortante
       n'a jamais été en force avant cette date, elle est marquée « remplacée le même jour » et sa fin reste vide. */
    var memeDate = !!(fiche.dateEffet && isoJour(fiche.dateEffet) === isoJour(d));
    ['id', 'statut', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', '_motifArchivage'].forEach(function (k) { delete copie[k]; });
    return colHistoriqueObligations().insert(Object.assign(copie, {
      obligationId: fiche.id, dateFin: memeDate ? null : veille(d), memeDate: memeDate, remplaceeLe: new Date().toISOString(), remplaceePar: acteur(),
      motifRemplacement: motif, retiree: !!retiree,
    })).record;
  }
  function echeancesImpactees(code, dateEffet) {
    var d = isoJour(dateEffet || aujIso());
    var rows = S.collection('echeancesFiscales').active().filter(function (e) {
      return e.code === code && e.exercice >= Number(d.slice(0, 4)) && (e.echeanceTheorique || e.echeance) >= d;
    });
    return { payees: rows.filter(function (e) { return e.paye; }).length, nonPayees: rows.filter(function (e) { return !e.paye; }).length, exercice: Number(d.slice(0, 4)) };
  }
  function annoncerRegeneration(code, reg) {
    try {
      notifier({ type: 'echeances_regenerees', poste: 'comptable', priorite: 'normale',
        libelle: 'Échéances régénérées : ' + code + ', ' + C.num(reg.creees),
        detail: C.num(reg.conservees) + ' payée(s) conservée(s), ' + C.num(reg.archivees) + ' non payée(s) régénérée(s) à partir du ' + C.dateFR(reg.dateEffet) + '.',
        reference: code });
    } catch (e) { /* la notification n'empêche pas le geste */ }
  }
  function modifierObligation(o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    var fiche = obligationActive(o);
    if (!fiche) return refusCfg('OBLIGATION_INCONNUE', 'Aucune obligation en vigueur ne porte cette référence.', 'Choisir une obligation du tableau.');
    if (!o.motif || !String(o.motif).trim()) return refusCfg('MOTIF_REQUIS', 'Le motif de la modification est obligatoire.', 'Dire ce qui change et pourquoi (texte de loi, note de la DGI…).');
    var d = isoJour(o.dateEffet || aujIso());
    r = controleDateEffet(d, fiche.dateEffet, fiche); if (r) return r;
    var fusion = Object.assign({}, fiche, o.valeurs || {});
    r = controleValeursObligation(fusion); if (r) return r;
    var apres = valeursObligation(fusion);
    copieHistorique(fiche, d, String(o.motif).trim(), false);
    var patch = Object.assign(apres, { dateEffet: d, modifieLe: new Date().toISOString(), modifiePar: acteur(), motif: String(o.motif).trim(), valideLe: null, validePar: null });
    var res = colObligations().update(fiche.id, patch);
    if (!res) return refusCfg('ECRITURE_REFUSEE', 'La fiche n’a pas pu être écrite.', 'Voir le journal.');
    var reg = S.regenererEcheances({ code: fiche.code, dateEffet: d, auteur: acteur() });
    annoncerRegeneration(fiche.code, reg);
    S.log('Modification d’obligation fiscale', 'CFG', 'ObligationsFiscales', fiche.id,
      { jour: fiche.jour, mois: fiche.mois, part: fiche.part }, { jour: apres.jour, mois: apres.mois, part: apres.part, dateEffet: d, motif: patch.motif });
    return { ok: true, fiche: colObligations().get(fiche.id), echeances: reg };
  }
  function creerObligation(o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    var v = o.valeurs || {};
    var code = String(v.code || '').trim().toUpperCase();
    if (!/^[A-Z0-9][A-Z0-9-]*$/.test(code)) return refusCfg('CODE_INVALIDE', 'Le code est en majuscules, chiffres et traits d’union (ex. : TPS-1).', 'Choisir un code court et stable : il identifie l’obligation au journal.');
    var existe = colObligations().all().concat(colHistoriqueObligations().all()).some(function (x) { return x.code === code; });
    if (existe) return refusCfg('CODE_EXISTANT', 'Le code ' + code + ' existe déjà.', 'Modifier l’obligation existante, ou choisir un autre code.');
    if (!o.motif || !String(o.motif).trim()) return refusCfg('MOTIF_REQUIS', 'Le motif de la création est obligatoire.', 'Citer le texte qui institue l’obligation.');
    var d = isoJour(o.dateEffet || aujIso());
    r = controleDateEffet(d); if (r) return r;
    r = controleValeursObligation(v); if (r) return r;
    var fiche = Object.assign({ type: 'obligation', code: code, famille: code.split('-')[0] }, valeursObligation(v), {
      source: 'Saisie à l’écran (cfg-comptabilite)', dateEffet: d,
      modifieLe: new Date().toISOString(), modifiePar: acteur(), motif: String(o.motif).trim(), valideLe: null, validePar: null,
    });
    var res = colObligations().insert(fiche);
    var reg = S.regenererEcheances({ code: code, dateEffet: d, auteur: acteur() });
    annoncerRegeneration(code, reg);
    S.log('Création d’obligation fiscale', 'CFG', 'ObligationsFiscales', res.record.id, null, { code: code, dateEffet: d, motif: fiche.motif });
    return { ok: true, fiche: res.record, echeances: reg };
  }
  function retirerObligation(o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    var app = global.SIGH.app;
    if (app && typeof app.droits === 'function' && !app.droits('CFG').annuler) {
      return refusCfg('RETRAIT_RESERVE', 'Le retrait d’une obligation appartient à la DAF ou à l’administrateur système. Profil : ' + libelleRole(roleCourant()) + '.',
        'Demander à la DAF de retirer l’obligation.');
    }
    var fiche = obligationActive(o);
    if (!fiche) return refusCfg('OBLIGATION_INCONNUE', 'Aucune obligation en vigueur ne porte cette référence.', 'Choisir une obligation du tableau.');
    if (!o.motif || !String(o.motif).trim()) return refusCfg('MOTIF_REQUIS', 'Le motif du retrait est obligatoire.', 'Citer le texte qui supprime l’obligation.');
    var d = isoJour(o.dateEffet || aujIso());
    r = controleDateEffet(d, fiche.dateEffet, fiche); if (r) return r;
    copieHistorique(fiche, d, String(o.motif).trim(), true);
    colObligations().archive(fiche.id, String(o.motif).trim());
    var reg = S.regenererEcheances({ code: fiche.code, dateEffet: d, auteur: acteur() });
    annoncerRegeneration(fiche.code, reg);
    S.log('Retrait d’obligation fiscale', 'CFG', 'ObligationsFiscales', fiche.id, { code: fiche.code }, { dateFin: veille(d), motif: String(o.motif).trim() });
    return { ok: true, fiche: colObligations().get(fiche.id), echeances: reg };
  }
  /** Les versions PROGRAMMÉES : fiches d'obligation dont la date d'effet n'est pas atteinte (la version en vigueur reste l'ancienne). */
  function versionsAVenir() {
    return colObligations().active().filter(function (f) { return f.type !== 'parametres' && f.dateEffet && isoJour(f.dateEffet) > aujIso(); });
  }
  function versionAVenirDe(code) { return versionsAVenir().filter(function (f) { return f.code === code; })[0] || null; }
  /** La version qui était en force juste avant la fiche : la copie d'historique fermée à la veille de sa date d'effet. */
  function versionPrecedente(fiche) {
    if (!fiche || !fiche.dateEffet) return null;
    var fin = veille(fiche.dateEffet);
    return colHistoriqueObligations().active().filter(function (h) {
      return h.type !== 'parametres' && h.obligationId === fiche.id && !h.retiree && h.dateFin === fin;
    }).sort(function (a, b) { return String(b.remplaceeLe || '').localeCompare(String(a.remplaceeLe || '')); })[0] || null;
  }
  /**
   * ANNULE UNE VERSION À VENIR (E-A3-03) : la fiche programmée est archivée (RG-14, motif obligatoire), la version qui la
   * précédait est ROUVERTE (nouvelle fiche active, copie fidèle, son entrée d'historique archivée), les échéances non payées
   * à partir de la date d'effet reviennent à l'ancienne version et les payées ne bougent pas. Une version déjà en force ne
   * s'annule pas : elle a produit des échéances, elle se corrige par une nouvelle version datée.
   */
  function annulerVersionAVenir(o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    var fiche = obligationActive(o);
    if (!fiche) return refusCfg('OBLIGATION_INCONNUE', 'Aucune obligation en vigueur ne porte cette référence.', 'Choisir une obligation du tableau.');
    if (!o.motif || !String(o.motif).trim()) return refusCfg('MOTIF_REQUIS', 'Le motif de l’annulation est obligatoire.', 'Dire pourquoi la version programmée est abandonnée (erreur de saisie, texte non confirmé…).');
    if (!fiche.dateEffet || isoJour(fiche.dateEffet) <= aujIso()) {
      return refusCfg('AUCUNE_VERSION_A_VENIR', 'La version de ' + fiche.code + ' est déjà en force' + (fiche.dateEffet ? ' depuis le ' + C.dateFR(isoJour(fiche.dateEffet)) : ' (version d’origine)') + ' : elle a produit des échéances, elle ne s’annule pas.',
        'La corriger par une nouvelle version datée (commande « Modifier »).');
    }
    var d = isoJour(fiche.dateEffet);
    var prec = versionPrecedente(fiche);
    if (!prec) return refusCfg('VERSION_PRECEDENTE_ABSENTE', 'La version qui précédait celle du ' + C.dateFR(d) + ' n’est pas à l’historique : la rouvrir est impossible.', 'Modifier l’obligation par une nouvelle version datée.');
    r = controleDateEffet(d); if (r) return r;
    var motif = String(o.motif).trim();
    var avant = { jour: fiche.jour, mois: fiche.mois, part: fiche.part, dateEffet: d };
    var copie = Object.assign({}, prec);
    ['id', 'statut', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe', '_motifArchivage',
      'obligationId', 'dateFin', 'remplaceeLe', 'remplaceePar', 'motifRemplacement', 'retiree', 'memeDate'].forEach(function (k) { delete copie[k]; });
    copie.rouverteLe = new Date().toISOString();
    copie.rouvertePar = acteur();
    copie.motifReouverture = 'Annulation de la version du ' + C.dateFR(d) + ' : ' + motif;
    colObligations().archive(fiche.id, 'Version à venir annulée : ' + motif);
    var rouverte = colObligations().insert(copie).record;
    colHistoriqueObligations().archive(prec.id, 'Version rouverte (annulation de la version du ' + C.dateFR(d) + ')');
    var reg = S.regenererEcheances({ code: fiche.code, dateEffet: d, auteur: acteur(), versionObligation: prec.dateEffet ? isoJour(prec.dateEffet) : null });
    annoncerRegeneration(fiche.code, reg);
    S.log('Annulation de version à venir d’obligation fiscale', 'CFG', 'ObligationsFiscales', fiche.id, avant,
      { rouverte: rouverte.id, jour: rouverte.jour, mois: rouverte.mois, part: rouverte.part, motif: motif });
    return { ok: true, fiche: rouverte, annulee: colObligations().get(fiche.id), echeances: reg };
  }

  /* --- Paramètres du calendrier fiscal (délais d'alerte, montant de la CCIB), versionnés par date ---------------------- */
  function colParametresFiscaux() { return S.collection('parametresFiscaux', { module: 'CFG', entite: 'paramètre fiscal', prefix: 'PFI' }); }
  /* Ce que chaque paramètre PORTE (noms de champs et règles de forme, jamais une valeur) : les valeurs vivent au magasin. */
  var CHAMPS_PARAMETRE_FISCAL = { 'DELAIS-ALERTE': ['delaiAPayer', 'delaiDeclaration'], 'CCIB-MONTANT': ['montantTotal'] };
  function versionsParametresFiscaux(code) {
    return colParametresFiscaux().active().filter(function (p) { return !code || p.code === code; })
      .sort(function (a, b) { return String(a.dateEffet || '').localeCompare(String(b.dateEffet || '')); });
  }
  function resumeParametre(p) {
    if (p.code === 'DELAIS-ALERTE') return 'à payer sous ' + p.delaiAPayer + ' jours, déclaration sous ' + p.delaiDeclaration + ' jours';
    return C.money(p.montantTotal, false);
  }
  function entier(v) { var n = Number(v); return v !== '' && v !== null && v !== undefined && isFinite(n) && n === Math.floor(n) ? n : null; }
  function controleValeursParametre(code, v) {
    if (code === 'DELAIS-ALERTE') {
      var a = entier(v.delaiAPayer), b = entier(v.delaiDeclaration);
      if (a === null || a < 1 || a > 365) return refusCfg('DELAI_INVALIDE', 'Le délai « à payer » est un nombre entier de jours, de 1 à 365.', 'Saisir le nombre de jours avant l’échéance où le paiement devient « à payer » (et alerté).');
      if (b === null || b < 1 || b > 365) return refusCfg('DELAI_INVALIDE', 'Le délai de déclaration est un nombre entier de jours, de 1 à 365.', 'Saisir le nombre de jours avant l’échéance où la déclaration est attendue.');
      if (b < a) return refusCfg('DELAI_INCOHERENT', 'Le délai de déclaration (' + b + ' j) ne peut pas être plus court que le délai « à payer » (' + a + ' j) : la déclaration précède le paiement.',
        'Porter le délai de déclaration à ' + a + ' jours au moins, ou réduire le délai « à payer ».');
    } else if (code === 'CCIB-MONTANT') {
      var m = entier(v.montantTotal);
      if (m === null || m < 1) return refusCfg('MONTANT_INVALIDE', 'Le montant de la CCIB est un nombre entier de francs strictement positif.', 'Saisir le montant annuel arrêté avec le cabinet comptable.');
    }
    return null;
  }
  /**
   * Modifie un paramètre du calendrier : UNE NOUVELLE FICHE à sa date d'effet, jamais une réécriture (la version d'avant reste
   * la version en vigueur jusqu'à la veille). Motif obligatoire, droits des obligations (poste mère, exercice ouvert).
   */
  function modifierParametreFiscal(o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    var code = String(o.code || '');
    if (!CHAMPS_PARAMETRE_FISCAL[code]) return refusCfg('PARAMETRE_INCONNU', 'Aucun paramètre du calendrier ne porte le code « ' + code + ' ».', 'Choisir un paramètre du tableau.');
    if (!o.motif || !String(o.motif).trim()) return refusCfg('MOTIF_REQUIS', 'Le motif de la modification est obligatoire.', 'Dire ce qui change et pourquoi (décision de la Direction, avis du cabinet…).');
    var d = isoJour(o.dateEffet || aujIso());
    var versions = versionsParametresFiscaux(code);
    var derniere = versions[versions.length - 1] || null;
    r = controleDateEffet(d, derniere && derniere.dateEffet,
      derniere && Object.assign({}, derniere, { libelleVersion: resumeParametre(derniere) })); if (r) return r;
    if (versions.some(function (p) { return p.dateEffet && isoJour(p.dateEffet) === d; })) {
      return refusCfg('VERSION_EXISTANTE', 'Une version de ' + code + ' prend déjà effet le ' + C.dateFR(d) + '.', 'Annuler cette version à venir si elle est fausse, ou choisir une autre date d’effet.');
    }
    var base = D.parametreFiscalALaDate(code, C.addDays(d, 36500)) || derniere || {};
    var vals = {};
    CHAMPS_PARAMETRE_FISCAL[code].forEach(function (k) { vals[k] = (o.valeurs && o.valeurs[k] !== undefined) ? o.valeurs[k] : base[k]; });
    r = controleValeursParametre(code, vals); if (r) return r;
    var fiche = { type: 'parametre', code: code, libelle: base.libelle || code, tranches: base.tranches,
      source: 'Saisie à l’écran (cfg-comptabilite)', aValider: false, dateEffet: d,
      modifieLe: new Date().toISOString(), modifiePar: acteur(), motif: String(o.motif).trim() };
    CHAMPS_PARAMETRE_FISCAL[code].forEach(function (k) { fiche[k] = entier(vals[k]); });
    var res = colParametresFiscaux().insert(fiche);
    S.log('Modification de paramètre du calendrier fiscal', 'CFG', 'ParametresFiscaux', res.record.id,
      derniere ? { resume: resumeParametre(derniere), dateEffet: derniere.dateEffet || null } : null,
      { resume: resumeParametre(res.record), dateEffet: d, motif: fiche.motif });
    return { ok: true, fiche: res.record, precedente: derniere, enForceAujourdhui: d <= aujIso() };
  }
  /** Annule une version à venir d'un paramètre : elle est archivée (RG-14, motif obligatoire) ; la version d'avant reste en vigueur. */
  function annulerParametreFiscal(o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    var f = o.id ? colParametresFiscaux().get(o.id) : null;
    if (!f || f.statut === 'archive') return refusCfg('PARAMETRE_INCONNU', 'Aucune version de paramètre ne porte cette référence.', 'Choisir une version du tableau.');
    if (!o.motif || !String(o.motif).trim()) return refusCfg('MOTIF_REQUIS', 'Le motif de l’annulation est obligatoire.', 'Dire pourquoi la version programmée est abandonnée.');
    if (!f.dateEffet || isoJour(f.dateEffet) <= aujIso()) {
      return refusCfg('AUCUNE_VERSION_A_VENIR', 'La version de ' + f.code + ' est déjà en force' + (f.dateEffet ? ' depuis le ' + C.dateFR(isoJour(f.dateEffet)) : ' (version d’origine)') + ' : elle ne s’annule pas.',
        'La corriger par une nouvelle version datée (commande « Modifier »).');
    }
    colParametresFiscaux().archive(f.id, 'Version à venir annulée : ' + String(o.motif).trim());
    S.log('Annulation de version à venir de paramètre du calendrier fiscal', 'CFG', 'ParametresFiscaux', f.id,
      { resume: resumeParametre(f), dateEffet: f.dateEffet }, { motif: String(o.motif).trim() });
    return { ok: true, annulee: f };
  }
  /* LA GARDE DU MAGASIN : une version de paramètre ne se réécrit pas (valeurs ni date d'effet) ; seule son archive est admise. */
  S.garder('parametresFiscaux', function (op, rec) {
    if (op !== 'modifier') return null;
    var avant = rec && rec.id ? colParametresFiscaux().get(rec.id) : null;
    if (!avant) return null;
    var change = String(avant.dateEffet || '') !== String(rec.dateEffet || '');
    CHAMPS_PARAMETRE_FISCAL[avant.code] && CHAMPS_PARAMETRE_FISCAL[avant.code].forEach(function (k) { if (String(avant[k]) !== String(rec[k])) change = true; });
    return change ? 'PARAMETRE_VERSION_FIGEE : une version de paramètre ne se réécrit pas. Ajouter une nouvelle version à une date d’effet postérieure.' : null;
  });

  function espaceMilliers(n) { return String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ' '); }
  function modifierOrtb(o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    var fiche = ficheOrtb();
    if (!fiche) return refusCfg('ORTB_ABSENT', 'La fiche des paramètres ORTB est absente du magasin.', 'Réinitialiser le jeu de démonstration (Paramètres système).');
    if (!o.motif || !String(o.motif).trim()) return refusCfg('MOTIF_REQUIS', 'Le motif de la modification est obligatoire.', 'Citer la décision ou le texte qui fixe le nouveau seuil.');
    var d = isoJour(o.dateEffet || aujIso());
    r = controleDateEffet(d, fiche.dateEffet); if (r) return r;
    var v = o.valeurs || {};
    var seuil = v.seuilTele === undefined ? fiche.seuilTele : Number(v.seuilTele);
    if (!(seuil >= 0)) return refusCfg('SEUIL_INVALIDE', 'Le seuil de la redevance Télé est un montant positif ou nul.', 'Saisir le salaire brut au-delà duquel la télé est due.');
    var redevances = (fiche.redevances || []).map(function (x) { return Object.assign({}, x); });
    var invalide = null;
    ['radio', 'tele'].forEach(function (id) {
      var saisie = v[id] || {};
      var red = redevances.filter(function (x) { return x.id === id; })[0];
      if (!red) return;
      if (saisie.montant !== undefined && saisie.montant !== null && saisie.montant !== '') red.montant = Number(saisie.montant);
      if (saisie.mois !== undefined && saisie.mois !== null && saisie.mois !== '') { red.mois = Number(saisie.mois); red.moisLabel = C.MOIS[red.mois]; }
      if (!(red.montant >= 0)) invalide = refusCfg('MONTANT_INVALIDE', 'Le montant de la redevance ' + red.categorie + ' est un montant positif ou nul.', 'Saisir le montant annuel par agent.');
      else if (!(red.mois >= 0 && red.mois <= 11)) invalide = refusCfg('MOIS_INVALIDE', 'Le mois de prélèvement de la redevance ' + red.categorie + ' va de janvier à décembre.', 'Choisir le mois du bulletin qui porte la retenue.');
      if (id === 'tele') { red.seuilMin = seuil + 1; red.assiette = 'Salaire brut supérieur à ' + espaceMilliers(seuil) + ' FCFA'; }
    });
    if (invalide) return invalide;
    var cumul = redevances.reduce(function (n, x) { return n + (x.montant || 0); }, 0);
    copieHistorique(fiche, d, String(o.motif).trim(), false);
    var res = colObligations().update(fiche.id, {
      seuilTele: seuil, redevances: redevances, cumulMaximum: cumul, dateEffet: d,
      modifieLe: new Date().toISOString(), modifiePar: acteur(), motif: String(o.motif).trim(), valideLe: null, validePar: null,
    });
    if (!res) return refusCfg('ECRITURE_REFUSEE', 'La fiche n’a pas pu être écrite.', 'Voir le journal.');
    S.log('Modification des paramètres ORTB', 'CFG', 'ObligationsFiscales', fiche.id,
      { seuilTele: fiche.seuilTele, cumul: fiche.cumulMaximum }, { seuilTele: seuil, cumul: cumul, dateEffet: d, motif: String(o.motif).trim() });
    return { ok: true, fiche: colObligations().get(fiche.id) };
  }
  function validerObligations() {
    var r = controleValidation(); if (r) return r;
    var cibles = colObligations().active();
    if (!cibles.length) return refusCfg('OBLIGATIONS_ABSENTES', 'Aucune obligation à valider.', 'Réinitialiser le jeu de démonstration (Paramètres système).');
    var quand = new Date().toISOString(), qui = acteur();
    marquerToutes('obligationsFiscales', cibles, { valideLe: quand, validePar: qui });
    S.log('Validation', 'CFG', 'ObligationsFiscales', 'toutes', null, { valideLe: quand, validePar: qui, nombre: cibles.length });
    return { ok: true, valideLe: quand, validePar: qui, nombre: cibles.length };
  }
  function versionsObligation(code) {
    return colHistoriqueObligations().active().filter(function (h) { return h.code === code; })
      .sort(function (a, b) { return String(a.dateEffet || '').localeCompare(String(b.dateEffet || '')); });
  }

  /* --- L'état affiché, une seule fonction ------------------------------------ */
  function etatConfigurationFiscale(nom) {
    var fiches, toutes;
    if (nom === 'identite') { fiches = versionsIdentiteAValider(); toutes = colIdentite().all(); }
    else { fiches = colObligations().active(); toutes = colObligations().all().concat(colHistoriqueObligations().all()); }
    var validees = fiches.filter(function (f) { return f.valideLe; })
      .sort(function (a, b) { return String(b.valideLe).localeCompare(String(a.valideLe)); });
    var nonValidees = fiches.filter(function (f) { return !f.valideLe; });
    var anterieure = toutes.filter(function (f) { return f.valideLe; })
      .sort(function (a, b) { return String(b.valideLe).localeCompare(String(a.valideLe)); })[0] || null;
    var dates = nonValidees.map(function (f) { return f._modifieLe || f.modifieLe || f.creeLe || f._creeLe || null; }).filter(Boolean).sort();
    var derniereModif = nonValidees.filter(function (f) { return (f._modifieLe || f.modifieLe || f.creeLe || f._creeLe) === dates[dates.length - 1]; })[0] || nonValidees[0] || null;
    var etat = fiches.length && !nonValidees.length ? 'valide' : (anterieure ? 'modifie_depuis' : 'a_valider');
    return {
      etat: etat, nombre: fiches.length, nonValidees: nonValidees.length,
      valideLe: etat === 'valide' ? validees[0].valideLe : null,
      validePar: etat === 'valide' ? validees[0].validePar : null,
      modifieLe: dates.length ? dates[dates.length - 1] : null,
      modifiePar: derniereModif ? (derniereModif._modifiePar || derniereModif.modifiePar || derniereModif.creePar || derniereModif._creePar || null) : null,
      validationAnterieure: anterieure ? { valideLe: anterieure.valideLe, validePar: anterieure.validePar } : null,
    };
  }

  /* ==========================================================================
   * MOTEUR DE VALIDATION COMMUN DES RÉFÉRENTIELS (Direction, 07/11/2026)
   * --------------------------------------------------------------------------
   * Tout ce qui porte un marquage « à valider » (modèle d'enquête, borne du
   * laboratoire, pathologie, catalogue d'imagerie, check-liste du bloc, tarif
   * d'attente, valorisation, objectif de pilotage, répartition des charges,
   * modèle de badge, jeu d'import, modèle de message, barème ITS) se valide par
   * UN geste, le même partout : `validerReferentiel`. Même doctrine que la
   * configuration fiscale : refus NOMMÉ (code, motif, geste), écriture de
   * `valideLe`, `validePar`, `valideRole`, UNE ligne de journal (RG-12), et
   * JAMAIS de validation en masse : un appel valide une fiche.
   *
   * LE COMPTE EST LU, JAMAIS ÉCRIT : `referentielsAValider()` relit les
   * marquages dans le magasin à chaque appel. Une validation ne modifie AUCUN
   * autre champ que le marquage et ses trois traces ; modifier un artefact déjà
   * validé le remet « à valider » (`remettreAValider`, appelé par l'écran qui
   * modifie), comme la configuration fiscale.
   *
   * Deux formes d'artefact : (1) une FICHE du magasin qui porte son marquage
   * (`aValider`, `tarifProvisoire`) : la validation l'écrit sur la fiche ;
   * (2) une CONSTANTE du code (check-listes du bloc, répartition fixe/variable,
   * barème ITS, jeu d'import) qui ne peut pas porter de marquage : sa
   * validation vit dans une fiche de la collection `validationsReferentiels`,
   * une par cible (`VRF-<cible>`). Un artefact de forme 2 est « à valider »
   * tant qu'aucune fiche porteuse d'un `valideLe` ne le couvre.
   * ======================================================================== */
  var VUE_COMPLETE_VALIDATIONS = ['direction', 'da', 'admin'];
  var FAMILLES_A_VALIDER = [
    { id: 'enquetes', libelle: 'Modèles d’enquête', module: 'M13', collections: ['enquetes'], champs: ['aValider'],
      roles: ['direction', 'da', 'admin'], ecran: 'adm-enquetes' },
    { id: 'labo_variables', libelle: 'Variables et unités du laboratoire (bornes suppléées)', module: 'M5',
      collections: ['variablesLabo', 'unitesLabo'], champs: ['aValider'],
      roles: ['laborantin'], ecran: 'm5-valeurs-reference', champsChiffres: ['min', 'max'] },
    { id: 'pathologies', libelle: 'Pathologies (tableau de morbidité)', module: 'M2', collections: ['pathologies'], champs: ['aValider'],
      roles: ['dm', 'medecin'], ecran: 'm2-pathologies' },
    { id: 'imagerie', libelle: 'Catalogue de l’imagerie (examens et variables)', module: 'CFG',
      collections: ['examensImagerie', 'variablesImagerie'], champs: ['aValider'],
      roles: ['echographiste', 'dm'], ecran: 'cfg-imagerie-catalogue' },
    { id: 'checklists_bloc', libelle: 'Check-listes du bloc, échelles ASA et Mallampati', module: 'M3', mode: 'fiche',
      cibles: [{ id: 'checklist-bloc', libelle: 'Check-listes d’entrée et de sortie du bloc' }],
      roles: ['chirurgien', 'anesthesiste'], ecran: 'm3-bloc-checklist' },
    { id: 'actes', libelle: 'Tarifs des actes (valeurs d’attente)', module: 'CFG', collections: ['actes'], champs: ['tarifProvisoire'],
      roles: ['direction', 'da', 'admin'], ecran: 'cfg-tarifs', champsChiffres: ['prix'] },
    { id: 'analyses', libelle: 'Tarifs des analyses', module: 'CFG', collections: ['analyses'], champs: ['tarifProvisoire', 'aValider'],
      roles: ['direction', 'da', 'admin'], ecran: 'cfg-tarifs', champsChiffres: ['prix'] },
    /* Les changements de prix en attente de Oui ou Non (PRD-TARIFS 5.3) : un compte LU sur `versionsTarif`, jamais écrit ; la décision se prend à « Tarifs et prix »,
       onglet Alertes, avec la comparaison. Mêmes profils que les familles des actes et des analyses. */
    { id: 'prix', libelle: 'Changements de prix en attente (Oui ou Non)', module: 'CFG', mode: 'prix', collections: ['versionsTarif'], champs: ['statut'],
      roles: ROLES_VALIDATION_TARIFS.slice(), ecran: 'cfg-tarifs' },
    { id: 'valorisation_sage', libelle: 'Valorisation des références de l’inventaire initial', module: 'M6', collections: ['valorisationsSage'], champs: ['aValider'],
      roles: ['direction', 'da', 'admin'], ecran: 'm6-produits', champsChiffres: ['prixRevient'] },
    { id: 'objectifs_pilotage', libelle: 'Objectifs de pilotage', module: 'M12', collections: ['objectifsPilotage'], champs: ['aValider'],
      roles: ['direction', 'da', 'admin'], ecran: 'm12-tableau-decisionnel', champsChiffres: ['cible'] },
    { id: 'repartition_charges', libelle: 'Répartition fixe et variable des charges', module: 'M12', mode: 'fiche',
      cibles: [{ id: 'repartition-fixe-variable', libelle: 'Répartition proposée des comptes de charge' }],
      roles: ['comptable', 'direction', 'da', 'admin'], ecran: 'm12-seuil-rentabilite' },
    { id: 'modeles_badge', libelle: 'Modèles de badge', module: 'M10', collections: ['modelesBadge'], champs: ['aValider'],
      roles: ['direction', 'da', 'admin'], ecran: 'm10-badges-modeles' },
    { id: 'jeux_import', libelle: 'Jeux d’import en proposition', module: 'IMP', mode: 'fiche',
      cibles: [{ id: 'imp-analyses', libelle: 'Importation du catalogue des analyses' }],
      roles: ['direction', 'da', 'admin'], ecran: 'imp-analyses' },
    { id: 'modeles_messages', libelle: 'Modèles de messages', module: 'CFG', collections: ['modelesMessage'], champs: ['aValider'],
      roles: ['direction', 'da', 'admin'], ecran: 'cfg-notifications' },
    { id: 'bareme_aib', libelle: 'Barème de l’AIB (taux par situation de l’acheteur)', module: 'CFG', collections: ['baremeAib', 'reglagesAib'], champs: ['aValider'],
      roles: ['direction', 'da', 'admin', 'comptable'], ecran: 'cfg-bareme-aib', champsChiffres: ['taux'] },
    { id: 'bareme_its', libelle: 'Barème de l’ITS', module: 'M11', mode: 'fiche',
      cibles: [{ id: 'bareme-its', libelle: 'Barème de l’impôt sur les traitements et salaires' }],
      roles: ['direction', 'da', 'admin'], ecran: 'cfg-comptabilite' },
  ];
  FAMILLES_A_VALIDER.forEach(function (f) { f.mode = f.mode || 'fiche-marquee'; });

  function colValidationsReferentiels() {
    return S.collection('validationsReferentiels', { module: 'CFG', entite: 'validation de référentiel', prefix: 'VRF' });
  }
  function familleAValider(id) {
    return FAMILLES_A_VALIDER.filter(function (f) { return f.id === id; })[0] || null;
  }
  function profilsFamille(f) { return f.roles.map(libelleRole).join(', '); }
  function ficheDeValidation(cible) {
    return colValidationsReferentiels().all().filter(function (x) { return x.id === 'VRF-' + cible && x.statut !== 'archive'; })[0] || null;
  }
  /* Les artefacts d'une famille, chacun avec son état LU : { id, libelle, enAttente, valideLe, rec, col }. */
  function artefactsDe(f) {
    var brut = S.raw();
    if (f.mode === 'fiche') {
      return f.cibles.map(function (c) {
        var fiche = ficheDeValidation(c.id);
        return { id: c.id, libelle: c.libelle, enAttente: !(fiche && fiche.valideLe), valideLe: fiche ? fiche.valideLe : null, rec: fiche, col: null };
      });
    }
    if (f.mode === 'prix') {
      return (brut.versionsTarif || []).filter(function (v) { return v && v.statut === 'propose'; }).map(function (v) {
        return { id: v.id, col: 'versionsTarif', rec: v, valideLe: null, enAttente: true,
          libelle: v.code + ' : ' + (v.etatNonAssure === 'manquant' || v.prixNonAssure == null ? 'prix à valider' : C.money(v.prixNonAssure, false)) };
      });
    }
    var out = [];
    f.collections.forEach(function (nom) {
      (brut[nom] || []).forEach(function (rec) {
        if (!rec || rec.statut === 'archive') return;
        out.push({
          id: rec.id, col: nom, rec: rec, valideLe: rec.valideLe || null,
          libelle: rec.libelle || rec.label || rec.designation || rec.nom || rec.reference || rec.id,
          enAttente: f.champs.some(function (c) { return rec[c] === true; }),
        });
      });
    });
    return out;
  }
  /** Les familles avec leur compte RÉEL. `{ role }` ne garde que les familles que ce profil valide. */
  function referentielsAValider(opts) {
    var role = opts && opts.role;
    var brut = S.raw();
    return FAMILLES_A_VALIDER.filter(function (f) { return !role || f.roles.indexOf(role) >= 0; }).map(function (f) {
      var arts = artefactsDe(f);
      var nonAmorce = f.mode !== 'fiche' && !arts.length
        && f.collections.every(function (nom) { return !(brut[nom] || []).length; }) && S.amorcable(f.collections[0]);
      var attente = arts.filter(function (a) { return a.enAttente; });
      return {
        famille: f.id, libelle: f.libelle, module: f.module, mode: f.mode,
        collections: f.collections || ['validationsReferentiels'], champs: f.champs || ['valideLe'],
        roles: f.roles.slice(), profil: profilsFamille(f), ecran: f.ecran,
        enAttente: nonAmorce ? null : attente.length,
        total: nonAmorce ? null : arts.length,
        nonAmorce: nonAmorce,
        ids: attente.map(function (a) { return a.id; }),
      };
    });
  }
  function refusValidation(code, motif, geste) { return refusCfg(code, motif, geste); }
  function validerReferentiel(familleId, id, opts) {
    opts = opts || {};
    var f = familleAValider(familleId);
    if (!f) return refusValidation('INTROUVABLE', 'Famille de référentiel inconnue : ' + familleId + '.', 'Choisir une famille du registre des validations.');
    if (f.mode === 'prix') return refusValidation('GESTE_A_SON_POSTE', 'Un changement de prix se décide à « Tarifs et prix », onglet Alertes : Oui ou Non, la comparaison sous les yeux.', 'Ouvrir l’écran « Tarifs et prix ».');
    var role = opts.role || roleCourant();
    var gardeMere = refusFileulValidation(f);
    if (gardeMere) return gardeMere;
    if (f.roles.indexOf(role) < 0) {
      return refusValidation('VALIDATION_RESERVEE', 'La validation de « ' + f.libelle + ' » est réservée à : ' + profilsFamille(f) + '. Profil : ' + libelleRole(role) + '.',
        'Demander à ' + libelleRole(f.roles[0]) + ' de valider depuis son poste.');
    }
    var cible = artefactsDe(f).filter(function (a) { return a.id === id; })[0];
    if (!cible) return refusValidation('INTROUVABLE', 'Aucun élément « ' + id + ' » dans « ' + f.libelle + ' ».', 'Ouvrir l’écran de la famille et choisir l’élément à valider.');
    if (!cible.enAttente) {
      return refusValidation('DEJA_VALIDE', cible.valideLe
        ? '« ' + cible.libelle + ' » est déjà validé (' + C.dateFR(String(cible.valideLe).slice(0, 10)) + ').'
        : '« ' + cible.libelle + ' » ne porte aucun marquage à valider.',
      'Rien à faire : toute modification ultérieure le remettra à valider.');
    }
    /* Un tarif ABSENT ne se valide pas : le tiret n'est ni un zéro ni un tarif arrêté. */
    if ((f.id === 'actes' || f.id === 'analyses') && cible.rec && cible.rec.prix == null) {
      return refusValidation('TARIF_ABSENT', '« ' + cible.libelle + ' » n\u2019a aucun tarif : il n\u2019y a rien à valider.', 'Saisir le tarif d\u2019attente, puis le valider.');
    }
    var quand = new Date().toISOString(), qui = acteur(), libRole = libelleRole(role);
    var avant;
    if (f.mode === 'fiche') {
      var col = colValidationsReferentiels();
      var fiche = ficheDeValidation(id);
      avant = { valideLe: fiche ? fiche.valideLe : null };
      /* UNE fiche VRF-<cible> par cible, jamais deux : une fiche ARCHIVÉE du même identifiant est réactivée, pas doublée (lot L1, V4). */
      var archivee = !fiche ? col.all().filter(function (x) { return x.id === 'VRF-' + id; })[0] : null;
      if (fiche) Object.assign(fiche, { valideLe: quand, validePar: qui, valideRole: libRole });
      else if (archivee) {
        Object.assign(archivee, { statut: 'actif', famille: f.id, cible: id, libelle: cible.libelle, valideLe: quand, validePar: qui, valideRole: libRole });
        delete archivee._archivePar; delete archivee._archiveLe; delete archivee._motifArchivage;
      } else col.all().push({ id: 'VRF-' + id, statut: 'actif', famille: f.id, cible: id, libelle: cible.libelle, valideLe: quand, validePar: qui, valideRole: libRole });
      S.save(); S.emit('validationsReferentiels');
    } else {
      var rec = cible.rec;
      avant = {};
      f.champs.forEach(function (c) { if (rec[c] === true) { avant[c] = true; rec[c] = false; } });
      rec.valideLe = quand; rec.validePar = qui; rec.valideRole = libRole;
      /* Plus aucune mention « à valider » sur un élément validé : le texte d'origine qui la portait est épuré. */
      var epure = epurerMentions(rec);
      Object.keys(epure).forEach(function (k) { rec[k] = epure[k]; });
      if (opts.motif) rec.motifCorrection = String(opts.motif).trim();
      /* Valider un tarif d'attente ARRÊTE aussi la version du référentiel de prix qui le portait (E2366) : le marquage « provisoire » ne reste pas d'un côté. */
      if (f.id === 'actes' || f.id === 'analyses') {
        var hv = D.TARIFS.lire(), pv = hv && (f.id === 'actes' ? hv.parActe[rec.code] : hv.parAnalyse[rec.code]);
        if (pv) leverProvisoireDe(pv.code);
      }
      S.save(); S.emit(cible.col);
    }
    S.log('Validation', f.module, f.libelle, id, avant, { valideLe: quand, validePar: qui, valideRole: libRole });
    return { ok: true, famille: f.id, id: id, valideLe: quand, validePar: qui, valideRole: libRole };
  }
  /* Appelé par l'écran qui MODIFIE un artefact validé : le marquage revient, les traces de validation tombent. */
  function remettreAValider(familleId, id) {
    var f = familleAValider(familleId);
    if (!f) return refusValidation('INTROUVABLE', 'Famille de référentiel inconnue : ' + familleId + '.', 'Choisir une famille du registre des validations.');
    var cible = artefactsDe(f).filter(function (a) { return a.id === id; })[0];
    if (!cible) return refusValidation('INTROUVABLE', 'Aucun élément « ' + id + ' » dans « ' + f.libelle + ' ».', 'Ouvrir l’écran de la famille.');
    if (cible.enAttente) return { ok: true, remis: false, famille: f.id, id: id };
    var avant = { valideLe: cible.valideLe };
    if (f.mode === 'fiche') {
      Object.assign(cible.rec, { valideLe: null, validePar: null, valideRole: null });
      S.save(); S.emit('validationsReferentiels');
    } else {
      cible.rec[f.champs[0]] = true;
      Object.assign(cible.rec, { valideLe: null, validePar: null, valideRole: null });
      S.save(); S.emit(cible.col);
    }
    S.log('Remise à valider', f.module, f.libelle, id, avant, { motif: 'modifié depuis la validation' });
    return { ok: true, remis: true, famille: f.id, id: id };
  }
  /* ==========================================================================
   * ENREGISTRER VALIDE, POUR LE PROFIL DE LA FAMILLE (Direction, 09/11/2026, lot L1)
   * --------------------------------------------------------------------------
   * Q1 : « plus de statut à valider en enregistrant » vaut pour les SEULS profils de la famille (la Direction ne signe pas à la place du
   * professionnel). Q2 (b) : un profil qui modifie sans être de la famille enregistre, et l'élément repasse « à valider ». Q3 : un élément
   * semé reste « à valider » jusqu'à la première relecture ou validation par la famille. Q4 : motif OBLIGATOIRE quand le validateur modifie une
   * valeur CHIFFRÉE (bornes, tarifs, barème), pas pour un libellé. Q5 : un élément créé par la famille naît validé ; hors famille, « à valider ».
   *
   * Trois fonctions, comme au poste : `controlerEnregistrement` REFUSE (code nommé) avant toute écriture ; `marquageEnregistrement` RENDS le patch
   * à fusionner dans l'écriture de l'écran et UNE ligne de journal (RG-12, avant/après, état inclus) ; `suivreEnregistrement` sert l'artefact
   * tenu ailleurs que dans la fiche écrite (constante du code, valorisation lue au produit). `remettreAValider` n'est plus appelé par un
   * enregistrement de la famille.
   * ======================================================================== */
  var SUFFIXE_A_VALIDER = /\s*(?:[—–:-]\s*)?(?:(?:tarif|proposition|modèle|valeur)\s+)?à\s+(?:valider|arrêter|confirmer)\b[^.;]*$/i;
  var CHAMPS_MENTION = ['source', 'motifPrix', 'observation'];
  /** Les textes d'origine d'une fiche qui disent « à valider » : rendus épurés (clés à réécrire), jamais touchés ailleurs. */
  function epurerMentions(rec) {
    var out = {};
    CHAMPS_MENTION.forEach(function (k) {
      if (typeof rec[k] === 'string' && SUFFIXE_A_VALIDER.test(rec[k])) out[k] = rec[k].replace(SUFFIXE_A_VALIDER, '').replace(/[\s:;,—–-]+$/, '');
    });
    return out;
  }
  function voyageDeLaMere(f) {
    if (f.mode === 'fiche') return true;
    var ess = S.COLLECTIONS_ESSENTIELLES || [];
    return (f.collections || []).some(function (c) { return ess.indexOf(c) >= 0; });
  }
  /** Sur un fileul, la configuration est tenue par la mère : le geste est refusé en le nommant (EF-VAL-07, même code qu'au poste). */
  function refusFileulValidation(f) {
    if (posteFileul() && voyageDeLaMere(f)) {
      return refusValidation('CONFIGURATION_DE_LA_MERE', 'Réglé sur la mère : cette configuration se modifie sur le poste principal, puis elle est reprise ici.',
        'Valider depuis le poste principal : la validation est reprise ici ensuite.');
    }
    return null;
  }
  function nombreOuNul(x) { return x == null || x === '' ? null : Number(x); }
  function texteOuNul(x) { return x == null || x === '' ? null : x; }
  /** Les champs CHIFFRÉS de la famille que cette écriture déplace (rien pour une création : il n'y a rien à corriger). */
  function chiffresModifies(familleId, avant, valeurs) {
    var f = familleAValider(familleId);
    if (!f || !avant) return [];
    return (f.champsChiffres || []).filter(function (c) {
      return valeurs && (c in valeurs) && nombreOuNul(valeurs[c]) !== nombreOuNul(avant[c]);
    });
  }
  function champsModifies(avant, valeurs) {
    return Object.keys(valeurs || {}).filter(function (k) {
      if (k.charAt(0) === '_' || k === 'id') return false;
      var a = avant ? avant[k] : undefined, b = valeurs[k];
      if ((a && typeof a === 'object') || (b && typeof b === 'object')) return JSON.stringify(a == null ? null : a) !== JSON.stringify(b == null ? null : b);
      return texteOuNul(a) !== texteOuNul(b);
    });
  }
  function controlerEnregistrement(familleId, o) {
    o = o || {};
    var f = familleAValider(familleId);
    if (!f) return refusValidation('INTROUVABLE', 'Famille de référentiel inconnue : ' + familleId + '.', 'Choisir une famille du registre des validations.');
    var gardeMere = refusFileulValidation(f);
    if (gardeMere) return gardeMere;
    var role = o.role || roleCourant();
    if (f.roles.indexOf(role) >= 0 && o.chiffres && o.chiffres.length && !String(o.motif || '').trim()) {
      return refusValidation('MOTIF_OBLIGATOIRE', 'La valeur chiffrée « ' + o.chiffres.join(', ') + ' » de « ' + f.libelle + ' » change : le motif de la correction est obligatoire.',
        'Saisir le motif de la correction, puis enregistrer.');
    }
    return null;
  }
  /** Le patch et la ligne de journal d'un enregistrement. `o` : { avant (fiche ou null), valeurs, motif, role? }. */
  function marquageEnregistrement(familleId, o) {
    o = o || {};
    var f = familleAValider(familleId);
    if (!f || f.mode === 'fiche') return refusValidation('INTROUVABLE', 'Famille à fiche marquée inconnue : ' + familleId + '.', 'Choisir une famille du registre des validations.');
    var role = o.role || roleCourant();
    var validateur = f.roles.indexOf(role) >= 0;
    var avant = o.avant || null, valeurs = o.valeurs || {};
    var enAttenteAvant = avant ? f.champs.some(function (c) { return avant[c] === true; }) : null;
    var changes = champsModifies(avant, valeurs);
    var chiffres = chiffresModifies(familleId, avant, valeurs);
    /* Hors famille, ENREGISTRER remet « à valider » (Q2 b), sauf si l'écran dit que la fiche n'a pas changé (`modifie: false`, ex. `siChange`). */
    var modifie = o.modifie == null ? true : !!o.modifie;
    var maintenant = new Date().toISOString(), qui = acteur(), libRole = libelleRole(role);
    var fusion = Object.assign({}, avant || {}, valeurs);
    var patch = {}, action = avant ? 'Modification' : 'Création', valide = false, nonValide = null;
    var rouvrir = function () {
      patch[f.champs[0]] = true;
      patch.valideLe = null; patch.validePar = null; patch.valideRole = null;
    };
    if (validateur) {
      if ((f.id === 'actes' || f.id === 'analyses') && fusion.prix == null) { rouvrir(); nonValide = 'TARIF_ABSENT'; }
      else {
        f.champs.forEach(function (c) { patch[c] = false; });
        patch.valideLe = maintenant; patch.validePar = qui; patch.valideRole = libRole;
        if (chiffres.length && o.motif) patch.motifCorrection = String(o.motif).trim();
        var epure = epurerMentions(fusion);
        Object.keys(epure).forEach(function (k) { patch[k] = epure[k]; });
        valide = true;
        if (avant && enAttenteAvant) action = 'Validation';
      }
    } else if (!avant) { rouvrir(); }
    else if (modifie) { rouvrir(); if (!enAttenteAvant) action = 'Remise à valider'; }
    var libEtat = function (v) { return v ? 'à valider' : 'validé'; };
    var etatApres = valide ? 'validé' : ((!validateur && avant && !modifie) ? libEtat(enAttenteAvant) : 'à valider');
    var jAvant = { etat: avant ? libEtat(enAttenteAvant) : null };
    var jApres = { etat: etatApres };
    /* Le MOTIF d'abord : l'extrait du journal est plafonné à 100 caractères et c'est lui, avec l'état, qui doit toujours s'y lire. */
    if (valide) { if (patch.motifCorrection) jApres.motif = patch.motifCorrection; jApres.valideRole = libRole; jApres.valideLe = maintenant; }
    changes.filter(function (k) { return k !== 'source'; }).slice(0, 4).forEach(function (k) {
      if (avant) jAvant[k] = avant[k] == null ? null : avant[k];
      jApres[k] = valeurs[k] == null ? null : valeurs[k];
    });
    return { ok: true, famille: f.id, validateur: validateur, valide: valide, nonValide: nonValide, patch: patch, chiffres: chiffres,
      journal: { action: action, module: f.module, entite: f.libelle, avant: avant ? jAvant : null, apres: jApres } };
  }
  /** Pour l'artefact tenu AILLEURS que dans la fiche écrite (constante du code, valorisation lue au produit) : après l'écriture de l'écran. */
  function suivreEnregistrement(familleId, cibleId, o) {
    o = o || {};
    var f = familleAValider(familleId);
    if (!f) return refusValidation('INTROUVABLE', 'Famille de référentiel inconnue : ' + familleId + '.', 'Choisir une famille du registre des validations.');
    var gardeMere = refusFileulValidation(f);
    if (gardeMere) return gardeMere;
    var role = o.role || roleCourant();
    if (f.roles.indexOf(role) >= 0) {
      var e = etatValidation(familleId, cibleId);
      if (e && e.enAttente) return validerReferentiel(familleId, cibleId, { role: role, motif: o.motif });
      return { ok: true, famille: f.id, id: cibleId, valide: false, rien: true };
    }
    if (o.modifie) return remettreAValider(familleId, cibleId);
    return { ok: true, famille: f.id, id: cibleId, rien: true };
  }
  /** L'état LU d'un artefact (jamais stocké) : sert les badges et les boutons des écrans. */
  function etatValidation(familleId, id) {
    var f = familleAValider(familleId);
    if (!f) return null;
    var a = artefactsDe(f).filter(function (x) { return x.id === id; })[0];
    if (!a) return null;
    var rec = a.rec || {};
    return { famille: f.id, id: id, libelle: a.libelle, enAttente: !!a.enAttente, valideLe: a.valideLe || null,
      validePar: rec.validePar || null, valideRole: rec.valideRole || null, roles: f.roles.slice(), profil: profilsFamille(f) };
  }
  /** Les familles qu'un profil VOIT au centre des validations : la Direction et la DAF voient tout, les autres leur ressort. */
  function referentielsVisiblesPar(role) {
    return referentielsAValider(VUE_COMPLETE_VALIDATIONS.indexOf(role) >= 0 ? null : { role: role });
  }

  global.SIGH.configurationFiscale = {
    ROLES_VALIDATION: ROLES_VALIDATION,
    identiteEnForce: identiteEnForce, identiteExigeVersion: identiteExigeVersion,
    enregistrerIdentite: enregistrerIdentite, nouvelleVersionIdentite: nouvelleVersionIdentite, validerIdentite: validerIdentite,
    obligationsEnVigueur: function (date) { return D.obligationsALaDate(date); },
    ortbEnVigueur: function (date) { return D.ortbALaDate(date); },
    ficheOrtb: ficheOrtb,
    modifierObligation: modifierObligation, creerObligation: creerObligation, retirerObligation: retirerObligation,
    annulerVersionAVenir: annulerVersionAVenir, versionsAVenir: versionsAVenir, versionAVenirDe: versionAVenirDe,
    parametresFiscauxEnVigueur: function (date) { return { delais: D.delaisFiscauxALaDate(date), ccib: D.montantCcibALaDate(date) }; },
    resumeParametre: resumeParametre, versionsParametresFiscaux: versionsParametresFiscaux, modifierParametreFiscal: modifierParametreFiscal, annulerParametreFiscal: annulerParametreFiscal,
    modifierOrtb: modifierOrtb, validerObligations: validerObligations,
    echeancesImpactees: echeancesImpactees, versionsObligation: versionsObligation,
    etatConfigurationFiscale: etatConfigurationFiscale, posteFileul: posteFileul,
  };
  global.SIGH.parcours.validerIdentite = validerIdentite;
  global.SIGH.parcours.validerObligations = validerObligations;
  global.SIGH.parcours.etatConfigurationFiscale = etatConfigurationFiscale;
  global.SIGH.validations = {
    FAMILLES_A_VALIDER: FAMILLES_A_VALIDER, VUE_COMPLETE: VUE_COMPLETE_VALIDATIONS,
    referentielsAValider: referentielsAValider, referentielsVisiblesPar: referentielsVisiblesPar,
    validerReferentiel: validerReferentiel, remettreAValider: remettreAValider, etatValidation: etatValidation,
    controlerEnregistrement: controlerEnregistrement, marquageEnregistrement: marquageEnregistrement, suivreEnregistrement: suivreEnregistrement,
    chiffresModifies: chiffresModifies, posteFileul: posteFileul, epurerMentions: epurerMentions,
  };
  global.SIGH.parcours.FAMILLES_A_VALIDER = FAMILLES_A_VALIDER;
  global.SIGH.parcours.referentielsAValider = referentielsAValider;
  global.SIGH.parcours.validerReferentiel = validerReferentiel;
  global.SIGH.parcours.remettreAValider = remettreAValider;

  /* ==========================================================================
   * LES PARAMÈTRES DE CLINIQUE (lot PARAM-CLINIQUE, 16/11/2026 ; décisions 10 et 14 de la Direction du 15/11/2026)
   * --------------------------------------------------------------------------
   * Le préavis de péremption (RG-05) et les deux bornes de la balance âgée se LISENT à la date dans `parametresClinique` (data.js :
   * `D.parametreCliniqueALaDate`), jamais dans une constante. Régler pose une NOUVELLE version datée (jamais une réécriture),
   * bornée et dite, motivée, journalisée (RG-12) ; geste réservé de la fiche RBAC `regler_parametres_clinique` (administrateur et
   * Directrice Administrative d'origine, proposition à valider) ; un fileul ne règle pas (réglage de branche, posé à la mère).
   * Une version à venir s'ANNULE en l'archivant (RG-14), jamais une version déjà en vigueur.
   * ======================================================================== */
  var GESTE_REGLER_PARAMETRES_CLINIQUE = 'regler_parametres_clinique';
  function colParametresClinique() { return S.collection('parametresClinique', { module: 'CFG', entite: 'paramètre de clinique', prefix: 'PCL' }); }
  function peutReglerParametresClinique(role) {
    var N = global.SIGH.nav;
    return !!(N && N.droitGeste && N.droitGeste(role == null ? roleCourant() : role, GESTE_REGLER_PARAMETRES_CLINIQUE));
  }
  /** Contrôle d'une valeur (pur, sans écriture) : null si recevable, sinon le refus nommé. `autres` : { cle: valeur } des autres clés à la même date (tranches). */
  function controleParametreClinique(cle, valeur, autres) {
    var def = D.definitionParametreClinique(cle);
    if (!def) return refusCfg('PARAMETRE_CLINIQUE_INCONNU', 'Le paramètre « ' + cle + ' » n’existe pas parmi les paramètres de clinique.', 'Choisir un paramètre listé à l’écran « Règles métier versionnées ».');
    var n = Number(valeur);
    if (valeur === '' || valeur === null || valeur === undefined || !isFinite(n) || n !== Math.floor(n) || n < def.min || n > def.max) {
      return refusCfg('PARAMETRE_HORS_BORNES', '« ' + def.libelle + ' » est un nombre entier de ' + def.min + ' à ' + def.max + ' ' + def.unite + ' (reçu « ' + valeur + ' »).',
        'Saisir un nombre entier de ' + def.min + ' à ' + def.max + '.', { min: def.min, max: def.max });
    }
    autres = autres || {};
    var courte = cle === 'creances.trancheCourteJours' ? n : Number(autres['creances.trancheCourteJours']);
    var longue = cle === 'creances.trancheLongueJours' ? n : Number(autres['creances.trancheLongueJours']);
    if ((cle === 'creances.trancheCourteJours' || cle === 'creances.trancheLongueJours') && isFinite(courte) && isFinite(longue) && !(courte < longue)) {
      return refusCfg('TRANCHES_INCOHERENTES', 'La fin de la première tranche (' + courte + ' jours) doit être plus petite que la fin de la deuxième (' + longue + ' jours).',
        'Saisir une première tranche plus courte que la deuxième, ou régler d’abord l’autre borne.', { courte: courte, longue: longue });
    }
    return null;
  }
  /** Régler : { cle, valeur, dateEffet?, motif }. Rend { ok, id, cle, valeur, dateEffet, avant } ou le refus nommé. */
  function definirParametreClinique(o) {
    o = o || {};
    var def = D.definitionParametreClinique(o.cle);
    if (!def) return controleParametreClinique(o.cle, o.valeur);
    if (!peutReglerParametresClinique()) {
      return refusCfg('PARAMETRE_CLINIQUE_RESERVE', 'Régler les paramètres de clinique est un droit réservé de la fiche du rôle : « ' + libelleRole(roleCourant()) + ' » ne l’a pas.',
        'Demander à un rôle qui détient le droit « Régler les paramètres de clinique » (matrice des droits).', { roles: global.SIGH.nav.rolesAvecGeste(GESTE_REGLER_PARAMETRES_CLINIQUE) });
    }
    var fileul = controleEcritureCfg();
    if (fileul) return fileul;
    if (!o.motif || String(o.motif).trim().length < 3) return refusCfg('PARAMETRE_MOTIF_OBLIGATOIRE', 'Un motif est obligatoire pour changer un paramètre de clinique.', 'Saisir le motif du changement.');
    var dateEffet = o.dateEffet ? isoJour(o.dateEffet) : aujIso();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateEffet)) return refusCfg('DATE_EFFET_INVALIDE', 'Date d’effet illisible : attendu AAAA-MM-JJ.', 'Choisir la date d’effet.');
    var autres = {};
    D.PARAMETRES_CLINIQUE.forEach(function (d) { if (d.cle !== o.cle) autres[d.cle] = D.parametreCliniqueALaDate(d.cle, dateEffet).valeur; });
    var refus = controleParametreClinique(o.cle, o.valeur, autres);
    if (refus) return refus;
    var existantes = D.versionsParametreClinique(o.cle).filter(function (v) { return v.dateEffet; });
    var derniere = existantes[existantes.length - 1] || null;
    if (derniere && String(dateEffet) < String(derniere.dateEffet).slice(0, 10)) {
      return refusCfg('DATE_EFFET_ANTERIEURE', 'La date d’effet ' + C.dateFR(dateEffet) + ' précède celle de la dernière version (' + C.dateFR(String(derniere.dateEffet).slice(0, 10)) + ') : une version ne s’insère pas dans le passé.',
        'Choisir une date d’effet égale ou postérieure, ou annuler d’abord la version à venir.');
    }
    var avant = D.parametreCliniqueALaDate(o.cle, dateEffet);
    var valeur = Number(o.valeur);
    var base = { cle: o.cle, valeur: valeur, libelle: def.libelle + ' : ' + valeur + ' ' + def.unite, dateEffet: dateEffet, source: String(o.source || '').trim() || null,
      motif: String(o.motif).trim(), creeLe: new Date().toISOString(), creePar: acteur() };
    var res = colParametresClinique().insert(base, { journal: { action: 'Paramètre de clinique : nouvelle version', module: def.module, entite: 'parametresClinique',
      avant: { valeur: avant.valeur, dateEffet: avant.dateEffet }, apres: { cle: o.cle, valeur: valeur, dateEffet: dateEffet, motif: base.motif } } });
    if (!res) return refusCfg('PARAMETRE_ECRITURE_REFUSEE', 'Le magasin a refusé l’écriture de la version.', 'Relire le journal.');
    return { ok: true, id: res.record.id, cle: o.cle, valeur: valeur, dateEffet: dateEffet, avant: avant.valeur, undo: res.undo };
  }
  /** Annuler une version À VENIR (archivage motivé, RG-14). Une version déjà en vigueur ne s'annule pas : on en pose une autre. */
  function annulerParametreClinique(id, motif) {
    var v = colParametresClinique().get(id);
    if (!v || v.statut === 'archive') return refusCfg('PARAMETRE_VERSION_INCONNUE', 'Version introuvable ou déjà annulée.', 'Rafraîchir l’écran.');
    if (!peutReglerParametresClinique()) return refusCfg('PARAMETRE_CLINIQUE_RESERVE', 'Annuler une version est réservé au droit « Régler les paramètres de clinique ».', 'Demander à un rôle qui détient ce droit.');
    var fileul = controleEcritureCfg();
    if (fileul) return fileul;
    if (!v.dateEffet || String(v.dateEffet).slice(0, 10) <= aujIso()) return refusCfg('PARAMETRE_VERSION_EN_VIGUEUR', 'Une version déjà en vigueur ne s’annule pas : elle a pu décider d’une alerte ou d’un état.', 'Poser une nouvelle version datée.');
    if (!motif || String(motif).trim().length < 3) return refusCfg('PARAMETRE_MOTIF_OBLIGATOIRE', 'Un motif est obligatoire pour annuler une version.', 'Saisir le motif.');
    var res = colParametresClinique().archive(id, String(motif).trim(), { journal: { action: 'Paramètre de clinique : version à venir annulée', module: 'CFG', entite: 'parametresClinique',
      avant: { valeur: v.valeur, dateEffet: v.dateEffet }, apres: { statut: 'archive', motif: String(motif).trim() } } });
    if (!res) return refusCfg('PARAMETRE_ECRITURE_REFUSEE', 'Le magasin a refusé l’archivage de la version.', 'Relire le journal.');
    return { ok: true, id: id, undo: res.undo };
  }
  S.garder('parametresClinique', function (op, rec) {
    if (op !== 'modifier') return null;
    var avant = rec && rec.id ? colParametresClinique().get(rec.id) : null;
    if (!avant) return null;
    if (JSON.stringify(avant.valeur) !== JSON.stringify(rec.valeur) || avant.cle !== rec.cle || String(avant.dateEffet || '') !== String(rec.dateEffet || '')) {
      return 'PARAMETRE_VERSION_FIGEE : une version d’un paramètre de clinique ne se réécrit pas (valeur, clé, date d’effet). Ajouter une nouvelle version datée.';
    }
    return null;
  });
  global.SIGH.parametresClinique = {
    GESTE: GESTE_REGLER_PARAMETRES_CLINIQUE, definitions: function () { return D.PARAMETRES_CLINIQUE; },
    aLaDate: D.parametreCliniqueALaDate, versions: D.versionsParametreClinique, controler: controleParametreClinique,
    definir: definirParametreClinique, annuler: annulerParametreClinique, peutRegler: peutReglerParametresClinique,
  };

  /* ==========================================================================
   * PASSERELLE SMS : LA FABRIQUE UNIQUE D’ENVOI (étape S2, 08/11/2026)
   * --------------------------------------------------------------------------
   * Tout déclencheur (rappel de rendez-vous, anniversaire, plus tard fêtes, relances, résultat disponible) passe par PR.envoyerSms, et par rien
   * d’autre : le consentement, le numéro, le journal et la mise en file ne se réécrivent pas à chaque déclencheur. Le SMS ne vise que des PATIENTS
   * (décision de la Direction) : les alertes internes passent par la cloche et le son.
   *
   * Qui décide quoi. Le POSTE décide du consentement du patient et de la validité du numéro (il tient le dossier). Le SERVEUR (api/sms.php) garde
   * ce qu’un poste ne peut pas contourner : le plafond du jour, les heures calmes, la liste des mots médicaux, le profil admis pour le motif.
   * La liste médicale n’est PAS recopiée ici : le poste ne la connaît pas, il envoie le texte et le serveur le refuse (DONNEE_MEDICALE).
   *
   * Un refus se nomme (code, motif, geste) et s’écrit au journal comme refus. Un message dont la suite est INTERROMPUE ne se perd pas :
   *   - heures calmes : file « reporté », retenté UNE SEULE FOIS à l’ouverture de la fenêtre ;
   *   - serveur ou fournisseur injoignable : file « hors ligne », retenté à chaque tour (cinq tentatives au plus).
   * Le même idClient accompagne chaque reprise et le serveur le retient : une réponse perdue en route ne produit jamais un second message.
   * Un rappel déclaré avec une clé (`cle`) ne part qu’une fois, même relancé par deux postes.
   * ======================================================================== */
  var SMS_MOTIFS = {
    rappel_rdv: { libelle: 'Rappel de rendez-vous', modele: 'rdv' },
    anniversaire: { libelle: 'Souhait d’anniversaire', modele: 'anniversaire' },
    fete: { libelle: 'Souhait de fête', modele: 'fete' },
    relance: { libelle: 'Relance', modele: 'echeance' },
    resultat_disponible: { libelle: 'Résultat disponible', modele: 'resultat' },
  };
  var SMS_REFUS_POSTE = {
    MOTIF_INCONNU: ['Le motif d’envoi n’est pas un motif patient admis.', 'Choisir un motif de la liste : ' + Object.keys(SMS_MOTIFS).join(', ') + '.'],
    PATIENT_INCONNU: ['Le destinataire n’est pas un patient enregistré : le SMS ne vise que des patients.', 'Retrouver ou ouvrir le dossier du patient.'],
    CONSENTEMENT_RETIRE: ['Le patient a retiré son consentement aux SMS : aucun message ne part.', 'Le consentement se rétablit au dossier du patient, par l’accueil, après accord de la personne.'],
    NUMERO_INVALIDE: ['Le numéro du dossier ne peut pas servir à un SMS : il manque l’indicatif ou le format est inconnu.', 'Corriger le téléphone au dossier : numéro à dix chiffres commençant par 01, ou format international avec le signe plus.'],
    HORS_LIGNE: ['Le serveur n’est pas joint : le message est mis en file et partira au retour de la connexion.', 'Rien à faire : un seul envoi sera tenté au retour, jamais deux.'],
    DEJA_TRAITE: ['Ce message a déjà été traité (même clé de déclencheur) : aucun second envoi.', 'Aucun.'],
    MODELE_ABSENT: ['Aucun modèle de message actif pour cette occasion.', 'Activer ou écrire le modèle dans Rappels & messages.'],
    ACCES_REFUSE: ['Ce profil n’envoie pas de message de ce motif.', 'S’adresser à l’accueil ou à l’administrateur système.'],
  };
  var SMS_FILE_TENTATIVES = 5;
  var _smsEnVol = {};
  var _smsDispo = { jeton: null, le: 0, v: null };

  function smsJournal() { return S.collection('messagesSms', { module: 'M13', entite: 'message SMS', prefix: 'SMS' }); }
  function smsFile() { return S.collection('fileSms', { module: 'M13', entite: 'message SMS en file', prefix: 'FSM' }); }
  function smsPatient(id) { return id ? S.collection('patients').active().filter(function (p) { return p.id === id; })[0] || null : null; }

  /** Consentement SMS d’un dossier : ACTIVÉ PAR DÉFAUT (décision de la Direction), retiré seulement par un `false` explicite. */
  function consentementSms(p) {
    return { accepte: !p || p.consentementSms !== false, le: (p && p.consentementSmsLe) || null, par: (p && p.consentementSmsPar) || null };
  }
  /** Date et auteur du consentement : posés à la création et à chaque CHANGEMENT. L’ancienne valeur reste lisible au journal d’audit (RG-12). */
  function tracerConsentementSms(v, record) {
    var avant = record ? record.consentementSms !== false : null;
    var voulu = v.consentementSms !== false;
    v.consentementSms = voulu;
    if (avant === null || avant !== voulu || !v.consentementSmsLe) {
      var s = S.session() || {};
      v.consentementSmsLe = new Date().toISOString();
      v.consentementSmsPar = s.nomComplet || s.nom || s.identifiant || 'inconnu';
    }
    return v;
  }

  /** Numéro international pour la passerelle. Règle proposée, à valider : un numéro à dix chiffres commençant par 01 (le format des lignes de la clinique) reçoit +229. */
  function numeroSms(brut) {
    var n = String(brut == null ? '' : brut).replace(/[\s.\-()]/g, '');
    if (/^\+/.test(n)) return n;
    if (/^00[1-9]/.test(n)) return '+' + n.slice(2);
    if (/^01[0-9]{8}$/.test(n)) return '+229' + n;
    return null;
  }

  function smsJourCle() { return C.iso(C.aujourdhui()); }
  function smsEntreeBase(motif, extra) {
    var now = C.aujourdhui(), s = S.session() || {};
    return Object.assign({
      date: C.iso(now), heure: C.pad(now.getHours()) + ':' + C.pad(now.getMinutes()), jourCle: C.iso(now),
      motif: motif, motifLibelle: (SMS_MOTIFS[motif] || {}).libelle || motif, fournisseur: '', idMessage: '',
      par: s.nomComplet || s.nom || s.identifiant || 'inconnu',
    }, extra || {});
  }
  function smsMasque(brut) {
    var c = String(brut == null ? '' : brut).replace(/\D/g, '');
    return c.length >= 4 ? '****' + c.slice(-4) : '';
  }
  function smsEcrire(entree) {
    try { return smsJournal().insert(entree); } catch (e) { console.error('[SIGH] journal SMS :', e); return null; }
  }
  function smsRefusPoste(code, detail) {
    var t = SMS_REFUS_POSTE[code] || [code, ''];
    return { code: code, motif: t[0] + (detail ? ' ' + detail : ''), geste: t[1] };
  }
  function smsDejaTraite(cle) {
    var auj = smsJourCle();
    var j = smsJournal().all().some(function (e) {
      return e.cle === cle && (e.statut === 'accepte' || e.statut === 'reporte' || e.statut === 'en_file' || (e.statut === 'refuse' && e.jourCle === auj));
    });
    return j || smsFile().all().some(function (e) { return e.cle === cle && e.statut === 'attente'; });
  }

  /** Appel de l’API `envoyer`. Rejette si le transport échoue (hors ligne), sinon rend {http, o}. */
  function smsAppeler(corps) {
    var racine = '';
    try { racine = document.documentElement.getAttribute('data-root') || ''; } catch (e) { racine = ''; }
    var jeton = S.jetonServeur ? S.jetonServeur() : null;
    if (!global.fetch || !jeton || global.location.protocol === 'file:') return global.Promise.reject(new Error('SANS_SERVEUR'));
    return global.fetch(racine + 'api/sms.php', {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Sigh-Jeton': jeton },
      body: JSON.stringify(Object.assign({ action: 'envoyer' }, corps)),
    }).then(function (r) {
      return r.text().then(function (t) { var o = {}; try { o = JSON.parse(t); } catch (e) { o = {}; } return { http: r.status, o: o }; });
    });
  }

  /** Une tentative auprès du serveur, SANS effet de bord sur le journal ni la file. @return Promise<{etat, http, o}> */
  function smsTenter(spec) {
    return smsAppeler({ motif: spec.motif, texte: spec.texte, destinataire: spec.numero, patientId: spec.patientId || undefined, idClient: spec.idClient, maintenant: spec.maintenant || undefined })
      .then(function (x) {
        var o = x.o || {};
        if (o.code === 'ACCES_REFUSE') return { etat: 'acces', http: x.http, o: o };
        if (o.etapes === undefined) return { etat: 'transitoire', http: x.http, o: o, code: 'HORS_LIGNE' };
        if (o.ok) return { etat: 'accepte', http: x.http, o: o };
        if (o.code === 'HEURES_CALMES') return { etat: 'reporte', http: x.http, o: o };
        if (o.code === 'FOURNISSEUR_INJOIGNABLE') return { etat: 'transitoire', http: x.http, o: o, code: 'FOURNISSEUR_INJOIGNABLE' };
        return { etat: 'refuse', http: x.http, o: o };
      }, function () { return { etat: 'transitoire', http: 0, o: {}, code: 'HORS_LIGNE' }; });
  }

  /** L’entrée du journal pour une réponse du serveur : celle que le serveur a bâtie, complétée de ce que seul le poste sait (clé, patient). */
  function smsEntreeServeur(t, spec, statut, extra) {
    var e = Object.assign({}, smsEntreeBase(spec.motif), t.o.entree || {}, { cle: spec.cle || '', patientId: spec.patientId || '', jourCle: smsJourCle() }, extra || {});
    if (statut) e.statut = statut;
    return e;
  }
  function smsDejaAuJournal(idMessage) {
    return !!idMessage && smsJournal().all().some(function (e) { return e.idMessage === idMessage && e.statut === 'accepte'; });
  }

  function envoyerSms(motif, patientId, texte, opts) {
    opts = opts || {};
    var cle = opts.cle || '';
    var spec = { motif: motif, patientId: patientId || '', cle: cle, texte: String(texte == null ? '' : texte), maintenant: opts.maintenant || null,
      idClient: opts.idClient || cle || ('sms:' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8)) };
    function refus(code, detail, numeroBrut, ecrire) {
      var r = smsRefusPoste(code, detail);
      if (ecrire !== false) {
        smsEcrire(smsEntreeBase(motif, { statut: 'refuse', code: code, detail: r.motif, numeroMasque: smsMasque(numeroBrut), longueur: spec.texte.length, cle: cle, patientId: patientId || '' }));
      }
      return global.Promise.resolve({ ok: false, statut: 'refuse', code: code, motif: r.motif, geste: r.geste });
    }
    if (!SMS_MOTIFS[motif]) return refus('MOTIF_INCONNU', '', '', false);
    if (cle && !opts.rejouer && smsDejaTraite(cle)) return refus('DEJA_TRAITE', '', '', false);
    var p = smsPatient(patientId);
    if (!p) return refus('PATIENT_INCONNU', '', '', false);
    if (!consentementSms(p).accepte) return refus('CONSENTEMENT_RETIRE', '', p.telephone);
    var numero = numeroSms(p.telephone);
    if (!numero) return refus('NUMERO_INVALIDE', '', p.telephone);
    spec.numero = numero;

    return smsTenter(spec).then(function (t) {
      var o = t.o, base = { longueur: spec.texte.length };
      if (t.etat === 'acces') return { ok: false, statut: 'refuse', code: 'ACCES_REFUSE', motif: o.motif || smsRefusPoste('ACCES_REFUSE').motif, geste: o.geste || smsRefusPoste('ACCES_REFUSE').geste };
      if (t.etat === 'accepte') {
        if (!(o.doublon && smsDejaAuJournal(o.idMessage))) smsEcrire(smsEntreeServeur(t, spec, 'accepte', base));
        return { ok: true, statut: 'accepte', idMessage: o.idMessage, numeroMasque: o.numeroMasque, doublon: !!o.doublon };
      }
      if (t.etat === 'refuse') {
        smsEcrire(smsEntreeServeur(t, spec, 'refuse', base));
        return { ok: false, statut: 'refuse', code: o.code, motif: o.motif, geste: o.geste };
      }
      /* interrompu : reporté (heures calmes) ou transitoire (hors ligne, fournisseur injoignable) : le message entre en file */
      var reporte = t.etat === 'reporte';
      var code = reporte ? 'HEURES_CALMES' : t.code;
      var r = (reporte || code === 'FOURNISSEUR_INJOIGNABLE') ? { motif: o.motif, geste: o.geste } : smsRefusPoste('HORS_LIGNE');
      smsFile().insert({ idClient: spec.idClient, cle: cle, motif: motif, patientId: patientId, texte: spec.texte, statut: 'attente', raison: reporte ? 'reporte' : 'transitoire', reporteA: reporte ? o.reporteA : '', tentatives: 0 });
      smsEcrire(Object.assign({ numeroMasque: smsMasque(numero) }, smsEntreeServeur(t, spec, reporte ? 'reporte' : 'en_file', base), { code: code, detail: r.motif }));
      return { ok: false, statut: reporte ? 'reporte' : 'en_file', code: code, motif: r.motif, geste: r.geste, reporteA: reporte ? o.reporteA : null };
    });
  }

  /** Reprise de la file : un envoi reporté se retente UNE fois à l’ouverture de la fenêtre ; un envoi hors ligne à chaque tour, cinq fois au plus. */
  function relancerSmsFile(opts) {
    opts = opts || {};
    var now = opts.maintenant ? new Date(opts.maintenant) : C.aujourdhui();
    var dus = smsFile().all().filter(function (e) {
      if (e.statut !== 'attente' || _smsEnVol[e.idClient]) return false;
      return e.raison !== 'reporte' || (e.reporteA && new Date(e.reporteA) <= now);
    });
    var bilan = [];
    return dus.reduce(function (chaine, e) {
      return chaine.then(function () {
        var p = smsPatient(e.patientId), numero = p ? numeroSms(p.telephone) : null;
        var spec = { motif: e.motif, patientId: e.patientId, cle: e.cle, texte: e.texte, idClient: e.idClient, numero: numero, maintenant: opts.maintenant || null };
        function clore(statut, extra) {
          smsFile().update(e.id, Object.assign({ statut: statut, texte: '' }, extra || {}));
        }
        if (!p || !numero || !consentementSms(p).accepte) {
          /* le consentement peut avoir été retiré, ou le dossier corrigé, pendant l’attente : la file ne passe jamais devant le patient */
          var c = !p ? 'PATIENT_INCONNU' : (!consentementSms(p).accepte ? 'CONSENTEMENT_RETIRE' : 'NUMERO_INVALIDE');
          var rc = smsRefusPoste(c);
          smsEcrire(smsEntreeBase(e.motif, { statut: 'refuse', code: c, detail: rc.motif, numeroMasque: p ? smsMasque(p.telephone) : '', longueur: e.texte.length, cle: e.cle, patientId: e.patientId }));
          clore('abandonne', { raisonFin: c });
          bilan.push({ id: e.id, fin: c });
          return null;
        }
        _smsEnVol[e.idClient] = true;
        return smsTenter(spec).then(function (t) {
          delete _smsEnVol[e.idClient];
          var o = t.o, n = (e.tentatives || 0) + 1, base = { longueur: e.texte.length, tentative: n };
          if (t.etat === 'acces') { bilan.push({ id: e.id, fin: 'acces' }); return null; }
          if (t.etat === 'accepte') {
            if (!(o.doublon && smsDejaAuJournal(o.idMessage))) smsEcrire(smsEntreeServeur(t, spec, 'accepte', base));
            clore('envoye', { tentatives: n, idMessage: o.idMessage });
            bilan.push({ id: e.id, fin: 'envoye' });
            return null;
          }
          if (t.etat === 'transitoire' && t.http === 0) { bilan.push({ id: e.id, fin: 'attente' }); return null; }   /* le transport échoue encore : ce n’est pas une tentative */
          if (t.etat === 'transitoire' && e.raison !== 'reporte' && n < SMS_FILE_TENTATIVES) {
            smsFile().update(e.id, { tentatives: n });
            bilan.push({ id: e.id, fin: 'attente' });
            return null;
          }
          /* refus définitif, heures calmes encore en cours après la reprise, ou tentatives épuisées : la file s’arrête, le journal le dit */
          var code = t.etat === 'transitoire' ? (t.code === 'HORS_LIGNE' ? 'HORS_LIGNE' : o.code) : (o.code || 'FOURNISSEUR_REFUS');
          smsEcrire(smsEntreeServeur(t, spec, 'refuse', Object.assign({ code: code, detail: o.motif || smsRefusPoste('HORS_LIGNE').motif }, base)));
          clore('abandonne', { tentatives: n, raisonFin: code });
          bilan.push({ id: e.id, fin: code });
          return null;
        });
      });
    }, global.Promise.resolve()).then(function () { return bilan; });
  }

  /** La passerelle est-elle active, pour ce profil ? Mémorisé une minute : les déclencheurs ne doivent pas questionner le serveur à chaque patient. */
  function smsDisponible(force) {
    var jeton = S.jetonServeur ? S.jetonServeur() : null;
    if (!jeton || !global.fetch || global.location.protocol === 'file:') return global.Promise.resolve(null);
    if (!force && _smsDispo.jeton === jeton && Date.now() - _smsDispo.le < 60000) return global.Promise.resolve(_smsDispo.v);
    var racine = '';
    try { racine = document.documentElement.getAttribute('data-root') || ''; } catch (e) { racine = ''; }
    return global.fetch(racine + 'api/sms.php?action=disponible', { headers: { 'X-Sigh-Jeton': jeton, Accept: 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (v) { _smsDispo = { jeton: jeton, le: Date.now(), v: v }; return v; }, function () { return null; });
  }

  /** Remplace les variables d’un modèle de message. Le motif du rendez-vous n’est PAS une variable : il ne peut donc jamais entrer dans un SMS (M6). */
  function smsComposer(modele, vars) {
    return String(modele || '')
      .replace(/\{\{nom\}\}/g, vars.nom || '').replace(/\{\{clinique\}\}/g, C.BRAND.nom)
      .replace(/\{\{date\}\}/g, vars.date || '').replace(/\{\{rdv\}\}/g, vars.rdv || '')
      .replace(/\{\{telephone\}\}/g, C.BRAND.telephoneRdv || (C.BRAND.telephones || [''])[0]);
  }
  function smsModele(occasion) {
    return S.collection('modelesMessage').active().filter(function (m) { return m.occasion === occasion && m.actif !== false; })[0] || null;
  }
  function smsJourDe(d) { return C.iso(new Date(d)); }
  function smsLot(elements, envoi) {
    var bilan = [];
    return elements.reduce(function (chaine, x) {
      return chaine.then(function () { return envoi(x).then(function (r) { bilan.push({ id: x.id, resultat: r }); }); });
    }, global.Promise.resolve()).then(function () { return bilan; });
  }

  /** DÉCLENCHEUR 1 : le rappel de la veille. Il nomme le médecin et l’heure, jamais le motif (décision M6). Même définition de « demain » que la tâche serveur rdv_lendemain. */
  function rappelsRdvSms(opts) {
    opts = opts || {};
    var auj = opts.aujourdhui ? new Date(opts.aujourdhui) : C.aujourdhui();
    var demain = new Date(auj.getFullYear(), auj.getMonth(), auj.getDate() + 1);
    var jour = C.iso(demain);
    var m = smsModele('rdv');
    var cibles = S.collection('consultations').active().filter(function (c) {
      return c.statut === 'planifiee' && c.patientId && !c.nonPatient && c.date && smsJourDe(c.date) === jour;
    });
    if (opts.patientIds) cibles = cibles.filter(function (c) { return opts.patientIds.indexOf(c.patientId) >= 0; });
    if (!cibles.length) return global.Promise.resolve([]);
    if (!m) return global.Promise.resolve([{ id: null, resultat: Object.assign({ ok: false, statut: 'refuse' }, smsRefusPoste('MODELE_ABSENT')) }]);
    return smsLot(cibles, function (c) {
      var p = smsPatient(c.patientId);
      var h = new Date(c.date);
      var rdv = C.dateFR(jour) + ' à ' + C.pad(h.getHours()) + 'h' + C.pad(h.getMinutes()) + (c.medecin ? ' avec ' + c.medecin : '');
      var texte = smsComposer(m.texte, { nom: p ? p.nom + ' ' + p.prenom : '', date: C.dateFR(jour), rdv: rdv });
      return envoyerSms('rappel_rdv', c.patientId, texte, { cle: 'rappel_rdv:' + c.id + ':' + jour, maintenant: opts.maintenant });
    });
  }

  /** DÉCLENCHEUR 2 : le vœu d’anniversaire. Le texte vient du modèle, il ne porte aucune donnée de santé ; un patient décédé n’en reçoit pas. */
  function anniversairesSms(opts) {
    opts = opts || {};
    var auj = opts.aujourdhui ? new Date(opts.aujourdhui) : C.aujourdhui();
    var jour = C.iso(auj), md = jour.slice(5), an = jour.slice(0, 4);
    var m = smsModele('anniversaire');
    var decedes = {};
    S.collection('deces').active().forEach(function (d) { if (d.patientId) decedes[d.patientId] = true; });
    var cibles = S.collection('patients').active().filter(function (p) {
      return p.dateNaissance && String(p.dateNaissance).slice(5, 10) === md && !decedes[p.id];
    });
    if (opts.patientIds) cibles = cibles.filter(function (p) { return opts.patientIds.indexOf(p.id) >= 0; });
    if (!cibles.length) return global.Promise.resolve([]);
    if (!m) return global.Promise.resolve([{ id: null, resultat: Object.assign({ ok: false, statut: 'refuse' }, smsRefusPoste('MODELE_ABSENT')) }]);
    return smsLot(cibles, function (p) {
      var texte = smsComposer(m.texte, { nom: p.nom + ' ' + p.prenom, date: C.dateFR(jour) });
      return envoyerSms('anniversaire', p.id, texte, { cle: 'anniversaire:' + p.id + ':' + an, maintenant: opts.maintenant });
    });
  }

  /** Le tour des déclencheurs, accroché à la surveillance de notifications.js. Silencieux tant que la passerelle n’est pas active : il n’écrit alors rien. Réservé au poste d’accueil. */
  var _smsAutoEnVol = false;
  function declencherSmsAuto() {
    var s = S.session();
    if (_smsAutoEnVol || !s || s.role !== 'reception') return global.Promise.resolve(null);
    _smsAutoEnVol = true;
    return smsDisponible().then(function (d) {
      if (!d || !d.actif || !d.configure) return null;
      return relancerSmsFile().then(function () { return rappelsRdvSms(); }).then(function () { return anniversairesSms(); });
    }).then(function (x) { _smsAutoEnVol = false; return x; }, function (e) { _smsAutoEnVol = false; console.error('[SIGH] déclencheurs SMS :', e); return null; });
  }

  global.SIGH.parcours.envoyerSms = envoyerSms;
  global.SIGH.parcours.relancerSmsFile = relancerSmsFile;
  global.SIGH.parcours.rappelsRdvSms = rappelsRdvSms;
  global.SIGH.parcours.anniversairesSms = anniversairesSms;
  global.SIGH.parcours.declencherSmsAuto = declencherSmsAuto;
  global.SIGH.parcours.smsDisponible = smsDisponible;
  global.SIGH.parcours.consentementSms = consentementSms;
  global.SIGH.parcours.tracerConsentementSms = tracerConsentementSms;
  global.SIGH.parcours.numeroSms = numeroSms;
  global.SIGH.parcours.SMS_MOTIFS = SMS_MOTIFS;

  /* ==========================================================================
   * LE BARÈME DE L'AIB PAR SITUATION DE L'ACHETEUR (Direction, 09/11/2026, lot A1)
   * --------------------------------------------------------------------------
   * TOUT EST PENSÉ POUR L'AVENIR : aucun taux, aucune date, aucun code de situation ni aucun libellé n'est écrit dans ce moteur. Il lit deux
   * collections du magasin, `situationsAib` (le code d'une situation, son libellé, le déclencheur qui la choisit d'office) et `baremeAib` (une
   * fiche par version ET par situation : taux, date d'effet, date de fin, source, motif). La semence (`D.SITUATIONS_AIB`, `D.BAREME_AIB`) n'est
   * qu'une PROPOSITION à valider ; on ajoute une situation, on change un taux à une date future ou on retire une version à l'écran
   * `cfg-bareme-aib`, sans toucher au code.
   *
   * Une version ne se réécrit JAMAIS : la corriger crée une nouvelle version à une date d'effet postérieure et FERME la précédente à la veille ;
   * la retirer l'archive (RG-14). La garde posée sur la collection refuse toute modification du taux, de la date d'effet ou de la situation d'une
   * version existante, d'où qu'elle vienne. Un taux absent n'est jamais zéro : le moteur refuse en le nommant (`AIB_SANS_BAREME`).
   * Un IFU saisi est PRÉSUMÉ actif : la maquette ne peut pas interroger la DGI, et le dit.
   * ======================================================================== */
  var ROLES_ECRITURE_AIB = ['comptable', 'admin', 'da'];
  var DECLENCHEURS_AIB = [
    { value: 'ifu_renseigne', label: 'Un IFU de 13 chiffres est saisi' },
    { value: 'ifu_absent', label: 'Aucun IFU saisi' },
    { value: 'choix', label: 'Choisie à la main par le caissier' },
  ];
  function colSituationsAib() { return S.collection('situationsAib', { module: 'CFG', entite: 'situation de l’acheteur (AIB)', prefix: 'SAI' }); }
  function colBaremeAib() { return S.collection('baremeAib', { module: 'CFG', entite: 'version du barème de l’AIB', prefix: 'BAI' }); }
  function refusAib(code, motif, geste, extra) { return refusCfg(code, motif, geste, extra); }
  function dateAib(d) { return d ? isoJour(d) : aujIso(); }
  function normaliserIfu(x) { return String(x == null ? '' : x).replace(/[\s  ]/g, ''); }
  function situationsAibActives() {
    return colSituationsAib().active().slice().sort(function (a, b) { return (a.ordre || 99) - (b.ordre || 99) || String(a.code).localeCompare(String(b.code)); });
  }
  function versionsAibDe(situation) {
    return colBaremeAib().active().filter(function (v) { return v.situation === situation; })
      .sort(function (a, b) { return String(a.dateEffet).localeCompare(String(b.dateEffet)); });
  }
  /** Le taux de la situation à la date : { ok, taux, arrete, dateEffet, dateFin, version (rang), versionId, situation, libelle, source } ou refus nommé. */
  function tauxAibALaDate(situation, date) {
    var d = dateAib(date);
    var sit = colSituationsAib().active().filter(function (s) { return s.code === situation; })[0];
    if (!sit) {
      return refusAib('AIB_SANS_BAREME', 'La situation « ' + situation + ' » n’est pas active au barème de l’AIB : aucun taux ne peut être rendu (un tiret n’est pas un zéro).',
        'Choisir une situation listée, ou la créer puis lui donner une version à l’écran « Barème de l’AIB ».', { situation: situation, date: d });
    }
    var toutes = versionsAibDe(situation);
    var couvrantes = toutes.filter(function (v) { return String(v.dateEffet) <= d && (!v.dateFin || String(v.dateFin) >= d); });
    var v = couvrantes[couvrantes.length - 1];
    if (!v || v.taux == null || v.taux === '' || !isFinite(Number(v.taux))) {
      return refusAib('AIB_SANS_BAREME', 'Aucune version du barème de l’AIB ne couvre la situation « ' + sit.libelle + ' » au ' + C.dateFR(d) + ' : le taux n’est pas arrêté, il ne vaut pas zéro.',
        'Ajouter une version de cette situation à l’écran « Barème de l’AIB » (taux, date d’effet, source), ou choisir une autre date.', { situation: situation, date: d });
    }
    return { ok: true, taux: Number(v.taux), arrete: v.aValider !== true, dateEffet: v.dateEffet, dateFin: v.dateFin || null,
      version: toutes.indexOf(v) + 1, versionId: v.id, situation: situation, libelle: sit.libelle, source: v.source || null, date: d };
  }
  /** La situation d'un acheteur d'après son IFU, et le taux de la date. Un IFU de 13 chiffres est PRÉSUMÉ actif (la DGI n'est pas interrogeable ici). */
  function tauxAibPourAcheteur(o) {
    o = o || {};
    var ifu = normaliserIfu(o.ifu);
    var declencheur;
    if (ifu === '') declencheur = 'ifu_absent';
    else if (/^\d{13}$/.test(ifu)) declencheur = 'ifu_renseigne';
    else return refusAib('IFU_INVALIDE', 'L’IFU de l’acheteur (« ' + ifu + ' ») doit comporter exactement 13 chiffres.', 'Corriger l’IFU, ou le laisser vide pour un particulier.');
    var sit = situationsAibActives().filter(function (s) { return s.declencheur === declencheur; })[0];
    if (!sit) {
      return refusAib('AIB_SANS_BAREME', 'Aucune situation active du barème de l’AIB ne se choisit d’office quand ' + (declencheur === 'ifu_absent' ? 'aucun IFU n’est saisi' : 'un IFU est saisi') + '.',
        'Régler le déclencheur d’une situation à l’écran « Barème de l’AIB », ou choisir le taux à la main.', { date: dateAib(o.date) });
    }
    var r = tauxAibALaDate(sit.code, o.date);
    if (!r.ok) return r;
    r.presomption = declencheur === 'ifu_renseigne';
    r.avertissement = r.presomption ? 'IFU présumé actif : la maquette ne peut pas interroger la DGI, l’activité de l’IFU n’est pas vérifiée.' : null;
    return r;
  }
  /** Les taux PROPOSÉS à la caisse à la date : un choix par situation active qui a un taux en vigueur, et le défaut selon l'IFU saisi. */
  function tauxAibProposes(o) {
    o = o || {};
    var d = dateAib(o.date);
    var choix = [];
    situationsAibActives().forEach(function (s) {
      var r = tauxAibALaDate(s.code, d);
      if (r.ok) choix.push({ situation: s.code, libelle: s.libelle, declencheur: s.declencheur, taux: r.taux, arrete: r.arrete, version: r.version, versionId: r.versionId });
    });
    var defaut = tauxAibPourAcheteur({ ifu: o.ifu, date: d });
    return { ok: true, date: d, choix: choix, defaut: defaut.ok ? defaut : null, defautRefus: defaut.ok ? null : defaut };
  }
  function motifEcritureAib() {
    var role = roleCourant();
    if (ROLES_ECRITURE_AIB.indexOf(role) < 0) {
      return refusAib('AIB_ECRITURE_RESERVEE', 'Le barème de l’AIB se tient par le comptable, la Directrice Administrative ou l’administrateur. Profil : ' + libelleRole(role) + '.',
        'Demander la modification au comptable ; la Direction consulte le barème sans l’écrire.');
    }
    if (posteFileul()) {
      return refusAib('AIB_POSTE_FILEUL', 'Ce poste est un fileul : le barème de l’AIB est tenu par la mère et se lit ici sans s’y écrire.', 'Faire la modification depuis le poste mère.');
    }
    return null;
  }
  /** Une version nouvelle : taux, date d'effet postérieure à la plus récente, source dite, motif. Elle FERME la précédente à la veille. Elle naît « à valider ». */
  function nouvelleVersionAib(o) {
    o = o || {};
    var refus = motifEcritureAib();
    if (refus) return refus;
    var sit = colSituationsAib().active().filter(function (s) { return s.code === o.situation; })[0];
    if (!sit) return refusAib('AIB_SITUATION_INCONNUE', 'La situation « ' + o.situation + ' » n’existe pas au barème de l’AIB.', 'Choisir une situation listée ou la créer d’abord.');
    var tauxBrut = o.taux;
    var taux = Number(tauxBrut);
    if (tauxBrut == null || tauxBrut === '' || !isFinite(taux) || Math.floor(taux) !== taux || taux < 0 || taux > 100) {
      return refusAib('AIB_TAUX_INVALIDE', 'Le taux (« ' + (tauxBrut == null ? '' : tauxBrut) + ' ») doit être un pourcentage entier de 0 à 100 : la maquette calcule en montants entiers.', 'Saisir un entier, par exemple 5.');
    }
    var dateEffet = o.dateEffet ? isoJour(o.dateEffet) : '';
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateEffet)) return refusAib('AIB_DATE_INVALIDE', 'La date d’effet est absente ou illisible.', 'Choisir la date à partir de laquelle le taux s’applique.');
    if (!String(o.source || '').trim()) return refusAib('AIB_SOURCE_ABSENTE', 'Aucune source n’est dite pour ce taux : on n’invente pas un taux, on cite son texte.', 'Indiquer le texte, la décision ou la déclaration d’où vient le taux.');
    if (!String(o.motif || '').trim()) return refusAib('AIB_MOTIF_ABSENT', 'Le motif de cette version est obligatoire.', 'Dire pourquoi le taux change ou pourquoi la version est ajoutée.');
    var existantes = versionsAibDe(o.situation);
    var derniere = existantes[existantes.length - 1] || null;
    if (existantes.some(function (v) { return String(v.dateEffet) === dateEffet; })) {
      return refusAib('AIB_DATE_EXISTANTE', 'Une version de cette situation commence déjà le ' + C.dateFR(dateEffet) + ' : une version ne se réécrit pas.', 'Choisir une date d’effet postérieure, ou retirer l’autre version (archive).');
    }
    if (derniere && String(derniere.dateEffet) > dateEffet) {
      return refusAib('AIB_DATE_ANTERIEURE', 'La version la plus récente de cette situation commence le ' + C.dateFR(derniere.dateEffet) + ' : une version insérée avant elle masquerait l’historique.', 'Choisir une date d’effet postérieure au ' + C.dateFR(derniere.dateEffet) + '.');
    }
    var veillee = veille(dateEffet);
    var ferme = null;
    if (derniere && (!derniere.dateFin || String(derniere.dateFin) > veillee)) {
      ferme = { id: derniere.id, avant: derniere.dateFin || null };
      colBaremeAib().update(derniere.id, { dateFin: veillee, modifieLe: aujIso(), modifiePar: acteur() });
    }
    /* Lot L1 (Q5) : une version saisie par un profil de la famille (comptable, DAF, administrateur) naît ARRÊTÉE, avec ses trois traces ; hors famille,
       elle naît « à valider ». UNE ligne de journal, qui porte l'état (le correctif est une version nouvelle : le motif y est déjà obligatoire). */
    var base = { situation: o.situation, taux: taux, dateEffet: dateEffet, dateFin: null,
      source: String(o.source).trim(), motif: String(o.motif).trim(), creeLe: aujIso(), creePar: acteur() };
    var mq = marquageEnregistrement('bareme_aib', { avant: null, valeurs: base });
    var res = colBaremeAib().insert(Object.assign(base, mq.patch), { journal: { action: 'Barème AIB : nouvelle version', module: 'CFG', entite: 'baremeAib',
      avant: { precedente: derniere ? { id: derniere.id, taux: derniere.taux, dateFin: ferme ? ferme.avant : derniere.dateFin || null } : null },
      apres: { etat: mq.valide ? 'validé' : 'à valider', situation: o.situation, taux: taux, dateEffet: dateEffet, precedenteFermeeLe: ferme ? veillee : null } } });
    return { ok: true, id: res.record.id, version: existantes.length + 1, situation: o.situation, taux: taux, dateEffet: dateEffet,
      precedente: derniere ? derniere.id : null, precedenteFermeeLe: ferme ? veillee : null, enAttenteDeValidation: !mq.valide, undo: res.undo };
  }
  /** Retirer une version : ARCHIVE (RG-14), jamais une suppression. Si elle était la dernière et fermait la précédente, la précédente est rouverte. */
  function retirerVersionAib(id, motif) {
    var refus = motifEcritureAib();
    if (refus) return refus;
    var v = colBaremeAib().get(id);
    if (!v || v.statut === 'archive') return refusAib('AIB_VERSION_INTROUVABLE', 'La version « ' + id + ' » n’existe pas ou est déjà archivée.', 'Choisir une version active du barème.');
    if (!String(motif || '').trim()) return refusAib('AIB_MOTIF_ABSENT', 'Le motif du retrait est obligatoire.', 'Dire pourquoi la version est retirée.');
    var autres = versionsAibDe(v.situation).filter(function (x) { return x.id !== v.id; });
    var precedente = autres.filter(function (x) { return String(x.dateEffet) < String(v.dateEffet); }).pop() || null;
    var derniere = !autres.some(function (x) { return String(x.dateEffet) > String(v.dateEffet); });
    var res = colBaremeAib().archive(id, String(motif).trim());
    var rouverte = null;
    if (precedente && derniere && precedente.dateFin && String(precedente.dateFin) === veille(v.dateEffet)) {
      colBaremeAib().update(precedente.id, { dateFin: null, modifieLe: aujIso(), modifiePar: acteur() });
      rouverte = precedente.id;
    }
    S.log('Barème AIB : version retirée', 'CFG', 'baremeAib', id, { taux: v.taux, dateEffet: v.dateEffet }, { statut: 'archive', motif: String(motif).trim(), precedenteRouverte: rouverte });
    return { ok: true, id: id, precedenteRouverte: rouverte, undo: res ? res.undo : null };
  }
  /** Ce qu'il FAUDRAIT brancher sur le barème, en lecture : le moteur liste, il ne branche pas (décision comptable de la Direction). */
  function aibABrancher() {
    return [
      { id: 'fenetre_mecef', lieu: 'Fenêtre « Facture normalisée » de la caisse (registre, file de caisse, émission)', etat: 'branche',
        detail: 'Branchée par le lot A1 : le taux par défaut vient du barème selon l’IFU saisi, les choix aussi ; le taux et sa version voyagent avec la vente.' },
      { id: 'registre_mecef', lieu: 'Registre fiscal MECeF et impression de la pièce normalisée (mecef.js)', etat: 'non_branche',
        detail: 'Lisent encore le paramètre fiscal fixe (AIB 1 %) pour décomposer les pièces anciennes. À brancher sur le taux et la version portés par chaque vente.' },
      { id: 'achats', lieu: 'Factures fournisseurs et bons de commande (M7)', etat: aibBranchementALaDate().actif ? 'branche' : 'non_branche',
        detail: aibBranchementALaDate().actif
          ? 'Branché par le comptable (réglage arrêté, deux comptes choisis) : une pièce en brouillon par facture listée à l’onglet « Achats à écrire ».'
          : 'Différé par décision de la Direction : le moteur liste à l’onglet « Achats à écrire » (situation du fournisseur d’après son IFU, taux du barème, charge) et n’écrit rien. Le branchement a son propre réglage, désactivé par défaut.' },
      { id: 'retenues_source', lieu: 'Retenues à la source et échéance mensuelle de l’AIB (M12, calendrier fiscal)', etat: 'non_branche',
        detail: 'L’échéance mensuelle ne lit aucun taux. À brancher pour rapprocher l’AIB prélevé aux ventes de l’AIB déclaré ; imputable sur l’impôt sur les bénéfices, pas une charge.' },
    ];
  }
  /* LA GARDE DU MAGASIN : une version existante ne change ni de taux, ni de situation, ni de date d'effet ; une situation ne change pas de code
     (des versions la citent). Les seules écritures admises sur une version sont sa fermeture (dateFin), sa validation et son archive. */
  S.garder('baremeAib', function (op, rec) {
    if (op !== 'modifier') return null;
    var avant = rec && rec.id ? colBaremeAib().get(rec.id) : null;
    if (!avant) return null;
    if (String(avant.taux) !== String(rec.taux) || avant.situation !== rec.situation || String(avant.dateEffet) !== String(rec.dateEffet)) {
      return 'AIB_VERSION_FIGEE : une version du barème ne se réécrit pas (taux, situation, date d’effet). Ajouter une nouvelle version à une date d’effet postérieure.';
    }
    return null;
  });
  S.garder('situationsAib', function (op, rec) {
    if (op !== 'modifier') return null;
    var avant = rec && rec.id ? colSituationsAib().get(rec.id) : null;
    if (avant && avant.code !== rec.code) return 'AIB_CODE_FIGE : le code d’une situation ne change pas, des versions du barème le citent. Créer une nouvelle situation et archiver celle-ci.';
    return null;
  });
  global.SIGH.baremeAib = {
    ROLES_ECRITURE: ROLES_ECRITURE_AIB, DECLENCHEURS: DECLENCHEURS_AIB,
    aLaDate: tauxAibALaDate, pourAcheteur: tauxAibPourAcheteur, proposes: tauxAibProposes,
    nouvelleVersion: nouvelleVersionAib, retirerVersion: retirerVersionAib, aBrancher: aibABrancher,
    versionsDe: versionsAibDe, situations: situationsAibActives,
  };
  global.SIGH.parcours.tauxAibALaDate = tauxAibALaDate;
  global.SIGH.parcours.tauxAibPourAcheteur = tauxAibPourAcheteur;
  global.SIGH.parcours.tauxAibProposes = tauxAibProposes;
  global.SIGH.parcours.nouvelleVersionAib = nouvelleVersionAib;
  global.SIGH.parcours.retirerVersionAib = retirerVersionAib;

  /* ==========================================================================
   * LES RÉGLAGES DE L'AIB (Direction, 09/11/2026, lot L2) : charge des 5 %, branchement différé sur les achats
   * --------------------------------------------------------------------------
   * Quatre réglages DATÉS (`D.REGLAGES_AIB` ne les DÉFINIT que : clé, valeurs admises), lus dans la collection `reglagesAib`, une fiche par version, jamais
   * réécrite, comme le barème : en changer crée une version à une date d'effet postérieure et ferme la précédente à la veille. Aucun défaut n'est écrit dans ce
   * moteur : les défauts de la Direction (la clinique supporte le prélèvement ; branchement désactivé) sont SEMÉS. Les comptes ne sont jamais présélectionnés.
   *   chargePrelevement  : qui supporte les 5 % (« clinique » ou « acheteur »). Texte officiel manquant : réglage non arrêté. AUCUN effet comptable n'en découle ;
   *                        la valeur à la date est portée par chaque vente et listée aux achats.
   *   branchementAchats  : « desactive » (défaut) ou « actif ». Désactivé, le moteur LISTE ce qu'il faudrait écrire et n'écrit RIEN (refus nommé si on le demande).
   *   compteAcompte / compteContrepartie : les deux comptes que le comptable désigne. L'écriture naît en BROUILLON, équilibrée (RG-10), une seule par facture.
   * L'activation est refusée (refus nommé) tant que les deux comptes ne sont pas arrêtés à la date d'effet ET que la charge n'est pas arrêtée : le branchement ne
   * rend « actif » que ce qui est arrêté. Elle porte la famille de validation `bareme_aib` : saisie par la famille, une version naît arrêtée (date, auteur, motif).
   * ======================================================================== */
  function colReglagesAib() { return S.collection('reglagesAib', { module: 'CFG', entite: 'réglage de l’AIB', prefix: 'RAI' }); }
  function definitionReglageAib(cle) { return (D.REGLAGES_AIB || []).filter(function (x) { return x.cle === cle; })[0] || null; }
  function versionsReglageAib(cle) {
    return colReglagesAib().active().filter(function (v) { return v.cle === cle; })
      .sort(function (a, b) { return String(a.dateEffet).localeCompare(String(b.dateEffet)); });
  }
  function compteDuPlan(num) {
    var n = String(num == null ? '' : num).trim();
    if (!n) return null;
    return S.collection('comptes').active().filter(function (c) { return String(c.num) === n; })[0] || null;
  }
  /** La valeur du réglage à la date : { ok, valeur, arrete, dateEffet, dateFin, version, versionId, cle, source } ou le refus nommé AIB_REGLAGE_SANS_VERSION (jamais une valeur inventée). */
  function reglageAibALaDate(cle, date) {
    var d = dateAib(date);
    var def = definitionReglageAib(cle);
    if (!def) return refusAib('AIB_REGLAGE_INCONNU', 'Le réglage « ' + cle + ' » n’existe pas parmi les réglages de l’AIB.', 'Choisir un réglage listé à l’écran « Barème de l’AIB ».', { cle: cle });
    var toutes = versionsReglageAib(cle);
    var couvrantes = toutes.filter(function (v) { return String(v.dateEffet) <= d && (!v.dateFin || String(v.dateFin) >= d); });
    var v = couvrantes[couvrantes.length - 1];
    if (!v || v.valeur == null || v.valeur === '') {
      return refusAib('AIB_REGLAGE_SANS_VERSION', 'Aucune version du réglage « ' + def.libelle + ' » ne couvre le ' + C.dateFR(d) + ' : la valeur n’est pas arrêtée, rien n’est supposé.',
        def.type === 'compte' ? 'Choisir le compte à l’écran « Barème de l’AIB », onglet « Réglages ».' : 'Ajouter une version de ce réglage à l’écran « Barème de l’AIB », onglet « Réglages ».', { cle: cle, date: d });
    }
    return { ok: true, cle: cle, valeur: v.valeur, arrete: v.aValider !== true, dateEffet: v.dateEffet, dateFin: v.dateFin || null,
      version: toutes.indexOf(v) + 1, versionId: v.id, source: v.source || null, date: d };
  }
  /** Qui supporte les 5 % à la date. Un réglage non arrêté se DIT (`arrete: false`, `message`) ; il ne change aucune écriture. */
  function aibChargeALaDate(date) {
    var r = reglageAibALaDate('chargePrelevement', date);
    if (!r.ok) return r;
    var def = definitionReglageAib('chargePrelevement');
    var lib = (def.valeurs.filter(function (x) { return x.value === r.valeur; })[0] || {}).label || r.valeur;
    r.libelle = lib;
    r.message = r.arrete ? null : 'Réglage non arrêté : le texte officiel manque. L’AIB reste affiché comme un acompte imputable, sans écriture.';
    return r;
  }
  /** L'état du branchement sur les achats à la date. `actif` n'est vrai que si la version est « actif » ET arrêtée, les deux comptes choisis et arrêtés, la charge arrêtée. */
  function aibBranchementALaDate(date) {
    var d = dateAib(date);
    var b = reglageAibALaDate('branchementAchats', d);
    var out = { ok: true, date: d, actif: false, valeur: b.ok ? b.valeur : 'desactive', arrete: b.ok ? b.arrete : null, versionId: b.ok ? b.versionId : null,
      compteAcompte: null, compteContrepartie: null, raisons: [] };
    var a = reglageAibALaDate('compteAcompte', d), c = reglageAibALaDate('compteContrepartie', d), ch = aibChargeALaDate(d);
    if (a.ok) { out.compteAcompte = String(a.valeur); out.compteAcompteArrete = a.arrete; }
    if (c.ok) { out.compteContrepartie = String(c.valeur); out.compteContrepartieArrete = c.arrete; }
    out.chargeArretee = ch.ok ? ch.arrete : false;
    if (!b.ok || b.valeur !== 'actif') { out.raisons.push('Le branchement est désactivé : le moteur liste, il n’écrit rien.'); return out; }
    if (b.arrete !== true) out.raisons.push('Le réglage du branchement n’est pas arrêté.');
    if (!a.ok) out.raisons.push('Le compte d’acompte n’est pas choisi.'); else if (a.arrete !== true) out.raisons.push('Le compte d’acompte n’est pas arrêté.');
    if (!c.ok) out.raisons.push('Le compte de contrepartie n’est pas choisi.'); else if (c.arrete !== true) out.raisons.push('Le compte de contrepartie n’est pas arrêté.');
    if (!ch.ok || ch.arrete !== true) out.raisons.push('Le réglage de la charge des 5 % n’est pas arrêté.');
    out.actif = out.raisons.length === 0;
    return out;
  }
  /** Une version nouvelle d'un réglage : valeur admise, date d'effet postérieure à la plus récente, motif. Elle FERME la précédente à la veille. Saisie par la famille, elle naît arrêtée. */
  function definirReglageAib(o) {
    o = o || {};
    var refus = motifEcritureAib();
    if (refus) return refus;
    var def = definitionReglageAib(o.cle);
    if (!def) return refusAib('AIB_REGLAGE_INCONNU', 'Le réglage « ' + o.cle + ' » n’existe pas parmi les réglages de l’AIB.', 'Choisir un réglage listé.');
    var valeur = o.valeur == null ? '' : String(o.valeur).trim();
    if (def.type === 'choix' && !def.valeurs.some(function (x) { return x.value === valeur; })) {
      return refusAib('AIB_VALEUR_INVALIDE', 'La valeur « ' + valeur + ' » n’est pas admise pour « ' + def.libelle + ' » (' + def.valeurs.map(function (x) { return x.value; }).join(', ') + ').', 'Choisir une valeur proposée.');
    }
    if (def.type === 'compte' && !compteDuPlan(valeur)) {
      return refusAib('AIB_COMPTE_INCONNU', 'Le compte « ' + valeur + ' » n’est pas au plan comptable : aucun numéro n’est inventé.', 'Choisir un compte du plan comptable (ou le créer d’abord à l’écran du plan).');
    }
    var dateEffet = o.dateEffet ? isoJour(o.dateEffet) : '';
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateEffet)) return refusAib('AIB_DATE_INVALIDE', 'La date d’effet est absente ou illisible.', 'Choisir la date à partir de laquelle le réglage s’applique.');
    if (!String(o.motif || '').trim()) return refusAib('AIB_MOTIF_ABSENT', 'Le motif de cette version est obligatoire.', 'Dire pourquoi le réglage change.');
    var existantes = versionsReglageAib(o.cle);
    var derniere = existantes[existantes.length - 1] || null;
    if (existantes.some(function (v) { return String(v.dateEffet) === dateEffet; })) {
      return refusAib('AIB_DATE_EXISTANTE', 'Une version de ce réglage commence déjà le ' + C.dateFR(dateEffet) + ' : une version ne se réécrit pas.', 'Choisir une date d’effet postérieure.');
    }
    if (derniere && String(derniere.dateEffet) > dateEffet) {
      return refusAib('AIB_DATE_ANTERIEURE', 'La version la plus récente de ce réglage commence le ' + C.dateFR(derniere.dateEffet) + ' : une version insérée avant elle masquerait l’historique.', 'Choisir une date d’effet postérieure au ' + C.dateFR(derniere.dateEffet) + '.');
    }
    if (o.cle === 'branchementAchats' && valeur === 'actif') {
      var a = reglageAibALaDate('compteAcompte', dateEffet), c = reglageAibALaDate('compteContrepartie', dateEffet), ch = aibChargeALaDate(dateEffet);
      var manque = [];
      if (!a.ok) manque.push('le compte d’acompte n’est pas choisi'); else if (a.arrete !== true) manque.push('le compte d’acompte n’est pas arrêté');
      if (!c.ok) manque.push('le compte de contrepartie n’est pas choisi'); else if (c.arrete !== true) manque.push('le compte de contrepartie n’est pas arrêté');
      if (!ch.ok || ch.arrete !== true) manque.push('le réglage de la charge des 5 % n’est pas arrêté');
      if (manque.length) {
        return refusAib('AIB_BRANCHEMENT_INCOMPLET', 'L’activation est refusée : ' + manque.join(', ') + '.',
          'Choisir les deux comptes à une date d’effet antérieure ou égale, arrêter la charge des 5 %, puis activer.', { manque: manque });
      }
    }
    var veillee = veille(dateEffet);
    var ferme = null;
    if (derniere && (!derniere.dateFin || String(derniere.dateFin) > veillee)) {
      ferme = { id: derniere.id, avant: derniere.dateFin || null };
      colReglagesAib().update(derniere.id, { dateFin: veillee, modifieLe: aujIso(), modifiePar: acteur() });
    }
    var libValeur = def.type === 'choix' ? (def.valeurs.filter(function (x) { return x.value === valeur; })[0] || {}).label || valeur : valeur;
    var base = { cle: o.cle, valeur: valeur, libelle: def.libelle + ' : ' + libValeur, dateEffet: dateEffet, dateFin: null, source: String(o.source || '').trim() || null,
      motif: String(o.motif).trim(), creeLe: aujIso(), creePar: acteur() };
    var mq = marquageEnregistrement('bareme_aib', { avant: null, valeurs: base });
    var res = colReglagesAib().insert(Object.assign(base, mq.patch), { journal: { action: 'Réglage AIB : nouvelle version', module: 'CFG', entite: 'reglagesAib',
      avant: { precedente: derniere ? { id: derniere.id, valeur: derniere.valeur, dateFin: ferme ? ferme.avant : derniere.dateFin || null } : null },
      apres: { etat: mq.valide ? 'validé' : 'à valider', cle: o.cle, valeur: valeur, dateEffet: dateEffet, motif: base.motif, precedenteFermeeLe: ferme ? veillee : null } } });
    return { ok: true, id: res.record.id, version: existantes.length + 1, cle: o.cle, valeur: valeur, dateEffet: dateEffet,
      precedente: derniere ? derniere.id : null, precedenteFermeeLe: ferme ? veillee : null, enAttenteDeValidation: !mq.valide, undo: res.undo };
  }
  /** Ce que le branchement sur les achats écrirait, facture par facture, SANS rien écrire. La situation du fournisseur se tire de son IFU (même règle que la caisse),
   *  le taux du barème de la date de la facture, la charge du réglage de la même date. Une ligne sans taux au barème porte son refus nommé, jamais un montant à zéro.
   *  La base est le montant facturé (la fiche ne distingue pas le hors taxes) et le montant arrondi à l'entier comme la caisse. */
  function aibAchatsAEcrire(o) {
    o = o || {};
    var au = o.au ? isoJour(o.au) : aujIso();
    var du = o.du ? isoJour(o.du) : au.slice(0, 4) + '-01-01';
    var br = aibBranchementALaDate(au);
    var fournisseurs = {};
    S.collection('fournisseurs').all().forEach(function (f) { fournisseurs[f.code] = f; });
    var posees = {};
    S.collection('ecritures').all().forEach(function (e) { if (e.statut !== 'archive' && e.aibFactureId) posees[e.aibFactureId] = e.numero; });
    var lignes = [];
    S.collection('facturesFournisseurs').active().filter(function (f) { return f.date && String(f.date) >= du && String(f.date) <= au; })
      .sort(function (a, b) { return String(a.date).localeCompare(String(b.date)) || String(a.reference).localeCompare(String(b.reference)); })
      .forEach(function (f) {
        var four = fournisseurs[f.fournisseur] || {};
        var ligne = { factureId: f.id, reference: f.reference, date: String(f.date).slice(0, 10), fournisseur: f.fournisseurNom || four.nom || f.fournisseur,
          ifu: four.ifu || null, base: Number(f.montantFacture) || 0, ecriteSous: posees[f.id] || null };
        var t = tauxAibPourAcheteur({ ifu: four.ifu || '', date: ligne.date });
        var ch = aibChargeALaDate(ligne.date);
        ligne.supporte = ch.ok ? ch.valeur : null;
        ligne.chargeArretee = ch.ok ? ch.arrete : null;
        if (!t.ok) { ligne.refus = t.code; ligne.motif = t.motif; lignes.push(ligne); return; }
        ligne.taux = t.taux; ligne.situation = t.situation; ligne.versionId = t.versionId; ligne.arrete = t.arrete;
        ligne.aib = divArrondi(ligne.base * t.taux, 100);
        lignes.push(ligne);
      });
    return { ok: true, du: du, au: au, branchement: br, lignes: lignes,
      aEcrire: lignes.filter(function (l) { return !l.refus && !l.ecriteSous && l.aib > 0; }).length, ecrire: br.actif === true,
      message: br.actif ? 'Branchement actif : « Écrire » pose en brouillon une pièce par facture listée, rien d’autre.'
        : 'Branchement non actif : la liste est un APERÇU, aucune écriture n’est posée. ' + br.raisons.join(' ') };
  }
  /** Écrit EXACTEMENT ce que la liste affiche, quand le branchement est actif : une pièce de deux lignes (débit acompte, crédit contrepartie) par facture, en brouillon,
   *  équilibrée (RG-10), jamais deux fois la même facture. Désactivé ou incomplet : refus nommé AIB_BRANCHEMENT_DESACTIVE, RIEN n'est écrit. */
  function aibEcrireAchats(o) {
    o = o || {};
    var refus = motifEcritureAib();
    if (refus) return refus;
    var ap = aibAchatsAEcrire(o);
    if (!ap.branchement.actif) {
      return refusAib('AIB_BRANCHEMENT_DESACTIVE', 'Le branchement de l’AIB sur les écritures d’achat n’est pas actif : aucune écriture n’est posée. ' + ap.branchement.raisons.join(' '),
        'Le comptable choisit les deux comptes, arrête la charge puis active le branchement à l’écran « Barème de l’AIB », onglet « Réglages ».', { raisons: ap.branchement.raisons });
    }
    var cA = compteDuPlan(ap.branchement.compteAcompte), cC = compteDuPlan(ap.branchement.compteContrepartie);
    if (!cA || !cC) {
      return refusAib('AIB_COMPTE_INCONNU', 'Un des deux comptes choisis n’est plus au plan comptable : aucune écriture n’est posée.', 'Rechoisir le compte à l’écran « Barème de l’AIB ».');
    }
    var posees = [], refusees = [];
    ap.lignes.filter(function (l) { return !l.refus && !l.ecriteSous && l.aib > 0; }).forEach(function (l) {
      var numero = 'AIB-' + l.reference;
      var base = { numero: numero, date: l.date, journal: 'OD', journalLibelle: 'Opérations diverses', libelle: 'AIB sur achat ' + l.reference + ' (' + l.taux + ' %), ' + l.fournisseur,
        pieceId: l.factureId, pieceNumero: l.reference, aibFactureId: l.factureId, aibTaux: l.taux, aibSupporte: l.supporte, origine: 'Automatique : AIB sur achat', statut: 'brouillon' };
      var debit = Object.assign({}, base, { compte: String(cA.num), compteLibelle: cA.libelle, debit: l.aib, credit: 0 });
      var credit = Object.assign({}, base, { compte: String(cC.num), compteLibelle: cC.libelle, debit: 0, credit: l.aib });
      if (debit.debit !== credit.credit) { refusees.push(l.factureId); return; }
      var r1 = col('ecritures').insert(debit);
      if (!r1 || !r1.record) { refusees.push(l.factureId); return; }
      var r2 = col('ecritures').insert(credit);
      posees.push({ factureId: l.factureId, numero: numero, montant: l.aib, ids: [r1.record.id, r2 && r2.record ? r2.record.id : null] });
    });
    S.log('AIB sur achats écrit', 'M12', 'Ecriture', 'AIB-achats', null, { pieces: posees.length, compteAcompte: String(cA.num), compteContrepartie: String(cC.num), du: ap.du, au: ap.au });
    return { ok: true, pieces: posees, refusees: refusees, du: ap.du, au: ap.au };
  }
  S.garder('reglagesAib', function (op, rec) {
    if (op !== 'modifier') return null;
    var avant = rec && rec.id ? colReglagesAib().get(rec.id) : null;
    if (!avant) return null;
    if (String(avant.valeur) !== String(rec.valeur) || avant.cle !== rec.cle || String(avant.dateEffet) !== String(rec.dateEffet)) {
      return 'AIB_VERSION_FIGEE : une version de réglage ne se réécrit pas (valeur, réglage, date d’effet). Ajouter une nouvelle version à une date d’effet postérieure.';
    }
    return null;
  });
  global.SIGH.reglagesAib = {
    aLaDate: reglageAibALaDate, charge: aibChargeALaDate, branchement: aibBranchementALaDate, definir: definirReglageAib,
    achatsAEcrire: aibAchatsAEcrire, ecrireAchats: aibEcrireAchats, versionsDe: versionsReglageAib, definitions: function () { return D.REGLAGES_AIB; },
  };
  global.SIGH.parcours.aibChargeALaDate = aibChargeALaDate;
  global.SIGH.parcours.aibBranchementALaDate = aibBranchementALaDate;

  /* ==========================================================================
   * MECeF, LOT M1 (08/11/2026) : montants entiers, acheteur, états de pièce, reprise sans doublon
   * --------------------------------------------------------------------------
   * Décision de la Direction du 07/11/2026 (PRD-MECEF, section 11 bis) : TOUTE VENTE EST NORMALISÉE à la clinique. Il n'y a donc pas de
   * « facture simple » : quand le mode n'est pas « Désactivé », chaque vente SOLDÉE passe par la normalisation, et la fenêtre « Facture
   * normalisée » ne sert qu'à saisir l'IFU et le nom de l'acheteur et le taux d'AIB.
   *
   * LA MAQUETTE SIMULE. Il n'y a ici ni boîtier, ni serveur de la DGI : `fauxBoitier` est un appareil de démonstration (compteur, journal
   * des émissions, pannes réglables pour les sondes). Aucune adresse d'API, aucun protocole, aucun modèle de boîtier n'est supposé : ces
   * éléments ne figurent dans aucun document remis (PRD, risques). Le numéro produit n'est PAS un numéro fiscal ; la pièce porte
   * `mecefSimule: true` et l'impression le dit.
   *
   * Les identifiants STOCKÉS des états restent `valide` et `rejete` (le poste les lit dans ses jeux, doctrine « on ne renomme pas un
   * identifiant technique ») : `etatMecef()` en donne le nom CANONIQUE (normalisee, en_attente, a_verifier, refusee, expiree).
   * ======================================================================== */
  var ETATS_MECEF = [
    { id: 'normalisee', stocke: 'valide', libelle: 'Normalisée', ton: 'success' },
    { id: 'en_attente', stocke: 'en_attente', libelle: 'En attente de transmission', ton: 'warning' },
    { id: 'a_verifier', stocke: 'a_verifier', libelle: 'À vérifier', ton: 'warning' },
    { id: 'refusee', stocke: 'rejete', libelle: 'Refusée', ton: 'danger' },
    { id: 'expiree', stocke: 'expiree', libelle: 'Expirée', ton: 'danger' },
  ];
  /** L'état canonique d'une pièce, ou null quand la pièce n'est pas du registre fiscal (avoir « sans_objet », statut absent). */
  function etatMecef(f) {
    var s = f && (typeof f === 'string' ? f : f.statutMecef);
    var e = ETATS_MECEF.filter(function (x) { return x.stocke === s; })[0];
    return e ? e.id : null;
  }
  function etatMecefFiche(id) { return ETATS_MECEF.filter(function (x) { return x.id === id; })[0] || null; }

  function refusMecef(code, motif, geste) { return { ok: false, code: code, motif: motif, geste: geste }; }
  function entierPositif(x) { return typeof x === 'number' && isFinite(x) && Math.floor(x) === x && x >= 0; }
  /** a / b arrondi au plus proche (la moitié vers le haut), en arithmétique ENTIÈRE : aucune décimale ne traverse. a >= 0, b > 0. */
  function divArrondi(a, b) { return Math.floor((2 * a + b) / (2 * b)); }
  function tauxTvaCourant() {
    var F = D.PARAM_FISCAL || {};
    var r = (F.regimesTva || []).filter(function (x) { return x.id === F.regimeTva; })[0];
    return r ? r.taux : 0;
  }

  /**
   * LA FONCTION UNIQUE DES MONTANTS (exposée : SIGH.mecefMontants). Tout montant envoyé à la normalisation naît ici.
   *   entree = { lignes: [{ id, designation, quantite, prixUnitaire, montantBrut?, remise?, partAssureur?, partPersonnel?, partPatient?,
   *                         statutPaiement? }],
   *              remiseGlobale?, totalAttendu?, paiements?, seulementPayees?, aibTaux?, tauxTva? }
   * Règles : prix unitaire ENTIER en FCFA (sauf quand la pièce porte son `montantBrut` : c'est lui qui gouverne, le prix envoyé est
   * alors déduit) ; quantité décimale admise jusqu'à trois décimales ; remise de ligne entière, remise globale RÉPARTIE au prorata du
   * net (par défaut, l'écart d'arrondi va sur la PLUS GRANDE ligne) ; la base MECeF ne porte que la part du PATIENT (jamais la part
   * assureur, jamais le personnel, jamais une remise) ; les totaux sont CONTRÔLÉS (TOTAL_INCOHERENT) avant tout envoi.
   * Retour : { ok: true, lignes, brut, remises, total, partAssureur, partPersonnel, partPatient, base, ht, tva, aib, net }
   *       ou { ok: false, code, motif, geste }.
   */
  function mecefMontants(entree) {
    var e = entree || {};
    var src = e.lignes || [];
    if (!src.length) return refusMecef('AUCUNE_LIGNE', 'La pièce ne porte aucune ligne à normaliser.', 'Ajouter au moins une prestation avant la normalisation.');
    var L = [];
    for (var i = 0; i < src.length; i++) {
      var l = src[i] || {};
      var nom = l.designation || l.id || ('ligne ' + (i + 1));
      var q = l.quantite == null ? 1 : Number(l.quantite);
      var qm = Math.round(q * 1000);
      if (!(isFinite(q) && q > 0) || Math.abs(qm / 1000 - q) > 1e-9) {
        return refusMecef('QUANTITE_INVALIDE', 'La quantité de « ' + nom + ' » (' + l.quantite + ') doit être positive, à trois décimales au plus.', 'Corriger la quantité de la ligne.');
      }
      var brut;
      if (l.montantBrut != null) {
        if (!entierPositif(l.montantBrut)) return refusMecef('MONTANT_DECIMAL', 'Le montant de « ' + nom + ' » (' + l.montantBrut + ') n’est pas un nombre entier de FCFA.', 'Corriger la ligne : un montant normalisé est un entier.');
        brut = l.montantBrut;
      } else {
        if (!entierPositif(Number(l.prixUnitaire))) return refusMecef('PRIX_DECIMAL', 'Le prix unitaire de « ' + nom + ' » (' + l.prixUnitaire + ') n’est pas un nombre entier de FCFA.', 'Corriger le prix : seule la quantité peut être décimale.');
        brut = divArrondi(qm * Number(l.prixUnitaire), 1000);
      }
      var remise = l.remise == null ? 0 : l.remise;
      if (!entierPositif(remise) || remise > brut) return refusMecef('REMISE_INVALIDE', 'La remise de « ' + nom + ' » (' + l.remise + ') doit être un entier de FCFA qui ne dépasse pas le montant de la ligne.', 'Corriger la remise de la ligne.');
      L.push({ src: l, id: l.id || null, designation: l.designation || null, qm: qm, quantite: q, brut: brut, remise: remise, net: brut - remise,
        partAssureur: l.partAssureur || 0, partPersonnel: l.partPersonnel || 0 });
    }
    /* La remise globale se répartit sur le net ; l'écart d'arrondi (strictement inférieur au nombre de lignes) va sur la PLUS GRANDE ligne. */
    var rg = e.remiseGlobale == null ? 0 : e.remiseGlobale;
    if (!entierPositif(rg)) return refusMecef('REMISE_INVALIDE', 'La remise globale (' + e.remiseGlobale + ') doit être un entier de FCFA.', 'Corriger la remise.');
    if (rg > 0) {
      var sommeNet = L.reduce(function (n, x) { return n + x.net; }, 0);
      if (rg > sommeNet) return refusMecef('REMISE_INVALIDE', 'La remise globale (' + rg + ') dépasse le total de la pièce (' + sommeNet + ').', 'Corriger la remise.');
      var parts = L.map(function (x) { return Math.floor(rg * x.net / sommeNet); });
      var reste = rg - parts.reduce(function (n, p) { return n + p; }, 0);
      var plus = 0;
      L.forEach(function (x, k) { if (x.net > L[plus].net) plus = k; });
      parts[plus] += reste;
      for (var k = 0; k < L.length; k++) {
        if (parts[k] > L[k].net) return refusMecef('REMISE_INVALIDE', 'La part de remise de « ' + (L[k].designation || L[k].id || 'ligne ' + (k + 1)) + ' » dépasse son montant.', 'Corriger la remise.');
        L[k].remise += parts[k]; L[k].net -= parts[k];
      }
    }
    var totalBrut = 0, totalRemises = 0, total = 0, tAss = 0, tPers = 0, tPat = 0, base = 0;
    var sortie = [];
    for (var j = 0; j < L.length; j++) {
      var x = L[j];
      var nomL = x.designation || x.id || ('ligne ' + (j + 1));
      if (!entierPositif(x.partAssureur) || !entierPositif(x.partPersonnel)) return refusMecef('MONTANT_DECIMAL', 'Une part de « ' + nomL + ' » n’est pas un nombre entier de FCFA.', 'Corriger la prise en charge de la ligne.');
      var pat = x.net - x.partAssureur - x.partPersonnel;
      if (x.src.partPatient != null && rg === 0 && x.src.partPatient !== pat) {
        return refusMecef('TOTAL_INCOHERENT', 'Les parts de « ' + nomL + ' » (patient ' + x.src.partPatient + ', assureur ' + x.partAssureur + ', personnel ' + x.partPersonnel + ') ne totalisent pas son montant (' + x.net + ').', 'Reprendre la répartition de la ligne.');
      }
      if (pat < 0) return refusMecef('TOTAL_INCOHERENT', 'Les parts de « ' + nomL + ' » dépassent son montant (' + x.net + ').', 'Reprendre la répartition de la ligne.');
      var compte = !e.seulementPayees || x.src.statutPaiement === 'paye';
      totalBrut += x.brut; totalRemises += x.remise; total += x.net; tAss += x.partAssureur; tPers += x.partPersonnel; tPat += pat;
      if (compte) base += pat;
      sortie.push({ id: x.id, designation: x.designation, quantite: x.quantite, prixUnitaireEnvoye: x.qm ? divArrondi(x.brut * 1000, x.qm) : x.brut,
        brut: x.brut, remise: x.remise, net: x.net, partAssureur: x.partAssureur, partPersonnel: x.partPersonnel, partPatient: pat });
    }
    if (e.totalAttendu != null && e.totalAttendu !== total) {
      return refusMecef('TOTAL_INCOHERENT', 'La somme des lignes (' + total + ') diffère du total de la pièce (' + e.totalAttendu + ').', 'Reprendre les lignes ou le total de la pièce avant la normalisation.');
    }
    if (e.paiements) {
      var somPaiements = e.paiements.reduce(function (n, p) { return n + p; }, 0);
      if (somPaiements !== base) return refusMecef('TOTAL_INCOHERENT', 'Les paiements (' + somPaiements + ') diffèrent de la base normalisée (' + base + ').', 'Reprendre les règlements de la pièce.');
    }
    var tva = e.tauxTva != null ? e.tauxTva : tauxTvaCourant();
    var aibTaux = e.aibTaux == null ? 0 : e.aibTaux;
    if (!entierPositif(aibTaux) || aibTaux > 100) return refusMecef('AIB_TAUX_INVALIDE', 'Le taux d’AIB (' + e.aibTaux + ') n’est pas un pourcentage entier.', 'Choisir 0, 1 ou 5 %.');
    var ht = tva ? divArrondi(base * 100, 100 + tva) : base;
    var aib = divArrondi(ht * aibTaux, 100);
    return { ok: true, lignes: sortie, brut: totalBrut, remises: totalRemises, total: total, partAssureur: tAss, partPersonnel: tPers,
      partPatient: tPat, base: base, ht: ht, tva: base - ht, aib: aib, net: base + aib };
  }

  /** Le taux par défaut de la fenêtre selon l'IFU saisi : lu au barème daté (null si le barème ne dit rien : jamais zéro). */
  function aibTauxDefaut(ifu, date) { var r = tauxAibPourAcheteur({ ifu: ifu, date: date }); return r.ok ? r.taux : null; }

  /** Les données de l'acheteur que la vente PORTE : le taux, la situation et la version du barème sous lesquels elle est émise. Une pièce émise ne se réécrit jamais. */
  function traceAibAcheteur(ach) {
    return { aibTaux: ach.aibTaux, aibSituation: ach.aibSituation || null, aibVersion: ach.aibVersion || null,
      aibArrete: ach.aibArrete == null ? null : ach.aibArrete, aibDateBareme: ach.aibDateBareme || null,
      aibCharge: chargeDeLaVente(ach.aibDateBareme).valeur, aibChargeArretee: chargeDeLaVente(ach.aibDateBareme).arretee };
  }
  /** Qui supporte les 5 % à la date de la vente (réglage daté, lot L2) : une trace, aucun effet sur les montants. Sans version à la date : null, jamais une valeur supposée. */
  function chargeDeLaVente(date) {
    if (!date) return { valeur: null, arretee: null };
    var r = aibChargeALaDate(date);
    return r.ok ? { valeur: r.valeur, arretee: r.arrete } : { valeur: null, arretee: null };
  }

  /** Contrôle de la fenêtre « Facture normalisée » : IFU de l'acheteur (13 chiffres quand il est renseigné, facultatif pour un particulier), nom, taux d'AIB.
   *  Le taux vient du barème daté : défaut selon l'IFU, choix parmi les taux en vigueur (ou « aucun »), jamais une liste écrite ici. `a.conserve` : pièce
   *  déjà émise, son taux est gardé tel quel (il n'est pas rejugé au barème d'aujourd'hui). */
  function validerAcheteurMecef(a) {
    a = a || {};
    var ifu = normaliserIfu(a.ifu);
    if (ifu && !/^\d{13}$/.test(ifu)) {
      return refusMecef('IFU_INVALIDE', 'L’IFU de l’acheteur (« ' + ifu + ' ») doit comporter exactement 13 chiffres.', 'Corriger l’IFU, ou le laisser vide pour un particulier.');
    }
    var nom = String(a.nom == null ? '' : a.nom).trim();
    if (ifu && !nom) return refusMecef('NOM_ACHETEUR_ABSENT', 'Un IFU d’acheteur est saisi sans son nom.', 'Saisir le nom de l’acheteur qui porte cet IFU.');
    var date = dateAib(a.date);
    var vide = a.aibTaux == null || a.aibTaux === '';
    var taux, situation = null, version = null, arrete = null, dateBareme = date, horsDefaut = false;
    var defaut = tauxAibPourAcheteur({ ifu: ifu, date: date });
    if (a.conserve && !vide) {
      taux = Number(a.aibTaux);
      if (!entierPositif(taux) || taux > 100) return refusMecef('AIB_TAUX_INVALIDE', 'Le taux d’AIB (' + a.aibTaux + ') n’est pas un pourcentage entier.', 'Reprendre la pièce.');
      situation = a.aibSituation || null; version = a.aibVersion || null; arrete = a.aibArrete == null ? null : a.aibArrete; dateBareme = a.date ? date : (a.aibDateBareme || null);
    } else if (a.aibSituation) {
      var rs = tauxAibALaDate(a.aibSituation, date);
      if (!rs.ok) return refusMecef(rs.code, rs.motif, rs.geste);
      taux = rs.taux; situation = rs.situation; version = rs.versionId; arrete = rs.arrete;
      horsDefaut = !defaut.ok || defaut.situation !== rs.situation;
    } else if (vide) {
      if (!defaut.ok) return refusMecef(defaut.code, defaut.motif, defaut.geste);
      taux = defaut.taux; situation = defaut.situation; version = defaut.versionId; arrete = defaut.arrete;
    } else {
      taux = Number(a.aibTaux);
      var prop = tauxAibProposes({ ifu: ifu, date: date });
      var retenus = prop.choix.filter(function (c) { return c.taux === taux; });
      if (taux !== 0 && !retenus.length) {
        return refusMecef('AIB_TAUX_INVALIDE', 'Le taux d’AIB (' + a.aibTaux + ') n’est pas l’un des taux du barème au ' + C.dateFR(date) + ' ('
          + (prop.choix.map(function (c) { return c.taux + ' %'; }).filter(function (x, i, t) { return t.indexOf(x) === i; }).concat(['aucun']).join(', ')) + ').',
        'Choisir un taux proposé, ou le faire ajouter au barème par le comptable.');
      }
      var choisi = defaut.ok && retenus.filter(function (c) { return c.situation === defaut.situation; })[0] || retenus[0] || null;
      if (choisi) { situation = choisi.situation; version = choisi.versionId; arrete = choisi.arrete; }
      horsDefaut = !defaut.ok || defaut.taux !== taux;
    }
    return { ok: true, acheteur: { ifu: ifu || null, nom: nom || null, aibTaux: taux, aibSituation: situation, aibVersion: version, aibArrete: arrete,
      aibDateBareme: dateBareme, aibDefaut: defaut.ok ? defaut.taux : null, aibHorsDefaut: horsDefaut } };
  }

  /* --- Le mode : réglage d'exploitation (le réglage se fait à « Configuration fiscale », lot L3) -------------------------------------------------- */
  var MODES_MECEF = ['desactive', 'boitier', 'emecef'];
  function modeMecef() { var m = S.reglage('mecefMode', 'boitier'); return MODES_MECEF.indexOf(m) >= 0 ? m : 'boitier'; }
  function definirModeMecef(m) {
    if (MODES_MECEF.indexOf(m) < 0) return refusMecef('MODE_INCONNU', 'Le mode « ' + m + ' » n’existe pas.', 'Choisir boîtier physique ou e-MECeF.');
    if (['admin', 'da'].indexOf(roleCourant()) < 0) return refusMecef('MODE_RESERVE', 'Le mode de facturation normalisée se règle par l’administrateur ou la Directrice Administrative.', 'Demander le changement à la DA.');
    var avant = modeMecef();
    S.setReglage('mecefMode', m);
    S.log('Mode de facturation normalisée', 'MECEF', 'reglage', 'mecefMode', { mode: avant }, { mode: m });
    return { ok: true, mode: m };
  }

  /* --- L'ADAPTATEUR du mode en vigueur (lot L3, Direction 09/11/2026) ------------------------------------------------------------
     AUCUN NUMÉRO SIMULÉ NE SE PRÉSENTE COMME FISCAL. Deux modes se proposent : le BOÎTIER physique (défaut) et e-MECeF. Aucun document remis ne
     donne le modèle du boîtier, son interface ni son protocole, ni le dossier d'interface e-MECeF de la DGI : ni URL, ni jeton, ni format de message
     n'est supposé. La maquette garde, en mode boîtier, son APPAREIL DE DÉMONSTRATION (la pièce porte `mecefSimule`, l'impression le dit). En mode
     e-MECeF, rien n'est branché : l'adaptateur est « non configuré », refuse en nommant (code, motif, geste), et la vente reste EN ATTENTE sans
     qu'aucun numéro ne soit fabriqué. L'émission de la vente n'est jamais bloquée par ce refus. */
  var CODE_NON_CONFIGURE = 'MECEF_NON_CONFIGURE';
  function adaptateurMecef() {
    var mode = modeMecef();
    if (mode === 'emecef') {
      return { mode: mode, configure: false, demonstration: false, code: CODE_NON_CONFIGURE,
        motif: 'e-MECeF non configuré : dossier d’interface DGI requis.',
        geste: 'La vente reste en attente de certification. Choisir le mode « Boîtier physique », ou fournir le dossier d’interface de la DGI.' };
    }
    return { mode: mode, configure: true, demonstration: true, code: null, motif: null, geste: null };
  }

  /* --- L'appareil de démonstration ------------------------------------------------------------------------------------------------ */
  var fauxBoitier = {
    /** Panne réglable pour les sondes : null | 'refus' | 'reponse_perdue' | 'delai'. En mémoire : un rechargement la lève. */
    panne: null,
    etat: function () { return S.reglage('mecefBoitier', { compteur: 0, emissions: [] }); },
    /** Le prochain numéro : séquentiel, JAMAIS déjà porté par une facture ou un avoir. */
    numeroSuivant: function () {
      var pris = {};
      col('factures').all().forEach(function (f) { if (f.numeroMecef) pris[f.numeroMecef] = true; });
      col('avoirs').all().forEach(function (a) { if (a.numeroMecef) pris[a.numeroMecef] = true; });
      var et = this.etat(), n = et.compteur, num;
      do { n++; num = 'MECEF' + String(2000000 + n); } while (pris[num]);
      return { numero: num, compteur: n };
    },
    emettre: function (demande) {
      /* Garde de fond : sans adaptateur configuré, l'appareil de démonstration ne fabrique JAMAIS de numéro (ni compteur, ni journal d'émission). */
      var ad = adaptateurMecef();
      if (!ad.configure) return { ok: false, code: ad.code, motif: ad.motif, geste: ad.geste, nonConfigure: true };
      if (this.panne === 'refus') return { ok: false, code: 'REFUS_SIMULE', motif: 'Refus simulé par l’appareil de démonstration.' };
      if (this.panne === 'delai') return { ok: false, code: 'DELAI_DEPASSE', motif: 'Délai simulé dépassé : la facture non confirmée a expiré.', expiree: true };
      var nx = this.numeroSuivant();
      var et = this.etat();
      var emissions = (et.emissions || []).concat([{ cle: demande.cle, numero: nx.numero, compteur: nx.compteur, total: demande.total, base: demande.base,
        ifuAcheteur: demande.ifuAcheteur, nomAcheteur: demande.nomAcheteur, aibTaux: demande.aibTaux, aib: demande.aib, horodatage: new Date().toISOString() }]).slice(-500);
      S.setReglage('mecefBoitier', { compteur: nx.compteur, emissions: emissions });
      if (this.panne === 'reponse_perdue') return { ok: false, code: 'REPONSE_PERDUE', motif: 'La réponse de l’appareil de démonstration s’est perdue après l’émission.', perdue: true };
      return { ok: true, numero: nx.numero, compteur: nx.compteur, horodatage: emissions[emissions.length - 1].horodatage };
    },
    /** Lecture seule : ce que l'appareil a déjà émis pour cette vente (jamais une émission). */
    consulter: function (cle) {
      var tr = (this.etat().emissions || []).filter(function (x) { return x.cle === cle; });
      return tr.length ? tr[tr.length - 1] : null;
    },
  };

  /** Les lignes d'une pièce vues par la fonction des montants (la pièce garde ses montants : `montantBrut` ou `montant` gouverne). */
  function ligneVersMecef(l) {
    var o = { id: l.id, designation: l.designation, quantite: l.quantite != null ? l.quantite : 1, prixUnitaire: l.prixUnitaire,
      partAssureur: l.partAssureur || 0, partPersonnel: l.partPersonnel || 0, statutPaiement: l.statutPaiement };
    if (l.montantBrut != null) { o.montantBrut = l.montantBrut; o.remise = l.remise || 0; }
    else if (l.montant != null) { o.montantBrut = l.montant; o.remise = 0; }
    return o;
  }
  function entreeMontantsPiece(fac, aibTaux) {
    var lignes = (fac.lignes && fac.lignes.length) ? fac.lignes.map(ligneVersMecef)
      : [{ designation: 'Prestation', quantite: 1, montantBrut: fac.montantTTC, prixUnitaire: fac.montantTTC,
        partAssureur: fac.partAssurance || 0, partPersonnel: fac.partPersonnel || 0 }];
    return { lignes: lignes, totalAttendu: fac.montantTTC, aibTaux: aibTaux };
  }

  /** L'ACHETEUR d'une pièce : ce que la fenêtre a saisi, sinon ce que la pièce porte déjà, sinon les défauts (particulier, AIB par défaut). */
  function acheteurDePiece(fac, saisi) {
    var s = saisi || {};
    /* Ce que la pièce porte déjà (taux, situation, version, date du barème) est CONSERVÉ : un taux changé au barème depuis ne réécrit pas une vente émise. */
    var garde = s.aibTaux === undefined && s.aibSituation === undefined && fac.aibTaux != null;
    return validerAcheteurMecef({
      ifu: s.ifu !== undefined ? s.ifu : fac.ifuClient,
      nom: s.nom !== undefined ? s.nom : fac.acheteurNom,
      aibTaux: s.aibTaux !== undefined ? s.aibTaux : fac.aibTaux,
      aibSituation: s.aibSituation !== undefined ? s.aibSituation : (garde ? fac.aibSituation : undefined),
      aibVersion: garde ? fac.aibVersion : undefined, aibArrete: garde ? fac.aibArrete : undefined, aibDateBareme: garde ? fac.aibDateBareme : undefined,
      date: s.date, conserve: garde,
    });
  }

  /**
   * NORMALISER UNE VENTE (faux boîtier). Une vente déjà normalisée ne se renormalise JAMAIS ; un numéro déjà porté n'est jamais réécrit ;
   * l'état `en_attente` est ÉCRIT AVANT l'appel à l'appareil (un redémarrage reprend au bon endroit, PRD section 8) ; aucune
   * réponse perdue ne se rejoue toute seule (état `a_verifier`, décision humaine).
   * Retour : { ok: true, numero, etat } | { ignore: true } (mode désactivé) | { ok: false, code, motif, geste, etat }.
   */
  function normaliserVente(factureId, opts) {
    opts = opts || {};
    var fac = col('factures').get(factureId);
    if (!fac) return refusMecef('FACTURE_INTROUVABLE', 'La facture ' + factureId + ' n’existe pas.', 'Rouvrir la caisse et choisir une pièce du registre.');
    if (fac.proforma) return refusMecef('PROFORMA', 'Une pro-forma n’est pas une vente : elle ne se normalise pas.', 'Émettre la facture de vente.');
    if (!(fac.montantPaye > 0)) return refusMecef('VENTE_NON_ENCAISSEE', 'La facture ' + fac.numero + ' n’a encaissé aucun règlement : une vente se normalise à l’encaissement.', 'Encaisser la vente à la caisse.');
    if (modeMecef() === 'desactive') return { ok: true, ignore: true, motif: 'Mode « Désactivé » : aucune normalisation (démonstration).' };
    if (etatMecef(fac) === 'normalisee' && fac.numeroMecef) {
      return refusMecef('DEJA_NORMALISEE', 'La facture ' + fac.numero + ' est déjà normalisée (' + fac.numeroMecef + ') : elle ne se renormalise jamais.', 'La corriger par un avoir.');
    }
    var ach = acheteurDePiece(fac, opts.acheteur);
    if (!ach.ok) return ach;
    var acheteur = ach.acheteur;
    var entree = entreeMontantsPiece(fac, acheteur.aibTaux);
    var m = mecefMontants(entree);
    var bascule = Object.assign({ ifuClient: acheteur.ifu, acheteurNom: acheteur.nom, modeMecef: modeMecef(), mecefSimule: true }, traceAibAcheteur(acheteur));
    /* Un taux choisi à la main, autre que le défaut du barème pour cet acheteur, est JOURNALISÉ (RG-12). */
    if (acheteur.aibHorsDefaut) {
      S.log('AIB : taux choisi hors défaut', 'M8', 'facture', fac.numero, { defaut: acheteur.aibDefaut }, { aibTaux: acheteur.aibTaux, situation: acheteur.aibSituation, version: acheteur.aibVersion });
    }
    if (!m.ok) {
      col('factures').update(factureId, Object.assign({ statutMecef: 'rejete', codeRetour: m.code, motifRefusMecef: m.motif }, bascule));
      S.log('Normalisation refusée', 'MECEF', 'facture', fac.numero, { statutMecef: fac.statutMecef }, { code: m.code });
      return Object.assign({}, m, { etat: 'refusee' });
    }
    var aib = m.aib;
    /* L'état est écrit AVANT l'appel à l'appareil. */
    col('factures').update(factureId, Object.assign({ statutMecef: 'en_attente', codeRetour: null, motifRefusMecef: null }, bascule));
    /* Lot L3 : sans adaptateur configuré (e-MECeF), la vente RESTE en attente de certification, aucun numéro n'est fabriqué ; le refus se nomme. */
    var ad = adaptateurMecef();
    if (!ad.configure && !fac.numeroMecef) {
      col('factures').update(factureId, { statutMecef: 'en_attente', codeRetour: ad.code, motifRefusMecef: ad.motif });
      S.log('Normalisation en attente (adaptateur non configuré)', 'MECEF', 'facture', fac.numero, { statutMecef: fac.statutMecef }, { statutMecef: 'en_attente', code: ad.code, mode: ad.mode });
      return { ok: false, code: ad.code, motif: ad.motif, geste: ad.geste, etat: 'en_attente' };
    }
    var rep;
    if (fac.numeroMecef) {
      /* Un numéro déjà porté (pièce ancienne, ou réponse reconciliée) n'est JAMAIS réécrit : on ne rappelle pas l'appareil. */
      rep = { ok: true, numero: fac.numeroMecef, horodatage: new Date().toISOString(), repris: true };
    } else {
      rep = fauxBoitier.emettre({ cle: factureId, total: fac.montantTTC, base: m.base, ifuAcheteur: acheteur.ifu, nomAcheteur: acheteur.nom, aibTaux: acheteur.aibTaux, aib: aib });
    }
    if (rep.ok) {
      col('factures').update(factureId, { statutMecef: 'valide', numeroMecef: rep.numero, codeRetour: 'OK-200', dateTransmission: rep.horodatage,
        aibMontant: aib, normalisePar: opts.utilisateur || S.currentUser() });
      S.log('Normalisation', 'MECEF', 'facture', fac.numero, { statutMecef: 'en_attente' }, { statutMecef: 'valide', numero: rep.numero, mode: modeMecef() });
      return { ok: true, numero: rep.numero, etat: 'normalisee', repris: !!rep.repris };
    }
    var stocke = rep.perdue ? 'a_verifier' : (rep.expiree ? 'expiree' : 'rejete');
    col('factures').update(factureId, { statutMecef: stocke, codeRetour: rep.code, motifRefusMecef: rep.motif });
    S.log('Normalisation non aboutie', 'MECEF', 'facture', fac.numero, { statutMecef: 'en_attente' }, { statutMecef: stocke, code: rep.code });
    var geste = rep.perdue ? 'Vérifier auprès de l’appareil : « Reprendre sans doubler » ne rejoue jamais l’émission.'
      : (rep.expiree ? 'Renormaliser la vente.' : 'Corriger puis retransmettre la vente.');
    return { ok: false, code: rep.code, motif: rep.motif, geste: geste, etat: etatMecef({ statutMecef: stocke }) };
  }

  /** REPRISE SANS DOUBLON d'une vente `a_verifier` : on LIT l'appareil, on n'émet pas. Émission retrouvée (même vente, même total) :
   *  réconciliée, avec SON numéro. Rien d'émis : la vente repasse en attente (le renvoi reste un geste humain). Total différent : à vérifier. */
  function reprendreMecef(factureId) {
    var fac = col('factures').get(factureId);
    if (!fac) return refusMecef('FACTURE_INTROUVABLE', 'La facture ' + factureId + ' n’existe pas.', 'Choisir une pièce du registre.');
    if (etatMecef(fac) !== 'a_verifier') return refusMecef('PAS_A_VERIFIER', 'La facture ' + fac.numero + ' n’est pas à vérifier (état : ' + (etatMecef(fac) || '—') + ').', 'Seule une vente « À vérifier » se reprend.');
    var em = fauxBoitier.consulter(factureId);
    if (!em) {
      col('factures').update(factureId, { statutMecef: 'en_attente', codeRetour: 'NON_EMISE', motifRefusMecef: 'L’appareil n’a rien émis pour cette vente.' });
      S.log('Reprise MECeF', 'MECEF', 'facture', fac.numero, { statutMecef: 'a_verifier' }, { statutMecef: 'en_attente', code: 'NON_EMISE' });
      return { ok: true, reconcilie: false, etat: 'en_attente', motif: 'Rien n’a été émis : la vente peut être renormalisée.' };
    }
    if (em.total !== fac.montantTTC) {
      return refusMecef('DIVERGENCE', 'L’appareil a émis ' + em.numero + ' pour un total de ' + em.total + ' alors que la pièce vaut ' + fac.montantTTC + '.', 'Ne pas renvoyer : en référer à la DA.');
    }
    col('factures').update(factureId, { statutMecef: 'valide', numeroMecef: em.numero, codeRetour: 'OK-200', dateTransmission: em.horodatage,
      aibMontant: em.aib, reconcilie: true, motifRefusMecef: null });
    S.log('Reprise MECeF', 'MECEF', 'facture', fac.numero, { statutMecef: 'a_verifier' }, { statutMecef: 'valide', numero: em.numero });
    return { ok: true, reconcilie: true, numero: em.numero, etat: 'normalisee' };
  }

  /** RETRANSMETTRE une vente refusée ou expirée (PRD section 7, Q7) : le caissier UNE fois, puis la DA ; jamais une vente normalisée. */
  function retransmettreMecef(factureId, opts) {
    var fac = col('factures').get(factureId);
    if (!fac) return refusMecef('FACTURE_INTROUVABLE', 'La facture ' + factureId + ' n’existe pas.', 'Choisir une pièce du registre.');
    var etat = etatMecef(fac);
    if (etat === 'normalisee') return refusMecef('DEJA_NORMALISEE', 'La facture ' + fac.numero + ' est déjà normalisée (' + fac.numeroMecef + ') : elle ne se retransmet jamais.', 'La corriger par un avoir.');
    if (['refusee', 'expiree', 'en_attente'].indexOf(etat) < 0) return refusMecef('PAS_RETRANSMISSIBLE', 'La facture ' + fac.numero + ' est à vérifier : elle se reprend sans doubler, elle ne se retransmet pas.', 'Utiliser « Reprendre sans doubler ».');
    var role = roleCourant();
    var deja = fac.retransmissions || 0;
    if (role === 'caissier' && deja >= 1) return refusMecef('RETRANSMISSION_RESERVEE', 'Le caissier ne retransmet qu’une fois : la facture ' + fac.numero + ' l’a déjà été.', 'Demander la retransmission à la Directrice Administrative.');
    if (['caissier', 'da', 'admin'].indexOf(role) < 0) return refusMecef('RETRANSMISSION_INTERDITE', 'La retransmission est réservée au caissier (une fois) et à la Directrice Administrative.', 'Demander à la caisse ou à la DA.');
    /* Lot L3 : sans adaptateur configuré, la retransmission n'émet rien et ne consomme PAS l'unique essai du caissier. */
    if (etat !== 'en_attente' && adaptateurMecef().configure) col('factures').update(factureId, { retransmissions: deja + 1 });
    return normaliserVente(factureId, opts);
  }

  global.SIGH.mecefMontants = mecefMontants;
  global.SIGH.mecef = {
    ETATS: ETATS_MECEF, MODES: MODES_MECEF,
    etat: etatMecef, fiche: etatMecefFiche,
    montants: mecefMontants, validerAcheteur: validerAcheteurMecef, aibTauxDefaut: aibTauxDefaut, tauxPropose: tauxAibProposes, traceAibAcheteur: traceAibAcheteur,
    mode: modeMecef, definirMode: definirModeMecef, adaptateur: adaptateurMecef, CODE_NON_CONFIGURE: CODE_NON_CONFIGURE,
    MODES_PROPOSES: ['boitier', 'emecef'],
    normaliser: normaliserVente, reprendre: reprendreMecef, retransmettre: retransmettreMecef,
    fauxBoitier: fauxBoitier, numeroSuivant: function () { return fauxBoitier.numeroSuivant(); },
  };
  global.SIGH.parcours.mecef = global.SIGH.mecef;

  /* ==========================================================================
   * RH, LOT L4 (10/11/2026) : LE RÉGIME INDIVIDUEL DÉROGE CHAMP PAR CHAMP, LE RESTE SUIT LA CATÉGORIE
   * --------------------------------------------------------------------------
   * Décision de la Direction du 09/11/2026 (Planning Q1) : le régime de la catégorie reste la règle ; le régime INDIVIDUEL d'un agent (vacations,
   * repos, cycle, honoraire) ne déroge que sur les champs RENSEIGNÉS, tous les autres suivent la catégorie. Deux médecins peuvent donc avoir des gardes
   * différentes sans toucher à leurs collègues. Le contrôle d'incompatibilité (repos obligatoire après une garde) s'applique à TOUTE saisie, quelle que
   * soit la voie (grille, rotation, proposition validée, application directe) : il vit ICI, une seule fois.
   *
   * UNE DÉROGATION SE VERSIONNE PAR DATE, ELLE NE SE RÉÉCRIT JAMAIS (même principe que la grille des primes, les plages par lot et le barème AIB) : une
   * fiche immuable par version (collection `regimesIndividuels`), la valeur en vigueur à une date est une fonction pure des fiches. « Revenir au régime de
   * la catégorie » est une VERSION (`retourCategorie`), pas une suppression. Une vacation porte le régime sous lequel elle a été posée (`regimeLibelle`,
   * `derogations`) : relever une dérogation ne change jamais une vacation passée.
   * ======================================================================== */
  var CHAMPS_DEROGEABLES = [
    { cle: 'vacations', libelle: 'Vacations du régime' },
    { cle: 'repos', libelle: 'Repos appliqué' },
    { cle: 'cycle', libelle: 'Cycle (jours)' },
    { cle: 'honoraire', libelle: 'Honoraire (FCFA)' },
    { cle: 'honorairePeriodicite', libelle: 'Périodicité de l’honoraire' },
  ];
  var VACATIONS_GARDE_RH = ['garde', 'garde_hospi'];
  function refusRh(code, motif, geste, extra) { return Object.assign({ ok: false, code: code, motif: motif, geste: geste }, extra || {}); }
  function colRegimesInd() { return S.collection('regimesIndividuels', { module: 'M10', entite: 'régime individuel', prefix: 'RGI' }); }
  function colPlanningRh() { return S.collection('planning', { module: 'M10', entite: 'Planning' }); }
  function employeRh(id) { return S.collection('personnel').get(id) || null; }
  /** L'agent de la session, retrouvé par son nom : la session ne porte pas d'identifiant de personnel. */
  function employeDeSession() {
    var nom = acteur();
    return S.collection('personnel').active().filter(function (e) { return e.nomComplet === nom; })[0] || null;
  }
  function typePlanning(id) { return (D.TYPES_PLANNING || []).filter(function (t) { return t.id === id; })[0] || null; }
  function libelleType(id) { var t = typePlanning(id); return t ? t.label : id; }

  /** Le régime de la CATÉGORIE : celui du magasin (modifiable), à défaut la règle relevée sur les plannings. */
  function regimeCategorieRh(fonction) {
    var r = S.collection('regimesTravail').active().filter(function (x) { return (x.fonctions || []).indexOf(fonction) !== -1; })[0];
    return r || D.regleDe(fonction) || null;
  }
  function versionsRegimeInd(employeId) {
    return colRegimesInd().active().filter(function (v) { return v.employeId === employeId; })
      .sort(function (a, b) { return String(a.dateEffet).localeCompare(String(b.dateEffet)); });
  }
  function champRenseigne(x) { return x !== undefined && x !== null && x !== '' && !(Array.isArray(x) && !x.length); }

  /** LE RÉGIME EN VIGUEUR POUR UN AGENT À UNE DATE : la catégorie, puis les champs dérogés de la dernière version à date d'effet atteinte. */
  function regimeALaDate(employeId, fonction, date) {
    var d = date ? isoJour(date) : aujIso();
    var base = regimeCategorieRh(fonction);
    var out = {
      date: d, categorie: base ? base.libelle : null, libelle: base ? base.libelle : null, fonctions: base ? (base.fonctions || []).slice() : [],
      vacations: base ? (base.vacations || []).slice() : [], repos: base ? (base.repos || null) : null, cycle: base ? base.cycle : null,
      honoraire: base ? (base.honoraire || null) : null, honorairePeriodicite: base ? (base.honorairePeriodicite || null) : null,
      source: base ? (base.source || null) : null, mention: base ? (base.mention || null) : null,
      individuel: false, derogations: [], versionId: null, dateEffet: null,
    };
    var v = versionsRegimeInd(employeId).filter(function (x) { return String(x.dateEffet) <= d; }).pop();
    if (!v) return out;
    out.versionId = v.id; out.dateEffet = v.dateEffet;
    if (v.retourCategorie) return out;
    CHAMPS_DEROGEABLES.forEach(function (c) {
      var x = v.champs ? v.champs[c.cle] : undefined;
      if (!champRenseigne(x)) return;
      out[c.cle] = c.cle === 'vacations' ? x.slice() : (c.cle === 'repos' && x === 'aucun' ? null : x);
      out.derogations.push(c.cle);
    });
    out.individuel = out.derogations.length > 0;
    return out;
  }
  /** L'historique d'un agent, version par version, avec le motif et l'auteur. */
  function historiqueRegimeInd(employeId) {
    return versionsRegimeInd(employeId).map(function (v, i) {
      return { id: v.id, version: i + 1, dateEffet: v.dateEffet, retourCategorie: v.retourCategorie === true, champs: JSON.parse(JSON.stringify(v.champs || {})),
        motif: v.motif, creePar: v.creePar, creeLe: v.creeLe };
    });
  }
  /** Les types de vacation qu'un agent peut recevoir à une date : ceux de son régime, le repos, et congé, absence, remplacement. */
  function typesAutorisesRh(employeId, fonction, date) {
    var r = regimeALaDate(employeId, fonction, date);
    if (!r.categorie && !r.individuel) return (D.TYPES_PLANNING || []).map(function (t) { return t.id; });
    return r.vacations.concat([r.repos, 'conge', 'absence', 'remplacement'].filter(Boolean));
  }

  /** POSER UNE DÉROGATION (ou le retour à la catégorie). Réservé à l'administrateur et à la Directrice Administrative : un honoraire et un repos
   *  engagent la paie et la santé de l'agent. */
  function derogerRegime(o) {
    o = o || {};
    if (['admin', 'da'].indexOf(roleCourant()) < 0) return refusRh('DEROGATION_RESERVEE', 'Le régime individuel se règle par la Directrice Administrative ou l’administrateur.', 'Demander à la Directrice Administrative de poser la dérogation.');
    var e = employeRh(o.employeId);
    if (!e) return refusRh('AGENT_INTROUVABLE', 'L’agent désigné n’existe pas au personnel.', 'Choisir un agent du personnel.');
    var dateEffet = o.dateEffet ? isoJour(o.dateEffet) : '';
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateEffet)) return refusRh('DATE_INVALIDE', 'La date d’effet est absente ou illisible.', 'Choisir la date à partir de laquelle la dérogation s’applique.');
    if (!String(o.motif || '').trim()) return refusRh('MOTIF_OBLIGATOIRE', 'Le motif de la dérogation est obligatoire.', 'Dire pourquoi le régime de cet agent diffère de celui de sa catégorie.');
    if (dateEffet < aujIso()) return refusRh('DATE_PASSEE', 'La date d’effet (' + C.dateFR(dateEffet) + ') est antérieure à aujourd’hui : une dérogation ne s’applique jamais rétroactivement.',
      'Choisir aujourd’hui ou une date à venir. Les vacations passées gardent le régime sous lequel elles ont été posées.');
    var retour = o.retourCategorie === true;
    var champs = {};
    if (!retour) {
      var c = o.champs || {};
      var vac = c.vacations;
      if (champRenseigne(vac)) {
        var admises = (D.TYPES_PLANNING || []).filter(function (t) { return t.duree > 0; }).map(function (t) { return t.id; });
        if (!Array.isArray(vac) || vac.some(function (x) { return admises.indexOf(x) < 0; })) return refusRh('CHAMP_INVALIDE', 'Les vacations proposées ne sont pas toutes des vacations travaillées du référentiel.', 'Choisir parmi les types de vacation du référentiel.', { champ: 'vacations' });
        champs.vacations = vac.slice();
      }
      if (champRenseigne(c.repos)) {
        if (['repos24', 'repos48', 'aucun'].indexOf(c.repos) < 0) return refusRh('CHAMP_INVALIDE', 'Le repos « ' + c.repos + ' » n’existe pas.', 'Choisir repos de 24 h, repos de 48 h ou aucun repos codifié.', { champ: 'repos' });
        champs.repos = c.repos;
      }
      if (champRenseigne(c.cycle)) {
        var cy = Number(c.cycle);
        if (!(cy >= 1) || Math.floor(cy) !== cy) return refusRh('CHAMP_INVALIDE', 'Le cycle doit être un nombre entier de jours, au moins 1.', 'Corriger le cycle.', { champ: 'cycle' });
        champs.cycle = cy;
      }
      if (champRenseigne(c.honoraire)) {
        var h = Number(c.honoraire);
        if (!(h >= 0)) return refusRh('CHAMP_INVALIDE', 'L’honoraire doit être un montant positif ou nul.', 'Corriger l’honoraire.', { champ: 'honoraire' });
        champs.honoraire = h;
      }
      if (champRenseigne(c.honorairePeriodicite)) {
        if (['mensuelle', 'occurrence'].indexOf(c.honorairePeriodicite) < 0) return refusRh('CHAMP_INVALIDE', 'La périodicité de l’honoraire est mensuelle ou par occurrence.', 'Corriger la périodicité.', { champ: 'honorairePeriodicite' });
        champs.honorairePeriodicite = c.honorairePeriodicite;
      }
      if (!Object.keys(champs).length) return refusRh('AUCUNE_DEROGATION', 'Aucun champ n’est dérogé : le régime de l’agent suit déjà celui de sa catégorie.', 'Renseigner au moins un champ, ou choisir « revenir au régime de la catégorie ».');
    }
    var existantes = versionsRegimeInd(e.id);
    var derniere = existantes[existantes.length - 1] || null;
    if (existantes.some(function (v) { return String(v.dateEffet) === dateEffet; })) return refusRh('DATE_EXISTANTE', 'Une version commence déjà le ' + C.dateFR(dateEffet) + ' pour cet agent : une version ne se réécrit pas.', 'Choisir une date d’effet postérieure.');
    if (derniere && String(derniere.dateEffet) > dateEffet) return refusRh('VERSION_ANTERIEURE', 'La version la plus récente de cet agent commence le ' + C.dateFR(derniere.dateEffet) + ' : une version insérée avant elle masquerait l’historique.', 'Choisir une date d’effet postérieure à la dernière version.');
    var avant = regimeALaDate(e.id, e.fonction, dateEffet);
    var res = colRegimesInd().insert({
      employeId: e.id, employe: e.nomComplet, matricule: e.matricule, fonction: e.fonction, categorie: avant.categorie,
      champs: champs, retourCategorie: retour, dateEffet: dateEffet, motif: String(o.motif).trim(), version: existantes.length + 1, creeLe: aujIso(), creePar: acteur(),
    }, { journal: { action: retour ? 'Régime individuel : retour à la catégorie' : 'Régime individuel : dérogation posée', module: 'M10', entite: 'regimesIndividuels',
      avant: { derogations: avant.derogations, dateEffet: avant.dateEffet }, apres: { champs: champs, retourCategorie: retour, dateEffet: dateEffet, motif: String(o.motif).trim() } } });
    if (!res) return refusRh('ECRITURE_REFUSEE', 'L’écriture a été refusée par le magasin.', 'Relire le journal.');
    return { ok: true, id: res.record.id, version: existantes.length + 1, dateEffet: dateEffet, derogations: Object.keys(champs), retourCategorie: retour, undo: res.undo };
  }
  S.garder('regimesIndividuels', function (op) {
    if (op === 'modifier' || op === 'archiver') return 'REGIME_INDIVIDUEL_FIGE : une version de régime individuel ne se réécrit ni ne s’archive (elle explique des vacations déjà posées). Ajouter une nouvelle version à une date d’effet postérieure, ou « revenir au régime de la catégorie ».';
    return null;
  });

  /** LE CONTRÔLE D'INCOMPATIBILITÉ, UNE SEULE FOIS : le repos qui suit une garde (durée du régime EN VIGUEUR À LA DATE, dérogation comprise), avant comme après,
   *  et la double affectation. `ignoreId` : la vacation qu'on remplace ou qu'on déplace. */
  function controlerVacationRh(o) {
    var e = employeRh(o.employeId);
    if (!e) return refusRh('AGENT_INTROUVABLE', 'L’agent désigné n’existe pas au personnel.', 'Choisir un agent du personnel.');
    var d = isoJour(o.date);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return refusRh('DATE_INVALIDE', 'La date de la vacation est absente ou illisible.', 'Choisir une date.');
    if (!typePlanning(o.type)) return refusRh('TYPE_INCONNU', 'Le type de vacation « ' + o.type + ' » n’existe pas.', 'Choisir un type du référentiel.');
    var regime = regimeALaDate(e.id, e.fonction, d);
    var autres = colPlanningRh().active().filter(function (p) { return p.employeId === e.id && p.id !== o.ignoreId; });
    var memeJour = autres.filter(function (p) { return p.date === d; })[0];
    if (memeJour) return refusRh('DOUBLE_AFFECTATION', e.nomComplet + ' a déjà une vacation le ' + C.dateFR(d) + ' (' + libelleType(memeJour.type) + ').', 'Modifier la vacation existante, ou choisir un autre jour.', { date: d, existante: memeJour.id });
    if (VACATIONS_GARDE_RH.indexOf(o.type) >= 0) {
      var joursRepos = regime.repos === 'repos48' ? 2 : 1;
      for (var k = 1; k <= joursRepos; k++) {
        var veille = autres.filter(function (p) { return p.date === C.iso(C.addDays(d, -k)) && VACATIONS_GARDE_RH.indexOf(p.type) >= 0; })[0];
        if (veille) return refusRh('INCOMPATIBILITE_REPOS', 'Incompatibilité : le repos de ' + (joursRepos * 24) + ' h qui suit une garde n’est pas respecté (garde déjà programmée le ' + C.dateFR(veille.date) + ' pour ' + e.nomComplet + ').',
          'Choisir un jour après le repos de ' + (joursRepos * 24) + ' h, ou retirer l’autre garde.', { date: d, autre: veille.id, reposHeures: joursRepos * 24, individuel: regime.individuel });
        var lendemain = autres.filter(function (p) { return p.date === C.iso(C.addDays(d, k)) && VACATIONS_GARDE_RH.indexOf(p.type) >= 0; })[0];
        if (lendemain) return refusRh('INCOMPATIBILITE_REPOS', 'Incompatibilité : le repos de ' + (joursRepos * 24) + ' h qui suivrait cette garde serait entamé par la garde déjà programmée le ' + C.dateFR(lendemain.date) + ' pour ' + e.nomComplet + '.',
          'Choisir un autre jour, ou retirer l’autre garde.', { date: d, autre: lendemain.id, reposHeures: joursRepos * 24, individuel: regime.individuel });
      }
    }
    return { ok: true, regime: regime, agent: e.id };
  }
  /** Ce qu'une vacation porte à l'écriture : l'agent, le régime sous lequel elle est posée (jamais réécrit ensuite). */
  function fabriquerVacationRh(o, regime, e, extra) {
    return Object.assign({
      date: isoJour(o.date), employeId: e.id, employe: e.nomComplet, fonction: e.fonction, service: e.service, type: o.type, observation: o.observation || null,
      statut: 'validee', regimeLibelle: regime.categorie || null, regimeIndividuelId: regime.versionId, derogations: regime.derogations.slice(),
    }, extra || {});
  }
  /** POSER OU REMPLACER une vacation depuis le poste : DAF, surveillant (ou administrateur). Écrite VALIDÉE (celui qui la pose est celui qui valide). */
  function poserVacationRh(o) {
    o = o || {};
    if (['admin', 'da', 'surveillant'].indexOf(roleCourant()) < 0) return refusRh('PLANNING_RESERVE', 'Le planning du personnel se pose par le surveillant ou la Directrice Administrative.', 'Un agent propose ses vacations (propositions de planning) ; le surveillant valide.');
    var ctrl = controlerVacationRh({ employeId: o.employeId, date: o.date, type: o.type, ignoreId: o.existantId });
    if (!ctrl.ok) return ctrl;
    var e = employeRh(o.employeId);
    var rec = fabriquerVacationRh(o, ctrl.regime, e, { validationEtat: 'validee', validePar: acteur(), valideLe: aujIso(), origine: 'poste' });
    var res = o.existantId ? colPlanningRh().update(o.existantId, rec) : colPlanningRh().insert(rec);
    if (!res) return refusRh('ECRITURE_REFUSEE', 'L’écriture a été refusée par le magasin.', 'Relire le journal.');
    return { ok: true, id: o.existantId || res.record.id, regime: ctrl.regime, undo: res.undo };
  }
  function retirerVacationRh(id, motif) {
    if (['admin', 'da', 'surveillant'].indexOf(roleCourant()) < 0) return refusRh('PLANNING_RESERVE', 'Le planning du personnel se retire par le surveillant ou la Directrice Administrative.', 'Demander au surveillant.');
    var v = colPlanningRh().get(id);
    if (!v || v.statut === 'archive') return refusRh('VACATION_INTROUVABLE', 'La vacation ' + id + ' n’existe pas ou est déjà retirée.', 'Choisir une vacation du registre.');
    var res = colPlanningRh().archive(id, motif || 'Vacation retirée');
    return { ok: true, id: id, undo: res && res.undo };
  }

  /* ==========================================================================
   * RH, LOT L5 (10/11/2026) : LE CIRCUIT DE VALIDATION DES PRÉSENCES, ABSENCES, CONGÉS ET ORDRES DE MISSION
   * --------------------------------------------------------------------------
   * Décision de la Direction du 09/11/2026 (Planning Q2 et Q3, la remarque l'emporte sur la case) : le SURVEILLANT valide les présences et absences de tout
   * le personnel et PEUT VALIDER SEUL. Le circuit est un réglage du poste, enregistré en base, avec son défaut : « surveillant seul » (défaut), « directrice
   * administrative seule », « surveillant puis directrice administrative ». Les congés et les ordres de mission suivent le même circuit ; la mission porte en
   * plus l'AVIS du chef de service. La DAF garde son droit d'écran.
   *
   * UNE PIÈCE NON VALIDÉE EST VISIBLE ET NE COMPTE PAS (RG-11, RG-12) : les lectures qui comptent passent par `compte()`. Les pièces d'AVANT le circuit (sans
   * `validationEtat`) sont lues d'après leur état d'origine (congé : `statutConge`, mission : `statutMission`, présence : validée) : ni les dire non validées
   * ni les dire validées toutes serait vrai. Le circuit en vigueur est lu à chaque geste ; la pièce tranchée note celui qui l'a tranchée (`circuitUtilise`) :
   * changer de circuit ne rouvre jamais une pièce déjà tranchée (une pièce à mi-circuit se complète au prochain geste habilité).
   * LE CIRCUIT SE TIENT AU MOTEUR, pas à l'écran : refus nommé VALIDATION_RESERVEE pour un rôle qui n'est pas l'étape attendue.
   * ======================================================================== */
  var CIRCUITS_PRESENCES = [
    { id: 'surveillant', libelle: 'Surveillant seul', etapes: ['surveillant'] },
    { id: 'daf', libelle: 'Directrice administrative seule', etapes: ['daf'] },
    { id: 'surveillant_puis_daf', libelle: 'Surveillant puis directrice administrative', etapes: ['surveillant', 'daf'] },
  ];
  var ROLES_ETAPE = { surveillant: ['surveillant', 'admin'], daf: ['da', 'admin'] };
  var NOM_ETAPE = { surveillant: 'le surveillant', daf: 'la directrice administrative' };
  var PIECES_RH = {
    presences: { meta: { module: 'M10', entite: 'Presence' }, nom: 'pointage', agent: 'employeId' },
    conges: { meta: { module: 'M10', entite: 'Conge' }, nom: 'demande de congé', agent: 'employeId' },
    missions: { meta: { module: 'M10', entite: 'Ordre de mission' }, nom: 'ordre de mission', agent: 'agentId' },
  };
  function circuitPresencesRh() {
    var c = S.reglage('planningCircuitPresences', 'surveillant');
    return CIRCUITS_PRESENCES.filter(function (x) { return x.id === c; })[0] ? c : 'surveillant';
  }
  function etapesDuCircuitRh(id) { return (CIRCUITS_PRESENCES.filter(function (x) { return x.id === (id || circuitPresencesRh()); })[0] || CIRCUITS_PRESENCES[0]).etapes.slice(); }
  function definirCircuitRh(id, motif) {
    if (['admin', 'da'].indexOf(roleCourant()) < 0) return refusRh('REGLAGE_RESERVE', 'Le circuit de validation se règle par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
    if (!CIRCUITS_PRESENCES.some(function (x) { return x.id === id; })) return refusRh('CIRCUIT_INCONNU', 'Le circuit « ' + id + ' » n’existe pas.', 'Choisir surveillant seul, directrice administrative seule, ou surveillant puis directrice administrative.');
    var avant = circuitPresencesRh();
    S.setReglage('planningCircuitPresences', id);
    S.log('Circuit de validation des présences', 'M10', 'reglage', 'planningCircuitPresences', { circuit: avant }, { circuit: id, motif: motif || null });
    return { ok: true, circuit: id, avant: avant };
  }
  function agentModifieDirectementRh() { return S.reglage('planningAgentModifieDirectement', false) === true; }
  function definirAgentDirectRh(oui) {
    if (['admin', 'da'].indexOf(roleCourant()) < 0) return refusRh('REGLAGE_RESERVE', 'Ce réglage se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
    var avant = agentModifieDirectementRh();
    S.setReglage('planningAgentModifieDirectement', oui === true);
    S.log('Planning : l’agent modifie directement', 'M10', 'reglage', 'planningAgentModifieDirectement', { valeur: avant }, { valeur: oui === true });
    return { ok: true, valeur: oui === true, avant: avant };
  }

  /** L'état de validation d'une pièce : a_valider, valide_surveillant, valide, refuse. */
  function etatValidationRh(nom, rec) {
    if (!rec) return null;
    if (rec.validationEtat) return rec.validationEtat;
    if (nom === 'conges') return { en_attente: 'a_valider', refuse: 'refuse' }[rec.statutConge] || 'valide';
    if (nom === 'missions') return (rec.statutMission === 'a_valider' || rec.statutMission === 'projet') ? 'a_valider' : (rec.statutMission === 'refusee' ? 'refuse' : 'valide');
    return 'valide';
  }
  /** Une pièce COMPTE (primes, évaluation, taux de présence, soldes) seulement validée. */
  function compteRh(nom, rec) { return etatValidationRh(nom, rec) === 'valide'; }
  function prochaineEtapeRh(rec) {
    var faites = (rec.etapesFaites || []).filter(function (x) { return x.decision !== 'refuse'; }).map(function (x) { return x.etape; });
    return etapesDuCircuitRh().filter(function (e) { return faites.indexOf(e) < 0; })[0] || null;
  }
  /** Le rôle courant peut-il trancher CETTE pièce ? { ok, etape } ou le refus nommé. */
  function peutTrancherRh(nom, rec) {
    var def = PIECES_RH[nom];
    if (!def) return refusRh('COLLECTION_INCONNUE', 'La collection « ' + nom + ' » ne passe pas par le circuit de validation.', 'Choisir pointage, congé ou ordre de mission.');
    if (!rec || rec.statut === 'archive') return refusRh('PIECE_INTROUVABLE', 'La pièce n’existe pas ou est archivée.', 'Choisir une ligne du registre.');
    var etat = etatValidationRh(nom, rec);
    if (etat === 'valide' || etat === 'refuse') return refusRh('DEJA_TRANCHEE', 'Cette pièce est déjà ' + (etat === 'valide' ? 'validée' : 'refusée') + ' : une décision ne se réécrit pas.', nom === 'presences' ? 'Pour corriger un pointage validé, le régulariser (motif, date et auteur consignés).' : 'Saisir une nouvelle demande.');
    var etapes = etapesDuCircuitRh();
    var etape = prochaineEtapeRh(rec) || etapes[etapes.length - 1];
    if (ROLES_ETAPE[etape].indexOf(roleCourant()) < 0) {
      return refusRh('VALIDATION_RESERVEE', 'L’étape en attente est celle de ' + NOM_ETAPE[etape] + ' (circuit : ' + CIRCUITS_PRESENCES.filter(function (x) { return x.id === circuitPresencesRh(); })[0].libelle + ').',
        'Demander à ' + NOM_ETAPE[etape] + ' de trancher.', { etape: etape });
    }
    var moi = employeDeSession();
    if (moi && String(rec[def.agent]) === String(moi.id)) return refusRh('AUTO_VALIDATION', 'Personne ne valide sa propre pièce : ' + def.nom + ' de ' + moi.nomComplet + '.', 'Demander à un autre habilité de trancher.');
    if ((rec.etapesFaites || []).some(function (x) { return x.par === acteur() && x.decision !== 'refuse'; })) {
      return refusRh('ETAPE_DEJA_SIGNEE', 'Vous avez déjà signé une étape de cette pièce : deux étapes ne se signent pas par la même personne.', 'Demander à ' + NOM_ETAPE[etape] + ' de trancher.');
    }
    return { ok: true, etape: etape };
  }
  /** L'AVIS DU CHEF DE SERVICE sur un ordre de mission : consigné par un habilité du circuit, lu à la validation. */
  function avisMissionRh(id, o) {
    o = o || {};
    var c = S.collection('missions', PIECES_RH.missions.meta), rec = c.get(id);
    if (!rec || rec.statut === 'archive') return refusRh('PIECE_INTROUVABLE', 'L’ordre de mission n’existe pas ou est archivé.', 'Choisir une ligne du registre.');
    if (['surveillant', 'da', 'admin'].indexOf(roleCourant()) < 0) return refusRh('AVIS_RESERVE', 'L’avis du chef de service se consigne par le surveillant, la Directrice Administrative ou l’administrateur.', 'Demander au surveillant.');
    if (['favorable', 'defavorable'].indexOf(o.avis) < 0) return refusRh('AVIS_INCONNU', 'L’avis est « favorable » ou « défavorable ».', 'Choisir l’avis.');
    var chef = String(o.chef || '').trim();
    if (!chef) return refusRh('CHEF_ABSENT', 'Le nom du chef de service qui donne l’avis est obligatoire.', 'Choisir le chef de service de l’agent.');
    if (o.avis === 'defavorable' && !String(o.motif || '').trim()) return refusRh('MOTIF_OBLIGATOIRE', 'Un avis défavorable exige son motif.', 'Dire pourquoi l’avis est défavorable.');
    if (['valide', 'refuse'].indexOf(etatValidationRh('missions', rec)) >= 0) return refusRh('DEJA_TRANCHEE', 'L’ordre de mission est déjà tranché : l’avis se donne avant la décision.', 'Saisir un nouvel ordre.');
    var res = c.update(id, { avisChefService: { avis: o.avis, chef: chef, motif: String(o.motif || '').trim() || null, le: aujIso(), consignePar: acteur() } },
      { journal: { action: 'Avis du chef de service sur un ordre de mission', module: 'M10', entite: 'Ordre de mission', avant: { avis: rec.avisChefService || null }, apres: { avis: o.avis, chef: chef, motif: o.motif || null } } });
    return { ok: true, avis: o.avis, undo: res && res.undo };
  }
  /** TRANCHER une pièce : valider (étape par étape selon le circuit) ou refuser (motif obligatoire). */
  function trancherPieceRh(o) {
    o = o || {};
    var def = PIECES_RH[o.collection];
    if (!def) return refusRh('COLLECTION_INCONNUE', 'La collection « ' + o.collection + ' » ne passe pas par le circuit de validation.', 'Choisir pointage, congé ou ordre de mission.');
    var c = S.collection(o.collection, def.meta), rec = c.get(o.id);
    if (['valider', 'refuser'].indexOf(o.decision) < 0) return refusRh('DECISION_INCONNUE', 'La décision est « valider » ou « refuser ».', 'Choisir une décision.');
    var p = peutTrancherRh(o.collection, rec);
    if (!p.ok) return p;
    var motif = String(o.motif || '').trim();
    if (o.decision === 'refuser' && !motif) return refusRh('MOTIF_OBLIGATOIRE', 'Un refus exige son motif : l’agent doit pouvoir le lire.', 'Écrire le motif du refus.');
    if (o.collection === 'missions') {
      if (rec.statutMission === 'projet') return refusRh('PAS_SOUMISE', 'L’ordre est encore en projet : il n’a pas été soumis à validation.', 'Le soumettre d’abord (état « en attente de validation »).');
      if (o.decision === 'valider') {
        if (!rec.avisChefService) return refusRh('AVIS_REQUIS', 'L’avis du chef de service est requis avant la validation d’un ordre de mission.', 'Consigner l’avis du chef de service, puis valider.');
        if (rec.avisChefService.avis === 'defavorable' && !motif) return refusRh('MOTIF_OBLIGATOIRE', 'Valider contre un avis défavorable exige un motif.', 'Écrire pourquoi la mission est validée malgré l’avis.');
      }
    }
    var trace = { etape: p.etape, par: acteur(), role: roleCourant(), le: aujIso(), decision: o.decision === 'valider' ? 'valide' : 'refuse', motif: motif || null };
    var etapes = (rec.etapesFaites || []).concat([trace]);
    var patch = { etapesFaites: etapes };
    var etatApres;
    if (o.decision === 'refuser') {
      etatApres = 'refuse';
      patch.validationEtat = 'refuse'; patch.motifRefus = motif; patch.refuseePar = acteur(); patch.refuseeLe = aujIso(); patch.circuitUtilise = circuitPresencesRh();
      if (o.collection === 'conges') patch.statutConge = 'refuse';
      if (o.collection === 'missions') patch.statutMission = 'refusee';
    } else {
      var faites = etapes.filter(function (x) { return x.decision === 'valide'; }).map(function (x) { return x.etape; });
      var restantes = etapesDuCircuitRh().filter(function (e) { return faites.indexOf(e) < 0; });
      if (restantes.length) {
        etatApres = 'valide_surveillant';
        patch.validationEtat = 'valide_surveillant';
      } else {
        etatApres = 'valide';
        patch.validationEtat = 'valide'; patch.validePar = acteur(); patch.valideLe = aujIso(); patch.circuitUtilise = circuitPresencesRh();
        if (o.collection === 'conges') patch.statutConge = 'valide';
        if (o.collection === 'missions') { patch.statutMission = 'validee'; patch.valideePar = acteur(); patch.valideeLe = aujIso(); }
      }
    }
    var res = c.update(o.id, patch, { journal: { action: o.decision === 'valider' ? 'Validation d’un ' + def.nom : 'Refus d’un ' + def.nom, module: 'M10', entite: def.meta.entite,
      avant: { etat: etatValidationRh(o.collection, rec) }, apres: { etat: etatApres, etape: p.etape, circuit: circuitPresencesRh(), motif: motif || null } } });
    if (!res) return refusRh('ECRITURE_REFUSEE', 'L’écriture a été refusée par le magasin.', 'Relire le journal.');
    return { ok: true, etat: etatApres, etape: p.etape, circuit: circuitPresencesRh(), complet: etatApres === 'valide', undo: res.undo };
  }
  /** Une pièce NAÎT à valider : l'état est posé à la création par la porte d'écriture de l'écran. */
  function naissanceRh() { return { validationEtat: 'a_valider', etapesFaites: [], saisiPar: acteur(), saisiLe: aujIso() }; }

  /** RÉGULARISER un pointage : correction DATÉE, avec auteur et motif obligatoire, réservée aux habilités du circuit (la pièce reste validée). */
  var MOTIFS_ABSENCE = [
    { id: 'maladie', libelle: 'Maladie' }, { id: 'mission', libelle: 'Mission' }, { id: 'conge', libelle: 'Congé' },
  ];
  function regulariserPresenceRh(id, o) {
    o = o || {};
    var c = S.collection('presences', PIECES_RH.presences.meta), rec = c.get(id);
    if (!rec || rec.statut === 'archive') return refusRh('PIECE_INTROUVABLE', 'Le pointage n’existe pas ou est archivé.', 'Choisir une ligne du registre.');
    if (['surveillant', 'da', 'admin'].indexOf(roleCourant()) < 0) return refusRh('REGULARISATION_RESERVEE', 'La régularisation d’un pointage se fait par le surveillant ou la Directrice Administrative.', 'Demander au surveillant.');
    if (!String(o.motif || '').trim()) return refusRh('MOTIF_OBLIGATOIRE', 'Le motif de la régularisation est obligatoire.', 'Dire ce qui justifie la correction.');
    if (['present', 'retard', 'absent', 'conge'].indexOf(o.etat) < 0) return refusRh('ETAT_INCONNU', 'L’état « ' + o.etat + ' » n’existe pas.', 'Choisir présent, retard, absent ou congé.');
    if (o.motifCode && !MOTIFS_ABSENCE.some(function (x) { return x.id === o.motifCode; })) return refusRh('MOTIF_CODE_INCONNU', 'Le motif codé « ' + o.motifCode + ' » n’existe pas.', 'Choisir maladie, mission ou congé.');
    var moi = employeDeSession();
    if (moi && String(rec.employeId) === String(moi.id)) return refusRh('AUTO_VALIDATION', 'Personne ne régularise son propre pointage.', 'Demander à un autre habilité.');
    var trace = { le: aujIso(), par: acteur(), motif: String(o.motif).trim(), etatAvant: rec.etat, etatApres: o.etat, motifCodeAvant: rec.motifCode || null, motifCodeApres: o.motifCode || rec.motifCode || null };
    var patch = { etat: o.etat, regularisations: (rec.regularisations || []).concat([trace]) };
    if (o.motifCode !== undefined) patch.motifCode = o.motifCode || null;
    if (o.justificatif !== undefined) patch.justificatif = o.justificatif || null;
    var res = c.update(id, patch, { journal: { action: 'Régularisation d’un pointage', module: 'M10', entite: 'Presence', avant: { etat: rec.etat, motifCode: rec.motifCode || null }, apres: { etat: o.etat, motifCode: patch.motifCode === undefined ? rec.motifCode || null : patch.motifCode, motif: trace.motif } } });
    return { ok: true, regularisation: trace, undo: res && res.undo };
  }

  /** UN POINTAGE VALIDÉ NE SE MODIFIE PAS DIRECTEMENT : il se régularise (motif, date et auteur consignés). Les pièces d'avant le circuit (sans état) restent éditables. */
  S.garder('presences', function (op, rec) {
    if (op !== 'modifier' || !rec || !rec.id) return null;
    var avant = S.collection('presences').get(rec.id);
    if (!avant || avant.validationEtat !== 'valide') return null;
    var change = ['etat', 'date', 'employeId', 'heureArrivee', 'heureDepart', 'motifCode'].some(function (k) { return String(avant[k] == null ? '' : avant[k]) !== String(rec[k] == null ? '' : rec[k]); });
    var regularise = (rec.regularisations || []).length > (avant.regularisations || []).length;
    return change && !regularise ? 'PRESENCE_VALIDEE : un pointage validé ne se modifie pas directement ; le régulariser (motif, date et auteur consignés).' : null;
  });

  /* ==========================================================================
   * RH, LOT L6 (10/11/2026) : L'AGENT PROPOSE, LE SURVEILLANT VALIDE
   * --------------------------------------------------------------------------
   * Décision de la Direction du 09/11/2026 (Planning Q4) : l'agent PROPOSE une modification ou un échange de son planning ; le surveillant valide. Le réglage
   * « l'agent modifie directement » (non par défaut, en base) lui laisse poser SES vacations sans validation : le contrôle d'incompatibilité s'applique
   * pareil, la vacation naît validée et marquée `modifieDirectement`. Un échange touche le planning d'un AUTRE agent : il passe toujours par la validation.
   * UNE PROPOSITION NE CHANGE JAMAIS LE PLANNING VALIDÉ TANT QU'ELLE N'EST PAS VALIDÉE. Le contrôle est fait à la proposition (l'agent apprend tout de suite)
   * ET refait à la validation (le planning a pu bouger entre-temps).
   * ======================================================================== */
  var TYPES_PROPOSITION = [
    { id: 'ajout', libelle: 'Ajouter une vacation' }, { id: 'modification', libelle: 'Modifier une vacation' },
    { id: 'retrait', libelle: 'Retirer une vacation' }, { id: 'echange', libelle: 'Échanger une vacation avec un collègue' },
  ];
  function colPropositionsRh() { return S.collection('propositionsPlanning', { module: 'M10', entite: 'proposition de planning', prefix: 'PPL' }); }
  /** Ce que la session peut lire : l'agent ne voit que SES propositions (RG-13), le surveillant, la DAF et l'administrateur voient tout. */
  function propositionsVisiblesRh() {
    var toutes = colPropositionsRh().active();
    if (['surveillant', 'da', 'admin'].indexOf(roleCourant()) >= 0) return toutes;
    var moi = employeDeSession();
    return moi ? toutes.filter(function (p) { return p.employeId === moi.id; }) : [];
  }
  /** Contrôle commun à la proposition et à la validation : { ok } ou le refus nommé (rien n'est écrit). */
  function controlerPropositionRh(p) {
    var cv = p.vacationId ? colPlanningRh().get(p.vacationId) : null;
    if (p.type === 'ajout') return controlerVacationRh({ employeId: p.employeId, date: p.date, type: p.typeVacation });
    if (!cv || cv.statut === 'archive') return refusRh('VACATION_INTROUVABLE', 'La vacation visée n’existe plus au planning.', 'Choisir une vacation du planning.');
    if (cv.employeId !== p.employeId) return refusRh('VACATION_D_AUTRUI', 'La vacation visée n’est pas celle de l’agent qui propose.', 'Choisir une de ses propres vacations.');
    if (p.type === 'retrait') return { ok: true };
    if (p.type === 'modification') return controlerVacationRh({ employeId: p.employeId, date: p.date || cv.date, type: p.typeVacation, ignoreId: cv.id });
    if (p.type === 'echange') {
      var cb = p.contrepartieId ? colPlanningRh().get(p.contrepartieId) : null;
      if (!cb || cb.statut === 'archive') return refusRh('ECHANGE_SANS_CONTREPARTIE', 'L’échange désigne une vacation de collègue qui n’existe plus.', 'Choisir la vacation du collègue.');
      if (cb.employeId === cv.employeId) return refusRh('ECHANGE_MEME_AGENT', 'Un échange se fait avec un autre agent.', 'Choisir la vacation d’un collègue.');
      var eA = employeRh(cv.employeId), eB = employeRh(cb.employeId);
      if (typesAutorisesRh(eB.id, eB.fonction, cv.date).indexOf(cv.type) < 0) return refusRh('ECHANGE_HORS_REGIME', libelleType(cv.type) + ' n’est pas une vacation du régime de ' + eB.nomComplet + '.', 'Choisir un collègue de même régime.');
      if (typesAutorisesRh(eA.id, eA.fonction, cb.date).indexOf(cb.type) < 0) return refusRh('ECHANGE_HORS_REGIME', libelleType(cb.type) + ' n’est pas une vacation du régime de ' + eA.nomComplet + '.', 'Choisir un collègue de même régime.');
      var r1 = controlerVacationRh({ employeId: eB.id, date: cv.date, type: cv.type, ignoreId: cb.id });
      if (!r1.ok) return r1;
      return controlerVacationRh({ employeId: eA.id, date: cb.date, type: cb.type, ignoreId: cv.id });
    }
    return refusRh('TYPE_PROPOSITION_INCONNU', 'Le type de proposition « ' + p.type + ' » n’existe pas.', 'Choisir ajout, modification, retrait ou échange.');
  }
  function proposerPlanningRh(o) {
    o = o || {};
    var moi = employeDeSession();
    if (!moi) return refusRh('AGENT_NON_IDENTIFIE', 'La session ne correspond à aucun agent du personnel : aucune proposition ne peut être rattachée.', 'Se connecter avec le compte nominatif de l’agent.');
    if (!TYPES_PROPOSITION.some(function (t) { return t.id === o.type; })) return refusRh('TYPE_PROPOSITION_INCONNU', 'Le type de proposition « ' + o.type + ' » n’existe pas.', 'Choisir ajout, modification, retrait ou échange.');
    if (!String(o.motif || '').trim()) return refusRh('MOTIF_OBLIGATOIRE', 'Le motif de la proposition est obligatoire : le surveillant doit savoir pourquoi.', 'Dire pourquoi le planning doit changer.');
    var p = { type: o.type, employeId: moi.id, employe: moi.nomComplet, fonction: moi.fonction, service: moi.service, motif: String(o.motif).trim(),
      date: o.date ? isoJour(o.date) : null, typeVacation: o.typeVacation || null, vacationId: o.vacationId || null, contrepartieId: o.contrepartieId || null };
    if (o.type !== 'retrait' && o.type !== 'echange' && !p.typeVacation) return refusRh('TYPE_INCONNU', 'Le type de vacation est obligatoire.', 'Choisir un type du référentiel.');
    if ((o.type === 'ajout') && !p.date) return refusRh('DATE_INVALIDE', 'La date de la vacation est obligatoire.', 'Choisir une date.');
    if (p.vacationId) { var cv = colPlanningRh().get(p.vacationId); if (cv) { p.date = p.date || cv.date; p.vacationType = cv.type; p.vacationDate = cv.date; } }
    if (p.contrepartieId) { var cb = colPlanningRh().get(p.contrepartieId); if (cb) { p.contrepartie = cb.employe; p.contrepartieDate = cb.date; p.contrepartieType = cb.type; } }
    var ctrl = controlerPropositionRh(p);
    if (!ctrl.ok) return ctrl;
    /* L'application directe : seulement pour SES vacations, sans échange. */
    if (agentModifieDirectementRh() && o.type !== 'echange') {
      var rec = null, res = null;
      if (o.type === 'retrait') { res = colPlanningRh().archive(p.vacationId, 'Retrait direct par l’agent'); }
      else {
        var regime = ctrl.regime;
        var fab = fabriquerVacationRh({ date: p.date, type: p.typeVacation, observation: p.motif }, regime, moi, { validationEtat: 'validee', validePar: 'l’agent (réglage « modifie directement »)', valideLe: aujIso(), origine: 'agent', modifieDirectement: true });
        res = o.type === 'ajout' ? colPlanningRh().insert(fab) : colPlanningRh().update(p.vacationId, fab);
        rec = res && res.record;
      }
      if (!res) return refusRh('ECRITURE_REFUSEE', 'L’écriture a été refusée par le magasin.', 'Relire le journal.');
      S.log('Planning modifié directement par l’agent', 'M10', 'Planning', (rec && rec.id) || p.vacationId, null, { type: o.type, date: p.date, vacation: p.typeVacation, motif: p.motif });
      return { ok: true, direct: true, vacationId: (rec && rec.id) || p.vacationId, undo: res.undo };
    }
    var ins = colPropositionsRh().insert(Object.assign(p, { etat: 'proposee', proposeeLe: aujIso(), proposeePar: acteur() }),
      { journal: { action: 'Proposition de planning', module: 'M10', entite: 'propositionsPlanning', avant: null, apres: { type: p.type, date: p.date, typeVacation: p.typeVacation, motif: p.motif } } });
    if (!ins) return refusRh('ECRITURE_REFUSEE', 'L’écriture a été refusée par le magasin.', 'Relire le journal.');
    return { ok: true, direct: false, id: ins.record.id, undo: ins.undo };
  }
  function annulerPropositionRh(id) {
    var c = colPropositionsRh(), p = c.get(id);
    if (!p || p.statut === 'archive') return refusRh('PROPOSITION_INTROUVABLE', 'La proposition n’existe pas.', 'Choisir une proposition de la liste.');
    var moi = employeDeSession();
    if (!moi || p.employeId !== moi.id) return refusRh('PROPOSITION_D_AUTRUI', 'Seul l’agent qui a proposé peut retirer sa proposition.', 'Se connecter avec son compte.');
    if (p.etat !== 'proposee') return refusRh('DEJA_TRANCHEE', 'La proposition est déjà ' + (p.etat === 'validee' ? 'validée' : (p.etat === 'refusee' ? 'refusée' : 'retirée')) + '.', 'Faire une nouvelle proposition.');
    var res = c.update(id, { etat: 'annulee', annuleeLe: aujIso() }, { journal: { action: 'Proposition de planning retirée', module: 'M10', entite: 'propositionsPlanning', avant: { etat: 'proposee' }, apres: { etat: 'annulee' } } });
    return { ok: true, undo: res && res.undo };
  }
  function trancherPropositionRh(o) {
    o = o || {};
    var c = colPropositionsRh(), p = c.get(o.id);
    if (['surveillant', 'da', 'admin'].indexOf(roleCourant()) < 0) return refusRh('VALIDATION_RESERVEE', 'Le planning se valide par le surveillant (ou la Directrice Administrative).', 'Demander au surveillant.');
    if (!p || p.statut === 'archive') return refusRh('PROPOSITION_INTROUVABLE', 'La proposition n’existe pas.', 'Choisir une proposition de la liste.');
    if (['valider', 'refuser'].indexOf(o.decision) < 0) return refusRh('DECISION_INCONNUE', 'La décision est « valider » ou « refuser ».', 'Choisir une décision.');
    if (p.etat !== 'proposee') return refusRh('DEJA_TRANCHEE', 'La proposition est déjà ' + (p.etat === 'validee' ? 'validée' : (p.etat === 'refusee' ? 'refusée' : 'retirée')) + ' : une décision ne se réécrit pas.', 'Attendre une nouvelle proposition.');
    var moi = employeDeSession();
    if (moi && p.employeId === moi.id) return refusRh('AUTO_VALIDATION', 'Personne ne valide sa propre proposition.', 'Demander à un autre habilité.');
    var motif = String(o.motif || '').trim();
    if (o.decision === 'refuser') {
      if (!motif) return refusRh('MOTIF_OBLIGATOIRE', 'Un refus exige son motif : l’agent doit pouvoir le lire.', 'Écrire le motif du refus.');
      var rr = c.update(p.id, { etat: 'refusee', motifRefus: motif, tranchePar: acteur(), trancheLe: aujIso() }, { journal: { action: 'Proposition de planning refusée', module: 'M10', entite: 'propositionsPlanning', avant: { etat: 'proposee' }, apres: { etat: 'refusee', motif: motif } } });
      return { ok: true, etat: 'refusee', undo: rr && rr.undo };
    }
    var ctrl = controlerPropositionRh(p);
    if (!ctrl.ok) return Object.assign({}, ctrl, { cause: ctrl.code, code: 'CONTROLE_ECHOUE', motif: 'Le planning a changé depuis la proposition : ' + ctrl.motif });
    var appliquees = [];
    var plan = colPlanningRh();
    var marque = { validationEtat: 'validee', validePar: acteur(), valideLe: aujIso(), origine: 'proposition', propositionId: p.id };
    if (p.type === 'ajout') {
      var r1 = plan.insert(fabriquerVacationRh({ date: p.date, type: p.typeVacation, observation: p.motif }, ctrl.regime, employeRh(p.employeId), marque));
      appliquees.push(r1.record.id);
    } else if (p.type === 'modification') {
      plan.update(p.vacationId, fabriquerVacationRh({ date: p.date, type: p.typeVacation, observation: p.motif }, ctrl.regime, employeRh(p.employeId), marque));
      appliquees.push(p.vacationId);
    } else if (p.type === 'retrait') {
      plan.archive(p.vacationId, 'Retrait validé (proposition ' + p.id + ')');
      appliquees.push(p.vacationId);
    } else {
      var cv = plan.get(p.vacationId), cb = plan.get(p.contrepartieId);
      var eA = employeRh(cv.employeId), eB = employeRh(cb.employeId);
      plan.update(cv.id, { employeId: eB.id, employe: eB.nomComplet, fonction: eB.fonction, service: eB.service, validationEtat: 'validee', validePar: acteur(), valideLe: aujIso(), origine: 'proposition', propositionId: p.id, echangeAvec: eA.nomComplet });
      plan.update(cb.id, { employeId: eA.id, employe: eA.nomComplet, fonction: eA.fonction, service: eA.service, validationEtat: 'validee', validePar: acteur(), valideLe: aujIso(), origine: 'proposition', propositionId: p.id, echangeAvec: eB.nomComplet });
      appliquees.push(cv.id, cb.id);
    }
    var rv = c.update(p.id, { etat: 'validee', tranchePar: acteur(), trancheLe: aujIso(), appliquees: appliquees, motifValidation: motif || null },
      { journal: { action: 'Proposition de planning validée', module: 'M10', entite: 'propositionsPlanning', avant: { etat: 'proposee' }, apres: { etat: 'validee', appliquees: appliquees } } });
    /* Pas d'annulation : la validation a modifié le planning, une nouvelle proposition corrige. */
    return { ok: true, etat: 'validee', appliquees: appliquees };
  }

  /* ==========================================================================
   * RH, LOT L7 (10/11/2026) : L'ESPACE « MES » DE L'AGENT, LA COPIE DE LA FICHE DE PAIE SUR LE TÉLÉPHONE, « MON ASSURANCE DU PERSONNEL »
   * --------------------------------------------------------------------------
   * Décisions de la Direction du 09/11/2026 (Planning Q5, Q6, Q8). (1) Q5 : la fiche de paie descend sur le téléphone en COPIE CHIFFRÉE LOCALE de la pièce ÉMISE
   * (bulletin DIFFUSÉ, jamais recalculé à l'appareil) de l'agent SEUL ; le réglage `paieCopieTelephone` (oui par défaut) l'active ou la coupe. (2) Q6 : l'espace
   * « Mes » s'ouvre aussi sur un POSTE PARTAGÉ en secours, par une connexion NOMINATIVE. (3) Q8 : « Mon assurance du personnel » reste en LECTURE SEULE.
   *
   * L'ESPACE LIT, IL N'ÉCRIT RIEN ET NE GARDE RIEN : chaque rubrique est lue à l'ouverture, filtrée sur l'agent de la session (rattaché au personnel par son nom, comme
   * partout), sans accorder de droit d'écran sur la collection entière (RG-13). Un compte NON NOMINATIF (aucun agent à ce nom) reçoit un refus nommé, jamais
   * l'espace d'un autre. Seul l'état d'AFFICHAGE (rubrique ouverte) vit dans `sessionStorage`, sous `sigh-cnt:mes-*` ; `purger()` le vide à la déconnexion
   * (`setSession(null)`) et au verrou. Au verrou la rubrique est gardée (retour à l'écran quitté), à la déconnexion tout part.
   * ======================================================================== */
  var RUBRIQUES_MES = [
    { n: 1, id: 'fiche_poste', libelle: 'Ma fiche de poste', ecran: 'm10-fiches-poste', source: 'fichesPoste', lien: 'poste' },
    { n: 2, id: 'fiche_paie', libelle: 'Ma fiche de paie', ecran: 'm11-bulletins', source: 'bulletins', lien: 'employeId', emise: true, sensible: true },
    { n: 3, id: 'contrat', libelle: 'Mon contrat', ecran: 'm10-contrats', source: 'contrats', lien: 'employeId', sensible: true },
    { n: 4, id: 'planning', libelle: 'Mes planning et gardes', ecran: 'm10-planning', source: 'planning', lien: 'employeId' },
    { n: 5, id: 'stats_garde', libelle: 'Mes statistiques de garde', ecran: 'm10-stats-gardes', calcule: 'garde' },
    { n: 6, id: 'stats_permanence', libelle: 'Mes statistiques des permanences', ecran: 'm10-stats-permanences', calcule: 'permanence' },
    { n: 7, id: 'taux_presence', libelle: 'Mon taux de présence par service', ecran: 'm10-stats-presence', calcule: 'presence' },
    { n: 8, id: 'presences', libelle: 'Mes présences et absences', ecran: 'm10-presences', source: 'presences', lien: 'employeId' },
    { n: 9, id: 'conges', libelle: 'Mes congés', ecran: 'm10-conges', source: 'conges', lien: 'employeId' },
    { n: 10, id: 'missions', libelle: 'Mes ordres de mission', ecran: 'm10-missions', source: 'missions', lien: 'agentId' },
    { n: 11, id: 'primes', libelle: 'Mes primes', ecran: 'm10-primes', source: 'bulletins', lien: 'employeId', emise: true, sensible: true },
    { n: 12, id: 'evenements', libelle: 'Événements du personnel', ecran: 'm10-evenements', source: 'evenements', lien: 'evenementsDeLAgent' },
    { n: 13, id: 'participations', libelle: 'Mes frais de participation', ecran: 'm10-participations', source: 'participations', lien: 'employeId' },
    { n: 14, id: 'assurance', libelle: 'Mon assurance du personnel', ecran: 'm10-assurance-personnel', calcule: 'assurance', lectureSeule: true },
    { n: 15, id: 'notes_service', libelle: 'Notes de service', ecran: 'm13-notes-service', calcule: 'notes' },
    { n: 16, id: 'agenda', libelle: 'Mon agenda', ecran: 'm2-agenda', source: 'consultations', lien: 'medecinId' },
    { n: 17, id: 'rendez_vous', libelle: 'Mes rendez-vous et visites', ecran: 'm2-rendezvous', source: 'consultations', lien: 'patientDeLAgent' },
  ];
  var CLE_MES = 'sigh-cnt:mes-';
  /* LA GARDE SOINS COMPTE COMME GARDE (Direction, 11/11/2026, P4). « Mes statistiques de garde » comptait la garde de 24 h (`garde`, `garde_hospi`) et laissait
     la garde soins de 08h à 18h30 (`garde_soins`) à la seule rubrique du planning : un agent du régime « garde soins » (les aides-soignantes, par exemple)
     y lisait zéro garde. L'écran de gestion `m10-stats-gardes` la comptait déjà comme garde (tout type qui commence par « garde ») : les deux disent
     désormais la même chose. */
  var TRAVAIL_MES = { garde: ['garde', 'garde_hospi', 'garde_soins'], permanence: ['permanence'] };

  function rubriqueMes(id) { return RUBRIQUES_MES.filter(function (r) { return r.id === id; })[0] || null; }
  function copiePaieTelephoneActive() { return S.reglage('paieCopieTelephone', true) !== false; }
  function definirCopiePaieTelephone(oui, motif) {
    if (['admin', 'da'].indexOf(roleCourant()) < 0) return refusRh('REGLAGE_RESERVE', 'Ce réglage se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
    var avant = copiePaieTelephoneActive();
    S.setReglage('paieCopieTelephone', oui === true);
    S.log('Copie de la fiche de paie sur le téléphone', 'M11', 'reglage', 'paieCopieTelephone', { valeur: avant }, { valeur: oui === true, motif: motif || null });
    return { ok: true, valeur: oui === true, avant: avant };
  }

  /** L'agent de la session : la connexion doit être NOMINATIVE (un agent du personnel à ce nom), sinon refus nommé. */
  function agentDeMes() {
    if (!(S.session && S.session())) return refusRh('SESSION_ABSENTE', 'Aucune session ouverte : l’espace « Mes » ne s’ouvre que sur une connexion nominative.', 'Se connecter avec son propre compte.');
    var e = employeDeSession();
    if (!e) return refusRh('COMPTE_NON_NOMINATIF', 'Le compte « ' + acteur() + ' » ne correspond à aucun agent du personnel : l’espace « Mes » est celui d’une personne, pas d’un poste.', 'Se connecter avec son compte nominatif (poste partagé : fermer la session de l’agent précédent).');
    return { ok: true, agent: e };
  }

  /** Les fiches d'une rubrique qui sont CELLES DE L'AGENT, et d'aucun autre (RG-13). */
  function fichesMes(r, e) {
    var col = S.collection(r.source).active();
    var dossiers = null;
    function dossiersAgent() {
      dossiers = dossiers || S.collection('patients').active().filter(function (p) { return p.personnelId === e.id; }).map(function (p) { return p.id; });
      return dossiers;
    }
    return col.filter(function (x) {
      if (r.lien === 'poste') return !!e.poste && x.intitule === e.poste;
      if (r.lien === 'evenementsDeLAgent') {
        return x.beneficiaireId === e.id || S.collection('participations').active().some(function (p) { return p.evenementId === x.id && p.employeId === e.id; });
      }
      if (r.lien === 'patientDeLAgent') return dossiersAgent().indexOf(x.patientId) >= 0;
      if (r.emise && x.statutBulletin !== 'diffuse') return false;
      return String(x[r.lien]) === String(e.id);
    });
  }

  /** Consultations, analyses et hospitalisations de l'agent soigné à 100 % : montant PORTÉ ou « non renseigné », jamais le prix courant (vague 20, Q8). */
  function montantPorte(v) { if (v === null || v === undefined || v === '') return null; var n = Number(v); return isFinite(n) ? n : null; }
  function assuranceDeLAgent(e) {
    var pids = S.collection('patients').active().filter(function (p) { return p.personnelId === e.id; }).map(function (p) { return p.id; });
    var lignes = [];
    S.collection('consultations').active().forEach(function (c) { if (pids.indexOf(c.patientId) >= 0) lignes.push({ id: c.id, nature: 'Consultation', date: String(c.date || '').slice(0, 10), valeur: montantPorte(c.tarif) }); });
    S.collection('demandesAnalyses').active().forEach(function (a) {
      if (pids.indexOf(a.patientId) >= 0) lignes.push({ id: a.id, nature: 'Analyse', date: String(a.date || a.dateDemande || a.dateHeure || '').slice(0, 10), valeur: montantPorte(a.montant != null && a.montant !== '' ? a.montant : a.prix) });
    });
    S.collection('admissions').active().forEach(function (h) { if (pids.indexOf(h.patientId) >= 0) lignes.push({ id: h.id, nature: 'Hospitalisation', date: String(h.dateEntree || '').slice(0, 10), valeur: montantPorte(h.montant) }); });
    var renseignees = lignes.filter(function (l) { return l.valeur !== null; });
    return { lignes: lignes, total: renseignees.reduce(function (t, l) { return t + l.valeur; }, 0), sansMontant: lignes.length - renseignees.length };
  }

  /** La lecture d'UNE rubrique par l'agent de la session : les identifiants de ses fiches, ou les valeurs calculées. Lecture seule, rien n'est écrit. */
  function lireMes(rubriqueId) {
    var r = rubriqueMes(rubriqueId);
    if (!r) return refusRh('RUBRIQUE_INCONNUE', 'La rubrique « ' + rubriqueId + ' » n’existe pas.', 'Choisir l’une des dix-sept rubriques de l’espace « Mes ».');
    var a = agentDeMes();
    if (!a.ok) return a;
    var e = a.agent;
    var out = { ok: true, rubrique: r.id, agentId: e.id, lectureSeule: r.lectureSeule === true };
    if (r.calcule === 'notes') { out.ids = [D.NS131.reference, D.NS132.reference]; out.total = out.ids.length; return out; }
    if (r.calcule === 'assurance') {
      var as = assuranceDeLAgent(e);
      out.ids = as.lignes.map(function (l) { return l.id; }); out.total = as.lignes.length; out.valeur = as.total; out.sansMontant = as.sansMontant;
      return out;
    }
    if (r.calcule === 'garde' || r.calcule === 'permanence') {
      var vacs = S.collection('planning').active().filter(function (x) { return x.employeId === e.id && TRAVAIL_MES[r.calcule].indexOf(x.type) >= 0 && (!x.validationEtat || x.validationEtat === 'validee'); });
      out.ids = vacs.map(function (x) { return x.id; }); out.total = vacs.length;
      return out;
    }
    if (r.calcule === 'presence') {
      var pts = S.collection('presences').active().filter(function (x) { return x.employeId === e.id && compteRh('presences', x); });
      out.ids = pts.map(function (x) { return x.id; }); out.total = pts.length;
      out.presents = pts.filter(function (x) { return x.etat === 'present'; }).length;
      out.retards = pts.filter(function (x) { return x.etat === 'retard'; }).length;
      out.absents = pts.filter(function (x) { return x.etat === 'absent'; }).length;
      return out;
    }
    var f = fichesMes(r, e);
    out.ids = f.map(function (x) { return x.id; }); out.total = f.length;
    return out;
  }

  /** LA COPIE DE LA FICHE DE PAIE POUR LE TÉLÉPHONE : les pièces ÉMISES (diffusées) de l'agent DEMANDEUR, jamais celles d'un autre, jamais l'ensemble de la paie. */
  function copiePaieAgent(o) {
    o = o || {};
    if (!copiePaieTelephoneActive()) return refusRh('COPIE_PAIE_DESACTIVEE', 'La copie de la fiche de paie sur le téléphone est désactivée au poste de la mère.', 'Demander à la Directrice Administrative de l’activer (paramètres, famille Paie).');
    var a = agentDeMes();
    if (!a.ok) return a;
    var e = a.agent;
    if (o.agentId && String(o.agentId) !== String(e.id)) return refusRh('COPIE_PAIE_AUTRE_AGENT', 'Une copie de fiche de paie ne se délivre qu’à l’agent concerné : celle d’un autre agent n’est jamais descendue (RG-13).', 'L’agent demande sa propre copie depuis son compte.');
    var pieces = S.collection('bulletins').active().filter(function (b) { return String(b.employeId) === String(e.id) && b.statutBulletin === 'diffuse'; });
    return { ok: true, agentId: e.id, ids: pieces.map(function (b) { return b.id; }), references: pieces.map(function (b) { return b.reference; }), total: pieces.length, chiffree: true, recalculee: false };
  }

  function etatMes(cle, valeur) {
    try {
      if (valeur === undefined) return global.sessionStorage.getItem(CLE_MES + cle);
      global.sessionStorage.setItem(CLE_MES + cle, String(valeur));
    } catch (e) { /* sans stockage : l'espace s'ouvre sur la première rubrique */ }
    return null;
  }
  /** Vide l'état d'affichage de l'espace « Mes » : à la déconnexion tout part ; au verrou la rubrique est gardée (retour à l'écran quitté). */
  function purgerMes(o) {
    var garde = o && o.gardeRubrique ? etatMes('rubrique') : null;
    var n = 0;
    try {
      var cles = [];
      for (var i = 0; i < global.sessionStorage.length; i++) { var k = global.sessionStorage.key(i); if (k && k.indexOf(CLE_MES) === 0) cles.push(k); }
      cles.forEach(function (k) { global.sessionStorage.removeItem(k); n++; });
      if (garde) global.sessionStorage.setItem(CLE_MES + 'rubrique', garde);
    } catch (e) { /* rien à purger */ }
    return n;
  }
  global.SIGH.espaceMes = {
    RUBRIQUES: RUBRIQUES_MES, rubrique: rubriqueMes, agent: agentDeMes, lire: lireMes, assurance: assuranceDeLAgent,
    copiePaieActive: copiePaieTelephoneActive, definirCopiePaie: definirCopiePaieTelephone, copiePaie: copiePaieAgent,
    etat: etatMes, purger: purgerMes,
  };

  global.SIGH.planningRh = {
    CHAMPS_DEROGEABLES: CHAMPS_DEROGEABLES, CIRCUITS: CIRCUITS_PRESENCES, MOTIFS_ABSENCE: MOTIFS_ABSENCE, TYPES_PROPOSITION: TYPES_PROPOSITION,
    regimeCategorie: regimeCategorieRh, regimeALaDate: regimeALaDate, historique: historiqueRegimeInd, deroger: derogerRegime, typesAutorises: typesAutorisesRh,
    controlerVacation: controlerVacationRh, poserVacation: poserVacationRh, retirerVacation: retirerVacationRh,
    circuit: circuitPresencesRh, etapesDuCircuit: etapesDuCircuitRh, definirCircuit: definirCircuitRh, agentModifieDirectement: agentModifieDirectementRh, definirAgentDirect: definirAgentDirectRh,
    etatValidation: etatValidationRh, compte: compteRh, peutTrancher: peutTrancherRh, trancher: trancherPieceRh, avisMission: avisMissionRh, naissance: naissanceRh, regulariser: regulariserPresenceRh,
    proposer: proposerPlanningRh, annulerProposition: annulerPropositionRh, trancherProposition: trancherPropositionRh, propositionsVisibles: propositionsVisiblesRh, controlerProposition: controlerPropositionRh,
    employeDeSession: employeDeSession,
  };
  /* ==========================================================================
   * L'ORGANIGRAMME, SES POSTES ET LE TITRE DE L'AGENT (11/11/2026, lot ORG2)
   * --------------------------------------------------------------------------
   * Décisions de la Direction : l'organigramme suit la photo du papier MAIS n'est pas figé (O4) ; le titulaire d'un poste se renomme quand une autre
   * personne est affectée (O2) ; le surveillant général est un infirmier, donc le titre affiché (« SG ») est porté par l'AGENT et non par le poste
   * (O3) ; aucune étoile (O5). Ce moteur est le SEUL chemin d'écriture des postes depuis l'écran « Organisation & organigramme » : réaffecter,
   * renommer le titulaire, poser le titre de l'agent, créer, archiver, tout est contrôlé, refusé en le nommant, et journalisé (RG-12).
   *
   * Le titre vit sur la fiche du PERSONNEL (`titreOrganigramme`), rattachée au poste par le NOM du titulaire, comme partout (l'espace « Mes », le
   * personnel). Un titulaire qui ne correspond à aucun agent n'a pas de titre à poser : refus nommé. Ni le titre ni le rattachement ne touchent aux
   * droits : le rôle RBAC du poste est un champ à part, et le titre d'un agent ne change aucun accès.
   * ======================================================================== */
  var TITRE_ORG_MAX = 12;
  var CHAMPS_POSTE_ORG = ['poste', 'parentId', 'effectif', 'titulaire', 'chef', 'role'];
  function refusOrg(code, motif, geste, extra) { return Object.assign({ ok: false, code: code, motif: motif, geste: geste }, extra || {}); }
  function colPostesOrg() { return S.collection('postes', { module: 'CFG', entite: 'poste', prefix: 'PST' }); }
  function colPersonnelOrg() { return S.collection('personnel'); }
  /** Un nom comparable : sans la mention d'épouse, sans accents ni majuscules, espaces réduits. */
  function cleNomOrg(n) {
    return String(n || '').replace(/\s+[ée]pse\s+.*$/i, '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
  }
  /** L'agent du personnel qui porte le nom du titulaire du poste, ou `null` (poste vacant, ou titulaire qui n'est pas au personnel). */
  function agentDuPosteOrg(p) {
    if (!p || !p.titulaire) return null;
    var cle = cleNomOrg(p.titulaire);
    return colPersonnelOrg().active().filter(function (a) { return cleNomOrg(a.nomComplet) === cle; })[0] || null;
  }
  function titreDuPosteOrg(p) { var a = agentDuPosteOrg(p); return a && a.titreOrganigramme ? String(a.titreOrganigramme) : null; }
  function droitOrg(quoi) {
    var N = global.SIGH.nav, role = roleCourant();
    if (!role) return false;
    try { return !!N.droitsEcran(role, 'cfg-organisation', 'CFG')[quoi]; } catch (e) { return false; }
  }
  function droitEcritureOrg() { return droitOrg('editer'); }
  function refusDroitOrg(archivage) {
    return refusOrg('ORGANIGRAMME_RESERVE', archivage
      ? 'L’archivage d’un poste est réservé aux profils qui annulent à l’écran « Organisation & organigramme » (RG-14).'
      : 'La modification de l’organigramme est réservée aux profils qui écrivent à l’écran « Organisation & organigramme ».',
    'Demander à l’administrateur ou à la Directrice Administrative.');
  }
  function nomPosteOrg(id) { var p = id ? colPostesOrg().get(id) : null; return p ? p.poste : null; }

  /** L'arbre des postes ACTIFS, chaque nœud portant le titre de son titulaire (`titreAgent`). Un poste dont le parent est archivé ou absent est un sommet. */
  function arbreOrganigramme() {
    var plats = colPostesOrg().active(), parId = {}, racines = [];
    plats.forEach(function (p) { parId[p.id] = Object.assign({}, p, { enfants: [], titreAgent: titreDuPosteOrg(p) }); });
    plats.forEach(function (p) {
      var n = parId[p.id];
      if (p.parentId && parId[p.parentId]) parId[p.parentId].enfants.push(n); else racines.push(n);
    });
    return racines;
  }
  /** Les identifiants des postes ACTIFS sous [id], à tous les niveaux. */
  function descendantsOrganigramme(id) {
    var actifs = colPostesOrg().active(), vus = {}, pile = [id], out = [];
    while (pile.length) {
      var x = pile.pop();
      actifs.forEach(function (p) { if (p.parentId === x && !vus[p.id]) { vus[p.id] = true; out.push(p.id); pile.push(p.id); } });
    }
    return out;
  }
  /** Le rattachement demandé est-il permis ? `null` si oui, sinon le refus nommé. */
  function controlerRattachementOrg(posteId, parentId) {
    if (!parentId) return null;
    var parent = colPostesOrg().get(parentId);
    if (!parent) return refusOrg('PARENT_INTROUVABLE', 'Le poste de rattachement demandé n’existe pas.', 'Choisir un poste de la liste.');
    if (parent.statut === 'archive') {
      return refusOrg('PARENT_ARCHIVE', 'Le poste « ' + parent.poste + ' » est archivé : on ne rattache rien à un poste archivé (RG-14).',
        'Restaurer ce poste depuis la corbeille, ou choisir un poste actif.');
    }
    if (posteId && (parentId === posteId || descendantsOrganigramme(posteId).indexOf(parentId) >= 0)) {
      var moi = nomPosteOrg(posteId) || 'ce poste';
      return refusOrg('RATTACHEMENT_CYCLE', 'Rattacher « ' + moi + ' » à « ' + parent.poste + ' » ferait de lui son propre supérieur : '
        + (parentId === posteId ? 'un poste ne se rattache pas à lui-même.' : '« ' + parent.poste + ' » dépend déjà de « ' + moi + ' ».'),
      'Choisir un poste qui ne dépende pas de celui-ci, ou réaffecter d’abord ses rattachés.', { parentId: parentId });
    }
    return null;
  }
  /**
   * Contrôle d'une saisie de poste SANS rien écrire. `posteId` nul : création. `champs` : les champs saisis (ceux d'une modification partielle suffisent).
   * `titreAgent` suppose un titulaire qui est un agent du personnel.
   */
  function controlerPosteOrg(posteId, champs) {
    champs = champs || {};
    var poste = posteId ? colPostesOrg().get(posteId) : null;
    if (posteId && !poste) return refusOrg('POSTE_INTROUVABLE', 'Ce poste n’existe pas.', 'Rouvrir l’écran puis choisir un poste de la liste.');
    if (poste && poste.statut === 'archive') return refusOrg('POSTE_ARCHIVE', 'Le poste « ' + poste.poste + ' » est archivé : il ne se modifie pas.', 'Le restaurer depuis la corbeille d’abord.');
    if (champs.poste !== undefined && !String(champs.poste).trim()) return refusOrg('INTITULE_VIDE', 'L’intitulé du poste est obligatoire.', 'Saisir l’intitulé du poste.');
    if (champs.effectif !== undefined && champs.effectif !== '' && champs.effectif !== null) {
      var n = Number(champs.effectif);
      if (!isFinite(n) || n < 0 || n !== Math.floor(n)) return refusOrg('EFFECTIF_INVALIDE', 'L’effectif d’un poste est un nombre entier, zéro ou plus.', 'Saisir un nombre entier.');
    }
    if (champs.role !== undefined && champs.role !== '' && !global.SIGH.nav.ROLES[champs.role]) {
      return refusOrg('ROLE_INCONNU', 'Le rôle « ' + champs.role + ' » n’existe pas.', 'Choisir un rôle de la liste.');
    }
    if (champs.parentId !== undefined) {
      var r = controlerRattachementOrg(posteId, champs.parentId || null);
      if (r) return r;
    }
    if (champs.titreAgent !== undefined) {
      var titre = String(champs.titreAgent || '').trim();
      var vise = poste ? Object.assign({}, poste, champs.titulaire !== undefined ? { titulaire: champs.titulaire } : {}) : { titulaire: champs.titulaire };
      if (titre.length > TITRE_ORG_MAX) return refusOrg('TITRE_TROP_LONG', 'Le titre dans l’organigramme tient en ' + TITRE_ORG_MAX + ' caractères au plus (« SG », « C/S »).', 'Abréger le titre.');
      var agent = agentDuPosteOrg(vise);
      if (titre && !vise.titulaire) return refusOrg('POSTE_VACANT', 'Le poste n’a pas de titulaire : le titre est porté par un agent, il n’y en a pas à qui le poser.', 'Saisir d’abord le titulaire du poste.');
      if (titre && !agent) {
        return refusOrg('AGENT_INTROUVABLE', 'Aucun agent du personnel ne porte le nom « ' + vise.titulaire + ' » : le titre est porté par l’agent, pas par le poste.',
          'Corriger le nom du titulaire pour qu’il corresponde à une fiche du personnel, ou enregistrer l’agent au personnel.');
      }
    }
    return null;
  }

  /**
   * Modifie un poste : n'importe quel sous-ensemble de { poste, parentId, effectif, titulaire, chef, role, titreAgent }. Tout est contrôlé AVANT
   * la première écriture (rien n'est écrit à moitié) ; le poste est journalisé, le titre de l'agent l'est aussi, sur sa propre ligne.
   * Rend { ok, record, inchange, undo } ou le refus nommé.
   */
  function modifierPosteOrg(posteId, champs) {
    champs = champs || {};
    if (!droitEcritureOrg()) return refusDroitOrg();
    var refus = controlerPosteOrg(posteId, champs);
    if (refus) return refus;
    var col = colPostesOrg(), poste = col.get(posteId);
    var patch = {};
    CHAMPS_POSTE_ORG.forEach(function (k) {
      if (champs[k] === undefined) return;
      var v = champs[k];
      if (k === 'poste') v = String(v).trim();
      else if (k === 'parentId') v = v || null;
      else if (k === 'effectif') v = v === '' || v === null ? poste.effectif : Number(v);
      else if (k === 'titulaire') v = String(v || '').trim() || null;
      else if (k === 'chef') v = v === true || v === 'true';
      if ((poste[k] === undefined ? null : poste[k]) !== v) patch[k] = v;
    });
    var cles = Object.keys(patch);
    var titreAvant = titreDuPosteOrg(poste);
    var titrePose = champs.titreAgent === undefined ? undefined : (String(champs.titreAgent || '').trim() || null);
    var vise = Object.assign({}, poste, patch);
    var agent = agentDuPosteOrg(vise);
    var changeTitre = titrePose !== undefined && agent && (agent.titreOrganigramme || null) !== titrePose;
    if (!cles.length && !changeTitre) return { ok: true, record: poste, inchange: true, undo: function () {} };
    var undos = [];
    if (cles.length) {
      var avant = {}, apres = {};
      cles.forEach(function (k) {
        avant[k] = k === 'parentId' ? nomPosteOrg(poste.parentId) : poste[k];
        apres[k] = k === 'parentId' ? nomPosteOrg(patch.parentId) : patch[k];
      });
      var action = cles.length === 1 && cles[0] === 'parentId' ? 'Réaffectation d’un poste'
        : cles.length === 1 && cles[0] === 'titulaire' ? 'Changement de titulaire d’un poste' : 'Modification d’un poste';
      var r1 = col.update(posteId, patch, { journal: { action: action, module: 'CFG', entite: 'Poste', avant: Object.assign({ poste: poste.poste }, avant), apres: apres } });
      if (!r1) return refusOrg('ECRITURE_REFUSEE', 'L’écriture du poste a été refusée par le magasin.', 'Réessayer, ou voir le journal.');
      undos.push(r1.undo);
    }
    if (changeTitre) {
      var r2 = colPersonnelOrg().update(agent.id, { titreOrganigramme: titrePose }, { journal: { action: 'Titre d’un agent dans l’organigramme', module: 'CFG', entite: 'Agent',
        avant: { agent: agent.nomComplet, titre: agent.titreOrganigramme || null }, apres: { titre: titrePose, poste: vise.poste } } });
      if (r2) undos.push(r2.undo);
    }
    return { ok: true, record: col.get(posteId), inchange: false, titre: titrePose === undefined ? titreAvant : titrePose, undo: function () { undos.slice().reverse().forEach(function (u) { u(); }); } };
  }
  /** Réaffecte un poste (et les postes qu'il porte) sous un autre, ou au sommet (`parentId` nul). */
  function reaffecterPosteOrg(posteId, parentId) { return modifierPosteOrg(posteId, { parentId: parentId || null }); }
  /** Renomme le titulaire d'un poste (une autre personne est affectée) ; vide : le poste devient vacant. */
  function renommerTitulaireOrg(posteId, nom) { return modifierPosteOrg(posteId, { titulaire: nom }); }
  /** Pose (ou retire, titre vide) le titre de l'agent qui tient le poste. */
  function poserTitreOrg(posteId, titre) { return modifierPosteOrg(posteId, { titreAgent: titre }); }
  /** Crée un poste (sans rattachement : un sommet). */
  function creerPosteOrg(champs) {
    champs = champs || {};
    if (!droitEcritureOrg()) return refusDroitOrg();
    var refus = controlerPosteOrg(null, champs);
    if (refus) return refus;
    if (champs.poste === undefined) return refusOrg('INTITULE_VIDE', 'L’intitulé du poste est obligatoire.', 'Saisir l’intitulé du poste.');
    var fiche = {
      poste: String(champs.poste).trim(), parentId: champs.parentId || null, effectif: champs.effectif === undefined || champs.effectif === '' ? 1 : Number(champs.effectif),
      titulaire: String(champs.titulaire || '').trim() || null, chef: champs.chef === true || champs.chef === 'true', role: champs.role || 'agentadmin',
    };
    var r = colPostesOrg().insert(fiche);
    return { ok: true, record: r.record, undo: r.undo };
  }
  /**
   * LES POSTES ACTIFS QU'UN POSTE PORTE DIRECTEMENT, ET OÙ ILS ATTERRIRAIENT SI ON L'ARCHIVAIT (lot ORG3, décision de la Direction du 11/11/2026).
   * Archiver un poste qui porte des sous-postes ne se REFUSE plus : on les RÉAFFECTE. Cible par défaut : le PARENT du poste archivé (les sous-postes
   * remontent d'un cran, la hiérarchie ne se creuse pas). Un sommet qui porte des sous-postes n'a pas de parent : la cible est alors OBLIGATOIRE, et
   * sans cible valide le refus se nomme (CIBLE_REQUISE) et dit quoi faire. La cible n'est ni le poste, ni l'un de ses descendants (cycle), ni un poste
   * archivé. Ne rien écrire : sert l'écran (la modale de confirmation) autant que le moteur.
   * Rend { ok, poste, portes: [{ id, poste }], cible: { id, poste } | null, parDefaut, candidats: [{ id, poste }] } ou le refus nommé.
   */
  function planArchivageOrg(posteId, cibleId) {
    var col = colPostesOrg(), poste = col.get(posteId);
    if (!poste) return refusOrg('POSTE_INTROUVABLE', 'Ce poste n’existe pas.', 'Rouvrir l’écran puis choisir un poste de la liste.');
    if (poste.statut === 'archive') return refusOrg('POSTE_ARCHIVE', 'Le poste « ' + poste.poste + ' » est déjà archivé.', 'Le restaurer depuis la corbeille si besoin.');
    var portes = col.active().filter(function (p) { return p.parentId === posteId; }).map(function (p) { return { id: p.id, poste: p.poste }; });
    var interdits = descendantsOrganigramme(posteId); interdits.push(posteId);
    var candidats = col.active().filter(function (p) { return interdits.indexOf(p.id) < 0; }).map(function (p) { return { id: p.id, poste: p.poste }; });
    if (!portes.length) return { ok: true, poste: { id: poste.id, poste: poste.poste }, portes: [], cible: null, parDefaut: false, candidats: candidats };
    var liste = portes.map(function (p) { return p.poste; }).join(', ');
    var parent = poste.parentId ? col.get(poste.parentId) : null;
    var parentActif = parent && parent.statut !== 'archive' ? parent : null;
    var visee = cibleId || (parentActif ? parentActif.id : null);
    if (!visee) {
      return refusOrg('CIBLE_REQUISE', 'Le poste « ' + poste.poste + ' » est au sommet de l’organigramme et porte ' + portes.length + ' poste' + (portes.length > 1 ? 's' : '') + ' (' + liste + ') : '
        + 'il n’y a pas de poste au-dessus vers lequel les faire remonter.',
      candidats.length
        ? 'Désigner le poste d’accueil de ces postes (celui qui prend leur suite), puis archiver.'
        : 'Créer d’abord le poste d’accueil de ces postes (aucun autre poste actif ne peut les recevoir), puis archiver.', { portes: portes.map(function (p) { return p.id; }), candidats: candidats.map(function (p) { return p.id; }) });
    }
    var cible = col.get(visee);
    if (!cible) return refusOrg('CIBLE_INTROUVABLE', 'Le poste d’accueil demandé n’existe pas.', 'Choisir un poste de la liste.', { cibleId: visee });
    if (cible.statut === 'archive') {
      return refusOrg('CIBLE_ARCHIVEE', 'Le poste « ' + cible.poste + ' » est archivé : on ne rattache rien à un poste archivé (RG-14).', 'Restaurer ce poste depuis la corbeille, ou choisir un poste actif.', { cibleId: visee });
    }
    if (interdits.indexOf(visee) >= 0) {
      return refusOrg('CIBLE_CYCLE', visee === posteId
        ? 'Les postes portés par « ' + poste.poste + ' » ne peuvent pas être réaffectés à ce poste lui-même : il est archivé.'
        : 'Réaffecter les postes portés par « ' + poste.poste + ' » sous « ' + cible.poste + ' » ferait de lui son propre supérieur : « ' + cible.poste + ' » dépend déjà de « ' + poste.poste + ' ».',
      'Choisir un poste qui ne dépende pas de celui-ci.', { cibleId: visee });
    }
    return { ok: true, poste: { id: poste.id, poste: poste.poste }, portes: portes, cible: { id: cible.id, poste: cible.poste }, parDefaut: !cibleId, candidats: candidats };
  }
  /**
   * Archive un poste (RG-14). S'il porte des postes actifs, ils sont RÉAFFECTÉS à `opts.cibleId` (par défaut son parent), tout ou rien : chaque rattachement
   * est contrôlé avant la première écriture, et une écriture refusée en cours de route défait les précédentes (rien n'est écrit à moitié). Une ligne de
   * journal pour l'archivage, une par poste réaffecté (ancien et nouveau parent, motif) ; l'auteur et la date sont ceux du journal.
   * Rend { ok, record, cible, reaffectes: [{ id, poste, de, vers }], undo } ou le refus nommé. `undo()` restaure le poste ET remet chaque poste réaffecté
   * sous son ancien parent, sauf celui que quelqu'un a déplacé depuis (laissé, et dit) : il rend { ok, restaures, laisses } ou le refus nommé.
   */
  function archiverPosteOrg(posteId, motif, opts) {
    opts = opts || {};
    if (!droitOrg('annuler')) return refusDroitOrg(true);
    var plan = planArchivageOrg(posteId, opts.cibleId || null);
    if (!plan.ok) return plan;
    var col = colPostesOrg(), poste = col.get(posteId);
    if (plan.portes.length && !droitEcritureOrg()) {
      return refusOrg('ORGANIGRAMME_RESERVE', 'Archiver « ' + poste.poste + ' » réaffecte les ' + plan.portes.length + ' poste' + (plan.portes.length > 1 ? 's' : '') + ' qu’il porte : une modification de l’organigramme, réservée aux profils qui écrivent à l’écran « Organisation & organigramme ».',
        'Demander à l’administrateur ou à la Directrice Administrative.');
    }
    /* Tout est contrôlé AVANT la première écriture : un rattachement qui ne passe pas fait refuser l'archivage entier. */
    for (var i = 0; i < plan.portes.length; i++) {
      var ctl = controlerRattachementOrg(plan.portes[i].id, plan.cible.id);
      if (ctl) return refusOrg('REAFFECTATION_REFUSEE', 'Le poste « ' + plan.portes[i].poste + ' » ne peut pas être réaffecté sous « ' + plan.cible.poste + ' » : ' + ctl.motif, ctl.geste, { causes: ctl.code, posteId: plan.portes[i].id });
    }
    var motifTxt = motif ? String(motif).trim() || null : null;
    var undos = [], reaffectes = [], instantanes = {};
    /* Le retour arrière remet les postes tels qu'ils étaient, marques d'écran comprises (une fiche « modifiée » par une tentative défaite ne serait plus
       reconnue intacte par la reprise), et l'abandon s'écrit au journal : sans cette ligne, les réaffectations déjà journalisées resteraient sans suite. */
    function defaire(raison) {
      undos.slice().reverse().forEach(function (u) { u(); });
      reaffectes.forEach(function (x) {
        var f = col.get(x.id), snap = instantanes[x.id];
        if (!f || !snap) return;
        ['_modifiePar', '_modifieLe'].forEach(function (k) { if (snap[k] === undefined) delete f[k]; else f[k] = snap[k]; });
      });
      S.log('Archivage abandonné', 'CFG', 'Poste', posteId, { poste: poste.poste, sousPostes: plan.portes.length }, { raison: raison, remisEnPlace: reaffectes.length });
    }
    for (var j = 0; j < plan.portes.length; j++) {
      var s = col.get(plan.portes[j].id);
      instantanes[s.id] = Object.assign({}, s);
      var r1 = col.update(s.id, { parentId: plan.cible.id }, { journal: { action: 'Réaffectation d’un poste', module: 'CFG', entite: 'Poste',
        avant: { poste: s.poste, parentId: poste.poste }, apres: { parentId: plan.cible.poste, motif: motifTxt, archivage: poste.poste } } });
      if (!r1) {
        defaire('écriture refusée pour « ' + s.poste + ' »');
        return refusOrg('REAFFECTATION_REFUSEE', 'L’écriture du poste « ' + s.poste + ' » a été refusée par le magasin : l’archivage de « ' + poste.poste + ' » est abandonné, aucun poste n’a changé de place.', 'Voir le journal, puis réessayer.', { posteId: s.id });
      }
      undos.push(r1.undo);
      reaffectes.push({ id: s.id, poste: s.poste, de: posteId, vers: plan.cible.id });
    }
    var r = col.archive(posteId, motifTxt, { journal: { action: 'Archivage', avant: { statut: 'actif', poste: poste.poste, sousPostes: reaffectes.length },
      apres: plan.portes.length ? { statut: 'archive', cible: plan.cible.poste, motif: motifTxt } : { statut: 'archive', motif: motifTxt } } });
    if (!r) {
      defaire('archivage refusé par le magasin');
      return refusOrg('ECRITURE_REFUSEE', 'L’archivage du poste « ' + poste.poste + ' » a été refusé par le magasin : aucun poste n’a changé de place.', 'Voir le journal, puis réessayer.');
    }
    var cibleNom = plan.cible ? plan.cible.poste : null, cibleId = plan.cible ? plan.cible.id : null;
    return {
      ok: true, record: r.record, cible: plan.cible, reaffectes: reaffectes,
      undo: function () {
        if (!droitOrg('annuler')) return refusDroitOrg(true);
        var cur = col.get(posteId);
        if (!cur || cur.statut !== 'archive') {
          return refusOrg('ANNULATION_IMPOSSIBLE', 'Le poste « ' + poste.poste + ' » n’est plus archivé (il a déjà été restauré) : il n’y a plus d’archivage à annuler.',
            'Contrôler la liste des postes ; remettre à la main les postes réaffectés si besoin (le journal donne leur ancien rattachement).');
        }
        if (reaffectes.length && !droitEcritureOrg()) return refusDroitOrg(false);
        r.undo();
        var restaures = [], laisses = [];
        reaffectes.forEach(function (x) {
          var s = col.get(x.id);
          if (!s || s.statut === 'archive') { laisses.push({ id: x.id, poste: x.poste, motif: 'il est archivé depuis' }); return; }
          if (s.parentId !== cibleId) { laisses.push({ id: x.id, poste: x.poste, motif: 'il a été déplacé depuis sous « ' + (nomPosteOrg(s.parentId) || 'le sommet') + ' »' }); return; }
          var ctl = controlerRattachementOrg(x.id, posteId);
          if (ctl) { laisses.push({ id: x.id, poste: x.poste, motif: ctl.motif }); return; }
          var r2 = col.update(x.id, { parentId: posteId }, { journal: { action: 'Réaffectation d’un poste', module: 'CFG', entite: 'Poste',
            avant: { poste: x.poste, parentId: cibleNom }, apres: { parentId: poste.poste, motif: 'Archivage de « ' + poste.poste + ' » annulé' } } });
          if (r2) restaures.push({ id: x.id, poste: x.poste }); else laisses.push({ id: x.id, poste: x.poste, motif: 'l’écriture a été refusée par le magasin' });
        });
        return { ok: true, restaures: restaures, laisses: laisses };
      },
    };
  }

  global.SIGH.organigramme = {
    TITRE_MAX: TITRE_ORG_MAX, arbre: arbreOrganigramme, descendants: descendantsOrganigramme, agentDe: agentDuPosteOrg, titreDe: titreDuPosteOrg,
    controlerRattachement: controlerRattachementOrg, controler: controlerPosteOrg, modifier: modifierPosteOrg, reaffecter: reaffecterPosteOrg,
    renommerTitulaire: renommerTitulaireOrg, poserTitre: poserTitreOrg, creer: creerPosteOrg, archiver: archiverPosteOrg, planArchivage: planArchivageOrg,
  };
  /* ==========================================================================
   * LE VERROU D'UN POSTE DE SECOURS (11/11/2026, lot ORG2, décision P3 de la Direction)
   * --------------------------------------------------------------------------
   * Sur un poste partagé de secours (un agent sans téléphone y ouvre sa propre session, planning Q6), l'écran se verrouille plus vite que sur un poste
   * ordinaire : 5 minutes par défaut, contre 15 (CDCT 12.2, politique de sécurité). Le délai est un RÉGLAGE EN BASE (`verrouDelaiSecoursMinutes`), jamais
   * une constante : valeur d'attente de l'équipe, MARQUÉE « à valider » (aucun document ne la fixe), réglable par l'administrateur ou la Directrice
   * Administrative seuls, journalisé avec l'ancienne et la nouvelle valeur (RG-12).
   * Quel poste est « de secours » ? Une propriété du POSTE lui-même (de ce navigateur, comme le nom du poste), pas de la session ni de l'agent : on la
   * pose à ce poste, elle ne voyage pas. Ce n'est pas un droit : désigner un poste ne change aucun accès.
   * ======================================================================== */
  var SECOURS_DEFAUT_MIN = 5, SECOURS_BORNES = [1, 120], CLE_POSTE_SECOURS = 'sigh-cnt:poste-secours';
  function delaiSecoursMinutes() {
    var v = Number(S.reglage('verrouDelaiSecoursMinutes', SECOURS_DEFAUT_MIN));
    return isFinite(v) && v === Math.floor(v) && v >= SECOURS_BORNES[0] && v <= SECOURS_BORNES[1] ? v : SECOURS_DEFAUT_MIN;
  }
  /** Le délai du poste ORDINAIRE : la politique de sécurité quand elle est écrite, sinon quinze minutes (CDCT 12.2). */
  function delaiOrdinaireMinutes() {
    try {
      var pol = (S.raw().politiqueSecurite || []).filter(function (f) { return f.statut !== 'archive'; })[0];
      if (pol && Number(pol.inactiviteMin) > 0) return Number(pol.inactiviteMin);
    } catch (e) { /* le délai de référence s'applique */ }
    return 15;
  }
  function posteDeSecours() { try { return S.storage.get(CLE_POSTE_SECOURS) === '1'; } catch (e) { return false; } }
  /** Le délai de verrou EN FORCE sur ce poste, en minutes : celui du secours si le poste est désigné tel, sinon l'ordinaire. */
  function delaiVerrouPosteMinutes() { return posteDeSecours() ? delaiSecoursMinutes() : delaiOrdinaireMinutes(); }
  function reglerVerrouSecoursOk() { return ['admin', 'da'].indexOf(roleCourant()) >= 0; }
  function refusSecours(code, motif, geste) { return { ok: false, code: code, motif: motif, geste: geste }; }
  function definirDelaiSecours(o) {
    o = o || {};
    if (!reglerVerrouSecoursOk()) return refusSecours('REGLAGE_RESERVE', 'Ce réglage se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
    var m = Number(o.minutes);
    if (o.minutes === '' || o.minutes === null || o.minutes === undefined || !isFinite(m) || m !== Math.floor(m) || m < SECOURS_BORNES[0] || m > SECOURS_BORNES[1]) {
      return refusSecours('DELAI_INVALIDE', 'Le délai de verrou d’un poste de secours est un nombre entier de minutes, de ' + SECOURS_BORNES[0] + ' à ' + SECOURS_BORNES[1] + '.', 'Saisir un nombre entier de minutes.');
    }
    var avant = delaiSecoursMinutes();
    S.setReglage('verrouDelaiSecoursMinutes', m);
    S.log('Délai de verrou d’un poste de secours', 'M14', 'reglage', 'verrouDelaiSecoursMinutes', { minutes: avant }, { minutes: m, motif: o.motif || null });
    return { ok: true, minutes: m, avant: avant };
  }
  /** Désigne (ou retire la désignation de) CE poste comme poste de secours. */
  function definirPosteDeSecours(oui, motif) {
    if (!reglerVerrouSecoursOk()) return refusSecours('REGLAGE_RESERVE', 'Cette désignation se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
    var avant = posteDeSecours();
    try { S.storage.set(CLE_POSTE_SECOURS, oui === true ? '1' : '0'); } catch (e) { return refusSecours('POSTE_NON_ECRIT', 'Le navigateur de ce poste refuse d’écrire la désignation.', 'Autoriser le stockage du site, puis recommencer.'); }
    S.log('Poste de secours', 'M14', 'reglage', 'posteDeSecours', { secours: avant }, { secours: oui === true, delaiMinutes: delaiVerrouPosteMinutes(), motif: motif || null });
    return { ok: true, secours: oui === true, avant: avant, delaiMinutes: delaiVerrouPosteMinutes() };
  }
  global.SIGH.verrouSecours = {
    DEFAUT_MIN: SECOURS_DEFAUT_MIN, BORNES: SECOURS_BORNES, delaiSecours: delaiSecoursMinutes, delaiOrdinaire: delaiOrdinaireMinutes, posteDeSecours: posteDeSecours,
    delaiPoste: delaiVerrouPosteMinutes, peutRegler: reglerVerrouSecoursOk, definirDelai: definirDelaiSecours, definirPoste: definirPosteDeSecours,
  };
  /* ==========================================================================
   * LE PLAN DU SITE EST UN RÉGLAGE, DÉSACTIVÉ PAR DÉFAUT (11/11/2026, Direction)
   * --------------------------------------------------------------------------
   * Réglage EN BASE (`planDuSiteAffiche`, défaut NON), jamais une constante ni un masquage écrit dans l'écran : le manifeste porte la page (elle ne s'en retire
   * jamais) et son entrée déclare `sousReglage` ; `N.can` et `N.ouvertParReglage` lisent CE réglage, donc le ruban, la recherche, les cartes de hub, les accès
   * rapides, le menu profil et l'adresse directe suivent d'un seul mouvement. Réglable par l'administrateur et la Directrice Administrative seuls (le moteur
   * refuse en nommant), journalisé avec l'ancienne et la nouvelle valeur (RG-12). Réglage de BRANCHE : il voyage aux fileuls par le journal de configuration,
   * jamais aux mobiles.
   * ======================================================================== */
  var PLAN_CLE = 'planDuSiteAffiche';
  function planDuSiteAffiche() { return S.reglage(PLAN_CLE, false) === true; }
  function reglerPlanDuSiteOk() { return ['admin', 'da'].indexOf(roleCourant()) >= 0; }
  function definirPlanDuSite(oui, motif) {
    if (!reglerPlanDuSiteOk()) {
      return { ok: false, code: 'REGLAGE_RESERVE', motif: 'Ce réglage se fait par l’administrateur ou la Directrice Administrative.', geste: 'Demander à la Directrice Administrative.' };
    }
    if (oui !== true && oui !== false) {
      return { ok: false, code: 'VALEUR_INVALIDE', motif: 'Le plan du site est affiché ou masqué : oui ou non.', geste: 'Cocher ou décocher la case.' };
    }
    var avant = planDuSiteAffiche();
    /* Le journal d'abord : `setReglage` sauvegarde, et c'est cette sauvegarde qui emporte la ligne du journal. */
    S.log('Plan du site', 'M14', 'reglage', PLAN_CLE, { affiche: avant }, { affiche: oui, motif: motif || null });
    S.setReglage(PLAN_CLE, oui);
    return { ok: true, affiche: oui, avant: avant };
  }
  global.SIGH.planDuSite = { CLE: PLAN_CLE, DEFAUT: false, affiche: planDuSiteAffiche, peutRegler: reglerPlanDuSiteOk, definir: definirPlanDuSite };

  /* ==========================================================================
   * STOCK : UNE FABRIQUE POUR LE TRANSFERT GROS VERS DÉTAIL, UNE POUR LA RÉGULARISATION D'UN INVENTAIRE (lot IMP-B1, 11/11/2026)
   * --------------------------------------------------------------------------
   * Le geste de l'écran (« Nouveau transfert », « Valider l'inventaire ») et l'import en masse passent par la MÊME fabrique : un transfert importé ne peut donc rien
   * faire que le geste ne ferait pas (un bon numéroté, deux mouvements symétriques par ligne, stocks gros et détail), et surtout ne peut JAMAIS contourner RG-03. La règle ne vit
   * qu'ici : une règle écrite en deux exemplaires diverge au premier correctif (le code patient l'a payé deux fois).
   *
   *  - `controlerTransfert(lignes)` : RG-03 LIGNE PAR LIGNE en nommant l'article, le disponible tenant compte de ce qui est DÉJÀ posé sur le bon. N'écrit rien.
   *  - `emettreTransfert(entete, lignes, opts)` : contrôle d'abord (rien n'est écrit si une ligne est refusée), numérote le bon APRÈS la vérification, écrit stocks, mouvements
   *    et bon, rend un jeton d'ANNULATION qui restitue toutes les lignes (dans l'ordre inverse : le même article peut figurer sur deux lignes de lots différents).
   *  - `regulariserInventaire(inv, opts)` : un mouvement par écart sur le magasin COMPTÉ. `opts.strict` (import) refuse si le stock a bougé depuis le comptage.
   * ======================================================================== */
  var DESTINATIONS_TRANSFERT = ['Pharmacie d’urgence', 'Pharmacie externe', 'Laboratoire', 'Hospitalisation', 'Maternité', 'Bloc opératoire', 'Salle de soins'];

  function refusStock(code, motif, geste, extra) { return Object.assign({ ok: false, code: code, motif: motif, geste: geste || null }, extra || {}); }

  /** Le lot à sortir en premier (FEFO, RG-05) : péremption la plus proche, ni périmé ni épuisé, et tenu au magasin CENTRAL (un lot posé au détail par un stock initial ne part pas du gros). */
  function lotFefo(produitId) {
    return S.collection('lots').active().filter(function (x) {
      return x.produitId === produitId && x.statut !== 'perime' && (x.quantiteRestante || 0) > 0 && x.magasin !== 'detail';
    }).sort(function (a, b) { return String(a.datePeremption).localeCompare(String(b.datePeremption)); })[0] || null;
  }

  /** RG-03 pour UNE ligne : `deja` est ce qui est déjà posé sur le bon pour cet article. Rend un refus nommé, ou `null`. Importée ligne à ligne par le jeu d'import (une seule règle). */
  function refusLigneTransfert(pr, q, deja, i) {
    q = Number(q);
    if (!(q > 0) || Math.floor(q) !== q) return refusStock('QUANTITE_INVALIDE', '« ' + pr.designation + ' » : la quantité doit être un entier supérieur à zéro', 'Indiquer une quantité entière d’au moins 1.', { ligne: i, produit: pr.designation });
    var dispo = (pr.stockGros || 0) - (deja || 0);
    /* RG-03, ligne par ligne, en NOMMANT l'article ; le disponible tient compte de ce qui est déjà posé sur le bon. */
    if (q > dispo) {
      return refusStock('RG03_STOCK_INSUFFISANT',
        'RG-03 : « ' + pr.designation + ' » : ' + C.num(Math.max(0, dispo)) + ' ' + (pr.unite || '') + ' encore disponible(s) au magasin' + (deja ? ' (déjà ' + C.num(deja) + ' sur ce bon)' : '') + ', ' + C.num(q) + ' demandé(s)',
        'Réduire la quantité, ou attendre une réception fournisseur : le stock du magasin ne peut jamais devenir négatif.', { ligne: i, produit: pr.designation, disponible: Math.max(0, dispo) });
    }
    return null;
  }

  function controlerTransfert(lignes) {
    var pose = {};
    for (var i = 0; i < (lignes || []).length; i++) {
      var l = lignes[i], pr = produitParId(l.produitId);
      if (!pr) return refusStock('PRODUIT_INCONNU', 'la ligne ' + (i + 1) + ' désigne un article inconnu', 'Choisir un article du référentiel.', { ligne: i });
      var r = refusLigneTransfert(pr, l.quantite, pose[pr.id] || 0, i);
      if (r) return r;
      pose[pr.id] = (pose[pr.id] || 0) + Number(l.quantite);
    }
    return { ok: true, pose: pose };
  }

  function emettreTransfert(entete, lignes, opts) {
    entete = entete || {}; opts = opts || {};
    if (!lignes || !lignes.length) return refusStock('BON_VIDE', 'un bon de transfert porte au moins un article', 'Ajouter au moins un article au bon.');
    if (!entete.demandeur) return refusStock('DESTINATION_ABSENTE', 'le bon n’a pas de service destinataire', 'Choisir le service demandeur.');
    var c = controlerTransfert(lignes);
    if (!c.ok) return c;
    var date = entete.date || C.iso(C.aujourdhui()), marque = opts.marque || {};
    /* LE NUMÉRO SUIT LE REGISTRE, pas un compteur de page, et il est pris APRÈS la vérification : un refus ne consomme aucun numéro. */
    var colBons = S.collection('transferts', { module: 'M6', entite: 'Transfert' });
    var dernier = colBons.all().reduce(function (mx, x) { var mm = /^TR-(\d+)$/.exec(x.reference || ''); return mm ? Math.max(mx, Number(mm[1])) : mx; }, 0);
    var reference = 'TR-' + C.pad(dernier + 1, 5);
    var colMvt = S.collection('mouvements', { module: 'M6', entite: 'MouvementStock' });
    var etats = [], mvts = [], pleines = [], res = null;
    function annuler() {
      etats.slice().reverse().forEach(function (e) { S.collection('produits').update(e.id, { stockGros: e.gros, stockDetail: e.detail }); });
      mvts.forEach(function (x) { x.undo(); });
      if (res) res.undo();
    }
    try {
      lignes.forEach(function (l) {
        var pr = produitParId(l.produitId);
        var lotF = l.lot === undefined ? lotFefo(pr.id) : (l.lot ? S.collection('lots').active().filter(function (x) { return x.produitId === pr.id && x.numeroLot === l.lot; })[0] : null);
        var pleine = { produitId: pr.id, code: pr.code, produit: pr.designation, categorie: pr.categorie, unite: pr.unite, cump: pr.cump, quantite: Number(l.quantite),
          lot: l.lot === undefined ? (lotF ? lotF.numeroLot : null) : (l.lot || null), peremption: l.peremption !== undefined ? l.peremption : (lotF ? lotF.datePeremption : null) };
        pleines.push(pleine);
        etats.push({ id: pr.id, gros: pr.stockGros, detail: pr.stockDetail });
        if (!S.collection('produits').update(pr.id, { stockGros: pr.stockGros - pleine.quantite, stockDetail: (pr.stockDetail || 0) + pleine.quantite })) throw new Error('le stock de « ' + pr.designation + ' » n’a pas pu être mis à jour');
        /* DEUX MOUVEMENTS SYMÉTRIQUES (RG-03) : le magasin débité, la pharmacie créditée. */
        [['Transfert — sortie magasin', 'gros'], ['Transfert — entrée pharmacie', 'detail']].forEach(function (t) {
          var m = colMvt.insert(Object.assign({
            reference: reference, date: date, produitId: pr.id, produit: pr.designation,
            type: 'transfert', typeLabel: t[0], quantite: pleine.quantite,
            stockType: t[1], justificatif: 'Bon de transfert ' + reference,
            utilisateur: S.currentUser(),
          }, marque));
          if (!m) throw new Error('un mouvement de stock a été refusé par le moteur');
          mvts.push(m);
        });
      });
      var total = pleines.reduce(function (n, l) { return n + l.quantite; }, 0);
      res = colBons.insert(Object.assign({}, { date: date, demandeur: entete.demandeur, motif: entete.motif || '' }, marque, {
        reference: reference, lignes: pleines.slice(), nbLignes: pleines.length, quantiteTotale: total,
        valeur: pleines.reduce(function (n, l) { return n + l.quantite * (l.cump || 0); }, 0),
        operateur: S.currentUser(), etat: 'receptionne', dateReception: date,
        /* Compatibilité avec les bons antérieurs, qui ne portaient qu'un produit : le tableau du registre lit ces champs. */
        produit: pleines.length === 1 ? pleines[0].produit : pleines.length + ' articles', unite: pleines.length === 1 ? pleines[0].unite : '', quantite: total,
      }));
      if (!res) throw new Error('le bon de transfert a été refusé par le moteur');
    } catch (e) {
      annuler();
      return refusStock('ECRITURE_REFUSEE', e && e.message ? e.message : String(e), 'Rien n’a été écrit : les stocks sont restitués.');
    }
    return { ok: true, bon: res.record, reference: reference, mouvements: mvts.map(function (m) { return m.record; }), lignes: pleines, annuler: annuler };
  }

  /** Régularise un inventaire : un mouvement par écart sur le magasin COMPTÉ, le total qui en découle. `opts.strict` : refuser si le stock du magasin a bougé depuis le comptage
      (un écart calculé sur un théorique périmé régulariserait un chiffre faux). Sans `strict`, c'est le geste de la feuille de saisie, qui régularise à l'instant du comptage. */
  function regulariserInventaire(inv, opts) {
    opts = opts || {};
    var magasin = inv.magasin === 'detail' ? 'detail' : 'gros', champ = magasin === 'detail' ? 'stockDetail' : 'stockGros';
    var ecarts = (inv.lignes || []).filter(function (l) { return l.ecart !== 0 && l.ecart != null; });
    if (opts.strict) {
      for (var i = 0; i < ecarts.length; i++) {
        var pr0 = produitParId(ecarts[i].produitId);
        if (!pr0) return refusStock('PRODUIT_INCONNU', 'l’article « ' + ecarts[i].designation + ' » n’existe plus', 'Retirer l’article de la feuille ou le restaurer.', { ligne: i });
        if ((pr0[champ] || 0) !== ecarts[i].theorique) {
          return refusStock('REGULARISATION_PERIMEE', 'le stock ' + (magasin === 'detail' ? 'détail' : 'gros') + ' de « ' + pr0.designation + ' » a bougé depuis le comptage (théorique ' + ecarts[i].theorique + ', aujourd’hui ' + (pr0[champ] || 0) + ')',
            'Recompter cet article et importer une nouvelle feuille : un écart calculé sur un théorique périmé ne se régularise pas.', { article: pr0.designation });
        }
        if ((pr0[champ] || 0) + ecarts[i].ecart < 0) return refusStock('RG03_STOCK_NEGATIF', 'RG-03 : la régularisation de « ' + pr0.designation + ' » rendrait le stock négatif', 'Corriger le comptage.', { article: pr0.designation });
      }
    }
    var annulations = [], mouvs = [];
    ecarts.forEach(function (x) {
      var pr = produitParId(x.produitId);
      if (!pr) return;
      var avant = { stockGros: pr.stockGros, stockDetail: pr.stockDetail, stock: pr.stock };
      var maj = { stock: Math.max(0, (pr.stock || 0) + x.ecart) };
      maj[champ] = Math.max(0, (pr[champ] || 0) + x.ecart);
      S.collection('produits').update(pr.id, maj);
      var mv = S.collection('mouvements', { module: 'M6', entite: 'MouvementStock' }).insert({
        reference: C.referenceSuivante('M', 6, S.collection('mouvements').all()), date: opts.date || inv.date, /* (E17) */
        produitId: pr.id, produit: pr.designation, type: 'inventaire', typeLabel: 'Régularisation inventaire',
        quantite: Math.abs(x.ecart), stockType: magasin, justificatif: 'Inventaire ' + inv.reference, utilisateur: opts.operateur || inv.operateur,
      });
      mouvs.push(mv.record);
      annulations.push(function () { S.collection('produits').update(pr.id, avant); mv.undo(); });
    });
    return { ok: true, nb: ecarts.length, mouvements: mouvs, annuler: function () { annulations.slice().reverse().forEach(function (u) { u(); }); } };
  }

  /* ==========================================================================
   * SEUILS DE VARIATION BRUTALE, OU DELTA CHECK (lot A2, EF-ANT-3 et EF-ANT-3b)
   * --------------------------------------------------------------------------
   * Un seuil dit de combien une variable numérique peut bouger entre deux mesures rendues du même patient avant que le laboratoire s'arrête
   * pour relire. Cinq règles, toutes tenues ICI (l'écran de réglage, le comparatif et l'écran de validation biologique les appellent) :
   *   1. AUCUN seuil par défaut, aucun n'est semé ni proposé : aucun document de cadrage n'en donne, c'est une décision du Biologiste médical.
   *      Un seuil vide veut dire « pas d'alerte configurée », jamais zéro (une valeur nulle ou négative est refusée en le disant).
   *   2. DEUX états visibles. « Enregistré » : saisi, SANS EFFET, aucune alerte. « Validé » : en vigueur. Enregistrer garde l'état Enregistré,
   *      Valider fait passer de Enregistré à Validé. Seul un seuil Validé alerte.
   *   3. Valider est le geste des profils de la famille « Variables et unités du laboratoire » (le Biologiste médical), liste de rôles lue à la
   *      famille et revérifiée ICI : masquer un bouton ne protège rien. Le geste est tracé (auteur, rôle, date, motif obligatoire, RG-12).
   *   4. Un seuil Validé est IMMUABLE (garde du magasin) : le modifier AJOUTE une version datée, l'ancienne reste lisible. Une mesure se juge au
   *      seuil en vigueur à la date de sa validation biologique (à aujourd'hui tant qu'elle n'est pas validée) : une alerte déjà levée garde donc
   *      le seuil sous lequel elle l'a été. La date d'effet ne peut pas être passée.
   *   5. L'alerte SIGNALE, elle ne bloque jamais (doctrine du bloc : signalé, jamais bloqué) et ne porte aucune donnée médicale dans une
   *      notification : elle n'en crée aucune.
   * ======================================================================== */
  var ECRAN_SEUILS = 'm5-valeurs-reference';
  function colSeuils() { return S.collection('seuilsDelta', { module: 'M5', entite: 'seuil de variation brutale', prefix: 'SEU' }); }
  function refusSeuil(code, motif, geste, extra) { return refusCfg(code, motif, geste, extra); }
  /* LE DROIT DE VALIDER UN SEUIL est un geste réservé de la fiche RBAC (nav.js, `valider_seuil_labo`) : aucune liste de rôles n'est écrite ici (lot B, réponse de la Direction du
     13/11/2026). Le Biologiste médical l'a d'origine, un administrateur peut l'accorder à un rôle ou le retirer. */
  var GESTE_VALIDER_SEUIL = 'valider_seuil_labo';
  function rolesValidationSeuils() { var N = global.SIGH.nav; return N && N.rolesAvecGeste ? N.rolesAvecGeste(GESTE_VALIDER_SEUIL) : []; }
  function peutValiderSeuil(role) { var N = global.SIGH.nav; return !!(N && N.droitGeste && N.droitGeste(role == null ? roleCourant() : role, GESTE_VALIDER_SEUIL)); }
  function peutEnregistrerSeuil(role) {
    var N = global.SIGH.nav, r = role == null ? roleCourant() : role;
    var d = N && N.droitsEcran ? N.droitsEcran(r, ECRAN_SEUILS, 'M5') : null;
    return !!(d && d.editer);
  }
  function versionsSeuil(variableId) {
    return colSeuils().active().filter(function (x) { return x.variableId === variableId; }).sort(function (a, b) { return a.version - b.version; });
  }
  /** Le seuil VALIDÉ en vigueur à une date : la version validée la plus récente dont la date d'effet est atteinte. Jamais un Enregistré. */
  function seuilEnVigueur(variableId, date) {
    var d = isoJour(date || aujIso());
    var c = versionsSeuil(variableId).filter(function (x) { return x.etat === 'valide' && x.dateEffet <= d; })
      .sort(function (a, b) { return String(a.dateEffet).localeCompare(String(b.dateEffet)) || a.version - b.version; });
    return c.length ? c[c.length - 1] : null;
  }
  function brouillonSeuil(variableId) { return versionsSeuil(variableId).filter(function (x) { return x.etat === 'enregistre'; })[0] || null; }
  /** L'état affiché d'une variable : 'aucun' | 'enregistre' | 'valide' | 'enregistre_sur_valide' (un brouillon attend sa validation, la version validée reste en force). */
  function etatSeuil(variableId) {
    var vig = seuilEnVigueur(variableId), b = brouillonSeuil(variableId), vs = versionsSeuil(variableId);
    var actif = vig && !vig.retrait ? vig : null;
    return {
      variableId: variableId, versions: vs, brouillon: b, enVigueur: actif, retire: !!(vig && vig.retrait),
      aVenir: vs.filter(function (x) { return x.etat === 'valide' && x.dateEffet > aujIso(); })[0] || null,
      etat: b ? (actif ? 'enregistre_sur_valide' : 'enregistre') : (actif ? 'valide' : 'aucun'),
    };
  }
  function seuilNombre(x) { return x == null || x === '' ? null : Number(x); }
  function controleDatesSeuil(variableId, d) {
    if (d < aujIso()) {
      return refusSeuil('DATE_EFFET_PASSEE', 'La date d’effet (' + C.dateFR(d) + ') est passée : un seuil ne s’applique jamais en arrière, une alerte déjà levée garde le seuil sous lequel elle l’a été.',
        'Choisir une date d’effet à partir d’aujourd’hui (' + C.dateFR(aujIso()) + ').');
    }
    var valides = versionsSeuil(variableId).filter(function (x) { return x.etat === 'valide'; });
    var derniere = valides.sort(function (a, b) { return String(a.dateEffet).localeCompare(String(b.dateEffet)) || a.version - b.version; }).pop();
    if (derniere && d < derniere.dateEffet) {
      return refusSeuil('DATE_EFFET_ANTERIEURE', 'La date d’effet (' + C.dateFR(d) + ') est antérieure à la version ' + derniere.version + ' déjà validée (' + C.dateFR(derniere.dateEffet) + ').',
        'Choisir une date d’effet au plus tôt le ' + C.dateFR(derniere.dateEffet) + '.');
    }
    return null;
  }
  /** ENREGISTRER : saisit un seuil (ou son retrait), état Enregistré, SANS EFFET. Une seconde saisie remplace le brouillon, jamais une version validée. */
  function enregistrerSeuil(variableId, o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    if (!peutEnregistrerSeuil()) {
      return refusSeuil('DROIT_REFUSE', 'Le profil ' + libelleRole(roleCourant()) + ' ne règle pas les seuils de variation brutale (écran « Valeurs de référence »).',
        'Demander à un profil qui modifie les valeurs de référence du laboratoire.');
    }
    var v = S.collection('variablesLabo').get(variableId);
    if (!v || v.statut === 'archive') return refusSeuil('VARIABLE_INTROUVABLE', 'Aucune variable « ' + variableId + ' » au catalogue du laboratoire.', 'Choisir une variable à l’écran « Valeurs de référence ».');
    if (v.type !== 'numerique' || v.accompagnement) {
      return refusSeuil('VARIABLE_NON_NUMERIQUE', 'Un seuil de variation ne se pose que sur une variable numérique : « ' + v.libelle + ' » est de type « ' + global.SIGH.labo.type(v.type) + ' » et se compare en texte.',
        'Choisir une variable numérique.');
    }
    var abs = seuilNombre(o.ecartAbsolu), rel = seuilNombre(o.ecartRelatif), retrait = o.retrait === true;
    if ((abs != null && !(abs > 0)) || (rel != null && !(rel > 0))) {
      return refusSeuil('SEUIL_INVALIDE', 'Un seuil est un nombre strictement positif : zéro alerterait à chaque mesure.', 'Saisir un nombre supérieur à zéro, ou laisser vide pour ne pas alerter.');
    }
    /* LE DÉLAI MAXIMAL ENTRE DEUX MESURES (lot B) : un nombre ENTIER de jours, VIDE par défaut (aucune valeur inventée). Il se pose AVEC le seuil, sur la même version, sous la même validation. */
    var delai = seuilNombre(o.delaiMaxJours);
    if (delai != null && !(Number.isInteger(delai) && delai > 0)) {
      return refusSeuil('DELAI_INVALIDE', 'Le délai maximal entre deux mesures est un nombre entier de jours, au moins 1 : zéro refuserait d’évaluer toute variation.', 'Saisir un nombre entier de jours supérieur à zéro, ou laisser vide pour n’imposer aucun délai.');
    }
    if (retrait) {
      if (delai != null) return refusSeuil('RETRAIT_AVEC_VALEURS', 'Retirer le seuil ne porte aucun délai.', 'Vider le délai, ou décocher le retrait.');
      if (abs != null || rel != null) return refusSeuil('RETRAIT_AVEC_VALEURS', 'Retirer le seuil ne porte aucune valeur.', 'Vider les deux champs, ou décocher le retrait.');
      if (!seuilEnVigueur(variableId, '9999-12-31')) return refusSeuil('RIEN_A_RETIRER', 'Aucun seuil validé sur « ' + v.libelle + ' » : il n’y a rien à retirer.', 'Fermer la fenêtre.');
    } else if (abs == null && rel == null) {
      return refusSeuil('SEUIL_VIDE', 'Aucune valeur saisie : un seuil vide veut dire « pas d’alerte configurée », il ne s’enregistre pas.', 'Saisir une variation absolue ou relative, ou ne rien enregistrer.');
    }
    var d = isoJour(o.dateEffet || aujIso());
    r = controleDatesSeuil(variableId, d); if (r) return r;
    var b = brouillonSeuil(variableId), maintenant = new Date().toISOString();
    var champs = { ecartAbsolu: abs, ecartRelatif: rel, delaiMaxJours: delai, retrait: retrait, dateEffet: d, note: o.note ? String(o.note).trim() : null,
      enregistrePar: acteur(), enregistreLe: maintenant, enregistreRole: roleCourant() };
    /* Le journal tronque ses extraits à 100 caractères : le plus utile vient en premier, la trace entière est la version elle-même (immuable une fois validée). */
    var apres = { v: b ? b.version : versionsSeuil(variableId).reduce(function (m, x) { return Math.max(m, x.version); }, 0) + 1, du: d, abs: abs, rel: rel, delai: delai, retrait: retrait };
    var rec;
    if (b) {
      rec = colSeuils().update(b.id, champs, { journal: { action: 'Seuil de variation enregistré (sans effet)', entite: 'seuil de variation', avant: { abs: b.ecartAbsolu, rel: b.ecartRelatif, du: b.dateEffet }, apres: apres } });
    } else {
      var n = versionsSeuil(variableId).reduce(function (m, x) { return Math.max(m, x.version); }, 0) + 1;
      rec = colSeuils().insert(Object.assign({
        variableId: variableId, variableCode: v.code, variableLibelle: v.libelle, examen: v.examen, examenLibelle: v.examenLibelle, unite: v.unite,
        version: n, etat: 'enregistre', valideLe: null, validePar: null, valideRole: null, motifValidation: null,
      }, champs), { journal: { action: 'Seuil de variation enregistré (sans effet)', entite: 'seuil de variation', avant: null, apres: apres } });
    }
    if (!rec) return refusSeuil('ECRITURE_REFUSEE', 'Le magasin a refusé l’écriture du seuil.', 'Voir le journal.');
    return { ok: true, seuil: colSeuils().get(rec.record.id), creation: !b };
  }
  /** VALIDER : le brouillon devient la version en vigueur à sa date d'effet. Réservé à la famille du laboratoire, revérifié ici, motif obligatoire. */
  function validerSeuil(variableId, o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    var role = roleCourant();
    if (!peutValiderSeuil(role)) {
      var liste = rolesValidationSeuils();
      return refusSeuil('VALIDATION_RESERVEE', 'Valider un seuil de variation brutale est un droit réservé' + (liste.length ? ' (porté aujourd’hui par : ' + liste.map(libelleRole).join(', ') + ')' : ' (aucun rôle ne le porte aujourd’hui)')
        + '. Profil : ' + libelleRole(role) + '.',
        liste.length ? 'Demander à ' + libelleRole(liste[0]) + ' de valider depuis son poste, ou faire accorder le droit « Valider un seuil » à ce rôle par un administrateur (Rôles et permissions, gestes réservés).'
          : 'Faire accorder le droit « Valider un seuil » à un rôle par un administrateur (Rôles et permissions, gestes réservés).');
    }
    var b = brouillonSeuil(variableId);
    if (!b) return refusSeuil('SEUIL_NON_ENREGISTRE', 'Aucun seuil Enregistré à valider sur cette variable : un seuil se saisit et s’enregistre d’abord.', 'Régler le seuil, l’enregistrer, puis le valider.');
    if (!String(o.motif || '').trim()) return refusSeuil('MOTIF_OBLIGATOIRE', 'Le motif de la validation est obligatoire : il dit sur quoi le seuil s’appuie.', 'Saisir le motif, puis valider.');
    r = controleDatesSeuil(variableId, b.dateEffet);
    if (r) return Object.assign(r, { geste: 'Enregistrer de nouveau le seuil avec une date d’effet à partir d’aujourd’hui, puis le valider.' });
    var quand = new Date().toISOString(), qui = acteur(), lib = libelleRole(role);
    var res = colSeuils().update(b.id, { etat: 'valide', valideLe: quand, validePar: qui, valideRole: lib, motifValidation: String(o.motif).trim() },
      { journal: { action: 'Seuil de variation validé', entite: 'seuil de variation', avant: { etat: 'enregistre' },
        apres: { v: b.version, du: b.dateEffet, abs: b.ecartAbsolu, rel: b.ecartRelatif, motif: String(o.motif).trim().slice(0, 40) } } });
    if (!res) return refusSeuil('ECRITURE_REFUSEE', 'Le magasin a refusé la validation du seuil.', 'Voir le journal.');
    return { ok: true, seuil: colSeuils().get(b.id), valideLe: quand, validePar: qui, valideRole: lib };
  }
  /** Abandonne le brouillon (archivage RG-14, jamais une suppression) : la version validée, s'il y en a une, reste en force. */
  function abandonnerSeuil(variableId, o) {
    o = o || {};
    var r = controleEcritureCfg(); if (r) return r;
    if (!peutEnregistrerSeuil()) return refusSeuil('DROIT_REFUSE', 'Le profil ' + libelleRole(roleCourant()) + ' ne règle pas les seuils de variation brutale.', 'Demander à un profil qui modifie les valeurs de référence du laboratoire.');
    var b = brouillonSeuil(variableId);
    if (!b) return refusSeuil('SEUIL_NON_ENREGISTRE', 'Aucun seuil Enregistré à abandonner sur cette variable.', 'Fermer la fenêtre.');
    var res = colSeuils().archive(b.id, o.motif || 'Brouillon abandonné', { journal: { action: 'Seuil de variation abandonné (brouillon)', entite: 'seuil de variation', avant: { etat: 'enregistre', abs: b.ecartAbsolu, rel: b.ecartRelatif }, apres: { statut: 'archive' } } });
    return res ? { ok: true } : refusSeuil('ECRITURE_REFUSEE', 'Le magasin a refusé l’abandon du brouillon.', 'Voir le journal.');
  }
  /**
   * L'alerte d'une variation (EF-ANT-3) : `null` quand aucun seuil Validé n'est en vigueur à la date (pas d'alerte configurée), sinon
   * { alerte, seuil, raisons[], nonEvaluable }. Le seuil absolu se compare à l'écart absolu, le relatif au pourcentage ; un seuil relatif ne s'évalue pas
   * sur une valeur précédente nulle (pas de pourcentage inventé) et le dit.
   */
  function alerteVariation(variable, variation, date, ctx) {
    if (!variable || !variation || variation.mode !== 'numerique') return null;
    var s = seuilEnVigueur(variable.id, date);
    if (!s || s.retrait) return null;
    /* LE DÉLAI (lot B) : au-delà du délai réglé entre la mesure précédente et la mesure jugée, la variation N'EST PAS ÉVALUÉE. « Non évalué » n'est pas « pas d'alerte » : le verdict le dit
       (`nonEvalue: 'delai'`, l'âge et le délai) pour que le comparatif l'écrive. Un âge qu'on ne sait pas calculer n'est ni zéro ni dépassé : la variation s'évalue et le verdict porte `ageInconnu`.
       Le délai ne BLOQUE jamais rien : il retire seulement l'évaluation. */
    var age = ctx && ctx.ageJours != null && isFinite(Number(ctx.ageJours)) ? Number(ctx.ageJours) : null;
    if (s.delaiMaxJours != null && age != null && age > s.delaiMaxJours) {
      return { alerte: false, seuil: s, raisons: [], nonEvaluable: false, nonEvalue: 'delai', ageJours: age, delaiMaxJours: s.delaiMaxJours };
    }
    var raisons = [];
    if (s.ecartAbsolu != null && variation.ecartAbsolu >= s.ecartAbsolu) raisons.push({ type: 'absolu', seuil: s.ecartAbsolu, mesure: variation.ecartAbsolu });
    if (s.ecartRelatif != null && variation.pourcent != null && Math.abs(variation.pourcent) >= s.ecartRelatif) raisons.push({ type: 'relatif', seuil: s.ecartRelatif, mesure: Math.abs(variation.pourcent) });
    return { alerte: raisons.length > 0, seuil: s, raisons: raisons, nonEvaluable: s.ecartRelatif != null && s.ecartAbsolu == null && variation.pourcent == null,
      nonEvalue: null, ageJours: age, delaiMaxJours: s.delaiMaxJours != null ? s.delaiMaxJours : null, ageInconnu: s.delaiMaxJours != null && age == null };
  }
  /** Les versions de seuil à l'état Enregistré (sans effet), toutes variables : ce que le centre des validations compte. Lu du magasin à chaque appel, jamais écrit. */
  function seuilsEnAttente() {
    var l = colSeuils().active().filter(function (x) { return x.etat === 'enregistre'; });
    return { total: l.length, variables: l.map(function (x) { return x.variableId; }) };
  }
  global.SIGH.laboSeuils = {
    enAttente: seuilsEnAttente,
    ECRAN: ECRAN_SEUILS, rolesValidation: rolesValidationSeuils, peutValider: peutValiderSeuil, peutEnregistrer: peutEnregistrerSeuil,
    versions: versionsSeuil, enVigueur: seuilEnVigueur, brouillon: brouillonSeuil, etat: etatSeuil,
    enregistrer: enregistrerSeuil, valider: validerSeuil, abandonner: abandonnerSeuil, alerteVariation: alerteVariation,
  };

  global.SIGH.parcours.DESTINATIONS_TRANSFERT = DESTINATIONS_TRANSFERT;
  global.SIGH.parcours.lotFefo = lotFefo;
  global.SIGH.parcours.controlerTransfert = controlerTransfert;
  global.SIGH.parcours.refusLigneTransfert = refusLigneTransfert;
  global.SIGH.parcours.emettreTransfert = emettreTransfert;
  global.SIGH.parcours.regulariserInventaire = regulariserInventaire;
})(window);
