/* =============================================================================
 * IMPORTATION DE DONNÉES (module IMP) : modèles .xlsx à télécharger, fichier à téléverser, analyse COMPLÈTE avant écriture
 * -----------------------------------------------------------------------------
 * UN MOTEUR, DES JEUX DÉCLARATIFS. Chaque jeu dit ses colonnes (type, obligatoire, référentiel de contrôle), sa clé de
 * dédoublonnage et ses règles métier par ligne ; le moteur fait le reste, toujours dans le même ordre :
 *   1. lire le fichier (.xlsx ou .csv) ; 2. contrôler les colonnes ; 3. contrôler chaque cellule ; 4. dédoublonner (dans le fichier,
 *   puis contre le magasin) ; 5. appliquer les règles métier ; 6. contrôler le lot entier (RG-10 pour les soldes d'ouverture).
 * RIEN n'est écrit avant la confirmation. Un refus se NOMME : ligne, colonne, valeur, motif et geste de correction.
 * Un fichier refusé est CONSIGNÉ (lot « refusé ») et n'écrit rien. Un lot accepté s'écrit d'un seul geste, chaque fiche portant
 * `source`, `lotImport`, `validePar` et `dateImport`. Un lot s'ANNULE en archivant ses fiches (RG-14), jamais en les supprimant.
 *
 * SOURCES : aucun jeu n'invente une donnée. Le modèle ne contient que des colonnes lues dans les collections existantes ; les
 * référentiels de contrôle viennent du magasin (assureurs, fournisseurs, plan comptable) ou des référentiels de la maquette.
 * Un jeu marqué « proposition à valider » écrit une donnée incomplète et le dit.
 *
 * LE DROIT D'IMPORT EST DISTINCT, PAR JEU, ET TENU PAR LE MOTEUR (lot IMP-A, 11/11/2026). Voir, importer et annuler se lisent de `N.droitImport(rôle, jeu)` (manifeste `N.IMPORTS`,
 * fiche RBAC `droitsImport`), jamais du droit d'éditer l'écran : `analyserOctets`, `appliquer` et `annulerLot` REFUSENT en nommant, car masquer un bouton ne protège rien.
 * Un jeu RESTREINT (patients, personnel, soldes d'ouverture) ne recopie jamais une valeur de cellule dans l'historique ni dans le rapport : le constat porte colonne, code et geste.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data, K = global.SIGH.kit,
      N = global.SIGH.nav, X = global.SIGH.xlsx;
  var el = C.el;

  var NOMS_FEUILLES = { donnees: 'Données', instructions: 'Instructions', listes: 'Listes' };

  /* --- Le droit d'import, la sensibilité et le mode de doublon : TOUS lus de la déclaration du manifeste ---------------- */
  function roleCourant() { var s = S.session() || {}; return s.role || ''; }
  function decl(j) { return (N.jeuImport && N.jeuImport(j.id)) || {}; }
  function droitDe(j) { return N.droitImport(roleCourant(), j.id); }
  function restreint(j) { return decl(j).sensibilite === 'restreinte'; }
  function modeDoublon(j) { return decl(j).doublon || 'refuser'; }
  function libelleRole(r) { return (N.ROLES[r] && N.ROLES[r].label) || r || 'inconnu'; }
  /** Un refus de droit se NOMME : le profil, le jeu, le geste. */
  function refusDroit(j, geste) {
    var d = droitDe(j);
    if (d[geste]) return null;
    var verbe = { voir: 'voir', importer: 'importer', annuler: 'annuler un lot de' }[geste] || geste;
    return { ok: false, code: 'DROIT_IMPORT_REFUSE',
      motif: 'le profil « ' + libelleRole(roleCourant()) + ' » ne détient pas le droit de ' + verbe + ' le jeu « ' + j.libelle + ' »',
      geste: 'Demander ce droit à l’administrateur : il se règle par jeu dans « Rôles & permissions », section Importation.' };
  }

  /* --- La taille maximale d'un fichier : UN RÉGLAGE EN BASE PAR JEU, avec un défaut (règle de paramétrage du 09/11) ------ *
   * Mesurée AVANT d'être posée (I12) : voir ECARTS-MAQUETTE.md. Jamais une constante du code : la valeur lue est celle du réglage `importBornes`, le défaut ci-dessous ne
   * sert que tant que la clinique n'a rien réglé. Le refus se nomme et dit où relever la borne. */
  var BORNE_DEFAUT_GENERALE = 5000;
  var BORNES_DEFAUT = {};
  var BORNE_MAXIMALE = 100000;
  function bornesImport() { return Object.assign({}, BORNES_DEFAUT, S.reglage('importBornes', null) || {}); }
  function borneDe(j) {
    var v = bornesImport()[typeof j === 'string' ? j : j.id];
    return typeof v === 'number' && isFinite(v) && v > 0 ? Math.floor(v) : BORNE_DEFAUT_GENERALE;
  }
  function definirBorne(jeuId, lignes, motif) {
    var j = jeu(jeuId);
    if (!j) return { ok: false, code: 'JEU_INCONNU', motif: 'aucun jeu d’import « ' + jeuId + ' »', geste: 'Choisir un jeu de la liste.' };
    if (!N.superviseImport(roleCourant())) return { ok: false, code: 'REGLAGE_RESERVE', motif: 'la taille maximale d’un fichier se règle par un profil qui supervise les importations (droit d’annuler sur tous les jeux)', geste: 'Demander le réglage à la Directrice Administrative ou à l’administrateur.' };
    var n = Number(lignes);
    if (lignes === '' || lignes === null || lignes === undefined || !isFinite(n) || n !== Math.floor(n) || n < 1 || n > BORNE_MAXIMALE) {
      return { ok: false, code: 'BORNE_INVALIDE', motif: 'la taille maximale est un nombre entier de lignes, de 1 à ' + BORNE_MAXIMALE, geste: 'Saisir un nombre entier de lignes.' };
    }
    if (!String(motif || '').trim()) return { ok: false, code: 'MOTIF_REQUIS', motif: 'un réglage de taille se motive', geste: 'Saisir le motif du réglage.' };
    var avant = borneDe(j), tous = Object.assign({}, S.reglage('importBornes', null) || {});
    tous[j.id] = n;
    S.log('Taille maximale d’un fichier d’import', 'IMP', 'reglage', j.id, { lignes: avant }, { lignes: n, motif: String(motif).slice(0, 60) });
    S.setReglage('importBornes', tous);
    return { ok: true, jeu: j.id, avant: avant, lignes: n };
  }

  /* --- Un jeu RESTREINT ne recopie jamais une valeur de cellule (RG-13, I11) ------------------------------------------- *
   * Le constat garde la ligne, la colonne, le code et le geste. Le MOTIF n'est pas recopié non plus : il cite la valeur (« « X » n'est pas une valeur permise »), le nom d'un
   * agent déjà tenu, les totaux d'une pièce. Il est remplacé par une phrase fixe, propre au code. */
  var MOTIFS_FIXES = {
    CHAMP_OBLIGATOIRE: 'valeur obligatoire absente', TYPE_INVALIDE: 'valeur d’un autre type que celui attendu', FORMAT_INVALIDE: 'format non conforme',
    TROP_LONG: 'texte plus long que le maximum', HORS_BORNES: 'valeur hors des bornes', VALEUR_HORS_LISTE: 'valeur hors de la liste permise',
    DOUBLON_FICHIER: 'ligne en double dans le fichier', DOUBLON_MAGASIN: 'une fiche équivalente est déjà tenue', DATE_FUTURE: 'date dans le futur',
    SALAIRE_ABSENT: 'salaire de base non renseigné', TELEPHONE_ABSENT: 'aucun téléphone', POLICE_ABSENTE: 'assuré sans numéro de police',
    COMPTE_INCONNU: 'compte absent du plan comptable', CLASSE_NON_REPORTABLE: 'compte de gestion : il ne se reporte pas', DEUX_SENS: 'débit et crédit renseignés ensemble',
    LIGNE_NULLE: 'ligne sans montant', DATES_MULTIPLES: 'plusieurs dates dans le fichier', RG10_DESEQUILIBRE: 'écriture non équilibrée (RG-10)',
    A_NOUVEAU_EXISTANT: 'l’exercice porte déjà un à-nouveau', COLONNE_RESERVEE: 'colonne réservée à un autre profil', COLONNE_RETIREE: 'colonne retirée du modèle',
    /* Jeux du stock (lot IMP-B1) : jamais le nom d'un article, d'un lot ni une quantité. */
    ARTICLE_INCONNU: 'article absent du référentiel produits', RG03_STOCK_INSUFFISANT: 'stock du magasin insuffisant (RG-03)', RG03_STOCK_NEGATIF: 'quantité négative (RG-03)',
    LOT_OBLIGATOIRE: 'lot et péremption obligatoires (RG-05)', LOT_INCOMPLET: 'lot et péremption vont ensemble', LOT_INCONNU: 'lot absent pour cet article', LOT_PERIME: 'lot périmé',
    LOT_NON_FEFO: 'lot qui ne part pas en premier (FEFO, RG-05)', PEREMPTION_PASSEE: 'lot déjà périmé', QUANTITE_NULLE: 'quantité nulle',
    DETAIL_DEJA_MOUVEMENTE: 'article déjà mouvementé : le stock détail initial ne se pose qu’une fois', DETAIL_DEJA_EN_STOCK: 'stock détail déjà présent', STOCK_INCOHERENT: 'stocks gros et détail incohérents avec le stock total',
    DESTINATION_ABSENTE: 'aucun service destinataire', DESTINATIONS_MULTIPLES: 'plusieurs services destinataires : une feuille est un seul bon', BON_UNIQUE: 'plusieurs valeurs pour un bon unique', FEUILLE_UNIQUE: 'plusieurs valeurs pour une feuille unique',
  };
  function masquer(j, p) {
    if (!restreint(j)) return p;
    return { n: p.n, colonne: p.colonne, valeur: '', code: p.code, niveau: p.niveau, motif: MOTIFS_FIXES[p.code] || 'constat de contrôle (le détail n’est pas recopié)', geste: p.geste };
  }

  /* --- Petits outils ---------------------------------------------------------------------------------------------- */
  function aujourdhuiIso() { return C.iso(C.aujourdhui()); }
  function vide(v) { return v === null || v === undefined || (typeof v === 'string' && v.trim() === ''); }
  function nettoyer(v) { return typeof v === 'string' ? v.replace(/[\u00A0\u202F]/g, ' ').trim() : v; }
  function dateValide(a, m, j) {
    var d = new Date(Date.UTC(a, m - 1, j));
    return d.getUTCFullYear() === a && d.getUTCMonth() === m - 1 && d.getUTCDate() === j;
  }
  /** Jours entiers entre deux dates ISO (AAAA-MM-JJ), sans heure : le port Dart calcule la même chose à l'identique. */
  function joursEntre(a, b) {
    function u(x) { return Date.UTC(+x.slice(0, 4), +x.slice(5, 7) - 1, +x.slice(8, 10)); }
    return Math.round((u(b) - u(a)) / 86400000);
  }
  function ageAu(naissance, jour) { return Math.max(0, Math.floor(joursEntre(naissance, jour) / 365.25)); }

  /* --- Typage d'une cellule --------------------------------------------------------------------------------------- *
   * Retourne { vide: true } | { valeur } | { erreur: { code, motif, geste } }. */
  function lireCellule(col, brut, ctx) {
    var v = nettoyer(brut);
    if (vide(v)) return { vide: true };
    var type = col.type || 'texte';
    function erreur(code, motif, geste) { return { erreur: { code: code, motif: motif, geste: geste } }; }
    if (type === 'texte') {
      var t = String(v);
      if (col.motif && !col.motif.test(t)) return erreur('FORMAT_INVALIDE', col.motifTexte || 'format non conforme', 'Corrigez la valeur selon le format indiqué dans l’onglet Instructions.');
      if (col.longueurMax && t.length > col.longueurMax) return erreur('TROP_LONG', 'texte de ' + t.length + ' caractères (maximum ' + col.longueurMax + ')', 'Raccourcissez la valeur à ' + col.longueurMax + ' caractères au plus.');
      return { valeur: t };
    }
    if (type === 'entier' || type === 'decimal') {
      var n;
      if (typeof v === 'number') n = v;
      else {
        var s = String(v).replace(/\s/g, '').replace(',', '.');
        n = /^-?\d+(\.\d+)?$/.test(s) ? Number(s) : NaN;
      }
      if (!isFinite(n)) return erreur('TYPE_INVALIDE', 'nombre attendu, « ' + v + ' » n’en est pas un', 'Saisissez un nombre sans lettre ni symbole monétaire.');
      if (type === 'entier' && Math.floor(n) !== n) return erreur('TYPE_INVALIDE', 'nombre entier attendu, « ' + v + ' » porte une décimale', 'Arrondissez à l’unité (le franc CFA n’a pas de décimale).');
      if (col.min !== undefined && n < col.min) {
        if (col.sousMin) return erreur(col.sousMin.code, col.sousMin.motif, col.sousMin.geste);
        return erreur('HORS_BORNES', 'valeur ' + n + ' inférieure au minimum ' + col.min, 'Saisissez une valeur d’au moins ' + col.min + '.');
      }
      if (col.max !== undefined && n > col.max) return erreur('HORS_BORNES', 'valeur ' + n + ' supérieure au maximum ' + col.max, 'Saisissez une valeur d’au plus ' + col.max + '.');
      return { valeur: n };
    }
    if (type === 'date') {
      var iso = null;
      if (typeof v === 'number') iso = X.versDate(v);
      else {
        var m1 = /^(\d{4})-(\d{2})-(\d{2})/.exec(v), m2 = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(v);
        if (m1 && dateValide(+m1[1], +m1[2], +m1[3])) iso = m1[1] + '-' + m1[2] + '-' + m1[3];
        else if (m2 && dateValide(+m2[3], +m2[2], +m2[1])) iso = m2[3] + '-' + C.pad(m2[2]) + '-' + C.pad(m2[1]);
      }
      if (!iso) return erreur('TYPE_INVALIDE', 'date attendue, « ' + v + ' » n’en est pas une', 'Saisissez la date au format AAAA-MM-JJ ou JJ/MM/AAAA.');
      return { valeur: iso };
    }
    if (type === 'liste') {
      var choix = valeursListe(col, ctx), cle = C.norm(String(v)).trim();
      var trouve = choix.filter(function (c) { return C.norm(c.valeur) === cle || C.norm(c.label) === cle; })[0];
      if (!trouve) {
        return erreur('VALEUR_HORS_LISTE', '« ' + v + ' » n’est pas une valeur permise',
          'Choisissez parmi : ' + choix.slice(0, 8).map(function (c) { return c.label; }).join(', ') + (choix.length > 8 ? ', …' : '') + '.');
      }
      return { valeur: trouve.valeur };
    }
    if (type === 'tarif') {
      var tv = String(v).trim();
      if (/^(-|\u2013|\u2014)$/.test(tv)) return { valeur: { etat: 'manquant' } };
      if (/^(nc|non couvert)$/i.test(tv)) return { valeur: { etat: 'nc' } };
      if (col.unique && /^(unique|prix unique)$/i.test(tv)) return { valeur: { etat: 'unique' } };
      var nn = typeof v === 'number' ? v : Number(tv.replace(/\s/g, '').replace(',', '.'));
      if (!isFinite(nn) || Math.floor(nn) !== nn || nn < 0) {
        return erreur('TYPE_INVALIDE', '« ' + v + ' » n’est ni un montant entier, ni NC, ni un tiret', 'Saisissez un montant en francs, NC (non couvert) ou un tiret (valeur manquante).');
      }
      return { valeur: { etat: 'montant', montant: nn } };
    }
    return { valeur: v };
  }

  function valeursListe(col, ctx) {
    var l = typeof col.liste === 'function' ? col.liste(ctx || {}) : (col.liste || []);
    return l.map(function (x) { return typeof x === 'string' ? { valeur: x, label: x } : x; });
  }

  /* ==========================================================================
   * LES JEUX. Chacun : colonnes, clé, contexte (ce que le magasin sait déjà), règles, écriture.
   * ======================================================================== */
  function col(cle, label, type, o) {
    return Object.assign({ cle: cle, label: label, type: type || 'texte', obligatoire: false }, o || {});
  }
  function oblig(cle, label, type, o) { return col(cle, label, type, Object.assign({ obligatoire: true }, o || {})); }

  function toutes(nom) { return S.collection(nom).all(); }
  function actives(nom) { return S.collection(nom).active(); }
  function utilise(nom, champ, valeur) {
    return S.collection(nom).active().some(function (r) { return r[champ] === valeur; });
  }

  var JEUX = [];

  /* --- 1. GRAND STOCK (inventaire SAGE) ------------------------------------------------------------------------------ */
  var PERISSABLES = ['medicament', 'reactif'];
  JEUX.push({
    id: 'grand-stock', ecran: 'm6-import-grand-stock', libelle: 'Importation Grand Stock', module: 'M6', statut: 'supporte',
    description: 'Situation initiale du magasin central : articles, lots, péremptions, quantités et prix de revient (inventaire SAGE « Grand Stock »).',
    source: 'Inventaire SAGE 100 « Grand Stock » du 15/07/2026 (docs/) : 184 articles, 12 080 unités, 3 976 459 FCFA.',
    cibles: ['produits', 'lots', 'mouvements'],
    fichierModele: 'modele-import-grand-stock',
    colonnes: [
      oblig('code', 'Code article', 'texte', { longueurMax: 24, exemple: 'PARA500', aide: 'Référence SAGE de l’article. Une ligne par lot : le même code peut figurer plusieurs fois avec des lots différents.' }),
      oblig('designation', 'Désignation', 'texte', { longueurMax: 160, exemple: 'PARACETAMOL 500 MG CP B/100' }),
      oblig('categorie', 'Catégorie', 'liste', { liste: function () { return D.CATEGORIES_PRODUIT.map(function (c) { return { valeur: c.id, label: c.label }; }); }, exemple: 'Médicaments' }),
      col('unite', 'Unité', 'texte', { longueurMax: 30, exemple: 'Boîte', aide: 'Vide : « Unité ».' }),
      oblig('quantite', 'Quantité', 'entier', { min: 0, exemple: 120, aide: 'Quantité de CE lot. Jamais négative (RG-03).',
        sousMin: { code: 'RG03_STOCK_NEGATIF', motif: 'quantité négative : le stock ne peut jamais être négatif (RG-03)', geste: 'Saisissez la quantité réellement comptée, zéro ou plus. Une sortie se déclare au mouvement de stock, pas à l’import.' } }),
      col('lot', 'N° de lot', 'texte', { longueurMax: 40, exemple: 'L2026-014', aide: 'Obligatoire pour les médicaments et réactifs (rangement FEFO, RG-05).' }),
      col('peremption', 'Date de péremption', 'date', { exemple: '2028-06-30' }),
      col('prixRevient', 'Prix de revient unitaire', 'entier', { min: 0, exemple: 350, aide: 'En francs CFA. Vide : l’article est créé « à valoriser » et le dit (aucun prix n’est inventé).' }),
      col('seuil', 'Seuil d’alerte', 'entier', { min: 0, exemple: 20, aide: 'Vide : proposé à 20 % de la quantité (minimum 5), marqué « à valider ».' }),
      col('emplacement', 'Emplacement', 'texte', { longueurMax: 60, exemple: 'Rayon A, Casier 3' }),
      col('fournisseur', 'Code fournisseur', 'texte', { longueurMax: 24, exemple: 'SOBAPS', aide: 'Code d’un fournisseur connu. Un code inconnu est signalé, jamais refusé.' }),
    ],
    contexte: function () {
      var p = {}, f = {};
      toutes('produits').forEach(function (x) { p[C.norm(x.code)] = x; });
      actives('fournisseurs').forEach(function (x) { f[C.norm(x.code)] = true; });
      return { produits: p, fournisseurs: f, jour: aujourdhuiIso() };
    },
    cle: function (v) { return [C.norm(v.code) + '|' + C.norm(v.lot || '')]; },
    existe: function (v, ctx) {
      var p = ctx.produits[C.norm(v.code)];
      return p ? 'l’article « ' + p.code + ' » existe déjà dans le référentiel (' + p.designation + ')' : null;
    },
    gesteExiste: 'Retirez la ligne du fichier, ou archivez d’abord l’article existant (RG-14). Un import ne modifie jamais un article déjà tenu.',
    regles: function (v, ctx, sc, n) {
      var pb = [];
      var lot = v.lot, per = v.peremption;
      if (PERISSABLES.indexOf(v.categorie) >= 0 && (!lot || !per)) {
        pb.push({ colonne: !lot ? 'N° de lot' : 'Date de péremption', valeur: '', code: 'LOT_OBLIGATOIRE', niveau: 'refus',
          motif: 'un ' + (v.categorie === 'reactif' ? 'réactif' : 'médicament') + ' sans lot ni péremption ne peut pas se ranger en FEFO (RG-05)',
          geste: 'Renseignez le numéro de lot ET la date de péremption relevés sur la boîte.' });
      } else if ((lot && !per) || (!lot && per)) {
        pb.push({ colonne: !lot ? 'N° de lot' : 'Date de péremption', valeur: '', code: 'LOT_INCOMPLET', niveau: 'refus',
          motif: 'le lot et sa péremption vont ensemble : l’un est renseigné, l’autre non', geste: 'Renseignez les deux colonnes, ou laissez-les vides toutes les deux.' });
      }
      if (per && per < ctx.jour && v.quantite > 0) {
        pb.push({ colonne: 'Date de péremption', valeur: per, code: 'PEREMPTION_PASSEE', niveau: 'avertissement',
          motif: 'le lot est déjà périmé au ' + per, geste: 'Le lot sera créé « périmé » pour être retiré du stock ; vérifiez la date saisie.' });
      }
      if (v.quantite === 0) {
        pb.push({ colonne: 'Quantité', valeur: 0, code: 'QUANTITE_NULLE', niveau: 'avertissement', motif: 'quantité nulle : l’article sera créé sans stock', geste: 'Vérifiez le comptage si ce n’est pas voulu.' });
      }
      if (v.prixRevient == null) {
        pb.push({ colonne: 'Prix de revient unitaire', valeur: '', code: 'A_VALORISER', niveau: 'avertissement',
          motif: 'prix de revient absent : l’article sera créé « à valoriser »', geste: 'Valorisez-le ensuite à l’écran Reprise SAGE, avec sa source.' });
      }
      if (v.fournisseur && !ctx.fournisseurs[C.norm(v.fournisseur)]) {
        pb.push({ colonne: 'Code fournisseur', valeur: v.fournisseur, code: 'FOURNISSEUR_INCONNU', niveau: 'avertissement',
          motif: 'aucun fournisseur « ' + v.fournisseur + ' » au référentiel', geste: 'Créez le fournisseur (jeu Fournisseurs) ou corrigez le code.' });
      }
      var k = C.norm(v.code), ref = sc.articles[k];
      if (!ref) sc.articles[k] = { n: n, designation: v.designation, categorie: v.categorie, unite: v.unite || 'Unité', prix: v.prixRevient };
      else if (ref.designation !== v.designation || ref.categorie !== v.categorie) {
        pb.push({ colonne: 'Désignation', valeur: v.designation, code: 'ARTICLE_INCOHERENT', niveau: 'refus',
          motif: 'le code « ' + v.code + ' » porte une autre désignation ou catégorie que la ligne ' + ref.n,
          geste: 'Un code désigne un seul article : alignez la désignation et la catégorie sur la ligne ' + ref.n + '.' });
      }
      return pb;
    },
    ecrire: function (lignes, ecrireFiche, lot) {
      var jour = aujourdhuiIso(), groupes = {}, ordre = [];
      lignes.forEach(function (l) {
        var k = C.norm(l.v.code);
        if (!groupes[k]) { groupes[k] = []; ordre.push(k); }
        groupes[k].push(l.v);
      });
      var mouvs = toutes('mouvements').slice();
      ordre.forEach(function (k) {
        var ls = groupes[k], p = ls[0];
        var total = ls.reduce(function (t, x) { return t + x.quantite; }, 0);
        var prix = p.prixRevient;
        var seuilFourni = ls.some(function (x) { return x.seuil != null; });
        var seuil = seuilFourni ? Math.max.apply(null, ls.map(function (x) { return x.seuil || 0; })) : Math.max(5, Math.round(total * 0.2));
        var prod = ecrireFiche('produits', Object.assign({
          code: p.code, designation: p.designation, unite: p.unite || 'Unité', categorie: p.categorie,
          prixAchat: prix || 0, prixVente: prix || 0, cump: prix || 0,
          seuilAlerte: seuil, seuilAValider: !seuilFourni,
          stockGros: total, stockDetail: 0, stock: total, quantiteImportee: total,
          emplacement: p.emplacement || '', fournisseur: p.fournisseur || '', valoriseSage: false,
        }, prix ? {} : { valorisationProvisoire: true, sourceValorisation: 'Prix de revient absent du fichier d’import ' + lot.reference + ' : à valoriser' }));
        ls.forEach(function (x) {
          if (x.lot) {
            var jours = joursEntre(jour, x.peremption);
            ecrireFiche('lots', {
              produitId: prod.id, produit: p.designation, numeroLot: x.lot, datePeremption: x.peremption,
              quantiteRestante: x.quantite, emplacement: x.emplacement || p.emplacement || '',
              statut: jours < 0 ? 'perime' : (jours < 90 ? 'alerte' : 'actif'),
            });
          }
          var ref = C.referenceSuivante('M', 6, mouvs);
          mouvs.push({ reference: ref });
          ecrireFiche('mouvements', {
            reference: ref, date: jour, produitId: prod.id, produit: p.designation, type: 'entree', typeLabel: 'Entrée',
            quantite: x.quantite, stockType: 'gros', justificatif: 'Import ' + lot.reference + ' (stock initial' + (x.lot ? ', lot ' + x.lot : '') + ')',
            utilisateur: S.currentUser(),
          });
        });
      });
    },
    dependances: function (lot) {
      var ids = {};
      lot.ecrits.forEach(function (e) { if (e.collection === 'produits') ids[e.id] = true; });
      var propres = {};
      lot.ecrits.forEach(function (e) { if (e.collection === 'mouvements') propres[e.id] = true; });
      var autre = S.collection('mouvements').active().filter(function (m) { return ids[m.produitId] && !propres[m.id]; })[0];
      if (autre) return { code: 'MOUVEMENT_POSTERIEUR', motif: 'l’article « ' + autre.produit + ' » a déjà un mouvement de stock (' + autre.reference + ', ' + autre.typeLabel + ')',
        geste: 'Annulez d’abord ce mouvement, ou régularisez le stock par un inventaire : le lot ne peut pas être retiré sous un stock vivant (RG-03).' };
      return null;
    },
  });

  /* --- 2. PERSONNEL -------------------------------------------------------------------------------------------------- */
  JEUX.push({
    id: 'personnel', ecran: 'imp-personnel', libelle: 'Importation du personnel', module: 'IMP', statut: 'supporte',
    description: 'Fiches des agents : matricule, identité, fonction, service, embauche. Aucune donnée de paie hors salaire de base.',
    source: 'Organigramme et liste du personnel de la clinique (docs/) : 44 agents.',
    cibles: ['personnel'],
    fichierModele: 'modele-import-personnel',
    colonnes: [
      oblig('matricule', 'Matricule', 'texte', { longueurMax: 20, exemple: '45' }),
      oblig('nom', 'Nom', 'texte', { longueurMax: 60, exemple: 'ADJOVI' }),
      oblig('prenom', 'Prénom', 'texte', { longueurMax: 80, exemple: 'Marie' }),
      oblig('sexe', 'Sexe', 'liste', { liste: [{ valeur: 'M', label: 'M' }, { valeur: 'F', label: 'F' }], exemple: 'F' }),
      oblig('fonction', 'Fonction', 'liste', { liste: function () { return Object.keys(D.CAPACITES || {}); }, exemple: 'infirmier', aide: 'Code de fonction du logiciel : il décide des capacités métier.' }),
      oblig('poste', 'Poste', 'texte', { longueurMax: 80, exemple: 'Infirmière' }),
      oblig('service', 'Service', 'liste', { liste: function (ctx) { return ctx.services; }, exemple: 'Soins infirmiers' }),
      col('categorie', 'Catégorie', 'texte', { motif: /^E[1-5]-[1-3]$/, motifTexte: 'catégorie de la convention (E1-1 à E5-3)', exemple: 'E3-2' }),
      col('dateEmbauche', 'Date d’embauche', 'date', { exemple: '2024-03-01' }),
      col('telephone', 'Téléphone', 'texte', { longueurMax: 20, exemple: '0197000000' }),
      col('cnss', 'N° CNSS', 'texte', { motif: /^\d{9}$/, motifTexte: '9 chiffres', exemple: '294011540' }),
      col('situation', 'Situation familiale', 'liste', { liste: ['Célibataire', 'Marié(e)', 'Veuf(ve)'], exemple: 'Marié(e)' }),
      col('salaireBase', 'Salaire de base', 'entier', { min: 0, capacite: 'paie', exemple: 150000, aide: 'Francs CFA bruts mensuels. Réservé aux profils qui détiennent la capacité paie (écriture dans le module Paie) : absente du modèle des autres, et un fichier qui la porte est refusé.' }),
    ],
    contexte: function () {
      var m = {}, ident = {}, serv = {};
      /* Les services viennent du référentiel (D.SERVICES) ET du personnel déjà tenu : une clinique qui démarre n'a pas encore d'agent. */
      D.SERVICES.forEach(function (s) { serv[s] = true; });
      toutes('personnel').forEach(function (p) {
        m[C.norm(p.matricule)] = p; ident[C.norm(p.nom) + '|' + C.norm(p.prenom)] = p;
        if (p.statut !== 'archive' && p.service) serv[p.service] = true;
      });
      return { matricules: m, identites: ident, services: Object.keys(serv).sort(), jour: aujourdhuiIso() };
    },
    cle: function (v) { return [C.norm(v.matricule), 'id:' + C.norm(v.nom) + '|' + C.norm(v.prenom)]; },
    existe: function (v, ctx) {
      var p = ctx.matricules[C.norm(v.matricule)] || ctx.identites[C.norm(v.nom) + '|' + C.norm(v.prenom)];
      return p ? 'l’agent ' + p.nom + ' ' + p.prenom + ' (matricule ' + p.matricule + ') existe déjà' : null;
    },
    gesteExiste: 'Retirez la ligne : un import ne modifie pas une fiche existante. Corrigez-la à l’écran Personnel.',
    regles: function (v, ctx) {
      var pb = [];
      if (v.dateEmbauche && v.dateEmbauche > ctx.jour) pb.push({ colonne: 'Date d’embauche', valeur: v.dateEmbauche, code: 'DATE_FUTURE', niveau: 'refus', motif: 'la date d’embauche est dans le futur', geste: 'Saisissez la date réelle d’entrée en fonction.' });
      if (v.salaireBase == null && colonnesDe(jeu('personnel')).some(function (c) { return c.cle === 'salaireBase'; })) pb.push({ colonne: 'Salaire de base', valeur: '', code: 'SALAIRE_ABSENT', niveau: 'avertissement', motif: 'salaire de base non renseigné', geste: 'Le bulletin de paie ne pourra pas se calculer avant sa saisie.' });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche) {
      lignes.forEach(function (l) {
        var v = l.v;
        ecrireFiche('personnel', {
          matricule: v.matricule, nom: v.nom, prenom: v.prenom, nomComplet: v.nom + ' ' + v.prenom, sexe: v.sexe, fonction: v.fonction,
          poste: v.poste, service: v.service, categorie: v.categorie || null, dateEmbauche: v.dateEmbauche || null,
          telephone: v.telephone || null, cnss: v.cnss || null, situation: v.situation || null, salaireBase: v.salaireBase == null ? null : v.salaireBase,
        });
      });
    },
    dependances: function (lot) {
      var ids = {};
      lot.ecrits.forEach(function (e) { ids[e.id] = true; });
      var p = S.collection('planning').active().filter(function (x) { return ids[x.employeId]; })[0];
      return p ? { code: 'AGENT_AU_PLANNING', motif: 'l’agent ' + p.employe + ' figure déjà au planning', geste: 'Retirez-le du planning avant d’annuler le lot.' } : null;
    },
  });

  /* --- 3. PATIENTS ----------------------------------------------------------------------------------------------------- */
  var RE_CODE_PATIENT = /^CNT\/?\d+\/\d{2}$/;
  JEUX.push({
    id: 'patients', ecran: 'imp-patients', libelle: 'Importation du répertoire patients', module: 'IMP', statut: 'supporte',
    description: 'Reprise du répertoire papier : identité, coordonnées, couverture. Jamais de dossier médical.',
    source: 'Registre papier des dossiers (environ 18 000) : seule l’identité administrative se reprend (CDCT 4.3).',
    cibles: ['patients'],
    /* I9 (Direction, 11/11/2026) : le groupe sanguin est une donnée de santé, il se saisit à la première consultation par un soignant. La colonne est RETIRÉE du modèle ; un fichier qui la
       porte est refusé en la nommant. Champs sensibles que ce jeu ÉCRIT encore : identité (nom, prénom, sexe, naissance ou âge), téléphone, quartier, adresse, personne à prévenir, assureur et n° de police. */
    colonnesRetirees: [{ label: 'Groupe sanguin', motif: 'le groupe sanguin est une donnée de santé : il ne se reprend pas à l’accueil, il se saisit à la première consultation par un soignant' }],
    fichierModele: 'modele-import-patients',
    colonnes: [
      col('code', 'Code dossier', 'texte', { motif: RE_CODE_PATIENT, motifTexte: 'code de la forme CNT/n/AA', exemple: '', aide: 'RG-01 : un code existant du registre papier est conservé tel quel et ne se modifie jamais. Vide : le prochain code est attribué automatiquement.' }),
      oblig('nom', 'Nom', 'texte', { longueurMax: 60, exemple: 'ADJOVI' }),
      oblig('prenom', 'Prénom', 'texte', { longueurMax: 80, exemple: 'Marie' }),
      oblig('sexe', 'Sexe', 'liste', { liste: [{ valeur: 'M', label: 'M' }, { valeur: 'F', label: 'F' }], exemple: 'F' }),
      col('dateNaissance', 'Date de naissance', 'date', { exemple: '1990-04-12', aide: 'Date de naissance OU âge déclaré : au moins l’une des deux.' }),
      col('age', 'Âge déclaré', 'entier', { min: 0, max: 120, exemple: '' }),
      col('telephone', 'Téléphone', 'texte', { longueurMax: 20, exemple: '0197000000' }),
      col('quartier', 'Quartier', 'texte', { longueurMax: 60, exemple: 'Boukoumbé' }),
      col('adresse', 'Adresse', 'texte', { longueurMax: 120, exemple: 'Tchirimina, Natitingou' }),
      col('personneAPrevenir', 'Personne à prévenir', 'texte', { longueurMax: 100, exemple: 'ADJOVI Paul' }),
      col('assureur', 'Code assureur', 'liste', { liste: function (ctx) { return ctx.assureurs; }, exemple: '' }),
      col('numeroPolice', 'N° de police', 'texte', { longueurMax: 40, exemple: '' }),
      col('dateCreation', 'Date d’ouverture du dossier', 'date', { exemple: '2024-05-02', aide: 'Vide : date du jour.' }),
    ],
    contexte: function () {
      var codes = {}, ident = {}, tel = {}, ass = {}, noms = {};
      toutes('patients').forEach(function (p) {
        codes[C.norm(p.code)] = p;
        if (p.dateNaissance) ident[C.norm(p.nom) + '|' + C.norm(p.prenom) + '|' + p.dateNaissance] = p;
        if (p.telephone) tel[C.norm(p.nom) + '|' + C.norm(p.prenom) + '|' + String(p.telephone).replace(/\s/g, '')] = p;
      });
      actives('assureurs').forEach(function (a) { ass[a.code] = a.nom; });
      return { codes: codes, ident: ident, tel: tel, assureurs: Object.keys(ass), nomsAssureurs: ass, jour: aujourdhuiIso() };
    },
    cle: function (v) {
      var k = [];
      if (v.code) k.push('code:' + C.norm(v.code));
      if (v.dateNaissance) k.push('nd:' + C.norm(v.nom) + '|' + C.norm(v.prenom) + '|' + v.dateNaissance);
      if (v.telephone) k.push('nt:' + C.norm(v.nom) + '|' + C.norm(v.prenom) + '|' + String(v.telephone).replace(/\s/g, ''));
      return k;
    },
    existe: function (v, ctx) {
      var p = v.code && ctx.codes[C.norm(v.code)];
      if (p) return 'RG-01 : le code ' + p.code + ' est déjà attribué à ' + p.nom + ' ' + p.prenom + ' (un code ne se réutilise jamais)';
      p = (v.dateNaissance && ctx.ident[C.norm(v.nom) + '|' + C.norm(v.prenom) + '|' + v.dateNaissance])
        || (v.telephone && ctx.tel[C.norm(v.nom) + '|' + C.norm(v.prenom) + '|' + String(v.telephone).replace(/\s/g, '')]);
      return p ? 'doublon probable du dossier ' + p.code + ' (' + p.nom + ' ' + p.prenom + ')' : null;
    },
    gesteExiste: 'Retirez la ligne : le dossier existe déjà. Un doublon d’identité se règle à l’écran Patients, jamais par un second dossier.',
    regles: function (v, ctx) {
      var pb = [];
      if (!v.dateNaissance && v.age == null) pb.push({ colonne: 'Date de naissance', valeur: '', code: 'CHAMP_OBLIGATOIRE', niveau: 'refus', motif: 'ni date de naissance ni âge déclaré', geste: 'Renseignez la date de naissance, ou à défaut l’âge déclaré.' });
      if (v.dateNaissance && v.dateNaissance > ctx.jour) pb.push({ colonne: 'Date de naissance', valeur: v.dateNaissance, code: 'DATE_FUTURE', niveau: 'refus', motif: 'la date de naissance est dans le futur', geste: 'Corrigez la date.' });
      if (v.dateCreation && v.dateCreation > ctx.jour) pb.push({ colonne: 'Date d’ouverture du dossier', valeur: v.dateCreation, code: 'DATE_FUTURE', niveau: 'refus', motif: 'la date d’ouverture est dans le futur', geste: 'Corrigez la date, ou laissez la colonne vide.' });
      if (v.assureur && !v.numeroPolice) pb.push({ colonne: 'N° de police', valeur: '', code: 'POLICE_ABSENTE', niveau: 'avertissement', motif: 'assuré sans numéro de police', geste: 'La prise en charge (RG-09) ne pourra pas s’appliquer avant sa saisie.' });
      if (!v.telephone) pb.push({ colonne: 'Téléphone', valeur: '', code: 'TELEPHONE_ABSENT', niveau: 'avertissement', motif: 'aucun téléphone : le patient ne pourra pas être rappelé', geste: 'Renseignez-le si le registre papier le porte.' });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche) {
      var rangs = {};
      toutes('patients').forEach(function (p) {
        var m = /^CNT\/?(\d+)\/(\d{2})$/.exec(p.code || '');
        if (m) rangs[m[2]] = Math.max(rangs[m[2]] || 0, Number(m[1]));
      });
      lignes.forEach(function (l) { var m = l.v.code && /^CNT\/?(\d+)\/(\d{2})$/.exec(l.v.code); if (m) rangs[m[2]] = Math.max(rangs[m[2]] || 0, Number(m[1])); });
      var jour = aujourdhuiIso();
      lignes.forEach(function (l) {
        var v = l.v, creation = v.dateCreation || jour;
        var code = v.code;
        if (!code) {
          var an = creation.slice(2, 4);
          rangs[an] = (rangs[an] || 0) + 1;
          code = C.codePatient(rangs[an], Number(creation.slice(0, 4)));
        }
        var age = v.age;
        var fiche = {
          code: code, nom: v.nom, prenom: v.prenom, sexe: v.sexe, dateNaissance: v.dateNaissance || null,
          telephone: v.telephone || null, quartier: v.quartier || null, adresse: v.adresse || null,
          personneAPrevenir: v.personneAPrevenir || null,
          assureur: v.assureur || null, numeroPolice: v.numeroPolice || null, dateCreation: creation,
          externe: false, origineDossier: 'Reprise du répertoire papier',
        };
        if (v.dateNaissance) fiche.age = ageAu(v.dateNaissance, jour);
        else { fiche.age = age; fiche.ageReferenceLe = jour; }
        if (v.assureur) {
          fiche.assure = true;
          var a = actives('assureurs').filter(function (x) { return x.code === v.assureur; })[0];
          fiche.assureurNom = a ? a.nom : null;
        }
        ecrireFiche('patients', fiche);
      });
    },
    dependances: function (lot) {
      var codes = {};
      lot.ecrits.forEach(function (e) { codes[e.id] = true; });
      var refs = ['consultations', 'factures', 'admissions', 'demandesLabo', 'ordonnances', 'rendezVous'];
      for (var i = 0; i < refs.length; i++) {
        var r = S.collection(refs[i]).active().filter(function (x) { return codes[x.patientId]; })[0];
        if (r) return { code: 'DOSSIER_UTILISE', motif: 'le dossier ' + (r.patientCode || r.patientId) + ' est déjà utilisé (' + refs[i] + ')',
          geste: 'Un dossier qui porte des actes ne s’annule pas par son lot : archivez-le à l’écran Patients.' };
      }
      return null;
    },
  });

  /* --- 4. TARIFS ET PRIX (PRD-TARIFS 7.2, lot IMP-A) ----------------------------------------------------------------------------- *
   * UN SEUL JEU pour tous les prix de prestation : il REMPLACE les jeux « actes » et « catalogue tarifaire » du PRD d'import (la facturation lit désormais le seul référentiel de
   * prix) et porte les prix d'analyses, d'imagerie, de consultations et de soins. Il écrit par le MÊME chemin que la saisie à l'écran (`PR.proposerTarif`, contrôles, journal,
   * alerte) : pas une seconde vérification. Le prix en vigueur ne bouge jamais à l'import :
   *   Oui + droit de décider   → version VALIDÉE d'emblée (tracée « validée à l'import IMP-… »), effective à sa date d'effet ;
   *   Oui sans ce droit / vide → PROPOSITION : l'alerte Oui/Non de la DAF ou de la Direction (le Oui d'un importateur vaut proposition, la vérification le dit ligne par ligne) ;
   *   Non (motif obligatoire)  → ligne NON appliquée, aucune version, ni erreur ni refus du fichier (c'est la décision de l'importateur) ;
   *   prix identique à celui en vigueur à cette date → « inchangée », comptée, jamais une version.
   * Les ERREURS refusent le fichier entier (tout ou rien) ; les DÉCISIONS se prennent ligne à ligne. Un tiret n'est jamais zéro ; NC n'existe qu'en colonne assurée ; zéro est refusé. */
  var FAMILLES_PRIX = [['CONSULTATION', 'Consultations'], ['ACTE', 'Actes'], ['HOSPITALISATION', 'Hospitalisation'], ['AMI', 'Actes médico-infirmiers'],
    ['GYNECO', 'Gynéco-obstétrique et kits'], ['CERTIFICAT', 'Certificats et attestations'], ['LABO', 'Analyses de laboratoire'], ['IMAGERIE', 'Imagerie médicale']];
  var COUVERTURES = [{ valeur: 'toutes', label: 'Toutes compagnies' }, { valeur: 'sos', label: 'SOS seule' }, { valeur: 'non', label: 'Non couvert' }];
  var ASSURABLE_DE = { toutes: true, sos: 'sos', non: false };
  var COLONNE_DU_REFUS = { MOTIF_REQUIS: 'Motif', DATE_EFFET_REQUISE: 'Date d’effet', DATE_PASSEE: 'Date d’effet', DATE_PASSEE_RESERVEE: 'Date d’effet', TARIF_DEJA_UTILISE: 'Date d’effet',
    CHANGEMENT_EN_ATTENTE: 'Code', PRESTATION_INTROUVABLE: 'Code', CODE_EXISTANT: 'Code', IDENTITE_INCOMPLETE: 'Désignation', PRIX_ABSENT: 'Prix non assuré', PRIX_INVALIDE: 'Prix non assuré' };
  function prixAffiche(na, etatA, pa) {
    var a = etatA === 'montant' ? C.num(pa) : (etatA === 'nc' ? 'NC' : (etatA === 'unique' ? 'unique' : 'absent'));
    return (na == null ? 'absent' : C.num(na)) + ' / ' + a;
  }
  function pourcent(avant, apres) { return avant ? (Math.round((apres - avant) / avant * 1000) / 10) + ' %' : ''; }
  /** Ce que la ligne propose, dans la forme que `PR.proposerTarif` attend. */
  function offreDeLigne(v, h, lot) {
    var p = h && h.parCode[v.code], etatA = v.prixAssure.etat;
    var o = { code: v.code, prixNonAssure: v.prixNonAssure.etat === 'montant' ? v.prixNonAssure.montant : null, etatAssure: etatA, prixAssure: etatA === 'montant' ? v.prixAssure.montant : null,
      dateEffet: v.dateEffet, motif: v.motif, source: v.source || undefined, import: { jeu: 'tarifs', lot: lot || undefined } };
    if (!p) {
      o.creation = { libelle: v.designation, famille: v.famille, secteur: v.secteur || undefined, source: v.source || undefined };
      if (v.couverture) o.assurable = ASSURABLE_DE[v.couverture]; else if (etatA === 'nc') o.assurable = false;
    }
    return o;
  }
  JEUX.push({
    id: 'tarifs', ecran: 'imp-actes', libelle: 'Importation des tarifs et prix', module: 'IMP', statut: 'supporte',
    description: 'Prix des prestations (consultations, actes, soins, analyses, imagerie, certificats) à deux colonnes, avec les trois états de la colonne assurée, une date d’effet et la décision Oui ou Non : chaque ligne qui change devient une version datée, jamais un écrasement.',
    source: 'Six grilles tarifaires imprimées et « Répartition des activités » (docs/) ; les prix du fichier font foi, aucun n’est complété par le logiciel.',
    limite: 'Un import de prix ne change jamais le prix en vigueur par lui-même : la ligne devient une proposition soumise à l’alerte Oui/Non de la Directrice Administrative ou de la Direction, sauf si votre profil détient le droit de décider ET que la ligne dit Oui.',
    cibles: ['tarifs', 'versionsTarif'],
    fichierModele: 'modele-import-tarifs',
    colonnes: [
      oblig('code', 'Code', 'texte', { longueurMax: 30, exemple: 'MG01', aide: 'Code d’une prestation connue (changement de prix) ou d’une prestation nouvelle (création : désignation et famille obligatoires). Un code d’alias est reconnu.' }),
      col('designation', 'Désignation', 'texte', { longueurMax: 160, exemple: 'Consultation généraliste', aide: 'Libellé de facturation. Obligatoire pour créer une prestation ; jamais appliqué à une prestation connue (un import ne modifie pas l’identité d’une fiche tenue).' }),
      col('famille', 'Famille', 'liste', { liste: FAMILLES_PRIX.map(function (f) { return { valeur: f[0], label: f[1] }; }), exemple: 'Actes', aide: 'Obligatoire pour créer une prestation.' }),
      col('secteur', 'Secteur', 'liste', { liste: function (ctx) { return ctx.secteurs; }, exemple: 'Médecine générale' }),
      oblig('prixNonAssure', 'Prix non assuré', 'tarif', { exemple: 5000, aide: 'Montant entier strictement positif en FCFA. NC n’existe pas dans cette colonne ; un tiret n’est pas un zéro : une ligne sans prix non assuré est refusée.' }),
      oblig('prixAssure', 'Prix assuré', 'tarif', { unique: true, exemple: 3000, aide: 'Montant, NC (aucune compagnie ne couvre l’acte : l’assuré paie le prix non assuré), UNIQUE (prix unique : la colonne assurée vaut la colonne non assurée) ou un tiret (valeur manquante, la ligne ne se facture pas aux assurés).' }),
      col('couverture', 'Couverture', 'liste', { liste: COUVERTURES, exemple: 'Toutes compagnies', aide: 'Pour une création seulement ; vide : toutes les compagnies (ou non couvert si le prix assuré est NC).' }),
      oblig('dateEffet', 'Date d’effet', 'date', { exemple: '2027-01-01', aide: 'Obligatoire : le prix en vigueur ne change qu’à cette date. Une date passée est refusée (elle se propose à l’écran, avec sa case et son motif).' }),
      col('valider', 'Valider (Oui/Non)', 'liste', { liste: [{ valeur: 'oui', label: 'Oui' }, { valeur: 'non', label: 'Non' }], exemple: 'Oui', aide: 'Oui : le prix s’applique (validé d’emblée si votre profil décide, sinon proposition). Non : la ligne n’est pas appliquée, le motif est obligatoire. Vide : proposition.' }),
      col('motif', 'Motif', 'texte', { longueurMax: 160, exemple: 'Nouvelle grille tarifaire', aide: 'Obligatoire pour toute ligne qui change un prix et pour tout Non.' }),
      col('source', 'Source', 'texte', { longueurMax: 160, exemple: 'Grille du 01/12/2026' }),
    ],
    contexte: function () {
      var h = D.TARIFS.lire(), sec = {};
      (h ? h.tarifs : []).forEach(function (p) { if (p.statut !== 'archive' && p.secteur) sec[p.secteur] = true; });
      D.ACTES.forEach(function (a) { if (a.secteur) sec[a.secteur] = true; });
      return { h: h, secteurs: Object.keys(sec).sort(), jour: aujourdhuiIso(), peutDecider: !!(global.SIGH.parcours && global.SIGH.parcours.peutDeciderTarif()) };
    },
    cle: function (v) { return [C.norm(v.code)]; },
    regles: function (v, ctx, sc, n) {
      var pb = [], ligne = sc.ligne, PR_ = global.SIGH.parcours;
      function pb_(colonne, valeur, code, niveau, motif, geste) { pb.push({ colonne: colonne, valeur: valeur, code: code, niveau: niveau, motif: motif, geste: geste }); }
      if (!ctx.h) { pb_('Code', v.code, 'REFERENTIEL_ABSENT', 'refus', 'le référentiel de prix n’est pas chargé', 'Rechargez la page.'); return pb; }
      var p = ctx.h.parCode[v.code], na = v.prixNonAssure, pa = v.prixAssure;
      var s = p ? D.TARIFS.instantane(ctx.h, p, v.dateEffet) : null;
      var extra = { ancien: s ? prixAffiche(s.na, s.etatAssure, s.pa) : 'nouvelle prestation', nouveau: prixAffiche(na.etat === 'montant' ? na.montant : null, pa.etat, pa.montant), variation: '', decision: '' };
      sc.extras[n] = extra;
      if (s && na.etat === 'montant' && s.na) {
        extra.variation = pourcent(s.na, na.montant);
        if (pa.etat === 'montant' && s.etatAssure === 'montant' && s.pa && s.pa !== pa.montant) extra.variation += ' (assuré ' + pourcent(s.pa, pa.montant) + ')';
      }
      /* Un NON est la décision de l'importateur : ni version, ni erreur. Son motif est obligatoire (il se lit au rapport et au lot). */
      if (v.valider === 'non') {
        if (!v.motif) pb_('Motif', '', 'MOTIF_REQUIS', 'refus', 'une ligne « Non » se motive : sans motif, on ne sait pas pourquoi le prix n’est pas appliqué', 'Saisissez le motif de la ligne ' + n + '.');
        else { ligne.sansEcriture = 'non'; extra.decision = 'Non : non appliquée'; pb_('Valider (Oui/Non)', 'Non', 'LIGNE_NON_APPLIQUEE', 'info', 'ligne non appliquée sur décision de l’importateur (motif : ' + v.motif + ')', 'Aucune version n’est créée.'); }
        return pb;
      }
      if (na.etat === 'nc') pb_('Prix non assuré', 'NC', 'NC_INTERDIT', 'refus', 'NC n’a de sens que dans la colonne assurée', 'Saisissez le prix de guichet en francs.');
      else if (na.etat === 'manquant') pb_('Prix non assuré', '-', 'PRIX_ABSENT', 'refus', 'un tiret n’est pas un zéro, et un prix non assuré absent n’est pas un tarif : la ligne ne se facturerait pas', 'Saisissez le prix non assuré, ou retirez la ligne.');
      else if (pa.etat === 'manquant') pb_('Prix assuré', '-', 'PRIX_MANQUANT', 'avertissement', 'prix assuré manquant : la ligne ne se facturera pas aux assurés (un tiret n’est pas un zéro)', 'Saisissez le prix assuré dès qu’il est arrêté, ou NC si aucune compagnie ne couvre la prestation.');
      if (pb.some(function (x) { return x.niveau === 'refus'; })) return pb;
      if (s && na.etat === 'montant' && pa.etat === 'montant' && s.etatAssure === 'montant' && na.montant === s.pa && pa.montant === s.na && s.pa !== s.na) {
        pb_('Prix assuré', pa.montant, 'COLONNES_INVERSEES', 'avertissement', 'les deux colonnes paraissent inversées par rapport au prix en vigueur (non assuré ' + C.num(s.na) + ', assuré ' + C.num(s.pa) + ') : le fichier fait foi, rien n’est corrigé', 'Vérifiez l’orientation des colonnes avant de confirmer.');
      }
      if (p) {
        if (v.designation && p.libelle && C.norm(v.designation) !== C.norm(p.libelle)) pb_('Désignation', v.designation, 'IDENTITE_DIFFERENTE', 'avertissement', 'la désignation du fichier diffère de celle de la fiche : elle n’est pas appliquée (un import ne modifie pas l’identité d’une prestation)', 'Modifiez le libellé à l’écran « Tarifs et prix ».');
        else if (v.famille && p.famille && v.famille !== p.famille) pb_('Famille', v.famille, 'IDENTITE_DIFFERENTE', 'avertissement', 'la famille du fichier diffère de celle de la fiche : elle n’est pas appliquée', 'Modifiez la fiche à l’écran « Tarifs et prix ».');
        else if (v.couverture && ASSURABLE_DE[v.couverture] !== p.assurable && !(ASSURABLE_DE[v.couverture] === true && p.assurable === undefined)) pb_('Couverture', v.couverture, 'IDENTITE_DIFFERENTE', 'avertissement', 'la couverture du fichier diffère de celle de la fiche : elle n’est pas appliquée', 'Modifiez la fiche à l’écran « Tarifs et prix ».');
      } else if (!v.designation) pb_('Désignation', '', 'IDENTITE_INCOMPLETE', 'refus', 'le code « ' + v.code + ' » est inconnu : une nouvelle prestation porte une désignation', 'Renseignez la désignation et la famille, ou corrigez le code.');
      else if (!v.famille) pb_('Famille', '', 'IDENTITE_INCOMPLETE', 'refus', 'le code « ' + v.code + ' » est inconnu : une nouvelle prestation porte une famille', 'Renseignez la famille, ou corrigez le code.');
      if (pb.some(function (x) { return x.niveau === 'refus'; })) return pb;
      /* LE MÊME CHEMIN QUE L'ÉCRAN : tous les contrôles de la proposition, sans écrire (essai). */
      var o = offreDeLigne(v, ctx.h, null);
      o.essai = true; o.valider = ctx.peutDecider && v.valider === 'oui';
      var ev = PR_.proposerTarif(o);
      if (!ev.ok && o.valider === true && (ev.code === 'VALIDATION_RESERVEE' || ev.code === 'CONFIGURATION_DE_LA_MERE')) { o.valider = false; ev = PR_.proposerTarif(o); }
      if (!ev.ok && ev.code === 'PRIX_INCHANGE') {
        ligne.sansEcriture = 'inchange'; extra.decision = 'Inchangée';
        pb_('Prix non assuré', '', 'PRIX_INCHANGE', 'info', 'ce prix est déjà celui en vigueur à cette date : aucune version, la ligne est comptée', 'Rien à faire.');
        return pb;
      }
      if (!ev.ok) { pb_(COLONNE_DU_REFUS[ev.code] || 'Prix non assuré', '', ev.code, 'refus', ev.motif, ev.geste); return pb; }
      if (!p) extra.decision = (o.valider ? 'Oui : prestation créée, version 1 validée' : 'Prestation créée, version 1 proposée (alerte)');
      else if (o.valider) extra.decision = 'Oui : version validée à l’import';
      else if (v.valider === 'oui') {
        extra.decision = 'Proposition (votre Oui vaut proposition)';
        pb_('Valider (Oui/Non)', 'Oui', 'OUI_VAUT_PROPOSITION', 'avertissement', 'votre profil ne détient pas le droit de décider un prix : le Oui vaut proposition, la décision revient à la Directrice Administrative ou à la Direction (alerte)', 'Aucune action : la ligne sera proposée.');
      } else extra.decision = 'Proposition (alerte Oui/Non)';
      return pb;
    },
    ecrire: function (lignes, ecrireFiche, lot, ctx, declarer) {
      var PR_ = global.SIGH.parcours;
      lignes.forEach(function (l) {
        var v = l.v, o = offreDeLigne(v, D.TARIFS.lire(), lot.reference);
        o.valider = PR_.peutDeciderTarif() && v.valider === 'oui';
        var r = PR_.proposerTarif(o);
        if (!r.ok && o.valider === true && (r.code === 'VALIDATION_RESERVEE' || r.code === 'CONFIGURATION_DE_LA_MERE')) { o.valider = false; r = PR_.proposerTarif(o); }
        if (!r.ok) throw new Error('ligne ' + l.n + ' (' + v.code + ') : ' + r.motif);
        if (r.identite) declarer('tarifs', r.identite.id);
        declarer('versionsTarif', r.version.id);
      });
    },
    /* Un lot de prix s'annule en RETIRANT ses propositions (RG-14, rien ne se supprime) ; une version déjà validée se remplace par une nouvelle version, elle ne s'efface pas. */
    dependances: function (lot) {
      if (lot.ecrits.some(function (e) { return e.collection === 'actes'; })) {
        return { code: 'LOT_ANCIEN', motif: 'ce lot a écrit l’ancienne liste des actes, devenue une projection de lecture du référentiel de prix', geste: 'Corrigez le prix à l’écran « Tarifs et prix » : une version se remplace par une nouvelle version.' };
      }
      var valide = lot.ecrits.filter(function (e) { return e.collection === 'versionsTarif'; }).map(function (e) { return S.collection('versionsTarif').get(e.id); })
        .filter(function (x) { return x && x.statut === 'valide'; })[0];
      return valide ? { code: 'VERSION_DEJA_VALIDEE', motif: 'la version ' + valide.id + ' est déjà validée : une décision se remplace par une nouvelle version, elle ne s’efface pas',
        geste: 'Proposez une nouvelle version à l’écran « Tarifs et prix » ; seules les propositions encore en attente se retirent avec leur lot.' } : null;
    },
    annuler: function (lot, motif) {
      var PR_ = global.SIGH.parcours, retirees = 0, archivees = 0;
      for (var i = 0; i < lot.ecrits.length; i++) {
        var e = lot.ecrits[i];
        if (e.collection !== 'versionsTarif') continue;
        var v = S.collection('versionsTarif').get(e.id);
        if (!v || v.statut !== 'propose') continue;
        var r = PR_.retirerProposition(e.id, 'Lot ' + lot.reference + ' annulé' + (motif ? ' : ' + motif : ''));
        if (!r.ok) return { ok: false, code: r.code, motif: r.motif, geste: r.geste };
        retirees++;
      }
      lot.ecrits.forEach(function (e) {
        if (e.collection !== 'tarifs') return;
        var vivantes = S.collection('versionsTarif').all().filter(function (x) { return x.code === e.id && (x.statut === 'propose' || x.statut === 'valide'); });
        if (!vivantes.length && S.collection('tarifs').archive(e.id, 'Annulation du lot ' + lot.reference)) archivees++;
      });
      return { ok: true, archives: retirees + archivees };
    },
  });

  /* --- 5. ANALYSES (proposition à valider) ------------------------------------------------------------------------------- */
  JEUX.push({
    id: 'analyses-modele', ecran: 'imp-analyses', libelle: 'Importation du modèle des analyses', module: 'IMP', statut: 'proposition',
    description: 'Entrées du catalogue des examens (code, désignation, section). Les variables, unités et bornes ne se reprennent pas : le biologiste les valide.',
    source: 'Bulletin d’analyses bio-médicales et fiche de résultats du 21/08/2026 (docs/) : 48 analyses au catalogue.',
    limite: 'PROPOSITION À VALIDER : seule l’entrée du catalogue est créée. Sans variables ni bornes, un examen importé ne peut pas recevoir de résultat avant que le biologiste les ait saisies et validées.',
    cibles: ['examensLabo'],
    fichierModele: 'modele-import-analyses',
    colonnes: [
      oblig('code', 'Code examen', 'texte', { longueurMax: 20, exemple: 'GLY' }),
      oblig('designation', 'Désignation', 'texte', { longueurMax: 160, exemple: 'Glycémie à jeun' }),
      oblig('section', 'Section', 'liste', { liste: function () { return global.SIGH.labo.SECTIONS.map(function (s) { return { valeur: s.id, label: s.label }; }); }, exemple: 'Biochimie' }),
      col('echantillon', 'Échantillon', 'texte', { longueurMax: 60, exemple: 'Sérum' }),
      col('delai', 'Délai de rendu', 'texte', { longueurMax: 20, exemple: '4 h' }),
    ],
    contexte: function () { var c = {}; toutes('examensLabo').forEach(function (e) { c[C.norm(e.code)] = e; }); return { examens: c }; },
    cle: function (v) { return [C.norm(v.code)]; },
    existe: function (v, ctx) { var e = ctx.examens[C.norm(v.code)]; return e ? 'l’examen « ' + e.code + ' » existe déjà (' + e.designation + ')' : null; },
    gesteExiste: 'Retirez la ligne : un examen en service se modifie à l’écran du catalogue du laboratoire.',
    regles: function () {
      return [{ colonne: 'Code examen', valeur: '', code: 'SANS_VARIABLES', niveau: 'avertissement', motif: 'examen importé sans variables ni bornes de référence', geste: 'Le biologiste les saisit puis les valide avant toute saisie de résultat.' }];
    },
    ecrire: function (lignes, ecrireFiche) {
      lignes.forEach(function (l) {
        var v = l.v;
        ecrireFiche('examensLabo', { code: v.code, designation: v.designation, section: v.section, sectionResultat: v.section, sectionBulletin: v.section,
          echantillon: v.echantillon || null, delai: v.delai || null, documente: false, aValider: true });
      });
    },
    dependances: function (lot) {
      var codes = {};
      lot.ecrits.forEach(function (e) { var a = S.collection('examensLabo').get(e.id); if (a) codes[a.code] = true; });
      var u = S.collection('demandesLabo').active().filter(function (x) { return codes[x.examenCode] || codes[x.code]; })[0];
      return u ? { code: 'EXAMEN_DEMANDE', motif: 'l’examen est déjà demandé', geste: 'Archivez-le au catalogue du laboratoire.' } : null;
    },
  });

  /* --- 6. FOURNISSEURS ------------------------------------------------------------------------------------------------------ */
  JEUX.push({
    id: 'fournisseurs', ecran: 'imp-fournisseurs', libelle: 'Importation des fournisseurs', module: 'IMP', statut: 'supporte',
    description: 'Fournisseurs de la clinique : identité fiscale, coordonnées, délai, banque.',
    source: 'Factures de vente et bons de livraison collectés (docs/), dont la facture SoBAPS.',
    cibles: ['fournisseurs'],
    fichierModele: 'modele-import-fournisseurs',
    colonnes: [
      oblig('code', 'Code fournisseur', 'texte', { longueurMax: 24, exemple: 'SOBAPS' }),
      oblig('nom', 'Raison sociale', 'texte', { longueurMax: 160, exemple: 'SoBAPS SA' }),
      col('type', 'Type', 'texte', { longueurMax: 60, exemple: 'Grossiste pharmaceutique' }),
      col('ville', 'Ville', 'texte', { longueurMax: 60, exemple: 'Parakou' }),
      col('adresse', 'Adresse', 'texte', { longueurMax: 120, exemple: 'BP 201 Parakou' }),
      col('tel', 'Téléphone', 'texte', { longueurMax: 60, exemple: '0191484242' }),
      col('ifu', 'IFU', 'texte', { motif: /^\d{13}$/, motifTexte: '13 chiffres', exemple: '3202112446712' }),
      col('delai', 'Délai de livraison (jours)', 'entier', { min: 0, max: 365, exemple: 5 }),
      col('banque', 'Banque', 'texte', { longueurMax: 60, exemple: 'BANK OF AFRICA' }),
      col('compte', 'N° de compte', 'texte', { longueurMax: 30, exemple: '007393360019' }),
    ],
    contexte: function () { var c = {}; toutes('fournisseurs').forEach(function (f) { c[C.norm(f.code)] = f; }); return { f: c }; },
    cle: function (v) { return [C.norm(v.code)]; },
    existe: function (v, ctx) { var f = ctx.f[C.norm(v.code)]; return f ? 'le fournisseur « ' + f.code + ' » existe déjà (' + f.nom + ')' : null; },
    gesteExiste: 'Retirez la ligne : modifiez la fiche existante à l’écran Fournisseurs.',
    regles: function (v) {
      return v.ifu ? [] : [{ colonne: 'IFU', valeur: '', code: 'IFU_ABSENT', niveau: 'avertissement', motif: 'IFU absent : la facture fournisseur ne sera pas justifiable fiscalement', geste: 'Renseignez-le dès que la facture le porte.' }];
    },
    ecrire: function (lignes, ecrireFiche) {
      lignes.forEach(function (l) {
        var v = l.v;
        ecrireFiche('fournisseurs', { code: v.code, nom: v.nom, type: v.type || null, ville: v.ville || null, adresse: v.adresse || null,
          tel: v.tel || null, ifu: v.ifu || null, delai: v.delai, banque: v.banque || null, compte: v.compte || null, habilite: false });
      });
    },
    dependances: function (lot) {
      var codes = {};
      lot.ecrits.forEach(function (e) { var a = S.collection('fournisseurs').get(e.id); if (a) codes[a.code] = true; });
      var u = S.collection('commandes').active().filter(function (x) { return codes[x.fournisseur] || codes[x.fournisseurCode]; })[0];
      return u ? { code: 'FOURNISSEUR_UTILISE', motif: 'une commande est déjà passée à ce fournisseur', geste: 'Archivez-le à l’écran Fournisseurs.' } : null;
    },
  });

  /* --- 7. ASSUREURS ------------------------------------------------------------------------------------------------------------ */
  JEUX.push({
    id: 'assureurs', ecran: 'imp-assureurs', libelle: 'Importation des compagnies d’assurance', module: 'IMP', statut: 'supporte',
    description: 'Compagnies d’assurance : code, raison sociale, contacts, état de la convention.',
    source: 'Treize assureurs relevés dans les documents de cadrage (docs/).',
    cibles: ['assureurs'],
    fichierModele: 'modele-import-assureurs',
    colonnes: [
      oblig('code', 'Code compagnie', 'texte', { motif: /^[A-Za-z0-9]{2,8}$/, motifTexte: '2 à 8 lettres ou chiffres', exemple: 'NSIA' }),
      oblig('nom', 'Raison sociale', 'texte', { longueurMax: 120, exemple: 'NSIA ASSURANCE' }),
      col('tel', 'Téléphones', 'texte', { longueurMax: 80, exemple: '0153212091 / 0196043695', aide: 'Plusieurs numéros séparés par une barre oblique.' }),
      col('email', 'E-mail', 'texte', { motif: /^[^\s@]+@[^\s@]+\.[^\s@]+$/, motifTexte: 'adresse e-mail', exemple: 'contact@exemple.bj' }),
      col('convention', 'Convention', 'liste', { liste: ['Signée', 'En négociation', 'Aucune'], exemple: 'Signée' }),
    ],
    contexte: function () { var c = {}; toutes('assureurs').forEach(function (a) { c[C.norm(a.code)] = a; }); return { a: c }; },
    cle: function (v) { return [C.norm(v.code)]; },
    existe: function (v, ctx) { var a = ctx.a[C.norm(v.code)]; return a ? 'la compagnie « ' + a.code + ' » existe déjà (' + a.nom + ')' : null; },
    gesteExiste: 'Retirez la ligne : modifiez la compagnie à l’écran Compagnies.',
    regles: function (v) { return v.convention ? [] : [{ colonne: 'Convention', valeur: '', code: 'CONVENTION_ABSENTE', niveau: 'avertissement', motif: 'état de la convention non renseigné', geste: 'Sans convention saisie, la facture reste intégralement au patient.' }]; },
    ecrire: function (lignes, ecrireFiche) {
      lignes.forEach(function (l) {
        var v = l.v;
        ecrireFiche('assureurs', { code: v.code, nom: v.nom, tel: v.tel ? v.tel.split('/').map(function (x) { return x.trim(); }) : [], email: v.email || null, convention: v.convention || null, assures: 0 });
      });
    },
    dependances: function (lot) {
      var codes = {};
      lot.ecrits.forEach(function (e) { var a = S.collection('assureurs').get(e.id); if (a) codes[a.code] = true; });
      var u = S.collection('souscripteurs').active().filter(function (x) { return codes[x.assureur]; })[0]
        || S.collection('patients').active().filter(function (x) { return codes[x.assureur]; })[0];
      return u ? { code: 'COMPAGNIE_UTILISEE', motif: 'un souscripteur ou un patient dépend de cette compagnie', geste: 'Annulez d’abord le lot des souscripteurs, ou archivez la compagnie.' } : null;
    },
  });

  /* --- 8. SOUSCRIPTEURS ------------------------------------------------------------------------------------------------------------ */
  JEUX.push({
    id: 'souscripteurs', ecran: 'imp-souscripteurs', libelle: 'Importation des souscripteurs', module: 'IMP', statut: 'supporte',
    description: 'Souscripteurs rattachés à une compagnie : n° de police, catégorie, effectif, période.',
    source: 'Relevés de prestations et factures mensuelles par souscripteur (docs/).',
    limite: 'La grille de garanties du souscripteur (taux par catégorie, plafonds, exclusions) ne s’importe pas : elle se saisit à l’écran Souscripteurs. Sans elle, la facture reste intégralement au patient.',
    cibles: ['souscripteurs'],
    fichierModele: 'modele-import-souscripteurs',
    colonnes: [
      oblig('nom', 'Souscripteur', 'texte', { longueurMax: 120, exemple: 'PIB Bénin' }),
      oblig('police', 'N° de police', 'texte', { longueurMax: 40, exemple: 'AFR/2024/0100' }),
      oblig('assureur', 'Code compagnie', 'liste', { liste: function (ctx) { return ctx.assureurs; }, exemple: 'AFR', aide: 'Une compagnie déjà connue du magasin : importez-la d’abord.' }),
      col('categorie', 'Catégorie', 'liste', { liste: ['entreprise', 'particulier', 'personnel'], exemple: 'entreprise' }),
      col('effectif', 'Effectif', 'entier', { min: 0, exemple: 75 }),
      col('dateDebut', 'Date de début', 'date', { exemple: '2024-08-01' }),
      col('dateFin', 'Date de fin', 'date', { exemple: '' }),
    ],
    contexte: function () {
      var p = {}, a = {};
      toutes('souscripteurs').forEach(function (s) { p[C.norm(s.police)] = s; });
      actives('assureurs').forEach(function (x) { a[x.code] = x.nom; });
      return { polices: p, nomsAssureurs: a, assureurs: Object.keys(a) };
    },
    cle: function (v) { return [C.norm(v.police)]; },
    existe: function (v, ctx) { var s = ctx.polices[C.norm(v.police)]; return s ? 'la police « ' + s.police + ' » existe déjà (' + s.nom + ')' : null; },
    gesteExiste: 'Retirez la ligne : modifiez le souscripteur à l’écran Souscripteurs.',
    regles: function (v) {
      var pb = [];
      if (v.dateDebut && v.dateFin && v.dateFin < v.dateDebut) pb.push({ colonne: 'Date de fin', valeur: v.dateFin, code: 'PERIODE_INVERSEE', niveau: 'refus', motif: 'la date de fin précède la date de début', geste: 'Corrigez l’une des deux dates.' });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche, lot, ctx) {
      lignes.forEach(function (l) {
        var v = l.v;
        ecrireFiche('souscripteurs', { nom: v.nom, police: v.police, assureur: v.assureur, assureurNom: ctx.nomsAssureurs[v.assureur], categorie: v.categorie || null,
          effectif: v.effectif, dateDebut: v.dateDebut || null, dateFin: v.dateFin || null, grilleSaisie: false, actesExclus: [], produitsExclus: [], accordPrealable: [] });
      });
    },
    dependances: function (lot) {
      var ids = {};
      lot.ecrits.forEach(function (e) { ids[e.id] = true; });
      var u = S.collection('patients').active().filter(function (x) { return ids[x.souscripteurId]; })[0];
      return u ? { code: 'SOUSCRIPTEUR_UTILISE', motif: 'le dossier ' + u.code + ' est rattaché à ce souscripteur', geste: 'Archivez le souscripteur plutôt que d’annuler son lot.' } : null;
    },
  });

  /* --- 9. PLAN COMPTABLE ------------------------------------------------------------------------------------------------------------- */
  JEUX.push({
    id: 'plan-comptable', ecran: 'imp-plan-comptable', libelle: 'Importation du plan comptable', module: 'IMP', statut: 'supporte',
    description: 'Comptes SYSCOHADA : numéro, libellé, journal par défaut. La classe se déduit du premier chiffre.',
    source: 'Plan comptable de la clinique, classeur SYSCOHADA 2025 (docs/) : 93 comptes.',
    cibles: ['comptes'],
    fichierModele: 'modele-import-plan-comptable',
    colonnes: [
      oblig('num', 'N° de compte', 'texte', { motif: /^[1-9]\d{3,7}$/, motifTexte: 'numéro de 4 à 8 chiffres, premier chiffre de 1 à 9', exemple: '571000' }),
      oblig('libelle', 'Libellé', 'texte', { longueurMax: 160, exemple: 'Caisse' }),
      col('journal', 'Journal', 'liste', { liste: function () { return D.JOURNAUX.map(function (j) { return { valeur: j.code, label: j.code }; }); }, exemple: 'CAI' }),
    ],
    contexte: function () { var c = {}; toutes('comptes').forEach(function (x) { if (x.statut !== 'archive') c[String(x.num)] = x; }); return { comptes: c }; },
    cle: function (v) { return [String(v.num)]; },
    existe: function (v, ctx) { var c = ctx.comptes[String(v.num)]; return c ? 'le compte ' + c.num + ' existe déjà (' + c.libelle + ')' : null; },
    gesteExiste: 'Retirez la ligne : un numéro de compte ne se double jamais au plan (le plan ne tolère aucun doublon).',
    regles: function () { return []; },
    ecrire: function (lignes, ecrireFiche) {
      lignes.forEach(function (l) { ecrireFiche('comptes', { num: l.v.num, libelle: l.v.libelle, classe: Number(String(l.v.num).charAt(0)), journal: l.v.journal || 'OD' }); });
    },
    dependances: function (lot) {
      var nums = {};
      lot.ecrits.forEach(function (e) { var a = S.collection('comptes').get(e.id); if (a) nums[String(a.num)] = true; });
      var u = S.collection('ecritures').active().filter(function (x) { return nums[String(x.compte)]; })[0];
      return u ? { code: 'COMPTE_UTILISE', motif: 'le compte ' + u.compte + ' porte déjà l’écriture ' + u.numero, geste: 'Archivez le compte au plan plutôt que d’annuler son lot.' } : null;
    },
  });

  /* --- 10. SOLDES D'OUVERTURE ------------------------------------------------------------------------------------------------------------- */
  JEUX.push({
    id: 'soldes-ouverture', ecran: 'imp-soldes-ouverture', libelle: 'Importation des soldes d’ouverture', module: 'IMP', statut: 'supporte',
    description: 'À-nouveaux d’un exercice : une pièce du journal AN, en brouillon, équilibrée (RG-10). Seules les classes 1 à 5 se reportent.',
    source: 'Bilan de clôture de l’exercice précédent : liasse déposée le 15/05/2026 (docs/).',
    cibles: ['ecritures'],
    fichierModele: 'modele-import-soldes-ouverture',
    colonnes: [
      oblig('date', 'Date', 'date', { exemple: '2026-01-01', aide: 'Premier jour de l’exercice. Une seule date pour tout le fichier.' }),
      oblig('compte', 'N° de compte', 'texte', { motif: /^[1-9]\d{3,7}$/, motifTexte: 'numéro de 4 à 8 chiffres', exemple: '571000' }),
      col('libelle', 'Libellé', 'texte', { longueurMax: 160, exemple: 'Caisse à l’ouverture' }),
      col('tiers', 'Tiers', 'texte', { longueurMax: 80, exemple: '', aide: 'Comptes de tiers (40, 41, 42, 43, 44, 47) : une ligne par tiers, le même compte peut donc se répéter.' }),
      col('debit', 'Débit', 'entier', { min: 0, exemple: 250000 }),
      col('credit', 'Crédit', 'entier', { min: 0, exemple: '' }),
    ],
    contexte: function () {
      var c = {}, an = {};
      toutes('comptes').forEach(function (x) { if (x.statut !== 'archive') c[String(x.num)] = x; });
      toutes('ecritures').forEach(function (e) { if (e.journal === 'AN' && e.statut !== 'archive') an[String(e.date).slice(0, 4)] = e.numero; });
      return { comptes: c, an: an };
    },
    cle: function (v) { return [String(v.compte) + '|' + C.norm(v.tiers || '')]; },
    existe: function () { return null; },
    regles: function (v, ctx) {
      var pb = [];
      var d = v.debit || 0, cr = v.credit || 0;
      if (!ctx.comptes[String(v.compte)]) pb.push({ colonne: 'N° de compte', valeur: v.compte, code: 'COMPTE_INCONNU', niveau: 'refus', motif: 'le compte ' + v.compte + ' n’existe pas au plan comptable', geste: 'Importez-le d’abord (jeu Plan comptable) ou corrigez le numéro.' });
      if (Number(String(v.compte).charAt(0)) > 5) pb.push({ colonne: 'N° de compte', valeur: v.compte, code: 'CLASSE_NON_REPORTABLE', niveau: 'refus', motif: 'un compte de gestion (classes 6, 7, 8, 9) ne se reporte jamais : il est soldé par le résultat', geste: 'Retirez la ligne : seules les classes 1 à 5 forment l’ouverture.' });
      if (d > 0 && cr > 0) pb.push({ colonne: 'Crédit', valeur: cr, code: 'DEUX_SENS', niveau: 'refus', motif: 'une ligne d’écriture a un sens, pas deux : débit et crédit sont tous deux renseignés', geste: 'Gardez le solde net dans UNE seule des deux colonnes.' });
      if (d === 0 && cr === 0) pb.push({ colonne: 'Débit', valeur: 0, code: 'LIGNE_NULLE', niveau: 'refus', motif: 'ligne sans montant', geste: 'Renseignez le débit ou le crédit, ou retirez la ligne.' });
      return pb;
    },
    reglesLot: function (lignes, ctx) {
      var pb = [], dates = {}, td = 0, tc = 0;
      lignes.forEach(function (l) { dates[l.v.date] = true; td += l.v.debit || 0; tc += l.v.credit || 0; });
      var ds = Object.keys(dates);
      if (ds.length > 1) pb.push({ n: 0, colonne: 'Date', valeur: ds.join(', '), code: 'DATES_MULTIPLES', niveau: 'refus', motif: 'le fichier porte ' + ds.length + ' dates : l’ouverture est une seule pièce à une seule date', geste: 'Alignez toutes les lignes sur le premier jour de l’exercice.' });
      if (td !== tc) pb.push({ n: 0, colonne: 'Débit / Crédit', valeur: 'débit ' + td + ' ≠ crédit ' + tc, code: 'RG10_DESEQUILIBRE', niveau: 'refus', motif: 'écriture non équilibrée (RG-10) : total débit ' + C.num(td) + ', total crédit ' + C.num(tc) + ', écart ' + C.num(Math.abs(td - tc)), geste: 'Corrigez les montants jusqu’à égalité des deux totaux ; aucune pièce déséquilibrée ne s’écrit.' });
      if (ds.length === 1 && ctx.an[ds[0].slice(0, 4)]) pb.push({ n: 0, colonne: 'Date', valeur: ds[0], code: 'A_NOUVEAU_EXISTANT', niveau: 'refus', motif: 'l’exercice ' + ds[0].slice(0, 4) + ' porte déjà un à-nouveau (' + ctx.an[ds[0].slice(0, 4)] + ')', geste: 'Un exercice ne s’ouvre qu’une fois : annulez d’abord le lot ou l’à-nouveau existant.' });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche) {
      var an = lignes[0].v.date.slice(0, 4);
      var existants = toutes('ecritures').filter(function (e) { return e.journal === 'AN' && String(e.numero).indexOf('AN-' + an + '-') === 0; });
      var numero = 'AN-' + an + '-' + C.pad(existants.length + 1, 5);
      var libJ = (D.JOURNAUX.filter(function (j) { return j.code === 'AN'; })[0] || {}).libelle || 'À-nouveaux';
      lignes.forEach(function (l) {
        var v = l.v, c = S.collection('comptes').all().filter(function (x) { return String(x.num) === String(v.compte); })[0] || {};
        ecrireFiche('ecritures', { numero: numero, date: v.date, journal: 'AN', journalLibelle: libJ, libelle: v.libelle || ('Solde d’ouverture ' + v.compte + (v.tiers ? ' ' + v.tiers : '')),
          compte: String(v.compte), compteLibelle: c.libelle || '', debit: v.debit || 0, credit: v.credit || 0, origine: 'Import des soldes d’ouverture', statut: 'brouillon' });
      });
    },
    dependances: function () { return null; },
  });

  /* ==========================================================================
   * LOT IMP-B1 (11/11/2026) : LES CINQ JEUX DU STOCK, détenus par le gestionnaire de stock (PRD-IMP 4 et 7.2 ; décisions I6, I8, I13).
   * --------------------------------------------------------------------------
   * Ils s'écrivent par les MÊMES règles que les gestes de l'écran, jamais à côté : le bon de transfert et la régularisation d'inventaire passent par les fabriques UNIQUES du
   * socle (`PR.emettreTransfert`, `PR.regulariserInventaire`, RG-03 ligne par ligne) ; le stock initial s'écrit comme le Grand Stock (un mouvement `entree` justifié par le lot
   * d'import). Un import n'invente rien et ne modifie JAMAIS une fiche tenue : le référentiel crée des fiches NEUVES, le stock détail ne se pose qu'une fois.
   * ======================================================================== */
  var PR = global.SIGH.parcours;
  /** Ce que le magasin sait déjà des articles : actifs par code, premier mouvement actif de chacun, lots par article. Lu UNE fois par analyse. */
  function contexteStock() {
    var p = {}, mv = {}, lotsDe = {};
    actives('produits').forEach(function (x) { p[C.norm(x.code)] = x; });
    actives('mouvements').forEach(function (m) { if (m.produitId && !mv[m.produitId]) mv[m.produitId] = m; });
    actives('lots').forEach(function (l) { (lotsDe[l.produitId] = lotsDe[l.produitId] || []).push(l); });
    return { produits: p, mouvements: mv, lots: lotsDe, jour: aujourdhuiIso() };
  }
  function articleInconnu(v) {
    return { colonne: 'Code article', valeur: v.code, code: 'ARTICLE_INCONNU', niveau: 'refus', motif: 'aucun article « ' + v.code + ' » au référentiel produits',
      geste: 'Créez l’article d’abord (jeu « Importation du référentiel produits » ou écran Référentiel produits), ou corrigez le code.' };
  }
  function statutLot(peremption, jour) { var j = joursEntre(jour, peremption); return j < 0 ? 'perime' : (j < 90 ? 'alerte' : 'actif'); }
  function distincts(lignes, cle) { var vus = {}, out = []; lignes.forEach(function (l) { var x = l.v[cle]; if (x != null && x !== '' && !vus[x]) { vus[x] = true; out.push(x); } }); return out; }
  /** L'article a-t-il servi à un acte (mouvement, lot, stock, pièce de caisse ou ordonnance) ? Un lot de référentiel ne s'annule que tant qu'aucun acte ne s'appuie dessus. */
  function acteSurProduit(produitId) {
    var p = S.collection('produits').get(produitId);
    var m = S.collection('mouvements').active().filter(function (x) { return x.produitId === produitId; })[0];
    if (m) return { code: 'MOUVEMENT_POSTERIEUR', motif: 'l’article « ' + (p ? p.designation : produitId) + ' » a déjà un mouvement de stock (' + m.reference + ', ' + m.typeLabel + ')', geste: 'Un article qui a servi ne s’annule plus avec son lot : archivez-le à l’écran Référentiel produits (RG-14).' };
    if (p && ((p.stock || 0) > 0 || (p.stockGros || 0) > 0 || (p.stockDetail || 0) > 0)) return { code: 'STOCK_PRESENT', motif: 'l’article « ' + p.designation + ' » porte du stock', geste: 'Régularisez le stock par un inventaire, puis archivez l’article.' };
    if (S.collection('lots').active().some(function (l) { return l.produitId === produitId; })) return { code: 'LOT_RATTACHE', motif: 'l’article « ' + (p ? p.designation : produitId) + ' » porte des lots', geste: 'Archivez l’article à l’écran Référentiel produits.' };
    var f = S.collection('factures').active().filter(function (x) { return (x.lignes || []).some(function (l) { return l.produitId === produitId; }); })[0];
    if (f) return { code: 'PRODUIT_FACTURE', motif: 'l’article « ' + (p ? p.designation : produitId) + ' » figure sur la facture ' + f.numero, geste: 'Une pièce émise ne se réécrit jamais : archivez l’article, il garde son prix sur la pièce.' };
    var o = S.collection('ordonnances').active().filter(function (x) { return (x.medicaments || []).some(function (l) { return l.produitId === produitId; }); })[0];
    if (o) return { code: 'PRODUIT_PRESCRIT', motif: 'l’article « ' + (p ? p.designation : produitId) + ' » figure sur l’ordonnance ' + (o.numero || o.reference), geste: 'Archivez l’article à l’écran Référentiel produits.' };
    return null;
  }

  /* --- 11. RÉFÉRENTIEL PRODUITS (sans quantités ni lots) -------------------------------------------------------------- */
  JEUX.push({
    id: 'produits-referentiel', ecran: 'imp-produits-referentiel', libelle: 'Importation du référentiel produits', module: 'M6', statut: 'supporte',
    description: 'Articles de la clinique : code, désignation, catégorie, unité, prix d’achat, seuil d’alerte. Jamais de quantité ni de lot.',
    source: 'Fiche du référentiel produits (écran « Référentiel produits ») et inventaire SAGE « Grand Stock » (docs/).',
    limite: 'Ce jeu crée des fiches NEUVES, sans stock : les quantités et les lots se reprennent par « Importation Grand Stock », et un fichier qui porte une colonne de quantité ou de lot est refusé. '
      + 'Il ne modifie jamais un article déjà tenu (RG-02 : le prix de vente d’un médicament est son prix d’achat). Un article sans seuil est signalé « sans seuil », jamais compté à zéro.',
    cibles: ['produits'], fichierModele: 'modele-import-referentiel-produits',
    colonnesRetirees: [
      { label: 'Quantité', motif: 'un référentiel ne porte jamais de quantité : le stock se reprend par le jeu « Importation Grand Stock »' },
      { label: 'N° de lot', motif: 'un référentiel ne porte jamais de lot : les lots se reprennent par le jeu « Importation Grand Stock »' },
      { label: 'Date de péremption', motif: 'un référentiel ne porte jamais de péremption : elle se reprend avec le lot, par le jeu « Importation Grand Stock »' },
      { label: 'Stock gros', motif: 'un référentiel ne porte jamais de stock : il se reprend par le jeu « Importation Grand Stock »' },
      { label: 'Stock détail', motif: 'un référentiel ne porte jamais de stock : le détail se pose par le jeu « Importation du stock détail initial »' },
    ],
    colonnes: [
      oblig('code', 'Code article', 'texte', { longueurMax: 24, exemple: 'PARA500', aide: 'Référence unique de l’article.' }),
      oblig('designation', 'Désignation', 'texte', { longueurMax: 160, exemple: 'PARACETAMOL 500 MG CP B/100' }),
      oblig('categorie', 'Catégorie', 'liste', { liste: function () { return D.CATEGORIES_PRODUIT.map(function (c) { return { valeur: c.id, label: c.label }; }); }, exemple: 'Médicaments' }),
      oblig('unite', 'Unité', 'texte', { longueurMax: 30, exemple: 'Boîte' }),
      col('prixAchat', 'Prix d’achat', 'entier', { min: 0, exemple: 350, aide: 'Francs CFA. Vide : l’article est créé « à valoriser » et le dit (aucun prix n’est inventé). Un médicament se facture à ce prix, sans marge (RG-02).' }),
      col('prixVente', 'Prix de vente', 'entier', { min: 0, aide: 'Hors médicament seulement. Vide : égal au prix d’achat. Un médicament n’a pas de prix de vente libre : renseigner un prix différent du prix d’achat est refusé.' }),
      col('seuil', 'Seuil d’alerte', 'entier', { min: 0, exemple: 20, aide: 'Vide : l’article est signalé « sans seuil », jamais compté à zéro (aucune alerte n’est possible sans seuil).' }),
      col('emplacement', 'Emplacement', 'texte', { longueurMax: 60, exemple: 'Rayon A, Casier 3' }),
      col('fournisseur', 'Code fournisseur', 'texte', { longueurMax: 24, exemple: 'SOBAPS', aide: 'Code d’un fournisseur connu. Un code inconnu est signalé, jamais refusé.' }),
    ],
    contexte: function () {
      var p = {}, f = {}, e = {}, ne = 0;
      toutes('produits').forEach(function (x) { p[C.norm(x.code)] = x; });
      actives('fournisseurs').forEach(function (x) { f[C.norm(x.code)] = true; });
      actives('emplacements').forEach(function (x) { e[C.norm(x.code)] = true; ne++; });
      return { produits: p, fournisseurs: f, emplacements: e, nbEmplacements: ne };
    },
    cle: function (v) { return [C.norm(v.code)]; },
    existe: function (v, ctx) {
      var p = ctx.produits[C.norm(v.code)];
      return p ? 'l’article « ' + p.code + ' » existe déjà (' + p.designation + ')' : null;
    },
    gesteExiste: 'Retirez la ligne : un import ne modifie jamais un article tenu. Corrigez-le à l’écran Référentiel produits.',
    regles: function (v, ctx) {
      var pb = [], med = v.categorie === 'medicament';
      if (med && v.prixVente != null && v.prixVente !== v.prixAchat) {
        pb.push({ colonne: 'Prix de vente', valeur: v.prixVente, code: 'RG02_PRIX_DE_VENTE', niveau: 'refus',
          motif: 'RG-02 : un médicament se facture au prix d’achat, sans marge : son prix de vente ne peut pas être libre',
          geste: 'Laissez la colonne « Prix de vente » vide : le prix de vente d’un médicament est son prix d’achat. Une exception se valide par la Direction, à l’écran.' });
      }
      if (v.prixAchat == null) {
        pb.push({ colonne: 'Prix d’achat', valeur: '', code: 'A_VALORISER', niveau: 'avertissement', motif: 'prix d’achat absent : l’article sera créé « à valoriser »', geste: 'Renseignez le prix d’achat à l’écran Référentiel produits, avec sa source.' });
      }
      if (v.seuil == null) {
        pb.push({ colonne: 'Seuil d’alerte', valeur: '', code: 'SANS_SEUIL', niveau: 'avertissement', motif: 'seuil d’alerte absent : l’article sera signalé « sans seuil », aucune alerte de stock ne le concernera', geste: 'Fixez le seuil à l’écran Référentiel produits.' });
      }
      if (v.fournisseur && !ctx.fournisseurs[C.norm(v.fournisseur)]) {
        pb.push({ colonne: 'Code fournisseur', valeur: v.fournisseur, code: 'FOURNISSEUR_INCONNU', niveau: 'avertissement', motif: 'aucun fournisseur « ' + v.fournisseur + ' » au référentiel', geste: 'Créez le fournisseur (jeu Fournisseurs) ou corrigez le code.' });
      }
      if (v.emplacement && ctx.nbEmplacements && !ctx.emplacements[C.norm(v.emplacement)]) {
        pb.push({ colonne: 'Emplacement', valeur: v.emplacement, code: 'EMPLACEMENT_INCONNU', niveau: 'avertissement', motif: 'aucun emplacement « ' + v.emplacement + ' » au référentiel des emplacements', geste: 'Créez l’emplacement (jeu Emplacements) pour que le plan des rayons ne compte pas deux casiers pour un.' });
      }
      return pb;
    },
    ecrire: function (lignes, ecrireFiche, lot) {
      lignes.forEach(function (l) {
        var v = l.v, med = v.categorie === 'medicament', prix = v.prixAchat == null ? 0 : v.prixAchat;
        ecrireFiche('produits', Object.assign({
          code: v.code, designation: v.designation, unite: v.unite, categorie: v.categorie,
          prixAchat: prix, prixVente: (med || v.prixVente == null) ? prix : v.prixVente, cump: prix,
          seuilAlerte: v.seuil == null ? null : v.seuil,
          stockGros: 0, stockDetail: 0, stock: 0, emplacement: v.emplacement || '', fournisseur: v.fournisseur || '',
        }, v.prixAchat == null ? { valorisationProvisoire: true, sourceValorisation: 'Prix d’achat absent du fichier d’import ' + lot.reference + ' : à valoriser' } : {}));
      });
    },
    dependances: function (lot) {
      var d = null;
      lot.ecrits.forEach(function (e) { if (!d && e.collection === 'produits') d = acteSurProduit(e.id); });
      return d;
    },
  });

  /* --- 12. EMPLACEMENTS DE RANGEMENT ---------------------------------------------------------------------------------- */
  var ZONES_EMPLACEMENT = ['Rayonnage sec', 'Chaîne du froid', 'Armoire sécurisée', 'Réserve', 'Salle de soins'];
  var TEMPERATURES_EMPLACEMENT = ['Ambiante', '2 à 8 °C', '− 20 °C', 'Sous clé, ambiante'];
  JEUX.push({
    id: 'emplacements', ecran: 'imp-emplacements', libelle: 'Importation des emplacements de rangement', module: 'M6', statut: 'supporte',
    description: 'Casiers et rayons du magasin : code (celui de l’étiquette), intitulé, zone, conservation, capacité.',
    source: 'Fiche du référentiel des emplacements (écran « Étiquetage & emplacements ») : même zones, mêmes conservations.',
    limite: 'Une zone ou une conservation vide reste vide (« à préciser ») : aucune valeur par défaut n’est inventée. Le code est celui qui figure sur l’étiquette : deux écritures qui ne diffèrent que par la casse ou les accents (« A2 », « a2 ») sont un seul casier. Les écritures qui diffèrent aussi par un tiret (« A2 », « A-2 ») restent deux casiers : la comparaison ne les rapproche pas.',
    cibles: ['emplacements'], fichierModele: 'modele-import-emplacements',
    colonnes: [
      oblig('code', 'Code du casier', 'texte', { longueurMax: 30, exemple: 'A2', aide: 'Court et stable : c’est lui qui figure sur l’étiquette.' }),
      oblig('libelle', 'Intitulé', 'texte', { longueurMax: 120, exemple: 'Rayon A, casier 2' }),
      col('zone', 'Zone', 'liste', { liste: ZONES_EMPLACEMENT, exemple: 'Rayonnage sec' }),
      col('temperature', 'Température de conservation', 'liste', { liste: TEMPERATURES_EMPLACEMENT, exemple: 'Ambiante' }),
      col('capacite', 'Capacité (références)', 'entier', { min: 0, exemple: 40 }),
      col('observation', 'Observation', 'texte', { longueurMax: 200 }),
    ],
    contexte: function () { var c = {}; toutes('emplacements').forEach(function (e) { c[C.norm(e.code)] = e; }); return { e: c }; },
    cle: function (v) { return [C.norm(v.code)]; },
    existe: function (v, ctx) { var e = ctx.e[C.norm(v.code)]; return e ? 'le casier « ' + e.code + ' » existe déjà (' + e.libelle + ')' : null; },
    gesteExiste: 'Retirez la ligne : modifiez le casier à l’écran Étiquetage & emplacements.',
    regles: function (v) {
      var pb = [];
      if (!v.zone) pb.push({ colonne: 'Zone', valeur: '', code: 'ZONE_ABSENTE', niveau: 'avertissement', motif: 'zone non renseignée : le casier est créé « à préciser »', geste: 'Précisez la zone à l’écran Étiquetage & emplacements.' });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche) {
      lignes.forEach(function (l) {
        var v = l.v;
        ecrireFiche('emplacements', { code: v.code, libelle: v.libelle, zone: v.zone || null, temperature: v.temperature || null, capacite: v.capacite == null ? null : v.capacite, observation: v.observation || null });
      });
    },
    dependances: function (lot) {
      var codes = {};
      lot.ecrits.forEach(function (e) { var a = S.collection('emplacements').get(e.id); if (a) codes[a.code] = true; });
      var p = S.collection('produits').active().filter(function (x) { return codes[x.emplacement]; })[0];
      return p ? { code: 'EMPLACEMENT_UTILISE', motif: 'l’article « ' + p.designation + ' » est rangé dans ce casier', geste: 'Changez l’emplacement de l’article, puis archivez le casier à l’écran Étiquetage & emplacements.' } : null;
    },
  });

  /* --- 13. STOCK DÉTAIL INITIAL (UNE SEULE FOIS, tant qu'aucun mouvement n'existe : I6) --------------------------------- */
  JEUX.push({
    id: 'stock-detail-initial', ecran: 'imp-stock-detail-initial', libelle: 'Importation du stock détail initial', module: 'M6', statut: 'supporte',
    description: 'Situation initiale de la pharmacie d’urgence : quantité de chaque article, avec son lot et sa péremption pour un médicament ou un réactif.',
    source: 'Comptage de la pharmacie d’urgence à la mise en service (décision de la Direction du 11/11/2026 : un stock détail initial est légitime, UNE SEULE FOIS).',
    limite: 'Un stock détail initial ne se pose qu’UNE FOIS par article, tant qu’aucun mouvement n’existe pour lui (comme le Grand Stock) : ensuite le détail naît d’un transfert du magasin central. '
      + 'Il est refusé si l’article porte déjà du stock détail ou si ses stocks gros et détail ne s’additionnent pas déjà au stock total.',
    cibles: ['produits', 'lots', 'mouvements'], fichierModele: 'modele-import-stock-detail-initial',
    colonnes: [
      oblig('code', 'Code article', 'texte', { longueurMax: 24, exemple: 'PARA500', aide: 'Un article déjà connu du référentiel produits. Une ligne par lot : le même code peut figurer plusieurs fois avec des lots différents.' }),
      col('lot', 'N° de lot', 'texte', { longueurMax: 40, exemple: 'L2026-014', aide: 'Obligatoire pour les médicaments et réactifs (rangement FEFO, RG-05).' }),
      col('peremption', 'Date de péremption', 'date', { exemple: '2028-06-30' }),
      oblig('quantite', 'Quantité', 'entier', { min: 0, exemple: 40, aide: 'Quantité de CE lot, au détail. Jamais négative (RG-03).',
        sousMin: { code: 'RG03_STOCK_NEGATIF', motif: 'quantité négative : le stock ne peut jamais être négatif (RG-03)', geste: 'Saisissez la quantité réellement comptée, zéro ou plus.' } }),
    ],
    contexte: contexteStock,
    cle: function (v) { return [C.norm(v.code) + '|' + C.norm(v.lot || '')]; },
    existe: function () { return null; },
    regles: function (v, ctx) {
      var p = ctx.produits[C.norm(v.code)];
      if (!p) return [articleInconnu(v)];
      var pb = [], mv = ctx.mouvements[p.id];
      if (mv) {
        pb.push({ colonne: 'Code article', valeur: v.code, code: 'DETAIL_DEJA_MOUVEMENTE', niveau: 'refus',
          motif: 'l’article « ' + p.designation + ' » a déjà un mouvement de stock (' + mv.reference + ', ' + mv.typeLabel + ') : un stock détail initial ne se pose qu’une fois, tant qu’aucun mouvement n’existe',
          geste: 'Constituez le détail par un transfert du magasin central, ou corrigez-le par un inventaire du stock détail.' });
      } else if ((p.stockDetail || 0) > 0) {
        pb.push({ colonne: 'Code article', valeur: v.code, code: 'DETAIL_DEJA_EN_STOCK', niveau: 'refus',
          motif: 'l’article « ' + p.designation + ' » porte déjà ' + C.num(p.stockDetail) + ' ' + (p.unite || '') + ' au détail : le stock initial ne se pose pas sur un stock existant',
          geste: 'Corrigez le stock détail par un inventaire, pas par un second stock initial.' });
      }
      if ((p.stock || 0) !== (p.stockGros || 0) + (p.stockDetail || 0)) {
        pb.push({ colonne: 'Code article', valeur: v.code, code: 'STOCK_INCOHERENT', niveau: 'refus',
          motif: 'les stocks gros (' + C.num(p.stockGros || 0) + ') et détail (' + C.num(p.stockDetail || 0) + ') de « ' + p.designation + ' » ne s’additionnent pas au stock total (' + C.num(p.stock || 0) + ') : un stock détail ne se pose pas sur une fiche incohérente',
          geste: 'Corrigez la fiche de l’article par un inventaire du magasin central, puis recommencez.' });
      }
      var perissable = PERISSABLES.indexOf(p.categorie) >= 0;
      if (perissable && (!v.lot || !v.peremption)) {
        pb.push({ colonne: !v.lot ? 'N° de lot' : 'Date de péremption', valeur: '', code: 'LOT_OBLIGATOIRE', niveau: 'refus',
          motif: 'un ' + (p.categorie === 'reactif' ? 'réactif' : 'médicament') + ' sans lot ni péremption ne peut pas se ranger en FEFO (RG-05)', geste: 'Renseignez le numéro de lot ET la date de péremption relevés sur la boîte.' });
      } else if ((v.lot && !v.peremption) || (!v.lot && v.peremption)) {
        pb.push({ colonne: !v.lot ? 'N° de lot' : 'Date de péremption', valeur: '', code: 'LOT_INCOMPLET', niveau: 'refus', motif: 'le lot et sa péremption vont ensemble : l’un est renseigné, l’autre non', geste: 'Renseignez les deux colonnes, ou laissez-les vides toutes les deux.' });
      }
      if (v.peremption && v.peremption < ctx.jour && v.quantite > 0) {
        pb.push({ colonne: 'Date de péremption', valeur: v.peremption, code: 'PEREMPTION_PASSEE', niveau: 'avertissement', motif: 'le lot est déjà périmé au ' + v.peremption, geste: 'Le lot sera créé « périmé » pour être retiré du stock ; vérifiez la date saisie.' });
      }
      if (v.quantite === 0) pb.push({ colonne: 'Quantité', valeur: 0, code: 'QUANTITE_NULLE', niveau: 'avertissement', motif: 'quantité nulle : la ligne n’écrit rien', geste: 'Retirez-la du fichier si ce n’est pas voulu.' });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche, lot, ctx) {
      var jour = aujourdhuiIso(), mouvs = toutes('mouvements').slice(), totaux = {}, ordre = [], faits = [];
      lignes.forEach(function (l) {
        var v = l.v, p = ctx.produits[C.norm(v.code)];
        if (!v.quantite) return;
        if (v.lot) ecrireFiche('lots', { produitId: p.id, produit: p.designation, numeroLot: v.lot, datePeremption: v.peremption, quantiteRestante: v.quantite, emplacement: p.emplacement || '', magasin: 'detail', statut: statutLot(v.peremption, jour) });
        var ref = C.referenceSuivante('M', 6, mouvs);
        mouvs.push({ reference: ref });
        ecrireFiche('mouvements', { reference: ref, date: jour, produitId: p.id, produit: p.designation, type: 'entree', typeLabel: 'Entrée', quantite: v.quantite, stockType: 'detail',
          justificatif: 'Import ' + lot.reference + ' (stock détail initial' + (v.lot ? ', lot ' + v.lot : '') + ')', utilisateur: S.currentUser() });
        if (!totaux[p.id]) { totaux[p.id] = 0; ordre.push(p); }
        totaux[p.id] += v.quantite;
      });
      /* Les compteurs en DERNIER : une fiche mise à jour ne se retire pas avec le reste de l'atomicité du moteur, elle se restitue ici. */
      try {
        ordre.forEach(function (p) {
          var avant = { stockDetail: p.stockDetail || 0, stock: p.stock || 0 };
          if (!S.collection('produits').update(p.id, { stockDetail: avant.stockDetail + totaux[p.id], stock: avant.stock + totaux[p.id] })) throw new Error('le stock de « ' + p.designation + ' » n’a pas pu être mis à jour');
          faits.push({ id: p.id, avant: avant });
        });
      } catch (e) {
        faits.reverse().forEach(function (f) { S.collection('produits').update(f.id, f.avant); });
        throw e;
      }
    },
    dependances: function (lot) {
      var ids = {}, propres = {};
      lot.ecrits.forEach(function (e) { if (e.collection === 'mouvements') { propres[e.id] = true; var m = S.collection('mouvements').get(e.id); if (m) ids[m.produitId] = true; } });
      var autre = S.collection('mouvements').active().filter(function (m) { return ids[m.produitId] && !propres[m.id]; })[0];
      return autre ? { code: 'MOUVEMENT_POSTERIEUR', motif: 'l’article « ' + autre.produit + ' » a déjà un mouvement de stock postérieur (' + autre.reference + ', ' + autre.typeLabel + ')',
        geste: 'Annulez d’abord ce mouvement, ou régularisez le stock détail par un inventaire : le lot ne peut pas être retiré sous un stock vivant (RG-03).' } : null;
    },
    /* L'ANNULATION ARCHIVE les lots et les mouvements du lot (RG-14) et RESTITUE les compteurs ; le détail ne peut jamais redescendre sous zéro (RG-03). */
    annuler: function (lot, motif) {
      var qte = {}, aArchiver = [];
      lot.ecrits.forEach(function (e) {
        var f = S.collection(e.collection).get(e.id);
        if (!f || f.statut === 'archive') return;
        aArchiver.push(e);
        if (e.collection === 'mouvements') qte[f.produitId] = (qte[f.produitId] || 0) + (f.quantite || 0);
      });
      for (var id in qte) {
        var p = S.collection('produits').get(id);
        if (!p || (p.stockDetail || 0) < qte[id]) return { ok: false, code: 'DETAIL_DEJA_DISPENSE', motif: 'l’article « ' + (p ? p.designation : id) + ' » n’a plus assez de stock détail pour retirer le stock initial (RG-03)', geste: 'Régularisez le stock détail par un inventaire.' };
      }
      var faits = [];
      for (var i = 0; i < aArchiver.length; i++) {
        var a = S.collection(aArchiver[i].collection).archive(aArchiver[i].id, 'Annulation du lot ' + lot.reference + (motif ? ' : ' + motif : ''));
        if (!a) {
          faits.forEach(function (x) { S.collection(x.collection).restore(x.id); });
          return { ok: false, code: 'ARCHIVAGE_REFUSE', motif: 'le moteur a refusé d’archiver une fiche de « ' + aArchiver[i].collection + ' »', geste: 'Rien n’a été annulé.' };
        }
        faits.push(aArchiver[i]);
      }
      for (var k in qte) {
        var pr = S.collection('produits').get(k);
        S.collection('produits').update(k, { stockDetail: (pr.stockDetail || 0) - qte[k], stock: Math.max(0, (pr.stock || 0) - qte[k]) });
      }
      return { ok: true, archives: faits.length };
    },
  });

  /* --- 14. BON DE TRANSFERT : UNE FEUILLE = UN BON NEUF, par la fabrique du geste ---------------------------------------- */
  JEUX.push({
    id: 'transfert-lignes', ecran: 'imp-transfert-lignes', libelle: 'Importation d’un bon de transfert', module: 'M6', statut: 'supporte',
    description: 'Un bon de transfert du magasin central vers la pharmacie de détail : une ligne par article (et par lot), un service destinataire pour tout le fichier.',
    source: 'Bon de transfert de l’écran « Transferts gros → détail » : même numérotation, mêmes mouvements, mêmes stocks.',
    limite: 'Une feuille crée UN bon neuf, par la MÊME fabrique que le geste de l’écran : un bon numéroté APRÈS la vérification, deux mouvements symétriques par ligne, stocks gros et détail. '
      + 'RG-03 se contrôle ligne par ligne en nommant l’article, en tenant compte des lignes déjà posées sur le bon ; le lot est celui qui part en premier (FEFO, RG-05) : un lot précisé qui n’est pas le premier est refusé. '
      + 'Le service, la date et le motif sont uniques pour tout le fichier.',
    cibles: ['transferts', 'mouvements', 'produits'], fichierModele: 'modele-import-transfert-lignes',
    colonnes: [
      oblig('code', 'Code article', 'texte', { longueurMax: 24, exemple: 'PARA500', aide: 'Un article connu du référentiel, déjà en stock au magasin central.' }),
      col('lot', 'N° de lot', 'texte', { longueurMax: 40, exemple: 'L2026-014', aide: 'Vide : le lot qui part en premier (FEFO) est retenu. Précisé : il doit être celui-là.' }),
      oblig('quantite', 'Quantité', 'entier', { min: 0, exemple: 20, aide: 'Quantité transférée au détail, au plus ce que le magasin central détient (RG-03).',
        sousMin: { code: 'RG03_STOCK_NEGATIF', motif: 'quantité négative : un transfert ne peut pas retirer du stock au détail (RG-03)', geste: 'Saisissez une quantité entière supérieure à zéro.' } }),
      col('destination', 'Service destinataire', 'liste', { liste: function () { return PR.DESTINATIONS_TRANSFERT; }, exemple: 'Pharmacie d’urgence', aide: 'Le même pour toutes les lignes du fichier : une feuille est un seul bon.' }),
      col('date', 'Date du transfert', 'date', { aide: 'Vide : aujourd’hui. La même pour toutes les lignes.' }),
      col('motif', 'Motif', 'texte', { longueurMax: 160, aide: 'Le même pour toutes les lignes.' }),
    ],
    contexte: contexteStock,
    cle: function (v) { return [C.norm(v.code) + '|' + C.norm(v.lot || '')]; },
    existe: function () { return null; },
    regles: function (v, ctx, sc, n) {
      var p = ctx.produits[C.norm(v.code)];
      if (!p) return [articleInconnu(v)];
      var pb = [];
      sc.pose = sc.pose || {};
      if (v.date && v.date > ctx.jour) pb.push({ colonne: 'Date du transfert', valeur: v.date, code: 'DATE_FUTURE', niveau: 'refus', motif: 'la date du transfert est dans le futur', geste: 'Saisissez la date du jour ou une date passée.' });
      if (v.quantite === 0) pb.push({ colonne: 'Quantité', valeur: 0, code: 'QUANTITE_NULLE', niveau: 'refus', motif: 'un transfert de zéro n’est pas un transfert', geste: 'Retirez la ligne ou saisissez une quantité d’au moins 1.' });
      else {
        /* RG-03 LIGNE PAR LIGNE : la règle est celle de la fabrique du geste (PR.refusLigneTransfert), le disponible tient compte de ce que les lignes précédentes ont déjà posé. */
        var r = PR.refusLigneTransfert(p, v.quantite, sc.pose[p.id] || 0, n);
        if (r) pb.push({ colonne: 'Quantité', valeur: v.quantite, code: r.code, niveau: 'refus', motif: r.motif, geste: r.geste });
        sc.pose[p.id] = (sc.pose[p.id] || 0) + v.quantite;
      }
      var lotRetenu = null, fefo = PR.lotFefo(p.id);
      if (v.lot) {
        var l = (ctx.lots[p.id] || []).filter(function (x) { return C.norm(x.numeroLot) === C.norm(v.lot); })[0];
        if (!l) pb.push({ colonne: 'N° de lot', valeur: v.lot, code: 'LOT_INCONNU', niveau: 'refus', motif: 'aucun lot « ' + v.lot + ' » pour l’article « ' + p.designation + ' »', geste: 'Corrigez le numéro de lot, ou laissez la colonne vide pour retenir le lot FEFO.' });
        else if (l.statut === 'perime') pb.push({ colonne: 'N° de lot', valeur: v.lot, code: 'LOT_PERIME', niveau: 'refus', motif: 'le lot « ' + v.lot + ' » est périmé : il ne se transfère pas', geste: 'Retirez-le du stock par une perte déclarée, puis transférez un lot valide.' });
        else if (fefo && fefo.numeroLot !== l.numeroLot) pb.push({ colonne: 'N° de lot', valeur: v.lot, code: 'LOT_NON_FEFO', niveau: 'refus', motif: 'le lot « ' + v.lot + ' » n’est pas le premier à sortir : le lot « ' + fefo.numeroLot + ' » (péremption ' + fefo.datePeremption + ') part avant lui (FEFO, RG-05)', geste: 'Laissez la colonne « N° de lot » vide pour retenir le lot FEFO, ou précisez-le.' });
        else lotRetenu = l;
      } else lotRetenu = fefo;
      sc.extras[n] = { detail: 'Disponible au magasin avant la ligne : ' + C.num(Math.max(0, (p.stockGros || 0) - ((sc.pose[p.id] || 0) - (v.quantite || 0)))) + ' ' + (p.unite || '')
        + (lotRetenu ? ' · lot retenu : ' + lotRetenu.numeroLot + ' (péremption ' + lotRetenu.datePeremption + ')' : ' · aucun lot recensé') };
      return pb;
    },
    reglesLot: function (lignes) {
      var pb = [], dest = distincts(lignes, 'destination'), dates = distincts(lignes, 'date'), motifs = distincts(lignes, 'motif');
      if (!dest.length) pb.push({ n: 0, colonne: 'Service destinataire', valeur: '', code: 'DESTINATION_ABSENTE', niveau: 'refus', motif: 'aucune ligne ne nomme le service destinataire : un bon a une destination', geste: 'Renseignez la colonne « Service destinataire » sur au moins une ligne.' });
      if (dest.length > 1) pb.push({ n: 0, colonne: 'Service destinataire', valeur: dest.join(', '), code: 'DESTINATIONS_MULTIPLES', niveau: 'refus', motif: 'le fichier porte ' + dest.length + ' services destinataires : une feuille est UN bon, pour UN service', geste: 'Faites un fichier par service destinataire.' });
      if (dates.length > 1) pb.push({ n: 0, colonne: 'Date du transfert', valeur: dates.join(', '), code: 'BON_UNIQUE', niveau: 'refus', motif: 'le fichier porte ' + dates.length + ' dates : une feuille est UN bon, à une seule date', geste: 'Alignez toutes les lignes sur la même date, ou laissez la colonne vide.' });
      if (motifs.length > 1) pb.push({ n: 0, colonne: 'Motif', valeur: motifs.join(', '), code: 'BON_UNIQUE', niveau: 'refus', motif: 'le fichier porte ' + motifs.length + ' motifs : une feuille est UN bon, avec un seul motif', geste: 'Alignez les lignes sur le même motif, ou laissez la colonne vide.' });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche, lot, ctx, declarer) {
      var premiere = lignes[0].v;
      var dest = distincts(lignes, 'destination')[0], dates = distincts(lignes, 'date'), motifs = distincts(lignes, 'motif');
      /* La MÊME fabrique que le geste : contrôle RG-03 d'abord (rien n'est écrit si une ligne est refusée), numéro du bon APRÈS la vérification, stocks, mouvements, bon. */
      var r = PR.emettreTransfert({ date: dates[0] || aujourdhuiIso(), demandeur: dest, motif: motifs[0] || '' },
        lignes.map(function (l) { var p = ctx.produits[C.norm(l.v.code)]; return { produitId: p.id, quantite: l.v.quantite, lot: l.v.lot || undefined }; }),
        { marque: { source: 'Import Importation d’un bon de transfert', lotImport: lot.reference, validePar: S.currentUser(), dateImport: aujourdhuiIso() } });
      if (!r.ok) throw new Error(r.motif);
      declarer('transferts', r.bon.id);
      r.mouvements.forEach(function (m) { declarer('mouvements', m.id); });
      void premiere;
    },
    dependances: function () { return null; },
    /* L'ANNULATION RESTITUE LES STOCKS : le gros retrouve ce qui est parti, le détail rend ce qu'il a reçu — et ne peut pas descendre sous zéro (RG-03) : s'il a déjà dispensé, le refus le dit. */
    annuler: function (lot, motif) {
      var bon = null, mouvs = [];
      lot.ecrits.forEach(function (e) {
        var f = S.collection(e.collection).get(e.id);
        if (!f || f.statut === 'archive') return;
        if (e.collection === 'transferts') bon = f; else if (e.collection === 'mouvements') mouvs.push(f);
      });
      if (!bon) return { ok: false, code: 'LOT_SANS_BON', motif: 'le bon de transfert de ce lot est déjà archivé', geste: 'Aucune action.' };
      var rendre = {};
      (bon.lignes || []).forEach(function (l) { rendre[l.produitId] = (rendre[l.produitId] || 0) + l.quantite; });
      for (var id in rendre) {
        var p = S.collection('produits').get(id);
        if (!p || (p.stockDetail || 0) < rendre[id]) return { ok: false, code: 'TRANSFERT_DEJA_DISPENSE', motif: 'l’article « ' + (p ? p.designation : id) + ' » n’a plus assez de stock détail pour rendre ce transfert (' + C.num(rendre[id]) + ' à rendre, ' + C.num(p ? p.stockDetail || 0 : 0) + ' au détail) : une partie a déjà été dispensée (RG-03)', geste: 'Régularisez le stock détail par un inventaire, ou annulez d’abord les dispensations.' };
      }
      var cibles = [{ collection: 'transferts', id: bon.id }].concat(mouvs.map(function (m) { return { collection: 'mouvements', id: m.id }; })), faits = [];
      for (var i = 0; i < cibles.length; i++) {
        if (!S.collection(cibles[i].collection).archive(cibles[i].id, 'Annulation du lot ' + lot.reference + (motif ? ' : ' + motif : ''))) {
          faits.forEach(function (x) { S.collection(x.collection).restore(x.id); });
          return { ok: false, code: 'ARCHIVAGE_REFUSE', motif: 'le moteur a refusé d’archiver une fiche de « ' + cibles[i].collection + ' »', geste: 'Rien n’a été annulé.' };
        }
        faits.push(cibles[i]);
      }
      for (var k in rendre) {
        var pr = S.collection('produits').get(k);
        S.collection('produits').update(k, { stockGros: (pr.stockGros || 0) + rendre[k], stockDetail: (pr.stockDetail || 0) - rendre[k] });
      }
      return { ok: true, archives: faits.length };
    },
  });

  /* --- 15. COMPTAGE D'INVENTAIRE : crée la feuille, ne régularise JAMAIS (I13) ------------------------------------------- */
  var MAGASINS_INVENTAIRE = [{ valeur: 'gros', label: 'Stock gros' }, { valeur: 'detail', label: 'Stock détail' }];
  var TYPES_INVENTAIRE = ['Hebdomadaire', 'Mensuel', 'Annuel', 'Tournant', 'Ponctuel'];
  function libelleMagasin(m) { return m === 'detail' ? 'Stock détail (pharmacie d’urgence)' : 'Stock gros (magasin central)'; }
  JEUX.push({
    id: 'inventaire-comptage', ecran: 'imp-inventaire-comptage', libelle: 'Importation d’un comptage d’inventaire', module: 'M6', statut: 'supporte',
    description: 'Un comptage physique déjà fait : une ligne par article et par magasin nommé (gros ou détail), avec la quantité comptée.',
    source: 'Feuille d’inventaire de l’écran « Inventaires » : même magasin nommé, même écart calculé du stock théorique de CE magasin.',
    limite: 'L’import crée une feuille d’inventaire « comptage importé » et NE TOUCHE À AUCUN STOCK : la régularisation reste un geste humain, au registre des inventaires (un mouvement par écart, RG-03). '
      + 'Les deux magasins se comptent séparément : une feuille par magasin nommé. Si le stock a bougé entre le comptage et la régularisation, celle-ci est refusée.',
    cibles: ['inventaires'], fichierModele: 'modele-import-inventaire-comptage',
    colonnes: [
      oblig('magasin', 'Magasin', 'liste', { liste: MAGASINS_INVENTAIRE, exemple: 'Stock gros', aide: 'Gros ou détail seulement : un article ne porte pas d’autre stock.' }),
      oblig('code', 'Code article', 'texte', { longueurMax: 24, exemple: 'PARA500' }),
      oblig('compte', 'Quantité comptée', 'entier', { min: 0, exemple: 118, aide: 'Le stock physique compté dans CE magasin. Jamais négative (RG-03).',
        sousMin: { code: 'RG03_STOCK_NEGATIF', motif: 'quantité comptée négative : un stock physique ne peut pas être négatif (RG-03)', geste: 'Saisissez la quantité réellement comptée, zéro ou plus.' } }),
      col('type', 'Type d’inventaire', 'liste', { liste: TYPES_INVENTAIRE, exemple: 'Ponctuel', aide: 'Vide : Ponctuel. Le même pour toutes les lignes d’un magasin.' }),
      col('date', 'Date du comptage', 'date', { aide: 'Vide : aujourd’hui. La même pour toutes les lignes d’un magasin.' }),
    ],
    contexte: contexteStock,
    cle: function (v) { return [v.magasin + '|' + C.norm(v.code)]; },
    existe: function () { return null; },
    regles: function (v, ctx, sc, n) {
      var p = ctx.produits[C.norm(v.code)];
      if (!p) return [articleInconnu(v)];
      var pb = [], theo = (v.magasin === 'detail' ? p.stockDetail : p.stockGros) || 0, ecart = v.compte - theo;
      if (v.date && v.date > ctx.jour) pb.push({ colonne: 'Date du comptage', valeur: v.date, code: 'DATE_FUTURE', niveau: 'refus', motif: 'la date du comptage est dans le futur', geste: 'Saisissez la date du comptage réel.' });
      sc.extras[n] = { detail: libelleMagasin(v.magasin) + ' : théorique ' + C.num(theo) + ', compté ' + C.num(v.compte) + ', écart ' + (ecart > 0 ? '+' : '') + C.num(ecart) };
      return pb;
    },
    reglesLot: function (lignes) {
      var pb = [];
      ['gros', 'detail'].forEach(function (m) {
        var ls = lignes.filter(function (l) { return l.v.magasin === m; });
        if (!ls.length) return;
        var types = distincts(ls, 'type'), dates = distincts(ls, 'date');
        if (types.length > 1) pb.push({ n: 0, colonne: 'Type d’inventaire', valeur: types.join(', '), code: 'FEUILLE_UNIQUE', niveau: 'refus', motif: 'les lignes du ' + libelleMagasin(m).toLowerCase() + ' portent ' + types.length + ' types d’inventaire : une feuille a un seul type', geste: 'Alignez les lignes de ce magasin sur le même type, ou laissez la colonne vide.' });
        if (dates.length > 1) pb.push({ n: 0, colonne: 'Date du comptage', valeur: dates.join(', '), code: 'FEUILLE_UNIQUE', niveau: 'refus', motif: 'les lignes du ' + libelleMagasin(m).toLowerCase() + ' portent ' + dates.length + ' dates : une feuille est un seul comptage', geste: 'Alignez les lignes de ce magasin sur la même date, ou laissez la colonne vide.' });
      });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche, lot, ctx) {
      ['gros', 'detail'].forEach(function (m) {
        var ls = lignes.filter(function (l) { return l.v.magasin === m; });
        if (!ls.length) return;
        var type = distincts(ls, 'type')[0] || 'Ponctuel', date = distincts(ls, 'date')[0] || aujourdhuiIso();
        var corps = ls.map(function (l) {
          var p = ctx.produits[C.norm(l.v.code)], theo = (m === 'detail' ? p.stockDetail : p.stockGros) || 0, e = l.v.compte - theo;
          return { produitId: p.id, code: p.code, designation: p.designation, unite: p.unite, theorique: theo, physique: l.v.compte, ecart: e, cump: p.cump, valeur: e * (p.cump || 0) };
        });
        var ecarts = corps.filter(function (x) { return x.ecart !== 0; });
        ecrireFiche('inventaires', {
          reference: C.referenceSuivante('INV-', 4, S.collection('inventaires').all()), date: date, type: type, perimetre: 'Comptage importé (' + corps.length + ' article' + (corps.length > 1 ? 's' : '') + ')',
          magasin: m, magasinLabel: libelleMagasin(m), operateur: S.currentUser(), statutInv: 'importe',
          nbArticles: corps.length, nbEcarts: ecarts.length, valeurEcart: ecarts.reduce(function (t, x) { return t + x.valeur; }, 0), lignes: corps,
        });
      });
    },
    dependances: function (lot) {
      var regularisee = null;
      lot.ecrits.forEach(function (e) { var f = S.collection('inventaires').get(e.id); if (f && f.statutInv === 'valide' && !regularisee) regularisee = f; });
      return regularisee ? { code: 'INVENTAIRE_REGULARISE', motif: 'la feuille ' + regularisee.reference + ' a été régularisée : des mouvements de stock s’appuient sur elle', geste: 'Annulez d’abord la régularisation par un inventaire inverse : un lot ne peut pas être retiré sous un stock régularisé (RG-03).' } : null;
    },
  });

  function jeu(id) { return JEUX.filter(function (j) { return j.id === id; })[0] || null; }

  /* --- Les colonnes d'un jeu selon le PROFIL (I9, I10) ---------------------------------------------------------------- *
   * Une colonne qui porte `capacite: 'paie'` n'est dans le modèle, et acceptée au fichier, que pour un profil qui détient cette capacité (lue de la matrice : écrire dans M11),
   * jamais d'un nom de rôle. Une colonne RETIRÉE du modèle (`colonnesRetirees` : le groupe sanguin du répertoire) n'existe pour personne. Un fichier qui porte l'une de ces
   * colonnes est REFUSÉ en la nommant : l'ignorer en silence ferait croire qu'elle a été reprise. */
  function capaciteDe(nom, r) { return nom === 'paie' ? N.capacitePaie(r) : false; }
  function colonnesDe(j) {
    var r = roleCourant();
    return j.colonnes.filter(function (c) { return !c.capacite || capaciteDe(c.capacite, r); });
  }
  function colonnesInterdites(j) {
    var r = roleCourant(), out = [];
    j.colonnes.forEach(function (c) {
      if (c.capacite && !capaciteDe(c.capacite, r)) out.push({ label: c.label, code: 'COLONNE_RESERVEE',
        motif: 'la colonne « ' + c.label + ' » est réservée aux profils qui détiennent la capacité « ' + c.capacite + ' » : elle n’est pas dans votre modèle',
        geste: 'Retirez la colonne « ' + c.label + ' » du fichier ; elle se renseigne à l’écran par un profil habilité.' });
    });
    (j.colonnesRetirees || []).forEach(function (c) {
      out.push({ label: c.label, code: 'COLONNE_RETIREE', motif: c.motif, geste: 'Retirez la colonne « ' + c.label + ' » du fichier.' });
    });
    return out;
  }

  /* ==========================================================================
   * ANALYSE : le fichier lu, contrôlé, jamais écrit.
   * ======================================================================== */
  function clefEntete(s) { return C.norm(String(s == null ? '' : s).replace(/\*/g, '')).replace(/\s+/g, ' ').trim(); }

  function ligneExemple(j) {
    return colonnesDe(j).map(function (c) { return c.exemple === undefined ? '' : c.exemple; });
  }

  function analyserLignes(j, lignes, fichier) {
    var res = { jeu: j.id, fichier: fichier || '', nbLignes: 0, lignes: [], globaux: [], accepte: false, aEcrire: 0,
      compte: { valides: 0, avertissements: 0, refus: 0, ignores: 0, inchanges: 0, non: 0 }, lignesBrutes: lignes };
    function global_(code, colonne, motif, geste, niveau, valeur) {
      res.globaux.push({ n: 0, colonne: colonne || '', valeur: valeur === undefined ? '' : valeur, code: code, motif: motif, geste: geste, niveau: niveau || 'refus' });
    }
    /* LE MOTEUR REFUSE AUSSI : pas de droit d'importer ce jeu, pas d'analyse (le refus ne se consigne pas : rien n'a été tenté par un détenteur). */
    var rd = refusDroit(j, 'importer');
    if (rd) { global_(rd.code, '', rd.motif, rd.geste); res.droitRefuse = true; return res; }
    if (!lignes || !lignes.length) {
      global_('FICHIER_VIDE', '', 'le fichier ne contient aucune ligne', 'Téléchargez le modèle, remplissez l’onglet Données et téléversez-le de nouveau.');
      return res;
    }
    /* LA TAILLE MAXIMALE, avant tout travail : un refus nommé, jamais une constante muette. */
    var borne = borneDe(j);
    if (lignes.length - 1 > borne) {
      global_('FICHIER_TROP_GROS', '', 'le fichier porte ' + (lignes.length - 1) + ' lignes ; le maximum réglé pour ce jeu est ' + borne,
        'Découpez le fichier en plusieurs fichiers de ' + borne + ' lignes au plus, ou faites relever la taille maximale du jeu par un profil qui supervise les importations (onglet « Tailles maximales » de l’accueil du module).');
      return res;
    }
    var cols = colonnesDe(j);
    var entete = lignes[0].map(clefEntete), idx = {}, manquantes = [];
    var interdites = colonnesInterdites(j).filter(function (c) { return entete.indexOf(clefEntete(c.label)) >= 0; });
    if (interdites.length) {
      interdites.forEach(function (c) { global_(c.code, c.label, c.motif, c.geste); });
      return res;
    }
    cols.forEach(function (c) {
      var i = entete.indexOf(clefEntete(c.label));
      if (i < 0) {
        if (c.obligatoire) manquantes.push(c);
        else global_('COLONNE_ABSENTE', c.label, 'colonne facultative « ' + c.label + ' » absente du fichier', 'Ses valeurs resteront vides ; ajoutez-la au besoin.', 'avertissement');
      } else idx[c.cle] = i;
    });
    if (manquantes.length) {
      manquantes.forEach(function (c) {
        global_('COLONNE_MANQUANTE', c.label, 'colonne obligatoire « ' + c.label + ' » absente de la première ligne du fichier',
          'Ajoutez la colonne « ' + c.label + ' » en respectant l’orthographe exacte du modèle, ou téléchargez le modèle de nouveau.');
      });
      return res;
    }
    var connus = {};
    cols.forEach(function (c) { connus[clefEntete(c.label)] = true; });
    lignes[0].forEach(function (h, i) {
      if (!vide(h) && !connus[clefEntete(h)]) global_('COLONNE_IGNOREE', String(h), 'colonne « ' + h + ' » inconnue : elle est ignorée', 'Retirez-la du fichier si elle est inutile.', 'avertissement');
    });
    var ctx = j.contexte ? j.contexte() : {}, sc = { articles: {}, extras: {}, ligne: null };
    var mode = modeDoublon(j);
    var exemple = ligneExemple(j).map(function (x) { return String(x).trim(); });
    var vus = {};
    for (var r = 1; r < lignes.length; r++) {
      var brute = lignes[r];
      if (brute.every(vide)) continue;
      var lecture = cols.map(function (c) { return String(nettoyer(brute[idx[c.cle]] == null ? '' : brute[idx[c.cle]])).trim(); });
      if (r === 1 && lecture.join('|') === exemple.join('|')) continue; /* la ligne d'exemple du modèle, restée telle quelle */
      var n = r + 1, ligne = { n: n, v: {}, brut: lecture, problemes: [], etat: 'valide', sansEcriture: null };
      var ok = true;
      cols.forEach(function (c) {
        var b = brute[idx[c.cle]];
        var lc = lireCellule(c, b, ctx);
        if (lc.erreur) {
          ok = false;
          ligne.problemes.push({ n: n, colonne: c.label, valeur: String(b), code: lc.erreur.code, motif: lc.erreur.motif, geste: lc.erreur.geste, niveau: 'refus' });
          ligne.v[c.cle] = null;
        } else if (lc.vide) {
          ligne.v[c.cle] = null;
          if (c.obligatoire) {
            ok = false;
            ligne.problemes.push({ n: n, colonne: c.label, valeur: '', code: 'CHAMP_OBLIGATOIRE', motif: 'valeur obligatoire absente', geste: 'Renseignez la colonne « ' + c.label + ' » de la ligne ' + n + '.', niveau: 'refus' });
          }
        } else ligne.v[c.cle] = lc.valeur;
      });
      if (ok) {
        var cles = j.cle(ligne.v), doublon = null;
        cles.forEach(function (k) { if (!doublon && vus[k]) doublon = vus[k]; });
        if (doublon) {
          ligne.problemes.push({ n: n, colonne: cols[0].label, valeur: lecture[0], code: 'DOUBLON_FICHIER', niveau: 'refus',
            motif: 'identique à la ligne ' + doublon + ' du même fichier', geste: 'Retirez l’une des deux lignes.' });
        } else cles.forEach(function (k) { vus[k] = n; });
        var existe = j.existe ? j.existe(ligne.v, ctx) : null;
        if (existe && mode === 'ignorer' && !doublon) {
          /* IGNORER LES EXISTANTS (I8, jeux de la liste fermée seulement) : la ligne n'écrit rien, elle est COMPTÉE et NOMMÉE au rapport, jamais perdue en silence. */
          ligne.problemes.push({ n: n, colonne: cols[0].label, valeur: lecture[0], code: 'IGNORE_EXISTANT', niveau: 'ignore', motif: existe,
            geste: 'Ligne ignorée : la fiche existe déjà et un import ne modifie jamais une fiche tenue.' });
          ligne.sansEcriture = 'ignore';
        } else {
          if (existe) ligne.problemes.push({ n: n, colonne: cols[0].label, valeur: lecture[0], code: 'DOUBLON_MAGASIN', niveau: 'refus', motif: existe, geste: j.gesteExiste || 'Retirez la ligne.' });
          sc.ligne = ligne;
          (j.regles ? j.regles(ligne.v, ctx, sc, n) : []).forEach(function (p) { ligne.problemes.push(Object.assign({ n: n }, p)); });
        }
      }
      var refus = ligne.problemes.some(function (p) { return p.niveau === 'refus'; });
      ligne.etat = refus ? 'refus' : (ligne.sansEcriture || (ligne.problemes.some(function (p) { return p.niveau === 'avertissement'; }) ? 'avertissement' : 'valide'));
      if (refus) ligne.sansEcriture = null;
      if (sc.extras[n]) ligne.extra = sc.extras[n];
      res.lignes.push(ligne);
    }
    res.nbLignes = res.lignes.length;
    if (!res.nbLignes) {
      global_('FICHIER_VIDE', '', 'aucune ligne de données (la ligne d’exemple du modèle n’est pas importée)', 'Remplacez la ligne d’exemple par vos données, ou ajoutez des lignes.');
      return res;
    }
    if (j.reglesLot && !res.lignes.some(function (l) { return l.etat === 'refus'; })) {
      j.reglesLot(res.lignes, ctx).forEach(function (p) { res.globaux.push(p); });
    }
    res.lignes.forEach(function (l) {
      if (l.etat === 'refus') res.compte.refus++;
      else if (l.etat === 'ignore') res.compte.ignores++;
      else if (l.etat === 'inchange') res.compte.inchanges++;
      else if (l.etat === 'non') res.compte.non++;
      else if (l.etat === 'avertissement') res.compte.avertissements++;
      else res.compte.valides++;
    });
    res.aEcrire = res.lignes.filter(function (l) { return !l.sansEcriture && l.etat !== 'refus'; }).length;
    res.accepte = !res.globaux.some(function (p) { return p.niveau === 'refus'; }) && res.compte.refus === 0 && res.nbLignes > 0;
    return res;
  }

  /** Tous les problèmes à plat (globaux, puis par ligne), pour le rapport et pour la consignation. */
  function problemes(analyse, j) {
    var out = analyse.globaux.slice();
    analyse.lignes.forEach(function (l) { l.problemes.forEach(function (p) { out.push(p); }); });
    return j ? out.map(function (p) { return masquer(j, p); }) : out;
  }
  /** Ce qui entre dans l'HISTORIQUE : masqué pour un jeu restreint, intégral sinon. */
  function problemesConsignes(j, analyse) { return problemes(analyse, j); }
  /** Les lignes ignorées (mode « ignorer »), pour le lot : le nombre ET la liste (borne de 500 noms, le total reste exact). */
  function ignoresDe(analyse) {
    var l = analyse.lignes.filter(function (x) { return x.etat === 'ignore'; });
    return { ignoresTotal: l.length, ignores: l.slice(0, 500).map(function (x) { return { n: x.n, cle: x.brut[0] }; }) };
  }

  function analyserOctets(jeuId, octets, fichier) {
    var j = jeu(jeuId), lignes;
    var rd = refusDroit(j, 'importer');
    if (rd) return { jeu: jeuId, fichier: fichier, nbLignes: 0, lignes: [], accepte: false, aEcrire: 0, droitRefuse: true, compte: { valides: 0, avertissements: 0, refus: 0, ignores: 0, inchanges: 0, non: 0 }, lignesBrutes: [],
      globaux: [{ n: 0, colonne: '', valeur: '', code: rd.code, niveau: 'refus', motif: rd.motif, geste: rd.geste }] };
    try {
      if (/\.csv$/i.test(fichier || '') || /\.txt$/i.test(fichier || '')) lignes = X.lireCsv(new TextDecoder('utf-8').decode(octets));
      else {
        var classeur = X.lire(octets);
        var feuille = classeur.feuilles.filter(function (f) { return C.norm(f.nom) === C.norm(NOMS_FEUILLES.donnees); })[0] || classeur.feuilles[0];
        if (!feuille) throw new Error('le classeur ne contient aucune feuille');
        lignes = feuille.lignes;
      }
    } catch (e) {
      var res = { jeu: jeuId, fichier: fichier, nbLignes: 0, lignes: [], accepte: false, aEcrire: 0, compte: { valides: 0, avertissements: 0, refus: 0, ignores: 0, inchanges: 0, non: 0 }, lignesBrutes: [],
        globaux: [{ n: 0, colonne: '', valeur: fichier || '', code: 'FORMAT_FICHIER', niveau: 'refus', motif: 'fichier illisible : ' + (e && e.message ? e.message : e),
          geste: 'Déposez un classeur .xlsx (modèle téléchargé) ou un fichier .csv encodé en UTF-8.' }] };
      res.empreinte = X.crc32(octets).toString(16);
      return res;
    }
    var a = analyserLignes(j, lignes, fichier);
    a.empreinte = X.crc32(octets).toString(16);
    return a;
  }

  /* ==========================================================================
   * LOTS : consignation, application atomique, annulation.
   * ======================================================================== */
  function colLots() { return S.collection('lotsImportation', { module: 'IMP', entite: 'LotImport', prefix: 'LIM' }); }

  function referenceLot() {
    var an = String(C.aujourdhui().getFullYear());
    var max = 0;
    colLots().all().forEach(function (l) {
      var m = /^IMP-(\d{4})-(\d+)$/.exec(l.reference || '');
      if (m && m[1] === an) max = Math.max(max, Number(m[2]));
    });
    return 'IMP-' + an + '-' + C.pad(max + 1, 3);
  }

  function consigner(j, analyse) {
    if (analyse.droitRefuse) return null; /* rien n'a été tenté par un détenteur : un refus de droit ne s'écrit pas à l'historique du jeu */
    var ps = problemesConsignes(j, analyse);
    var r = colLots().insert({
      reference: referenceLot(), jeu: j.id, jeuLibelle: j.libelle, fichier: analyse.fichier, empreinte: analyse.empreinte || null,
      date: aujourdhuiIso(), par: S.currentUser(), etat: 'refuse', nbLignes: analyse.nbLignes,
      nbAvertissements: analyse.compte.avertissements, nbRefus: analyse.compte.refus + analyse.globaux.filter(function (p) { return p.niveau === 'refus'; }).length,
      ecrits: [], erreurs: ps.slice(0, 100), erreursTotal: ps.length,
    });
    S.log('Import refusé', 'IMP', 'LotImport', r.record.reference, null, { jeu: j.id, fichier: analyse.fichier, refus: r.record.nbRefus });
    return r.record;
  }

  function appliquer(jeuId, analyse) {
    var j = jeu(jeuId);
    /* LE MOTEUR REFUSE AUSSI : un bouton masqué ne protège rien. Le droit d'importer ce jeu se relit ICI, au moment d'écrire, pas à l'ouverture de la fenêtre. */
    var rd = j && refusDroit(j, 'importer');
    if (rd) return rd;
    if (!analyse || !analyse.accepte) return { ok: false, code: 'ANALYSE_REFUSEE', motif: 'le fichier n’a pas passé l’analyse', geste: 'Corrigez les refus listés, puis téléversez de nouveau.' };
    /* L'état du magasin a pu bouger entre l'analyse et la confirmation (un autre poste a pu créer le même article) :
       on rejoue l'analyse sur les lignes d'origine et l'on n'écrit que si elle tient toujours. */
    var rejeu = analyserLignes(j, analyse.lignesBrutes, analyse.fichier);
    if (!rejeu.accepte) {
      var c = consigner(j, Object.assign(rejeu, { empreinte: analyse.empreinte }));
      return { ok: false, code: 'MAGASIN_CHANGE', motif: 'le magasin a changé depuis l’analyse ; le fichier est refusé et consigné (' + c.reference + ')', geste: 'Relisez le rapport du lot ' + c.reference + ' et téléversez de nouveau.', lot: c, analyse: rejeu };
    }
    if (!rejeu.aEcrire) return { ok: false, code: 'RIEN_A_ECRIRE', motif: 'aucune ligne ne s’écrirait : toutes sont ignorées, inchangées ou refusées par leur auteur (Non)', geste: 'Rien à confirmer : aucun lot n’est consigné.' };
    var ctx = j.contexte ? j.contexte() : {};
    var lot = { reference: referenceLot() }, ecrits = [], par = S.currentUser(), jour = aujourdhuiIso();
    function declarer(nom, id) { ecrits.push({ collection: nom, id: id }); }
    function ecrireFiche(nom, fiche) {
      var meta = { module: j.module === 'IMP' ? 'IMP' : j.module, entite: nom };
      var res = S.collection(nom, meta).insert(Object.assign({
        source: 'Import ' + j.libelle + ' (' + (analyse.fichier || 'fichier') + ')', lotImport: lot.reference, validePar: par, dateImport: jour,
      }, fiche));
      if (!res) throw new Error('l’écriture dans « ' + nom + ' » a été refusée par le moteur');
      ecrits.push({ collection: nom, id: res.record.id });
      return res.record;
    }
    try {
      j.ecrire(rejeu.lignes.filter(function (l) { return !l.sansEcriture && l.etat !== 'refus'; }), ecrireFiche, lot, ctx, declarer);
    } catch (e) {
      /* Atomicité : on retire ce qui vient d'être posé dans CE geste. Ces fiches n'ont jamais été vues d'un autre écran. */
      ecrits.slice().reverse().forEach(function (x) { S.collection(x.collection)._remove(x.id); });
      var motif = e && e.message ? e.message : String(e);
      var consigne = consigner(j, Object.assign(rejeu, { globaux: rejeu.globaux.concat([{ n: 0, colonne: '', valeur: '', code: 'ECRITURE_REFUSEE', niveau: 'refus', motif: motif, geste: 'Rien n’a été écrit. Corrigez la cause puis téléversez de nouveau.' }]), empreinte: analyse.empreinte }));
      return { ok: false, code: 'ECRITURE_REFUSEE', motif: motif, geste: 'Rien n’a été écrit ; le fichier est consigné (' + consigne.reference + ').', lot: consigne };
    }
    var rec = colLots().insert(Object.assign({
      reference: lot.reference, jeu: j.id, jeuLibelle: j.libelle, fichier: analyse.fichier, empreinte: analyse.empreinte || null,
      date: jour, par: par, validePar: par, etat: 'applique', nbLignes: rejeu.nbLignes, nbAvertissements: rejeu.compte.avertissements, nbRefus: 0,
      nbIgnores: rejeu.compte.ignores, nbInchanges: rejeu.compte.inchanges, nbNon: rejeu.compte.non,
      ecrits: ecrits, erreurs: problemesConsignes(j, rejeu).slice(0, 100), erreursTotal: problemes(rejeu).length,
    }, ignoresDe(rejeu)));
    rec = rec.record;
    S.log('Import', 'IMP', 'LotImport', rec.reference, null, { jeu: j.id, fichier: analyse.fichier, lignes: rejeu.nbLignes, fiches: ecrits.length });
    return { ok: true, lot: rec, ecrits: ecrits.length };
  }

  function annulerLot(lotId, motif) {
    var col_ = colLots(), lot = col_.get(lotId);
    if (!lot) return { ok: false, code: 'LOT_INCONNU', motif: 'lot introuvable', geste: 'Actualisez l’historique.' };
    if (lot.etat !== 'applique') return { ok: false, code: 'LOT_NON_APPLIQUE', motif: 'seul un lot appliqué s’annule (état actuel : ' + lot.etat + ')', geste: 'Aucune action : ce lot n’a rien écrit ou est déjà annulé.' };
    var j = jeu(lot.jeu);
    var rd = j && refusDroit(j, 'annuler');
    if (rd) return rd;
    /* Un lot se défait par son AUTEUR ; celui d'un autre relève de la SUPERVISION (droit d'annuler sur chaque jeu). */
    if (lot.par !== S.currentUser() && !N.superviseImport(roleCourant())) {
      return { ok: false, code: 'LOT_D_UN_AUTRE', motif: 'le lot ' + lot.reference + ' a été écrit par un autre agent', geste: 'Seul son auteur, ou un profil qui supervise les importations, peut l’annuler.' };
    }
    var dep = j && j.dependances ? j.dependances(lot) : null;
    if (dep) return { ok: false, code: dep.code, motif: dep.motif, geste: dep.geste };
    /* Un jeu qui ne s'annule pas par archivage de ses fiches (les VERSIONS de prix sont immuables : une proposition se RETIRE) porte son propre geste d'annulation. */
    if (j && typeof j.annuler === 'function') {
      var ra = j.annuler(lot, motif);
      if (!ra.ok) return ra;
      col_.update(lot.id, { etat: 'annule', annulePar: S.currentUser(), annuleLe: aujourdhuiIso(), motifAnnulation: motif || null });
      S.log('Import annulé', 'IMP', 'LotImport', lot.reference, { etat: 'applique' }, { etat: 'annule', fiches: ra.archives });
      return { ok: true, lot: col_.get(lot.id), archives: ra.archives };
    }
    var faits = [], echec = null;
    for (var i = 0; i < lot.ecrits.length && !echec; i++) {
      var e = lot.ecrits[i], c = S.collection(e.collection);
      var f = c.get(e.id);
      if (!f || f.statut === 'archive') continue;
      if (!c.archive(e.id, 'Annulation du lot ' + lot.reference + (motif ? ' : ' + motif : ''))) echec = e; else faits.push(e);
    }
    if (echec) {
      faits.forEach(function (e) { S.collection(e.collection).restore(e.id); });
      return { ok: false, code: 'ARCHIVAGE_REFUSE', motif: 'le moteur a refusé d’archiver une fiche de « ' + echec.collection + ' » (exercice clos ou fiche verrouillée)', geste: 'Rien n’a été annulé. Rouvrez l’exercice ou traitez la fiche à la main.' };
    }
    col_.update(lot.id, { etat: 'annule', annulePar: S.currentUser(), annuleLe: aujourdhuiIso(), motifAnnulation: motif || null });
    S.log('Import annulé', 'IMP', 'LotImport', lot.reference, { etat: 'applique' }, { etat: 'annule', fiches: faits.length });
    return { ok: true, lot: col_.get(lot.id), archives: faits.length };
  }

  /* ==========================================================================
   * MODÈLES ET RAPPORTS .xlsx
   * ======================================================================== */
  function typeLisible(c) {
    return { texte: 'Texte', entier: 'Nombre entier', decimal: 'Nombre', date: 'Date (AAAA-MM-JJ ou JJ/MM/AAAA)', liste: 'Liste de valeurs', tarif: 'Montant, NC ou tiret' }[c.type] || c.type;
  }
  function valeursPermises(c, ctx) {
    if (c.type === 'liste') return valeursListe(c, ctx).map(function (x) { return x.label; }).join(' ; ');
    if (c.type === 'entier') return 'entier' + (c.min !== undefined ? ' ≥ ' + c.min : '') + (c.max !== undefined ? ' et ≤ ' + c.max : '');
    if (c.type === 'tarif') return 'montant entier en FCFA ; NC ; tiret (-)' + (c.unique ? ' ; UNIQUE (prix unique)' : '');
    if (c.motifTexte) return c.motifTexte;
    if (c.longueurMax) return 'jusqu’à ' + c.longueurMax + ' caractères';
    return '';
  }

  function modele(jeuId) {
    var j = jeu(jeuId), ctx = j.contexte ? j.contexte() : {}, cols = colonnesDe(j);
    var entetes = cols.map(function (c) { return c.label; });
    var donnees = [entetes, ligneExemple(j)];
    var instructions = [
      ['Modèle d’importation : ' + j.libelle],
      ['Source : ' + j.source],
      [j.statut === 'proposition' ? 'Statut du jeu : PROPOSITION À VALIDER. ' + (j.limite || '') : 'Statut du jeu : supporté.'],
      [''],
      ['Mode d’emploi'],
      ['1. Remplissez l’onglet « Données » à partir de la ligne 2 : une ligne par enregistrement. La ligne 2 est un exemple, remplacez-la ou supprimez-la (elle est ignorée tant qu’elle reste identique à l’exemple).'],
      ['2. Ne changez ni l’ordre ni l’orthographe des en-têtes de la ligne 1 : ils sont reconnus à l’identique. Les colonnes obligatoires doivent toutes figurer.'],
      ['3. Téléversez le fichier : l’analyse complète s’exécute avant toute écriture, ligne par ligne. Un refus nomme la ligne, la colonne, la valeur, le motif et le geste de correction.'],
      ['4. Si une seule ligne est refusée, le fichier entier est refusé et rien n’est écrit. Corrigez et téléversez de nouveau.'],
      ['5. Un lot confirmé s’annule (les fiches sont archivées, jamais supprimées) tant qu’aucun acte ne s’appuie dessus.'],
      [{ refuser: '6. Doublon : une ligne dont la fiche existe déjà REFUSE le fichier entier ; un import ne modifie jamais une fiche tenue.',
         ignorer: '6. Doublon : une ligne dont la fiche existe déjà est IGNORÉE (ni écrite, ni modifiée) ; leur nombre et leur liste figurent au rapport du lot.',
         versionner: '6. Doublon : une ligne dont le prix diffère crée une NOUVELLE VERSION datée (jamais d’écrasement) ; une ligne identique est comptée « inchangée ».' }[modeDoublon(j)]],
      [''],
      ['Colonne', 'Obligatoire', 'Type', 'Valeurs permises', 'Exemple', 'Explication'],
    ].concat(cols.map(function (c) {
      return [c.label, c.obligatoire ? 'oui' : 'non', typeLisible(c), valeursPermises(c, ctx), c.exemple === undefined ? '' : c.exemple, c.aide || ''];
    }));
    var listes = [], listesCols = [], validations = [];
    cols.forEach(function (c) {
      if (c.type !== 'liste') return;
      var vals = valeursListe(c, ctx);
      listesCols.push({ titre: c.label, valeurs: vals.map(function (x) { return x.label; }) });
    });
    var hauteur = listesCols.reduce(function (m, l) { return Math.max(m, l.valeurs.length); }, 0);
    listes.push(listesCols.map(function (l) { return l.titre; }));
    for (var i = 0; i < hauteur; i++) listes.push(listesCols.map(function (l) { return l.valeurs[i] === undefined ? '' : l.valeurs[i]; }));
    var k = 0;
    cols.forEach(function (c, ci) {
      if (c.type !== 'liste') return;
      var lettre = String.fromCharCode(65 + k);
      validations.push({ colonne: ci, formule: 'Listes!$' + lettre + '$2:$' + lettre + '$' + Math.max(2, listesCols[k].valeurs.length + 1) });
      k++;
    });
    var texteCols = [];
    cols.forEach(function (c, ci) { if (c.type === 'texte') texteCols.push(ci); });
    return X.ecrire({ feuilles: [
      { nom: NOMS_FEUILLES.donnees, lignes: donnees, largeurs: cols.map(function (c) { return Math.max(14, c.label.length + 4); }), listes: validations, texteColonnes: texteCols },
      { nom: NOMS_FEUILLES.instructions, lignes: instructions, largeurs: [28, 12, 28, 46, 22, 70], entete: false },
      { nom: NOMS_FEUILLES.listes, lignes: listesCols.length ? listes : [['Aucune liste pour ce jeu']], largeurs: listesCols.map(function () { return 30; }) },
    ] });
  }

  function modeleCsv(jeuId) {
    var j = jeu(jeuId);
    function ligne(a) { return a.map(function (x) { return '"' + String(x).replace(/"/g, '""') + '"'; }).join(';'); }
    return '\uFEFF' + [ligne(colonnesDe(j).map(function (c) { return c.label; })), ligne(ligneExemple(j))].join('\r\n') + '\r\n';
  }

  function rapport(lotOuAnalyse, j) {
    /* Pour un jeu RESTREINT : ni valeur de cellule, ni motif qui la cite (une lecture d'un lot déjà masqué reste masquée : `masquer` est idempotent). */
    var ps = (lotOuAnalyse.erreurs || problemes(lotOuAnalyse)).map(function (p) { return j ? masquer(j, p) : p; });
    var sans = !!(j && restreint(j));
    var LIB = { refus: 'refus', avertissement: 'avertissement', ignore: 'ignorée', info: 'information' };
    var entete = sans ? ['Ligne', 'Colonne', 'Niveau', 'Code', 'Motif', 'Geste de correction'] : ['Ligne', 'Colonne', 'Valeur', 'Niveau', 'Code', 'Motif', 'Geste de correction'];
    var lignes = [entete].concat(ps.map(function (p) {
      var base = [p.n || '', p.colonne || ''];
      if (!sans) base.push(p.valeur === undefined ? '' : String(p.valeur));
      return base.concat([LIB[p.niveau] || p.niveau, p.code, p.motif, p.geste]);
    }));
    var ign = lotOuAnalyse.ignoresTotal != null ? lotOuAnalyse.ignoresTotal : (lotOuAnalyse.compte ? lotOuAnalyse.compte.ignores : 0);
    var resume = [['Rapport d’importation'], ['Jeu', j ? j.libelle : lotOuAnalyse.jeuLibelle || ''], ['Fichier', lotOuAnalyse.fichier || ''],
      ['Lot', lotOuAnalyse.reference || 'non consigné'], ['Lignes lues', lotOuAnalyse.nbLignes], ['Problèmes', ps.length],
      ['Lignes ignorées (fiche déjà tenue)', ign || 0]];
    if (sans) resume.push(['Valeurs de cellule', 'non recopiées (jeu restreint, RG-13)']);
    return X.ecrire({ feuilles: [
      { nom: 'Erreurs', lignes: lignes, largeurs: sans ? [8, 26, 14, 24, 70, 70] : [8, 26, 24, 14, 24, 70, 70] },
      { nom: 'Résumé', lignes: resume, entete: false, largeurs: [34, 50] },
    ] });
  }

  function telecharger(nom, octets, mime) {
    global.SIGH.importer.dernierTelechargement = { nom: nom, octets: octets };
    var blob = new Blob([octets], { type: mime });
    var url = URL.createObjectURL(blob);
    var a = el('a', { href: url, download: nom });
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }
  var MIME_XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /* ==========================================================================
   * ÉCRANS
   * ======================================================================== */
  var TONS_ETAT = { applique: ['Appliqué', 'success'], refuse: ['Refusé, rien écrit', 'danger'], annule: ['Annulé', 'neutral'] };
  var TONS_LIGNE = { valide: ['Valide', 'success'], avertissement: ['Avertissement', 'warning'], refus: ['Refus', 'danger'],
    ignore: ['Ignorée', 'neutral'], inchange: ['Inchangée', 'neutral'], non: ['Non (non appliquée)', 'neutral'] };
  /* Les anciennes fiches de lot (RG-14 : elles restent lisibles) portent l'identifiant des deux jeux qui ont changé de nom avec le référentiel de prix unique (lot IMP-A). */
  var ANCIENS_JEUX = { actes: 'tarifs', analyses: 'analyses-modele' };
  function jeuDeLot(l) { return jeu(l.jeu) || jeu(ANCIENS_JEUX[l.jeu]); }

  /** Les jeux que ce profil VOIT : calculé du droit de la matrice, jamais d'une liste de rôles. */
  function jeuxVisibles() { return JEUX.filter(function (j) { return droitDe(j).voir; }); }

  function peutOuvrirPage(j) {
    var e = N.get(j.ecran);
    return !!e && N.can(roleCourant(), { id: e.id, roles: e.roles, module: e.module });
  }
  /** Un lot se lit de son AUTEUR et des profils qui SUPERVISENT (droit d'annuler sur chaque jeu : liste tirée du droit, pas d'un nom de rôle), pour un jeu que le profil voit. */
  function lotVisible(l) {
    var j = jeuDeLot(l);
    if (!j || !droitDe(j).voir) return false;
    return N.superviseImport(roleCourant()) || l.par === S.currentUser();
  }
  function lotsDuProfil(j) { return colLots().all().filter(function (l) { return (!j || jeuDeLot(l) === j) && lotVisible(l); }); }
  function peutAnnuler(l) {
    var j = jeuDeLot(l);
    return !!j && droitDe(j).annuler && (l.par === S.currentUser() || N.superviseImport(roleCourant()));
  }

  function tableLots(lots, rafraichir) {
    return U.dataTable({
      rows: lots, pageSize: 10, defaultSort: 'reference', defaultDir: 'desc', exportName: 'lots-importation',
      columns: [
        { key: 'reference', label: 'Lot', nowrap: true, render: function (l) { return el('span.font-mono.text-xs.font-semibold.text-navy-800', { text: l.reference }); } },
        { key: 'jeuLibelle', label: 'Jeu d’import' },
        { key: 'fichier', label: 'Fichier' },
        { key: 'date', label: 'Date', render: function (l) { return C.dateFR(l.date); }, text: function (l) { return C.dateFR(l.date); } },
        { key: 'nbLignes', label: 'Lignes', align: 'right' },
        { key: 'nbAvertissements', label: 'Avert.', align: 'right' },
        { key: 'par', label: 'Validé par', render: function (l) { return l.validePar || l.par || ''; }, text: function (l) { return l.validePar || l.par || ''; } },
        { key: 'etat', label: 'État', text: function (l) { return (TONS_ETAT[l.etat] || [l.etat])[0]; },
          render: function (l) { var t = TONS_ETAT[l.etat] || [l.etat, 'neutral']; return U.badge(t[0], t[1]); } },
      ],
      filters: [{ name: 'etat', label: 'État', options: [{ value: 'applique', label: 'Appliqué' }, { value: 'refuse', label: 'Refusé' }, { value: 'annule', label: 'Annulé' }] }],
      rowActions: function (l) {
        var out = [];
        if (l.erreurs && l.erreurs.length) {
          out.push(K.iconBtn('file-down', 'Rapport d’erreurs (.xlsx)', function () { telecharger('rapport-' + l.reference + '.xlsx', rapport(l, jeuDeLot(l)), MIME_XLSX); }));
        }
        /* L'annulation est une commande de CE JEU : son droit est celui du jeu et de l'auteur du lot, jamais celui de l'écran. Le moteur refuse aussi (annulerLot). */
        if (l.etat === 'applique' && peutAnnuler(l)) {
          out.push(K.iconBtn('undo-2', 'Annuler le lot', function () {
            U.confirm({
              title: 'Annuler le lot ' + l.reference + ' ?',
              message: 'Les ' + l.ecrits.length + ' fiches écrites par ce lot seront <strong>archivées</strong> (RG-14), jamais supprimées. '
                + 'L’annulation est refusée si un acte s’appuie déjà sur elles.',
              confirmLabel: 'Annuler le lot',
            }).then(function (ok) {
              if (!ok) return;
              var r = annulerLot(l.id, 'annulation demandée par ' + S.currentUser());
              if (r.ok) U.toast('Lot annulé.', { type: 'success', detail: r.archives + ' fiche(s) archivée(s).' });
              else U.toast('Annulation refusée.', { type: 'error', detail: r.motif + '. ' + r.geste });
              rafraichir();
            });
          }, 'danger'));
        }
        return out;
      },
    });
  }

  /* Un jeu en proposition se valide par le moteur commun (famille `jeux_import`, cible = l'écran du jeu) : l'état se LIT, il ne se déduit pas de la constante. */
  function jeuValide(j) {
    if (j.statut !== 'proposition') return false;
    var e = global.SIGH.validations && global.SIGH.validations.etatValidation('jeux_import', j.ecran);
    return !!(e && !e.enAttente);
  }
  function badgeStatut(j) {
    if (j.statut === 'supporte') return U.badge('Supporté', 'success');
    return jeuValide(j) ? K.badgeValidation('jeux_import', j.ecran) : U.badge('Proposition à valider', 'warning');
  }

  /* ==========================================================================
   * LA FENÊTRE EN TROIS TEMPS : UN SEUL CONTENU, DEUX PORTES
   * --------------------------------------------------------------------------
   * 1. le MODÈLE (engendré de la déclaration du jeu) ; 2. la VÉRIFICATION (analyse complète, rien d'écrit) ; 3. l'IMPORT (confirmé, atomique, annulable).
   * Le bouton « Importer les données » des écrans métier (`K.importer`) l'ouvre en modale ; la page `imp-<jeu>` la porte en pleine page avec l'historique. Une seule construction :
   * deux copies divergeraient au premier champ ajouté.
   * ======================================================================== */
  function contenuJeu(j, o) {
    o = o || {};
    var host = el('div.space-y-4'), zone = el('div.space-y-4'), histo = el('div'), etat = { analyse: null };
    var d = droitDe(j);
    /* La REPRISE valorisée du Grand Stock a ses propres droits (ceux de M6) : elle reste atteignable de qui l'a, même sans détenir le JEU. */
    function ajouterReprise() {
      if (o.modale || j.id !== 'grand-stock' || typeof global.SIGH.rendreRepriseGrandStock !== 'function') return;
      host.appendChild(el('h2.text-base.font-semibold.text-navy-900', { text: 'Stock repris : traçabilité et valorisation' }));
      host.appendChild(K.note('Le stock initial n’a pas été saisi manuellement : il provient de l’import de l’inventaire « Grand Stock ». '
        + 'Chaque article conserve sa source, son lot d’import et sa quantité d’origine, afin de distinguer les données reprises des '
        + 'mouvements opérationnels ultérieurs. Les références que le document ne tarife pas se valorisent ici, à part, datées et signées.',
        { tone: 'info', icon: 'history' }));
      var reprise = el('div.space-y-4');
      host.appendChild(reprise);
      global.SIGH.rendreRepriseGrandStock(reprise);
    }
    if (!d.voir) {
      host.appendChild(K.note('Votre profil ne détient pas ce jeu d’import : ni son modèle, ni son historique ne vous sont ouverts.', { tone: 'warning', icon: 'lock' }));
      ajouterReprise();
      return host;
    }

    function dessinerHistorique() {
      C.clear(histo);
      histo.appendChild(U.card('Historique des lots de ce jeu', tableLots(lotsDuProfil(j), dessinerHistorique)));
      U.icons(histo);
    }

    if (!o.modale) {
      host.appendChild(U.kpiGrid((function () {
        var lots = lotsDuProfil(j);
        var appl = lots.filter(function (l) { return l.etat === 'applique'; });
        return [
          { label: 'Lots appliqués', value: String(appl.length), icon: 'package-check', tone: 'navy' },
          { label: 'Fiches importées', value: C.num(appl.reduce(function (t, l) { return t + l.ecrits.length; }, 0)), icon: 'database', tone: 'info' },
          { label: 'Fichiers refusés', value: String(lots.filter(function (l) { return l.etat === 'refuse'; }).length), icon: 'file-x', tone: 'warning' },
          { label: 'Statut du jeu', value: j.statut === 'supporte' ? 'Supporté' : (jeuValide(j) ? 'Validé' : 'À valider'), icon: 'badge-check', tone: j.statut === 'supporte' || jeuValide(j) ? 'success' : 'warning' },
        ];
      })()));
    }

    if (j.statut === 'proposition' && !jeuValide(j)) {
      host.appendChild(K.note('<strong>Proposition à valider.</strong> ' + j.limite, { tone: 'warning', icon: 'help-circle' }));
      if (!o.modale) {
        var bv = K.boutonValider('jeux_import', j.ecran, { apres: function () { global.SIGH.app.go(j.ecran); } });
        if (bv) host.appendChild(el('div.flex.justify-end', null, bv));
      }
    } else if (j.statut === 'proposition') {
      host.appendChild(K.note('<strong>Jeu validé.</strong> ' + String(j.limite || '').replace(/^PROPOSITION À VALIDER\s*:\s*/, ''), { tone: 'info', icon: 'check-circle-2' }));
      if (!o.modale) host.appendChild(el('div.flex.justify-end', null, K.badgeValidation('jeux_import', j.ecran)));
    } else if (j.limite) host.appendChild(K.note(j.limite, { tone: 'info', icon: 'info' }));

    if (restreint(j)) {
      host.appendChild(K.note('<strong>Jeu restreint (RG-13).</strong> Le fichier est lu et contrôlé ici, mais <strong>aucune valeur de cellule</strong> n’est recopiée dans l’historique ni dans le rapport : '
        + 'chaque constat porte la ligne, la colonne, le code et le geste de correction. Les lots ne sont visibles que de leur auteur et des profils qui supervisent les importations.',
        { tone: 'info', icon: 'shield-check' }));
    }
    var mode = modeDoublon(j);
    if (mode === 'ignorer') {
      host.appendChild(K.note('<strong>Fiches déjà tenues : ignorées.</strong> Une ligne dont la fiche existe déjà n’écrit rien et ne modifie rien ; elle est comptée et nommée au rapport. '
        + 'Un fichier peut donc être rejoué sans refus (mode arrêté par la Direction pour ce jeu seulement).', { tone: 'info', icon: 'copy-minus' }));
    }

    if (mode === 'versionner') {
      host.appendChild(K.note('<strong>Une ligne qui change un prix devient une version datée, jamais un écrasement.</strong> La vérification montre, pour chaque ligne, l’ancien prix, le nouveau et la variation. '
        + 'Les erreurs refusent le fichier entier ; les décisions se prennent ligne à ligne : <em>Oui</em> (validé d’emblée si votre profil décide, sinon proposition), <em>Non</em> (non appliquée, motif obligatoire), vide (proposition). '
        + 'Le prix en vigueur ne change jamais à l’import par lui-même.', { tone: 'info', icon: 'tags' }));
    }

    var cols = colonnesDe(j);
    /* 1. Le modèle */
    var colTable = K.miniTable(['Colonne', 'Obligatoire', 'Type', 'Valeurs permises', 'Exemple'], cols.map(function (c) {
      return [c.label, c.obligatoire ? U.badge('oui', 'danger') : 'non', typeLisible(c), valeursPermises(c, j.contexte ? j.contexte() : {}), c.exemple === undefined ? '' : String(c.exemple)];
    }));
    host.appendChild(U.card('1. Télécharger le modèle', el('div.space-y-3', null, [
      el('p.text-sm.text-slate-600', { text: 'Le modèle est un classeur .xlsx de trois feuilles : « Données » (en-têtes exacts et une ligne d’exemple), « Instructions » (colonnes, formats, valeurs permises) et « Listes » (les référentiels de contrôle).' }),
      el('div.flex.flex-wrap.gap-2', null, [
        K.btn('Télécharger le modèle (.xlsx)', { variant: 'primary', icon: 'file-down', onclick: function () { telecharger(j.fichierModele + '.xlsx', modele(j.id), MIME_XLSX); } }),
        K.btn('Modèle CSV', { icon: 'file-text', onclick: function () { telecharger(j.fichierModele + '.csv', new TextEncoder().encode(modeleCsv(j.id)), 'text/csv;charset=utf-8'); } }),
      ]),
      colTable,
    ])));

    /* 2. Le téléversement : la commande n'existe que pour qui détient le droit D'IMPORTER CE JEU (pas celui d'éditer l'écran). */
    var entree = el('input', { type: 'file', accept: '.xlsx,.csv', class: 'hidden', 'data-import-fichier': j.id, 'aria-label': 'Fichier à importer' });
    entree.addEventListener('change', function () {
      var f = entree.files && entree.files[0];
      if (!f) return;
      var lecteur = new FileReader();
      lecteur.onload = function () { analyser(new Uint8Array(lecteur.result), f.name); entree.value = ''; };
      lecteur.readAsArrayBuffer(f);
    });
    var barreTele = el('div.flex.flex-wrap.items-center.gap-2');
    if (d.importer) {
      barreTele.appendChild(K.btn('Téléverser un fichier (.xlsx ou .csv)', { variant: 'primary', icon: 'upload', onclick: function () { entree.click(); } }));
      barreTele.appendChild(entree);
    } else {
      barreTele.appendChild(el('p.text-sm.text-slate-500', { text: 'Votre profil voit ce jeu sans pouvoir y importer : le téléversement n’est pas proposé.' }));
    }
    host.appendChild(U.card('2. Téléverser et analyser', el('div.space-y-3', null, [
      el('p.text-sm.text-slate-600', { text: 'L’analyse est complète et ne modifie rien : chaque ligne est contrôlée, un refus est nommé, et c’est vous qui confirmez l’écriture. Taille maximale de ce jeu : ' + C.num(borneDe(j)) + ' lignes.' }),
      barreTele,
    ])));
    host.appendChild(zone);
    if (!o.modale) {
      host.appendChild(histo);
      dessinerHistorique();
    }

    /* LE GRAND STOCK A DEUX FACES SUR LE MÊME ÉCRAN (E2158, corrigé le 06/11/2026) : l'IMPORT l'écrit (ci-dessus), la REPRISE le suit et le valorise (ci-dessous). */
    ajouterReprise();

    function analyser(octets, nom) {
      var a = analyserOctets(j.id, octets, nom);
      etat.analyse = a;
      C.clear(zone);
      var lot = null;
      if (!a.accepte) lot = consigner(j, a);
      zone.appendChild(apercu(a, lot));
      U.icons(zone);
      if (!o.modale) dessinerHistorique();
    }

    function apercu(a, lot) {
      var ps = problemes(a);
      var cartes = el('div.space-y-3');
      var resume = el('div.flex.flex-wrap.gap-2', null, [
        U.badge(a.nbLignes + ' ligne(s) lue(s)', 'navy'), U.badge(a.compte.valides + ' valide(s)', 'success'),
        U.badge(a.compte.avertissements + ' avertissement(s)', 'warning'), U.badge(a.compte.refus + ' refus', a.compte.refus ? 'danger' : 'neutral'),
      ]);
      if (a.compte.ignores) resume.appendChild(U.badge(a.compte.ignores + ' ignorée(s) (fiche déjà tenue)', 'neutral'));
      if (a.compte.inchanges) resume.appendChild(U.badge(a.compte.inchanges + ' inchangée(s)', 'neutral'));
      if (a.compte.non) resume.appendChild(U.badge(a.compte.non + ' « Non » (non appliquée(s))', 'neutral'));
      cartes.appendChild(resume);
      if (a.accepte && a.aEcrire > 0) {
        cartes.appendChild(K.note('<strong>Analyse conforme.</strong> ' + a.aEcrire + ' ligne(s) peuvent être écrites' + (a.compte.avertissements ? ', dont ' + a.compte.avertissements + ' avec avertissement' : '') + '. Rien n’est encore écrit.', { tone: 'success', icon: 'check-circle' }));
      } else if (a.accepte) {
        cartes.appendChild(K.note('<strong>Rien à écrire.</strong> Toutes les lignes sont ignorées, inchangées ou refusées par leur auteur (Non) : aucune erreur, aucun lot consigné.', { tone: 'info', icon: 'info' }));
      } else if (a.droitRefuse) {
        cartes.appendChild(K.note('<strong>Importation refusée.</strong> ' + a.globaux[0].motif + '. ' + a.globaux[0].geste, { tone: 'danger', icon: 'octagon-alert' }));
      } else {
        cartes.appendChild(K.note('<strong>Fichier refusé.</strong> Rien n’a été écrit. Le fichier est consigné au lot <span class="font-mono">' + (lot ? lot.reference : '') + '</span> ; corrigez les points ci-dessous puis téléversez de nouveau.', { tone: 'danger', icon: 'octagon-alert' }));
      }
      if (a.globaux.length) {
        cartes.appendChild(U.card('Points concernant le fichier entier', K.miniTable(['Niveau', 'Colonne', 'Motif', 'Geste de correction'], a.globaux.map(function (p) {
          return [U.badge(p.niveau === 'refus' ? 'Refus' : 'Avertissement', p.niveau === 'refus' ? 'danger' : 'warning'), p.colonne || '', p.motif, p.geste];
        }))));
      }
      if (a.lignes.length) {
        var avecExtra = a.lignes.some(function (l) { return l.extra && l.extra.decision !== undefined; }), avecDetail = a.lignes.some(function (l) { return l.extra && l.extra.detail; });
        var colonnes = [
          { key: 'n', label: 'Ligne', align: 'right' },
          { key: 'etat', label: 'État', text: function (r) { return TONS_LIGNE[r.etat][0]; }, render: function (r) { return U.badge(TONS_LIGNE[r.etat][0], TONS_LIGNE[r.etat][1]); } },
          { key: 'resume', label: 'Contenu' },
        ];
        if (avecExtra) {
          /* Pour un jeu de PRIX : l'agent voit ce qu'il importe AVANT de l'importer, ligne qui change par ligne qui change (ancien prix, nouveau, variation, décision). */
          colonnes.push({ key: 'ancien', label: 'Ancien prix', align: 'right', nowrap: true });
          colonnes.push({ key: 'nouveau', label: 'Nouveau prix', align: 'right', nowrap: true });
          colonnes.push({ key: 'variation', label: 'Variation', align: 'right', nowrap: true });
          colonnes.push({ key: 'decision', label: 'Décision' });
        }
        if (avecDetail) colonnes.push({ key: 'detail', label: 'Détail de la ligne' });
        colonnes.push({ key: 'problemes', label: 'Constats', sortable: false,
          text: function (r) { return r.problemes.map(function (p) { return p.colonne + ' : ' + p.motif; }).join(' | '); },
          render: function (r) {
            return el('div.space-y-1', null, r.problemes.map(function (p) {
              return el('p.text-xs', { class: p.niveau === 'refus' ? 'text-danger-700' : (p.niveau === 'ignore' || p.niveau === 'info' ? 'text-slate-500' : 'text-warning-700') }, [
                el('strong', { text: p.colonne + ' ' }), (p.valeur !== '' && p.valeur !== undefined ? '« ' + p.valeur + ' » : ' : ': ') + p.motif + '. ', el('em', { text: p.geste }),
              ]);
            }));
          } });
        cartes.appendChild(U.card('Aperçu ligne par ligne', U.dataTable({
          rows: a.lignes.map(function (l) {
            var x = l.extra || {};
            return { n: l.n, etat: l.etat, resume: l.brut.slice(0, 3).filter(Boolean).join(' · '), problemes: l.problemes,
              detail: x.detail || '', ancien: x.ancien == null ? '' : x.ancien, nouveau: x.nouveau == null ? '' : x.nouveau, variation: x.variation == null ? '' : x.variation, decision: x.decision || '' };
          }),
          pageSize: 10, defaultSort: 'n', exportName: 'apercu-importation',
          filters: [{ name: 'etat', label: 'État', options: Object.keys(TONS_LIGNE).map(function (k) { return { value: k, label: TONS_LIGNE[k][0] }; }) }],
          columns: colonnes,
        })));
      }
      var actions = el('div.flex.flex-wrap.gap-2');
      if (a.accepte && a.aEcrire > 0 && d.importer) {
        actions.appendChild(K.btn('Confirmer l’importation (' + a.aEcrire + ' ligne' + (a.aEcrire > 1 ? 's' : '') + ')', {
          variant: 'primary', icon: 'package-check',
          onclick: function () {
            U.confirm({
              title: 'Écrire ce lot ?',
              message: a.aEcrire + ' ligne(s) du fichier « ' + a.fichier + ' » vont s’écrire en un seul geste, au nom de ' + S.currentUser() + ' (validé par). Le lot pourra être annulé tant qu’aucun acte ne s’appuie dessus.',
              confirmLabel: 'Écrire le lot',
            }).then(function (ok) {
              if (!ok) return;
              var r = appliquer(j.id, a);
              C.clear(zone);
              if (r.ok) {
                U.toast('Lot ' + r.lot.reference + ' appliqué.', { type: 'success', detail: r.ecrits + ' fiche(s) écrite(s).' });
                zone.appendChild(K.note('<strong>Lot ' + r.lot.reference + ' appliqué.</strong> ' + r.ecrits + ' fiche(s) écrite(s), journalisées (RG-12).', { tone: 'success', icon: 'check-circle' }));
                if (o.apres) o.apres(r);
              } else {
                U.toast('Importation refusée.', { type: 'error', detail: r.motif });
                zone.appendChild(K.note('<strong>Importation refusée.</strong> ' + r.motif + '. ' + r.geste, { tone: 'danger', icon: 'octagon-alert' }));
              }
              U.icons(zone);
              if (!o.modale) dessinerHistorique();
            });
          },
        }));
      }
      if (ps.length && !a.droitRefuse) actions.appendChild(K.btn('Rapport d’erreurs (.xlsx)', { icon: 'file-down', onclick: function () { telecharger('rapport-' + (lot ? lot.reference : 'analyse') + '.xlsx', rapport(lot || a, j), MIME_XLSX); } }));
      actions.appendChild(K.btn('Abandonner', { onclick: function () { C.clear(zone); } }));
      cartes.appendChild(actions);
      return U.card('Résultat de l’analyse du fichier « ' + a.fichier + ' »', cartes);
    }
    return host;
  }

  function ecranJeu(j) {
    return function (root) {
      root.appendChild(contenuJeu(j, {}));
      return null;
    };
  }

  /** La fenêtre du bouton « Importer les données » (fabrique unique `K.importer`) : un jeu, ou le choix parmi ceux que le profil peut importer. */
  function ouvrirFenetre(ids, opts) {
    opts = opts || {};
    var jeux = [].concat(ids || []).map(jeu).filter(Boolean).filter(function (j) { return droitDe(j).importer; });
    if (!jeux.length) { U.toast('Aucun jeu d’import n’est ouvert à votre profil.', { type: 'error' }); return null; }
    var ecrit = { oui: false }, corps = el('div.space-y-4'), m = null;
    function ouvrirJeu(j) {
      C.clear(corps);
      if (jeux.length > 1) corps.appendChild(K.btn('Changer de jeu', { icon: 'arrow-left', size: 'sm', onclick: choisir }));
      corps.appendChild(contenuJeu(j, { modale: true, apres: function () { ecrit.oui = true; } }));
      U.icons(corps);
    }
    function choisir() {
      C.clear(corps);
      corps.appendChild(el('p.text-sm.text-slate-600', { text: 'Cet écran reçoit plusieurs jeux d’import : choisissez celui qui correspond à votre fichier.' }));
      var grille = el('div.grid.gap-3', { class: 'sm:grid-cols-2' });
      jeux.forEach(function (j) {
        grille.appendChild(el('div.card', null, el('div.card-body.space-y-2', null, [
          el('h3.font-semibold.text-navy-900', { text: j.libelle }), el('p.text-sm.text-slate-600', { text: j.description }),
          K.btn('Choisir ce jeu', { variant: 'primary', icon: 'arrow-right', onclick: function () { ouvrirJeu(j); } }),
        ])));
      });
      corps.appendChild(grille);
      U.icons(corps);
    }
    m = U.modal({
      title: 'Importer les données', subtitle: jeux.length === 1 ? jeux[0].libelle : 'Choix du jeu', size: 'xl', body: corps,
      footer: [K.btn('Fermer', { onclick: function () { m.close(); } })],
      onClose: function () { if (ecrit.oui && opts.apres) opts.apres(); },
    });
    if (jeux.length === 1) ouvrirJeu(jeux[0]); else choisir();
    return m;
  }

  /* --- Accueil du module -------------------------------------------------------------------------------------------- */
  function ecranAccueil(root) {
    var host = el('div.space-y-4');
    root.appendChild(host);
    var visibles = jeuxVisibles();
    var tous = lotsDuProfil(null);
    var superviseur = N.superviseImport(roleCourant());
    host.appendChild(K.note(superviseur
      ? '<strong>Supervision.</strong> Votre profil détient le droit d’annuler sur chaque jeu : vous lisez les lots de tous les agents. Chacun des autres ne lit que les siens.'
      : 'Vous lisez les <strong>lots que vous avez vous-même écrits</strong>, pour les jeux que votre profil détient. Les profils qui supervisent les importations lisent tous les lots.', { tone: 'info', icon: 'eye' }));
    host.appendChild(U.kpiGrid([
      { label: 'Jeux d’import', value: String(visibles.length), icon: 'files', tone: 'navy' },
      { label: 'Lots appliqués', value: String(tous.filter(function (l) { return l.etat === 'applique'; }).length), icon: 'package-check', tone: 'success' },
      { label: 'Fichiers refusés', value: String(tous.filter(function (l) { return l.etat === 'refuse'; }).length), icon: 'file-x', tone: 'warning' },
      { label: 'Lots annulés', value: String(tous.filter(function (l) { return l.etat === 'annule'; }).length), icon: 'undo-2', tone: 'neutral' },
    ]));
    host.appendChild(U.tabs([
      { id: 'jeux', label: 'Jeux d’import', render: function () {
        var grille = el('div.grid.gap-3', { class: 'sm:grid-cols-2 lg:grid-cols-3' });
        visibles.forEach(function (j) {
          var dernier = lotsDuProfil(j)[0];
          grille.appendChild(el('div.card', null, el('div.card-body.space-y-2', null, [
            el('div.flex.items-start.justify-between.gap-2', null, [el('h3.font-semibold.text-navy-900', { text: j.libelle }), badgeStatut(j)]),
            el('p.text-sm.text-slate-600', { text: j.description }),
            el('p.text-xs.text-slate-500', { text: 'Source : ' + j.source }),
            el('p.text-xs.text-slate-500', { text: 'Écrit dans : ' + j.cibles.join(', ') + '. ' + (dernier ? 'Dernier lot : ' + dernier.reference + ' (' + (TONS_ETAT[dernier.etat] || [dernier.etat])[0] + ').' : 'Aucun lot à ce jour.') }),
            peutOuvrirPage(j) ? K.lien(j.ecran, 'Ouvrir', { variant: 'primary', icon: 'arrow-right' }) : el('p.text-xs.text-slate-400', { text: 'La page de ce jeu n’est pas ouverte à votre profil.' }),
          ])));
        });
        return grille;
      } },
      { id: 'historique', label: 'Historique des lots', badge: tous.length, render: function (panel) {
        function dessiner() {
          C.clear(panel);
          panel.appendChild(tableLots(lotsDuProfil(null), dessiner));
          U.icons(panel);
        }
        dessiner();
        return null;
      } },
      { id: 'tailles', label: 'Tailles maximales', render: function (panel) {
        function dessiner() {
          C.clear(panel);
          panel.appendChild(K.note('La taille maximale d’un fichier est un <strong>réglage en base</strong>, par jeu, avec un défaut. Un fichier plus long est refusé en le nommant, avant tout travail. '
            + (superviseur ? 'Votre profil la règle.' : 'Elle se règle par un profil qui supervise les importations.'), { tone: 'info', icon: 'gauge' }));
          var lignes = visibles.map(function (j) {
            return { id: j.id, jeu: j.libelle, borne: borneDe(j), defaut: BORNES_DEFAUT[j.id] || BORNE_DEFAUT_GENERALE };
          });
          panel.appendChild(U.dataTable({
            rows: lignes, pageSize: 12, defaultSort: 'jeu', exportName: 'tailles-importation',
            columns: [
              { key: 'jeu', label: 'Jeu d’import' },
              { key: 'borne', label: 'Maximum (lignes)', align: 'right', render: function (r) { return C.num(r.borne); }, text: function (r) { return String(r.borne); } },
              { key: 'defaut', label: 'Défaut (lignes)', align: 'right', render: function (r) { return C.num(r.defaut); }, text: function (r) { return String(r.defaut); } },
            ],
            rowActions: function (r) {
              if (!superviseur) return [];
              return [K.iconBtn('pencil', 'Régler la taille maximale', function () {
                var f = U.form([
                  { name: 'lignes', label: 'Taille maximale (lignes)', type: 'number', required: true, col: 'full', hint: 'Entier de 1 à ' + BORNE_MAXIMALE + '.' },
                  { name: 'motif', label: 'Motif du réglage', type: 'text', required: true, col: 'full' },
                ], { lignes: r.borne });
                var m = U.modal({ title: 'Taille maximale : ' + r.jeu, size: 'md', body: f, footer: [
                  K.btn('Annuler', { onclick: function () { m.close(); } }),
                  K.btn('Enregistrer', { variant: 'primary', icon: 'save', onclick: function () {
                    var v = f.collect(); if (!v) return;
                    var res = definirBorne(r.id, v.lignes, v.motif);
                    if (res.ok) { m.close(); U.toast('Taille maximale réglée.', { type: 'success', detail: C.num(res.lignes) + ' lignes (avant : ' + C.num(res.avant) + ').' }); dessiner(); }
                    else U.toast('Réglage refusé.', { type: 'error', detail: res.motif + '. ' + res.geste });
                  } }),
                ] });
              })];
            },
          }));
          U.icons(panel);
        }
        dessiner();
        return null;
      } },
    ]));
    U.icons(host);
    return null;
  }

  global.SIGH.screen('imp-accueil', {
    title: 'Importation de données',
    description: 'Les jeux d’import de la clinique en démarrage : modèle .xlsx à télécharger, fichier à téléverser, analyse complète avant écriture, historique et annulation des lots.',
    regle: 'Un import <strong>n’invente rien</strong> : il écrit ce que le fichier porte, après une analyse ligne par ligne. Un refus se nomme (ligne, colonne, valeur, motif, geste). Un fichier refusé est consigné et n’écrit rien. Un lot s’annule en archivant ses fiches (RG-14). '
      + 'Le droit d’importer est <strong>propre à chaque jeu</strong> (voir, importer, annuler) ; chacun lit ses lots, les profils qui supervisent lisent tous les lots.',
    render: ecranAccueil,
  });
  JEUX.forEach(function (j) {
    global.SIGH.screen(j.ecran, {
      title: j.libelle,
      description: j.description,
      regle: 'Source : ' + j.source + ' Le fichier est analysé en entier avant toute écriture ; chaque fiche écrite porte <strong>source</strong>, <strong>lot d’import</strong> et <strong>validé par</strong> (RG-12).',
      render: ecranJeu(j),
    });
  });

  global.SIGH.importer = {
    JEUX: JEUX, jeu: jeu, lireCellule: lireCellule, analyserLignes: analyserLignes, analyserOctets: analyserOctets, problemes: problemes,
    consigner: consigner, appliquer: appliquer, annulerLot: annulerLot, modele: modele, modeleCsv: modeleCsv, rapport: rapport,
    lots: colLots, dernierTelechargement: null,
    ouvrirFenetre: ouvrirFenetre, contenuJeu: contenuJeu, colonnesDe: colonnesDe, masquer: masquer, borneDe: borneDe, definirBorne: definirBorne,
    BORNES_DEFAUT: BORNES_DEFAUT, BORNE_DEFAUT_GENERALE: BORNE_DEFAUT_GENERALE, lotsVisibles: lotsDuProfil, jeuxVisibles: jeuxVisibles, mode: modeDoublon,
  };
})(window);
