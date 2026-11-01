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
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, D = global.SIGH.data, K = global.SIGH.kit,
      N = global.SIGH.nav, X = global.SIGH.xlsx;
  var el = C.el;

  var NOMS_FEUILLES = { donnees: 'Données', instructions: 'Instructions', listes: 'Listes' };

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
    roles: ['stock', 'da', 'admin', 'direction'],
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
    roles: ['da', 'admin'],
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
      col('salaireBase', 'Salaire de base', 'entier', { min: 0, exemple: 150000, aide: 'Francs CFA bruts mensuels. Réservé à la DAF et à l’administrateur.' }),
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
      if (v.salaireBase == null) pb.push({ colonne: 'Salaire de base', valeur: '', code: 'SALAIRE_ABSENT', niveau: 'avertissement', motif: 'salaire de base non renseigné', geste: 'Le bulletin de paie ne pourra pas se calculer avant sa saisie.' });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche) {
      lignes.forEach(function (l) {
        var v = l.v;
        ecrireFiche('personnel', {
          matricule: v.matricule, nom: v.nom, prenom: v.prenom, nomComplet: v.nom + ' ' + v.prenom, sexe: v.sexe, fonction: v.fonction,
          poste: v.poste, service: v.service, categorie: v.categorie || null, dateEmbauche: v.dateEmbauche || null,
          telephone: v.telephone || null, cnss: v.cnss || null, situation: v.situation || null, salaireBase: v.salaireBase,
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
    roles: ['reception', 'agentadmin', 'da', 'admin'],
    description: 'Reprise du répertoire papier : identité, coordonnées, couverture. Jamais de dossier médical.',
    source: 'Registre papier des dossiers (environ 18 000) : seule l’identité administrative se reprend (CDCT 4.3).',
    cibles: ['patients'],
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
      col('groupeSanguin', 'Groupe sanguin', 'liste', { liste: function () { return D.GROUPES_SANGUINS; }, exemple: 'O+' }),
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
          personneAPrevenir: v.personneAPrevenir || null, groupeSanguin: v.groupeSanguin || null,
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

  /* --- 4. ACTES ET TARIFS ----------------------------------------------------------------------------------------------- */
  JEUX.push({
    id: 'actes', ecran: 'imp-actes', libelle: 'Importation du catalogue des actes', module: 'IMP', statut: 'supporte',
    roles: ['da', 'admin', 'direction'],
    description: 'Actes et tarifs à deux prix (non assuré, assuré) avec les trois états de la colonne assurée : montant, NC (non couvert), tiret (valeur manquante).',
    source: 'Six grilles tarifaires imprimées et « Répartition des activités » (docs/) ; les prix du fichier font foi, aucun n’est complété par le logiciel.',
    cibles: ['actes'],
    fichierModele: 'modele-import-actes',
    colonnes: [
      oblig('code', 'Code acte', 'texte', { longueurMax: 20, exemple: 'MG01' }),
      oblig('libelle', 'Libellé', 'texte', { longueurMax: 160, exemple: 'Consultation généraliste' }),
      oblig('secteur', 'Secteur', 'liste', { liste: function (ctx) { return ctx.secteurs; }, exemple: 'Médecine générale' }),
      oblig('prixNonAssure', 'Prix non assuré', 'tarif', { exemple: 5000, aide: 'Montant entier en FCFA, ou un tiret si le prix manque. Un tiret n’est pas un zéro : l’acte ne se facture pas.' }),
      oblig('prixAssure', 'Prix assuré', 'tarif', { exemple: 3000, aide: 'Montant, NC (aucune compagnie ne couvre l’acte : l’assuré paie le prix non assuré) ou un tiret (valeur manquante).' }),
      col('codeTarif', 'Code tarif', 'texte', { longueurMax: 30, exemple: 'CONS-GEN' }),
    ],
    contexte: function () {
      var c = {}, sec = {};
      /* Les secteurs viennent du catalogue de référence (D.ACTES) ET des actes déjà tenus : une clinique qui démarre n'a pas encore d'acte. */
      D.ACTES.forEach(function (a) { if (a.secteur) sec[a.secteur] = true; });
      toutes('actes').forEach(function (a) { c[C.norm(a.code)] = a; if (a.statut !== 'archive' && a.secteur) sec[a.secteur] = true; });
      return { actes: c, secteurs: Object.keys(sec).sort() };
    },
    cle: function (v) { return [C.norm(v.code)]; },
    existe: function (v, ctx) { var a = ctx.actes[C.norm(v.code)]; return a ? 'l’acte « ' + a.code + ' » existe déjà (' + a.libelle + ')' : null; },
    gesteExiste: 'Retirez la ligne : un tarif en vigueur se modifie à l’écran Catalogue des actes, versionné, jamais écrasé par un import.',
    regles: function (v) {
      var pb = [];
      if (v.prixNonAssure.etat === 'nc') pb.push({ colonne: 'Prix non assuré', valeur: 'NC', code: 'NC_INTERDIT', niveau: 'refus', motif: 'NC n’a de sens que dans la colonne assurée', geste: 'Saisissez le prix de guichet, ou un tiret s’il manque.' });
      if (v.prixNonAssure.etat === 'manquant') pb.push({ colonne: 'Prix non assuré', valeur: '-', code: 'PRIX_MANQUANT', niveau: 'avertissement', motif: 'prix non assuré manquant : l’acte ne se facturera pas (un tiret n’est pas un zéro)', geste: 'Saisissez le prix au catalogue dès qu’il est arrêté.' });
      if (v.prixAssure.etat === 'manquant') pb.push({ colonne: 'Prix assuré', valeur: '-', code: 'PRIX_MANQUANT', niveau: 'avertissement', motif: 'prix assuré manquant : l’acte ne se facturera pas aux assurés', geste: 'Saisissez le prix assuré, ou NC si aucune compagnie ne couvre l’acte.' });
      return pb;
    },
    ecrire: function (lignes, ecrireFiche, lot) {
      lignes.forEach(function (l) {
        var v = l.v, na = v.prixNonAssure, as = v.prixAssure;
        var f = {
          code: v.code, libelle: v.libelle, secteur: v.secteur, codeTarif: v.codeTarif || null,
          prixNonAssure: na.etat === 'montant' ? na.montant : null,
          prixAssure: as.etat === 'montant' ? as.montant : null,
          nonCouvert: as.etat === 'nc', assurable: as.etat !== 'nc',
          prix: na.etat === 'montant' ? na.montant : null, tarifProvisoire: false,
        };
        if (na.etat === 'manquant' || as.etat === 'manquant') f.motifPrix = 'Valeur manquante à l’import ' + lot.reference + ' : l’acte ne se facture pas tant que le prix n’est pas saisi.';
        ecrireFiche('actes', f);
      });
    },
    dependances: function (lot) {
      var codes = {};
      lot.ecrits.forEach(function (e) { var a = S.collection('actes').get(e.id); if (a) codes[a.code] = true; });
      var u = S.collection('prescriptions').active().filter(function (x) { return codes[x.acteCode]; })[0];
      return u ? { code: 'ACTE_UTILISE', motif: 'l’acte « ' + u.acteCode + ' » est déjà prescrit', geste: 'Archivez l’acte au catalogue plutôt que d’annuler son lot.' } : null;
    },
  });

  /* --- 5. ANALYSES (proposition à valider) ------------------------------------------------------------------------------- */
  JEUX.push({
    id: 'analyses', ecran: 'imp-analyses', libelle: 'Importation du catalogue des analyses', module: 'IMP', statut: 'proposition',
    roles: ['laborantin', 'da', 'admin'],
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
    roles: ['stock', 'da', 'comptable', 'admin'],
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
    roles: ['da', 'comptable', 'admin'],
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
    roles: ['da', 'comptable', 'admin'],
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
    roles: ['comptable', 'da', 'admin'],
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
    roles: ['comptable', 'da', 'admin'],
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

  function jeu(id) { return JEUX.filter(function (j) { return j.id === id; })[0] || null; }

  /* ==========================================================================
   * ANALYSE : le fichier lu, contrôlé, jamais écrit.
   * ======================================================================== */
  function clefEntete(s) { return C.norm(String(s == null ? '' : s).replace(/\*/g, '')).replace(/\s+/g, ' ').trim(); }

  function ligneExemple(j) {
    return j.colonnes.map(function (c) { return c.exemple === undefined ? '' : c.exemple; });
  }

  function analyserLignes(j, lignes, fichier) {
    var res = { jeu: j.id, fichier: fichier || '', nbLignes: 0, lignes: [], globaux: [], accepte: false,
      compte: { valides: 0, avertissements: 0, refus: 0 }, lignesBrutes: lignes };
    function global_(code, colonne, motif, geste, niveau, valeur) {
      res.globaux.push({ n: 0, colonne: colonne || '', valeur: valeur === undefined ? '' : valeur, code: code, motif: motif, geste: geste, niveau: niveau || 'refus' });
    }
    if (!lignes || !lignes.length) {
      global_('FICHIER_VIDE', '', 'le fichier ne contient aucune ligne', 'Téléchargez le modèle, remplissez l’onglet Données et téléversez-le de nouveau.');
      return res;
    }
    var entete = lignes[0].map(clefEntete), idx = {}, manquantes = [];
    j.colonnes.forEach(function (c) {
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
    j.colonnes.forEach(function (c) { connus[clefEntete(c.label)] = true; });
    lignes[0].forEach(function (h, i) {
      if (!vide(h) && !connus[clefEntete(h)]) global_('COLONNE_IGNOREE', String(h), 'colonne « ' + h + ' » inconnue : elle est ignorée', 'Retirez-la du fichier si elle est inutile.', 'avertissement');
    });
    var ctx = j.contexte ? j.contexte() : {}, sc = { articles: {} };
    var exemple = ligneExemple(j).map(function (x) { return String(x).trim(); });
    var vus = {};
    for (var r = 1; r < lignes.length; r++) {
      var brute = lignes[r];
      if (brute.every(vide)) continue;
      var lecture = j.colonnes.map(function (c) { return String(nettoyer(brute[idx[c.cle]] == null ? '' : brute[idx[c.cle]])).trim(); });
      if (r === 1 && lecture.join('|') === exemple.join('|')) continue; /* la ligne d'exemple du modèle, restée telle quelle */
      var n = r + 1, ligne = { n: n, v: {}, brut: lecture, problemes: [], etat: 'valide' };
      var ok = true;
      j.colonnes.forEach(function (c) {
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
          ligne.problemes.push({ n: n, colonne: j.colonnes[0].label, valeur: lecture[0], code: 'DOUBLON_FICHIER', niveau: 'refus',
            motif: 'identique à la ligne ' + doublon + ' du même fichier', geste: 'Retirez l’une des deux lignes.' });
        } else cles.forEach(function (k) { vus[k] = n; });
        var existe = j.existe ? j.existe(ligne.v, ctx) : null;
        if (existe) ligne.problemes.push({ n: n, colonne: j.colonnes[0].label, valeur: lecture[0], code: 'DOUBLON_MAGASIN', niveau: 'refus', motif: existe, geste: j.gesteExiste || 'Retirez la ligne.' });
        (j.regles ? j.regles(ligne.v, ctx, sc, n) : []).forEach(function (p) { ligne.problemes.push(Object.assign({ n: n }, p)); });
      }
      ligne.etat = ligne.problemes.some(function (p) { return p.niveau === 'refus'; }) ? 'refus'
        : (ligne.problemes.length ? 'avertissement' : 'valide');
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
      if (l.etat === 'refus') res.compte.refus++; else if (l.etat === 'avertissement') res.compte.avertissements++; else res.compte.valides++;
    });
    res.accepte = !res.globaux.some(function (p) { return p.niveau === 'refus'; }) && res.compte.refus === 0 && res.nbLignes > 0;
    return res;
  }

  /** Tous les problèmes à plat (globaux, puis par ligne), pour le rapport et pour la consignation. */
  function problemes(analyse) {
    var out = analyse.globaux.slice();
    analyse.lignes.forEach(function (l) { l.problemes.forEach(function (p) { out.push(p); }); });
    return out;
  }

  function analyserOctets(jeuId, octets, fichier) {
    var j = jeu(jeuId), lignes;
    try {
      if (/\.csv$/i.test(fichier || '') || /\.txt$/i.test(fichier || '')) lignes = X.lireCsv(new TextDecoder('utf-8').decode(octets));
      else {
        var classeur = X.lire(octets);
        var feuille = classeur.feuilles.filter(function (f) { return C.norm(f.nom) === C.norm(NOMS_FEUILLES.donnees); })[0] || classeur.feuilles[0];
        if (!feuille) throw new Error('le classeur ne contient aucune feuille');
        lignes = feuille.lignes;
      }
    } catch (e) {
      var res = { jeu: jeuId, fichier: fichier, nbLignes: 0, lignes: [], accepte: false, compte: { valides: 0, avertissements: 0, refus: 0 }, lignesBrutes: [],
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
    var ps = problemes(analyse);
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
    if (!analyse || !analyse.accepte) return { ok: false, code: 'ANALYSE_REFUSEE', motif: 'le fichier n’a pas passé l’analyse', geste: 'Corrigez les refus listés, puis téléversez de nouveau.' };
    /* L'état du magasin a pu bouger entre l'analyse et la confirmation (un autre poste a pu créer le même article) :
       on rejoue l'analyse sur les lignes d'origine et l'on n'écrit que si elle tient toujours. */
    var rejeu = analyserLignes(j, analyse.lignesBrutes, analyse.fichier);
    if (!rejeu.accepte) {
      var c = consigner(j, Object.assign(rejeu, { empreinte: analyse.empreinte }));
      return { ok: false, code: 'MAGASIN_CHANGE', motif: 'le magasin a changé depuis l’analyse ; le fichier est refusé et consigné (' + c.reference + ')', geste: 'Relisez le rapport du lot ' + c.reference + ' et téléversez de nouveau.', lot: c, analyse: rejeu };
    }
    var ctx = j.contexte ? j.contexte() : {};
    var lot = { reference: referenceLot() }, ecrits = [], par = S.currentUser(), jour = aujourdhuiIso();
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
      j.ecrire(rejeu.lignes, ecrireFiche, lot, ctx);
    } catch (e) {
      /* Atomicité : on retire ce qui vient d'être posé dans CE geste. Ces fiches n'ont jamais été vues d'un autre écran. */
      ecrits.slice().reverse().forEach(function (x) { S.collection(x.collection)._remove(x.id); });
      var motif = e && e.message ? e.message : String(e);
      var consigne = consigner(j, Object.assign(rejeu, { globaux: rejeu.globaux.concat([{ n: 0, colonne: '', valeur: '', code: 'ECRITURE_REFUSEE', niveau: 'refus', motif: motif, geste: 'Rien n’a été écrit. Corrigez la cause puis téléversez de nouveau.' }]), empreinte: analyse.empreinte }));
      return { ok: false, code: 'ECRITURE_REFUSEE', motif: motif, geste: 'Rien n’a été écrit ; le fichier est consigné (' + consigne.reference + ').', lot: consigne };
    }
    var rec = colLots().insert({
      reference: lot.reference, jeu: j.id, jeuLibelle: j.libelle, fichier: analyse.fichier, empreinte: analyse.empreinte || null,
      date: jour, par: par, validePar: par, etat: 'applique', nbLignes: rejeu.nbLignes, nbAvertissements: rejeu.compte.avertissements, nbRefus: 0,
      ecrits: ecrits, erreurs: problemes(rejeu).slice(0, 100), erreursTotal: problemes(rejeu).length,
    }).record;
    S.log('Import', 'IMP', 'LotImport', rec.reference, null, { jeu: j.id, fichier: analyse.fichier, lignes: rejeu.nbLignes, fiches: ecrits.length });
    return { ok: true, lot: rec, ecrits: ecrits.length };
  }

  function annulerLot(lotId, motif) {
    var col_ = colLots(), lot = col_.get(lotId);
    if (!lot) return { ok: false, code: 'LOT_INCONNU', motif: 'lot introuvable', geste: 'Actualisez l’historique.' };
    if (lot.etat !== 'applique') return { ok: false, code: 'LOT_NON_APPLIQUE', motif: 'seul un lot appliqué s’annule (état actuel : ' + lot.etat + ')', geste: 'Aucune action : ce lot n’a rien écrit ou est déjà annulé.' };
    var j = jeu(lot.jeu);
    var dep = j && j.dependances ? j.dependances(lot) : null;
    if (dep) return { ok: false, code: dep.code, motif: dep.motif, geste: dep.geste };
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
    if (c.type === 'tarif') return 'montant entier en FCFA ; NC ; tiret (-)';
    if (c.motifTexte) return c.motifTexte;
    if (c.longueurMax) return 'jusqu’à ' + c.longueurMax + ' caractères';
    return '';
  }

  function modele(jeuId) {
    var j = jeu(jeuId), ctx = j.contexte ? j.contexte() : {};
    var entetes = j.colonnes.map(function (c) { return c.label; });
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
      [''],
      ['Colonne', 'Obligatoire', 'Type', 'Valeurs permises', 'Exemple', 'Explication'],
    ].concat(j.colonnes.map(function (c) {
      return [c.label, c.obligatoire ? 'oui' : 'non', typeLisible(c), valeursPermises(c, ctx), c.exemple === undefined ? '' : c.exemple, c.aide || ''];
    }));
    var listes = [], listesCols = [], validations = [];
    j.colonnes.forEach(function (c) {
      if (c.type !== 'liste') return;
      var vals = valeursListe(c, ctx);
      listesCols.push({ titre: c.label, valeurs: vals.map(function (x) { return x.label; }) });
    });
    var hauteur = listesCols.reduce(function (m, l) { return Math.max(m, l.valeurs.length); }, 0);
    listes.push(listesCols.map(function (l) { return l.titre; }));
    for (var i = 0; i < hauteur; i++) listes.push(listesCols.map(function (l) { return l.valeurs[i] === undefined ? '' : l.valeurs[i]; }));
    var k = 0;
    j.colonnes.forEach(function (c, ci) {
      if (c.type !== 'liste') return;
      var lettre = String.fromCharCode(65 + k);
      validations.push({ colonne: ci, formule: 'Listes!$' + lettre + '$2:$' + lettre + '$' + Math.max(2, listesCols[k].valeurs.length + 1) });
      k++;
    });
    var texteCols = [];
    j.colonnes.forEach(function (c, ci) { if (c.type === 'texte') texteCols.push(ci); });
    return X.ecrire({ feuilles: [
      { nom: NOMS_FEUILLES.donnees, lignes: donnees, largeurs: j.colonnes.map(function (c) { return Math.max(14, c.label.length + 4); }), listes: validations, texteColonnes: texteCols },
      { nom: NOMS_FEUILLES.instructions, lignes: instructions, largeurs: [28, 12, 28, 46, 22, 70], entete: false },
      { nom: NOMS_FEUILLES.listes, lignes: listesCols.length ? listes : [['Aucune liste pour ce jeu']], largeurs: listesCols.map(function () { return 30; }) },
    ] });
  }

  function modeleCsv(jeuId) {
    var j = jeu(jeuId);
    function ligne(a) { return a.map(function (x) { return '"' + String(x).replace(/"/g, '""') + '"'; }).join(';'); }
    return '\uFEFF' + [ligne(j.colonnes.map(function (c) { return c.label; })), ligne(ligneExemple(j))].join('\r\n') + '\r\n';
  }

  function rapport(lotOuAnalyse, j) {
    var ps = lotOuAnalyse.erreurs || problemes(lotOuAnalyse);
    var entete = ['Ligne', 'Colonne', 'Valeur', 'Niveau', 'Code', 'Motif', 'Geste de correction'];
    var lignes = [entete].concat(ps.map(function (p) { return [p.n || '', p.colonne || '', p.valeur === undefined ? '' : String(p.valeur), p.niveau, p.code, p.motif, p.geste]; }));
    var resume = [['Rapport d’importation'], ['Jeu', j ? j.libelle : lotOuAnalyse.jeuLibelle || ''], ['Fichier', lotOuAnalyse.fichier || ''],
      ['Lot', lotOuAnalyse.reference || 'non consigné'], ['Lignes lues', lotOuAnalyse.nbLignes], ['Problèmes', ps.length]];
    return X.ecrire({ feuilles: [
      { nom: 'Erreurs', lignes: lignes, largeurs: [8, 26, 24, 14, 24, 70, 70] },
      { nom: 'Résumé', lignes: resume, entete: false, largeurs: [24, 50] },
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
  var TONS_LIGNE = { valide: ['Valide', 'success'], avertissement: ['Avertissement', 'warning'], refus: ['Refus', 'danger'] };

  function peutOuvrir(j) {
    var s = S.session() || {};
    var e = N.get(j.ecran);
    return !!e && N.can(s.role, { id: e.id, roles: e.roles || N.ALL, module: e.module });
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
          out.push(K.iconBtn('file-down', 'Rapport d’erreurs (.xlsx)', function () { telecharger('rapport-' + l.reference + '.xlsx', rapport(l, jeu(l.jeu)), MIME_XLSX); }));
        }
        if (l.etat === 'applique') {
          out.push(K.commandeIcone('undo-2', 'Annuler le lot', function () {
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
          }, { droit: 'annuler', variant: 'danger' }));
        }
        return out;
      },
    });
  }

  function badgeStatut(j) { return j.statut === 'supporte' ? U.badge('Supporté', 'success') : U.badge('Proposition à valider', 'warning'); }

  function ecranJeu(j) {
    return function (root) {
      var host = el('div.space-y-4'), zone = el('div.space-y-4'), histo = el('div'), etat = { analyse: null };
      root.appendChild(host);

      function dessinerHistorique() {
        C.clear(histo);
        var lots = colLots().all().filter(function (l) { return l.jeu === j.id; });
        histo.appendChild(U.card('Historique des lots de ce jeu', tableLots(lots, dessinerHistorique)));
        U.icons(histo);
      }

      host.appendChild(U.kpiGrid((function () {
        var lots = colLots().all().filter(function (l) { return l.jeu === j.id; });
        var appl = lots.filter(function (l) { return l.etat === 'applique'; });
        return [
          { label: 'Lots appliqués', value: String(appl.length), icon: 'package-check', tone: 'navy' },
          { label: 'Fiches importées', value: C.num(appl.reduce(function (t, l) { return t + l.ecrits.length; }, 0)), icon: 'database', tone: 'info' },
          { label: 'Fichiers refusés', value: String(lots.filter(function (l) { return l.etat === 'refuse'; }).length), icon: 'file-x', tone: 'warning' },
          { label: 'Statut du jeu', value: j.statut === 'supporte' ? 'Supporté' : 'À valider', icon: 'badge-check', tone: j.statut === 'supporte' ? 'success' : 'warning' },
        ];
      })()));

      if (j.statut === 'proposition') host.appendChild(K.note('<strong>Proposition à valider.</strong> ' + j.limite, { tone: 'warning', icon: 'help-circle' }));
      else if (j.limite) host.appendChild(K.note(j.limite, { tone: 'info', icon: 'info' }));

      /* 1. Le modèle */
      var colTable = K.miniTable(['Colonne', 'Obligatoire', 'Type', 'Valeurs permises', 'Exemple'], j.colonnes.map(function (c) {
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

      /* 2. Le téléversement */
      var entree = el('input', { type: 'file', accept: '.xlsx,.csv', class: 'hidden', 'data-import-fichier': j.id, 'aria-label': 'Fichier à importer' });
      entree.addEventListener('change', function () {
        var f = entree.files && entree.files[0];
        if (!f) return;
        var lecteur = new FileReader();
        lecteur.onload = function () { analyser(new Uint8Array(lecteur.result), f.name); entree.value = ''; };
        lecteur.readAsArrayBuffer(f);
      });
      var barreTele = el('div.flex.flex-wrap.items-center.gap-2', null, [
        K.commande('Téléverser un fichier (.xlsx ou .csv)', { variant: 'primary', icon: 'upload', onclick: function () { entree.click(); } }),
        entree,
      ]);
      host.appendChild(U.card('2. Téléverser et analyser', el('div.space-y-3', null, [
        el('p.text-sm.text-slate-600', { text: 'L’analyse est complète et ne modifie rien : chaque ligne est contrôlée, un refus est nommé, et c’est vous qui confirmez l’écriture.' }),
        barreTele,
      ])));
      host.appendChild(zone);
      host.appendChild(histo);
      dessinerHistorique();

      function analyser(octets, nom) {
        var a = analyserOctets(j.id, octets, nom);
        etat.analyse = a;
        C.clear(zone);
        var lot = null;
        if (!a.accepte) lot = consigner(j, a);
        zone.appendChild(apercu(a, lot));
        U.icons(zone);
        dessinerHistorique();
      }

      function apercu(a, lot) {
        var ps = problemes(a);
        var cartes = el('div.space-y-3');
        var resume = el('div.flex.flex-wrap.gap-2', null, [
          U.badge(a.nbLignes + ' ligne(s) lue(s)', 'navy'), U.badge(a.compte.valides + ' valide(s)', 'success'),
          U.badge(a.compte.avertissements + ' avertissement(s)', 'warning'), U.badge(a.compte.refus + ' refus', a.compte.refus ? 'danger' : 'neutral'),
        ]);
        cartes.appendChild(resume);
        if (a.accepte) {
          cartes.appendChild(K.note('<strong>Analyse conforme.</strong> ' + a.nbLignes + ' ligne(s) peuvent être écrites' + (a.compte.avertissements ? ', dont ' + a.compte.avertissements + ' avec avertissement' : '') + '. Rien n’est encore écrit.', { tone: 'success', icon: 'check-circle' }));
        } else {
          cartes.appendChild(K.note('<strong>Fichier refusé.</strong> Rien n’a été écrit. Le fichier est consigné au lot <span class="font-mono">' + lot.reference + '</span> ; corrigez les points ci-dessous puis téléversez de nouveau.', { tone: 'danger', icon: 'octagon-alert' }));
        }
        if (a.globaux.length) {
          cartes.appendChild(U.card('Points concernant le fichier entier', K.miniTable(['Niveau', 'Colonne', 'Motif', 'Geste de correction'], a.globaux.map(function (p) {
            return [U.badge(p.niveau === 'refus' ? 'Refus' : 'Avertissement', p.niveau === 'refus' ? 'danger' : 'warning'), p.colonne || '', p.motif, p.geste];
          }))));
        }
        if (a.lignes.length) {
          cartes.appendChild(U.card('Aperçu ligne par ligne', U.dataTable({
            rows: a.lignes.map(function (l) {
              return { n: l.n, etat: l.etat, resume: l.brut.slice(0, 3).filter(Boolean).join(' · '), problemes: l.problemes };
            }),
            pageSize: 10, defaultSort: 'n', exportName: 'apercu-importation',
            filters: [{ name: 'etat', label: 'État', options: [{ value: 'valide', label: 'Valide' }, { value: 'avertissement', label: 'Avertissement' }, { value: 'refus', label: 'Refus' }] }],
            columns: [
              { key: 'n', label: 'Ligne', align: 'right' },
              { key: 'etat', label: 'État', text: function (r) { return TONS_LIGNE[r.etat][0]; }, render: function (r) { return U.badge(TONS_LIGNE[r.etat][0], TONS_LIGNE[r.etat][1]); } },
              { key: 'resume', label: 'Contenu' },
              { key: 'problemes', label: 'Constats', sortable: false,
                text: function (r) { return r.problemes.map(function (p) { return p.colonne + ' : ' + p.motif; }).join(' | '); },
                render: function (r) {
                  return el('div.space-y-1', null, r.problemes.map(function (p) {
                    return el('p.text-xs', { class: p.niveau === 'refus' ? 'text-danger-700' : 'text-warning-700' }, [
                      el('strong', { text: p.colonne + ' ' }), (p.valeur !== '' && p.valeur !== undefined ? '« ' + p.valeur + ' » : ' : ': ') + p.motif + '. ', el('em', { text: p.geste }),
                    ]);
                  }));
                } },
            ],
          })));
        }
        var actions = el('div.flex.flex-wrap.gap-2');
        if (a.accepte) {
          actions.appendChild(K.commande('Confirmer l’importation (' + a.nbLignes + ' ligne' + (a.nbLignes > 1 ? 's' : '') + ')', {
            variant: 'primary', icon: 'package-check',
            onclick: function () {
              U.confirm({
                title: 'Écrire ce lot ?',
                message: a.nbLignes + ' ligne(s) du fichier « ' + a.fichier + ' » vont s’écrire en un seul geste, au nom de ' + S.currentUser() + ' (validé par). Le lot pourra être annulé tant qu’aucun acte ne s’appuie dessus.',
                confirmLabel: 'Écrire le lot',
              }).then(function (ok) {
                if (!ok) return;
                var r = appliquer(j.id, a);
                C.clear(zone);
                if (r.ok) {
                  U.toast('Lot ' + r.lot.reference + ' appliqué.', { type: 'success', detail: r.ecrits + ' fiche(s) écrite(s).' });
                  zone.appendChild(K.note('<strong>Lot ' + r.lot.reference + ' appliqué.</strong> ' + r.ecrits + ' fiche(s) écrite(s), journalisées (RG-12).', { tone: 'success', icon: 'check-circle' }));
                } else {
                  U.toast('Importation refusée.', { type: 'error', detail: r.motif });
                  zone.appendChild(K.note('<strong>Importation refusée.</strong> ' + r.motif + '. ' + r.geste, { tone: 'danger', icon: 'octagon-alert' }));
                }
                U.icons(zone);
                dessinerHistorique();
              });
            },
          }));
        }
        if (ps.length) actions.appendChild(K.btn('Rapport d’erreurs (.xlsx)', { icon: 'file-down', onclick: function () { telecharger('rapport-' + (lot ? lot.reference : 'analyse') + '.xlsx', rapport(lot || a, j), MIME_XLSX); } }));
        actions.appendChild(K.btn('Abandonner', { onclick: function () { C.clear(zone); } }));
        cartes.appendChild(actions);
        return U.card('Résultat de l’analyse du fichier « ' + a.fichier + ' »', cartes);
      }
      return null;
    };
  }

  /* --- Accueil du module -------------------------------------------------------------------------------------------- */
  function ecranAccueil(root) {
    var host = el('div.space-y-4');
    root.appendChild(host);
    var tous = colLots().all();
    host.appendChild(U.kpiGrid([
      { label: 'Jeux d’import', value: String(JEUX.length), icon: 'files', tone: 'navy' },
      { label: 'Lots appliqués', value: String(tous.filter(function (l) { return l.etat === 'applique'; }).length), icon: 'package-check', tone: 'success' },
      { label: 'Fichiers refusés', value: String(tous.filter(function (l) { return l.etat === 'refuse'; }).length), icon: 'file-x', tone: 'warning' },
      { label: 'Lots annulés', value: String(tous.filter(function (l) { return l.etat === 'annule'; }).length), icon: 'undo-2', tone: 'neutral' },
    ]));
    host.appendChild(U.tabs([
      { id: 'jeux', label: 'Jeux d’import', render: function () {
        var grille = el('div.grid.gap-3', { class: 'sm:grid-cols-2 lg:grid-cols-3' });
        JEUX.filter(peutOuvrir).forEach(function (j) {
          var dernier = colLots().all().filter(function (l) { return l.jeu === j.id; })[0];
          grille.appendChild(el('div.card', null, el('div.card-body.space-y-2', null, [
            el('div.flex.items-start.justify-between.gap-2', null, [el('h3.font-semibold.text-navy-900', { text: j.libelle }), badgeStatut(j)]),
            el('p.text-sm.text-slate-600', { text: j.description }),
            el('p.text-xs.text-slate-500', { text: 'Source : ' + j.source }),
            el('p.text-xs.text-slate-500', { text: 'Écrit dans : ' + j.cibles.join(', ') + '. ' + (dernier ? 'Dernier lot : ' + dernier.reference + ' (' + (TONS_ETAT[dernier.etat] || [dernier.etat])[0] + ').' : 'Aucun lot à ce jour.') }),
            K.lien(j.ecran, 'Ouvrir', { variant: 'primary', icon: 'arrow-right' }),
          ])));
        });
        return grille;
      } },
      { id: 'historique', label: 'Historique des lots', badge: tous.length, render: function (panel) {
        function dessiner() {
          C.clear(panel);
          var visibles = {};
          JEUX.filter(peutOuvrir).forEach(function (j) { visibles[j.id] = true; });
          panel.appendChild(tableLots(colLots().all().filter(function (l) { return visibles[l.jeu]; }), dessiner));
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
    regle: 'Un import <strong>n’invente rien</strong> : il écrit ce que le fichier porte, après une analyse ligne par ligne. Un refus se nomme (ligne, colonne, valeur, motif, geste). Un fichier refusé est consigné et n’écrit rien. Un lot s’annule en archivant ses fiches (RG-14).',
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
  };
})(window);
