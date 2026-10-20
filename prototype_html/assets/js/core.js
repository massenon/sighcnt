/* =============================================================================
 * SIGH-CNT — Noyau : configuration de marque, formats, utilitaires DOM
 * -----------------------------------------------------------------------------
 * BRAND provient du « Brand Configuration Center » (draf1 §18) : aucune mention
 * légale n'est écrite en dur dans les pages, tous les états officiels lisent ici.
 * ========================================================================== */
(function (global) {
  'use strict';

  /* --- Identité de l'établissement (CDCT §4.2) ---------------------------- */
  var BRAND = {
    sigle: 'CNT',
    nom: 'CLINIQUE NASSIERA TOO SARL',
    /* Slogan dicté par la Direction le 24/08/2026. Le prototype portait
       « Votre santé, notre priorité », qui n'est pas la formule de la clinique. */
    slogan: 'Votre santé, notre raison de vivre',
    forme: 'Société à Responsabilité Limitée',
    adresse: 'Quartier Tchirimina, Natitingou',
    bp: 'BP : 507 NATITINGOU (Rép. du Bénin)',
    pays: 'République du Bénin',
    /* Numérotation à dix chiffres, arrêtée par la Direction le 26/08/2026. */
    telephones: ['01 95 44 51 51', '01 66 43 28 20'],
    /* Ligne dédiée aux rendez-vous, relevée sur la fiche d'observation réelle.
       Elle ne figure sur aucun autre document, mais c'est le numéro que le
       patient compose pour prendre rendez-vous. */
    telephoneRdv: '60 33 92 92',
    email: 'cliniquenassiera@gmail.com',
    ifu: '3201642748214',
    /* UN SEUL RCCM — arbitrage de la Direction du 31/08/2026 (Bugs 7/8/13 des
       Instructions) : toutes les pièces, caisse comprise, portent la même
       identité légale. Les pièces anciennes qui portaient NAT/2021/M02-020
       restent documentées dans les scans de docs/, mais le logiciel n'imprime
       plus que celui-ci. */
    rccm: 'RB/NAT/2016-B-268',
    /* L'AUTORISATION D'EXERCICE N'EST PLUS IMPRIMÉE : elle n'est plus valable,
       l'inscription à l'ordre suffisant depuis la loi 2025-1 de juin 2026.
       Continuer à l'imprimer ferait état d'un titre caduc. */
    autorisationExercice: null,
    autorisationExerciceMotif: 'Non applicable — l’inscription à l’ordre suffit depuis la loi 2025-1 '
      + 'de juin 2026. L’autorisation d’exercice n’est plus imprimée sur les états.',
    devise: 'FCFA',
    /* Formules imprimées sur toutes les pièces de caisse, relevées à
       l'identique sur les factures et tickets réellement émis. */
    formuleArrete: 'Arrêtée la présente facture à la somme de',
    formulePolitesse: 'QUE DIEU VOUS GUÉRISSE ! AMINE !',
    autorisation: 'N° 066/MS/DC/SGM/CJ/DNSP/SRS/SA/058SGG20/N°20 du 02/07/2020',
    logo: 'assets/img/logo.jpeg',
    devise: 'FCFA',
    codeDevise: 'XOF',
  };

  /* --- Formats ------------------------------------------------------------ */
  var MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  var JOURS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];

  /** Cadre un nombre sur `largeur` chiffres (2 par défaut) : pad(7, 4) → "0007". */
  function pad(n, largeur) { return String(n).padStart(largeur || 2, '0'); }

  /** Montant en francs CFA — pas de décimale, séparateur d'espace insécable. */
  function money(v, withCurrency) {
    var n = Number(v) || 0;
    var s = Math.round(Math.abs(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    if (n < 0) s = '-' + s;
    return withCurrency === false ? s : s + ' ' + BRAND.devise;
  }
  function num(v, dec) {
    var n = Number(v) || 0;
    return n.toFixed(dec == null ? 0 : dec).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  }
  function pct(v, dec) { return num(v, dec == null ? 1 : dec) + ' %'; }

  function toDate(d) { return d instanceof Date ? d : new Date(d); }
  function dateFR(d) { var x = toDate(d); return pad(x.getDate()) + '/' + pad(x.getMonth() + 1) + '/' + x.getFullYear(); }
  function dateLong(d) { var x = toDate(d); return x.getDate() + ' ' + MOIS[x.getMonth()] + ' ' + x.getFullYear(); }
  function dateJour(d) { var x = toDate(d); return JOURS[x.getDay()] + ' ' + x.getDate() + ' ' + MOIS[x.getMonth()] + ' ' + x.getFullYear(); }
  function heure(d) { var x = toDate(d); return pad(x.getHours()) + 'h' + pad(x.getMinutes()); }
  function dateHeure(d) { return dateFR(d) + ' à ' + heure(d); }

  /* ==========================================================================
   * LES PARAMÈTRES D'UNE PAGE (21/09/2026)
   * --------------------------------------------------------------------------
   * Une modale reçoit son contexte de l'écran qui l'ouvre ; une PAGE, elle,
   * se charge à froid et ne sait rien. Convertir une modale en page suppose
   * donc un canal — et c'est l'adresse qui le porte, comme elle portait déjà
   * l'onglet visé par la recherche globale (`…/cfg-tarifs.html#onglet=actes`).
   *
   * L'ANCRE ET NON LA CHAÎNE DE REQUÊTE : le prototype s'ouvre aussi depuis
   * le système de fichiers (`file://`), où une chaîne de requête n'est pas
   * toujours transmise. L'ancre l'est toujours, et elle ne déclenche aucune
   * requête réseau — la contrainte hors ligne vaut ici comme ailleurs.
   * ======================================================================== */
  function params(source) {
    var brut = String(source == null ? (global.location ? global.location.hash : '') : source);
    var out = {};
    brut.replace(/^#/, '').split('&').forEach(function (bout) {
      if (!bout) return;
      var i = bout.indexOf('=');
      var cle = i < 0 ? bout : bout.slice(0, i);
      var val = i < 0 ? '' : bout.slice(i + 1);
      try { out[decodeURIComponent(cle)] = decodeURIComponent(val); }
      catch (e) { out[cle] = val; }
    });
    return out;
  }

  /** L'ancre correspondante — la réciproque exacte de `params()`. */
  function ancre(opts) {
    var bouts = [];
    Object.keys(opts || {}).forEach(function (k) {
      var v = opts[k];
      if (v == null || v === '') return;
      bouts.push(encodeURIComponent(k) + '=' + encodeURIComponent(v));
    });
    return bouts.length ? '#' + bouts.join('&') : '';
  }

  /** Âge en années révolues, depuis une date de naissance. */
  function age(naissance) {
    if (!naissance) return null;
    return Math.max(0, Math.floor(daysBetween(naissance, new Date()) / 365.25));
  }

  /* ==========================================================================
   * L'ÂGE QUAND LA DATE DE NAISSANCE MANQUE (21/09/2026)
   * --------------------------------------------------------------------------
   * Une grande partie des patients ne connaît pas sa date de naissance — c'est
   * la situation ordinaire, pas l'exception. Le dossier l'exigeait pourtant :
   * l'accueil inscrivait donc un 1er janvier de fantaisie, et cette date
   * inventée ressortait ensuite sur chaque pièce imprimée comme un fait.
   *
   * UN ÂGE VIEILLIT, ET C'EST TOUTE LA DIFFICULTÉ. Le stocker nu le figerait :
   * « 45 ans » saisi en 2026 se lirait encore « 45 ans » en 2030. On le DATE
   * donc — `age` + `ageReferenceLe` — et on ajoute les années écoulées depuis
   * la déclaration. C'est le mécanisme de la couverture d'assurance, de la
   * grille des primes et des plages par lot de réactif, et ce n'est pas un
   * hasard : chaque fois qu'une donnée ne vaut qu'à une DATE, on porte la
   * date avec elle plutôt que de faire comme si elle valait toujours.
   *
   * La date de naissance, quand elle existe, FAIT TOUJOURS FOI : elle est
   * exacte, l'âge déclaré est une approximation. On ne remplace jamais la
   * première par le second.
   * ======================================================================== */
  function ageDe(rec) {
    if (!rec) return null;
    if (rec.dateNaissance) return age(rec.dateNaissance);
    var declare = rec.age;
    if (declare == null || declare === '') return null;
    var n = parseInt(String(declare), 10);
    if (!isFinite(n) || n < 0) return null;
    if (!rec.ageReferenceLe) return n;
    var ecoule = Math.floor(daysBetween(rec.ageReferenceLe, new Date()) / 365.25);
    return Math.max(0, n + Math.max(0, ecoule));
  }

  /** Vrai si l'âge repose sur une DÉCLARATION et non sur une date exacte. */
  function ageEstDeclare(rec) {
    return !!(rec && !rec.dateNaissance && rec.age != null && rec.age !== '');
  }

  /**
   * L'âge tel qu'il s'ÉCRIT sur une pièce : « 45 ans », ou « 45 ans (âge
   * déclaré) » quand aucune date de naissance ne l'établit. La mention n'est
   * pas un ornement — elle dit au lecteur de la pièce que le chiffre est une
   * approximation, ce qu'une date de naissance inventée ne disait pas.
   */
  function ageTexte(rec) {
    var a = ageDe(rec);
    if (a == null) return '—';
    return a + ' an' + (a > 1 ? 's' : '') + (ageEstDeclare(rec) ? ' (âge déclaré)' : '');
  }
  function iso(d) { var x = toDate(d); return x.getFullYear() + '-' + pad(x.getMonth() + 1) + '-' + pad(x.getDate()); }
  /* LA DATE DU JOUR VIT ICI, ET NULLE PART AILLEURS (vague 68, 20/10/2026).
     Dix-neuf modules portaient `var AUJ = new Date(2026, 7, 16)` — la date du
     jeu de démonstration, figée pour que les tableaux de bord aient quelque
     chose à montrer. Conséquence vécue : un rendez-vous pris aujourd'hui tombait
     hors de la fenêtre de l'agenda (du 14 au 20 août) et ne se retrouvait nulle
     part. L'application lit l'horloge RÉELLE ; c'est le BANC D'ESSAI qui décale
     l'horloge sur la date du jeu (build/_banc.js), jamais le code livré. */
  function aujourdhui() { return new Date(); }
  /** Valeur d'un champ `datetime-local` à l'heure LOCALE — `toISOString()` rend
   *  l'heure UTC, et le Bénin est à UTC+1 : l'heure proposée était fausse d'une heure. */
  function isoLocal(d) {
    var x = toDate(d || aujourdhui());
    return iso(x) + 'T' + pad(x.getHours()) + ':' + pad(x.getMinutes());
  }
  function moisAnnee(d) { var x = toDate(d); return MOIS[x.getMonth()] + ' ' + x.getFullYear(); }

  /** Ancienneté / il y a X — pour timelines et journaux d'audit. */
  function ilYA(d) {
    var diff = (Date.now() - toDate(d).getTime()) / 1000;
    if (diff < 60) return 'à l’instant';
    if (diff < 3600) return 'il y a ' + Math.floor(diff / 60) + ' min';
    if (diff < 86400) return 'il y a ' + Math.floor(diff / 3600) + ' h';
    if (diff < 2592000) return 'il y a ' + Math.floor(diff / 86400) + ' j';
    return dateFR(d);
  }

  function addDays(d, n) { var x = new Date(toDate(d).getTime()); x.setDate(x.getDate() + n); return x; }
  function daysBetween(a, b) { return Math.round((toDate(b) - toDate(a)) / 86400000); }

  /* --------------------------------------------------------------------------
   * PÉRIODICITÉS — les six pas de découpage que la clinique demande
   * --------------------------------------------------------------------------
   * « Journalier ou hebdomadaire ou mensuel ou trimestriel ou semestriel ou
   * annuel », plus une plage libre. Elles vivaient dans le module de
   * facturation ; le gestionnaire de stock demande les mêmes sur ses points de
   * vente et de stock, qui sont des écrans de M6 — et une page ne charge que
   * le module de son écran. Leur place est donc ici.
   * ----------------------------------------------------------------------- */
  var PERIODES = [
    { id: 'jour', label: 'Journalière', jours: 1 },
    { id: 'semaine', label: 'Hebdomadaire', jours: 7 },
    { id: 'mois', label: 'Mensuelle', jours: 30 },
    { id: 'trimestre', label: 'Trimestrielle', jours: 91 },
    { id: 'semestre', label: 'Semestrielle', jours: 182 },
    { id: 'annee', label: 'Annuelle', jours: 365 },
  ];

  /** Bornes d'une période finissant à la date choisie. */
  function bornes(periodeId, fin) {
    var p = PERIODES.filter(function (x) { return x.id === periodeId; })[0] || PERIODES[0];
    var f = toDate(fin);
    return { debut: addDays(f, -(p.jours - 1)), fin: f, label: p.label, jours: p.jours };
  }

  /** Bornes d'une plage libre, remises dans l'ordre si l'agent les a inversées. */
  function bornesLibres(du, au) {
    var a = toDate(du), b = toDate(au);
    if (a.getTime() > b.getTime()) { var t = a; a = b; b = t; }
    return { debut: a, fin: b, label: 'Plage libre', jours: daysBetween(a, b) + 1 };
  }

  /** Une date tombe-t-elle dans les bornes ? Les deux extrémités sont incluses. */
  function dansBornes(date, b) {
    if (!date || !b) return false;
    var d = toDate(date).getTime();
    return d >= toDate(b.debut).getTime() && d <= toDate(b.fin).getTime();
  }

  /** Intitulé lisible d'une période — c'est lui qui coiffe les états imprimés. */
  function libellePeriode(b) {
    if (!b) return '';
    if (b.jours === 1) return 'Journée du ' + dateFR(b.debut);
    return 'Du ' + dateFR(b.debut) + ' au ' + dateFR(b.fin);
  }

  /* --------------------------------------------------------------------------
   * Montant en toutes lettres — mention obligatoire sur les factures
   * normalisées : « Arrêté la présente facture à la somme de … ».
   * Applique les accords français : « quatre-vingts » et « cents » prennent un
   * s lorsqu'ils terminent le nombre, « mille » reste invariable.
   * ----------------------------------------------------------------------- */
  var UNITES = ['zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf',
    'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize'];
  var DIZAINES = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante', 'soixante', 'quatre-vingt', 'quatre-vingt'];

  function centaineEnLettres(n) {
    if (n < 17) return UNITES[n];
    if (n < 20) return 'dix-' + UNITES[n - 10];
    if (n < 100) {
      var d = Math.floor(n / 10), u = n % 10;
      var base = DIZAINES[d];
      if (d === 7 || d === 9) u += 10;
      if (u === 0) return d === 8 ? base + 's' : base;
      if (u === 1 && d !== 8 && d !== 7 && d !== 9) return base + ' et un';
      if (u === 11 && d === 7) return base + ' et onze';
      return base + '-' + (u < 17 ? UNITES[u] : 'dix-' + UNITES[u - 10]);
    }
    var c = Math.floor(n / 100), r = n % 100;
    var tete = c === 1 ? 'cent' : UNITES[c] + ' cent';
    if (r === 0) return c === 1 ? 'cent' : tete + 's';
    return tete + ' ' + centaineEnLettres(r);
  }

  function nombreEnLettres(n) {
    n = Math.round(Math.abs(Number(n) || 0));
    if (n === 0) return 'zéro';
    var tranches = [
      { valeur: 1e9, singulier: 'milliard', pluriel: 'milliards' },
      { valeur: 1e6, singulier: 'million', pluriel: 'millions' },
      { valeur: 1e3, singulier: 'mille', pluriel: 'mille' },
    ];
    var mots = [];
    tranches.forEach(function (t) {
      var q = Math.floor(n / t.valeur);
      if (!q) return;
      n -= q * t.valeur;
      if (t.valeur === 1e3 && q === 1) mots.push('mille');
      else mots.push(centaineEnLettres(q) + ' ' + (q > 1 ? t.pluriel : t.singulier));
    });
    if (n > 0) mots.push(centaineEnLettres(n));
    return mots.join(' ');
  }

  /** Montant en lettres suivi de la devise, prêt pour la mention légale. */
  function montantEnLettres(v) {
    return nombreEnLettres(v) + ' francs CFA';
  }

  /* --- Identifiants ------------------------------------------------------- */
  /**
   * RG-01 — code patient CNT/[n° d'ordre]/[année], non modifiable.
   *
   * Le séparateur après CNT est celui que la Direction a arrêté le 24/08/2026 :
   * « CNT530/25 » se lit mal, on hésite entre le numéro et l'année ;
   * « CNT/530/25 » ne laisse aucun doute.
   *
   * RG-01 interdisant de modifier un code attribué, le format ne vaut que pour
   * les dossiers À VENIR : cette fonction est appelée à la création, jamais à
   * l'affichage. Renuméroter l'existant romprait le lien avec l'archive papier.
   */
  function codePatient(ordre, annee) {
    var y = String(annee == null ? new Date().getFullYear() : annee).slice(-2);
    return 'CNT/' + ordre + '/' + y;
  }
  var _seq = {};
  function nextRef(prefix, width) {
    _seq[prefix] = (_seq[prefix] || 0) + 1;
    return prefix + String(_seq[prefix]).padStart(width || 5, '0');
  }
  function uid() {
    return 'x' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  }

  /* --- Chaînes ------------------------------------------------------------ */
  function slug(s) {
    return String(s).normalize('NFD').replace(/[̀-ͯ]/g, '')
      .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  }
  function initials(s) {
    return String(s).trim().split(/\s+/).slice(0, 2).map(function (w) { return w[0] || ''; }).join('').toUpperCase();
  }
  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  /** Recherche insensible aux accents et à la casse. */
  function norm(s) {
    return String(s == null ? '' : s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  }
  function matches(haystack, needle) { return norm(haystack).indexOf(norm(needle)) !== -1; }

  /* --- DOM ---------------------------------------------------------------- */
  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  /**
   * Crée un élément.
   *   el('div.card', {onclick: fn}, [enfant | 'texte'])
   *
   * Le sélecteur accepte `tag`, `#id` et des classes séparées par des points.
   * Les classes Tailwind contenant un point, un crochet ou une barre oblique
   * s'échappent par une contre-oblique — indispensable pour des utilitaires
   * comme `gap-2\.5`, `w-\[22rem\]` ou `bg-navy-950\/40` :
   *   el('div.flex.gap-2\\.5.w-\\[22rem\\]')  →  class="flex gap-2.5 w-[22rem]"
   */
  function splitSpec(spec) {
    var parts = [], buf = '', s = String(spec);
    for (var i = 0; i < s.length; i++) {
      var ch = s[i];
      if (ch === '\\' && i + 1 < s.length) { buf += s[i + 1]; i++; continue; }
      if (ch === '.' || ch === '#') { parts.push(buf); buf = ch; continue; }
      buf += ch;
    }
    parts.push(buf);
    return parts.filter(function (p) { return p !== ''; });
  }

  function el(spec, attrs, children) {
    var parts = splitSpec(spec);
    var node = document.createElement(parts[0] && parts[0][0] !== '.' && parts[0][0] !== '#' ? parts[0] : 'div');
    parts.forEach(function (p, i) {
      if (i === 0 && p[0] !== '.' && p[0] !== '#') return;
      if (p[0] === '.') node.classList.add(p.slice(1));
      else if (p[0] === '#') node.id = p.slice(1);
    });
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        var v = attrs[k];
        if (v == null || v === false) return;
        if (k === 'class') node.className += (node.className ? ' ' : '') + v;
        else if (k === 'html') node.innerHTML = v;
        else if (k === 'text') node.textContent = v;
        else if (k === 'dataset') Object.keys(v).forEach(function (d) { node.dataset[d] = v[d]; });
        else if (k.slice(0, 2) === 'on' && typeof v === 'function') node.addEventListener(k.slice(2), v);
        else if (v === true) node.setAttribute(k, '');
        else node.setAttribute(k, v);
      });
    }
    /* Plusieurs enfants passés À LA SUITE — el(tag, attrs, a, b, c) — étaient
       ignorés au-delà du premier : les notes et sections d'une vue de détail
       disparaissaient sans un mot (vague 62). Ils sont désormais tous ajoutés. */
    if (arguments.length > 3) children = Array.prototype.slice.call(arguments, 2);
    append(node, children);
    return node;
  }
  function append(node, children) {
    if (children == null) return node;
    (Array.isArray(children) ? children : [children]).forEach(function (c) {
      if (c == null || c === false) return;
      /* Un enfant peut être lui-même une liste (un `.map()` passé à la suite). */
      if (Array.isArray(c)) { append(node, c); return; }
      node.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
    });
    return node;
  }
  function clear(node) { while (node && node.firstChild) node.removeChild(node.firstChild); return node; }

  /** Icône Lucide — rendue en SVG au moment du montage par app.js. */
  function icon(name, cls) {
    return el('i', { 'data-lucide': name, class: cls || 'h-4 w-4' });
  }

  /* --------------------------------------------------------------------------
   * CODE QR — rendu SVG, engendré LOCALEMENT (vendor/qr.js)
   * --------------------------------------------------------------------------
   * Aucune requête réseau, aucune API de génération en ligne : c'est la même
   * contrainte que le reste du prototype, et elle n'est pas négociable pour un
   * badge — on l'imprime aussi un jour de coupure.
   *
   * Le SVG plutôt que le canvas : il s'imprime net à n'importe quelle taille,
   * et la zone de silence (quatre modules, comme la norme le demande) fait
   * partie du dessin — un QR collé au bord d'une carte ne se lit pas.
   *
   * `taille` accepte une unité d'impression (« 18mm ») aussi bien qu'un nombre
   * de pixels : le badge est composé en millimètres, l'écran en pixels.
   * ----------------------------------------------------------------------- */
  var SVG_NS = 'http://www.w3.org/2000/svg';
  function qr(texte, opts) {
    var o = opts || {};
    var marge = o.marge == null ? 4 : o.marge;
    var svg = document.createElementNS(SVG_NS, 'svg');
    var dim = typeof o.taille === 'number' ? o.taille + 'px' : (o.taille || '120px');
    svg.setAttribute('width', dim);
    svg.setAttribute('height', dim);
    svg.setAttribute('role', 'img');
    svg.setAttribute('aria-label', o.alt || 'Code QR');
    if (o.class) svg.setAttribute('class', o.class);
    svg.setAttribute('shape-rendering', 'crispEdges');

    var trame;
    try {
      trame = global.QR.matrice(texte);
    } catch (e) {
      /* Une charge utile trop longue est un DÉFAUT DE CONCEPTION du contenu,
         pas un incident d'affichage : on le dit à l'écran au lieu de laisser
         un carré vide que personne ne saurait interpréter. */
      svg.setAttribute('viewBox', '0 0 100 100');
      var t = document.createElementNS(SVG_NS, 'text');
      t.setAttribute('x', '50'); t.setAttribute('y', '50');
      t.setAttribute('text-anchor', 'middle'); t.setAttribute('font-size', '8');
      t.textContent = 'QR impossible';
      svg.appendChild(t);
      svg.setAttribute('data-erreur', e.message);
      return svg;
    }

    var n = trame.taille + marge * 2;
    svg.setAttribute('viewBox', '0 0 ' + n + ' ' + n);
    var fond = document.createElementNS(SVG_NS, 'rect');
    fond.setAttribute('width', n); fond.setAttribute('height', n);
    fond.setAttribute('fill', o.fond || '#ffffff');
    svg.appendChild(fond);

    var d = '';
    for (var r = 0; r < trame.taille; r++) {
      for (var c = 0; c < trame.taille; c++) {
        if (trame.modules[r][c]) d += 'M' + (c + marge) + ' ' + (r + marge) + 'h1v1h-1z';
      }
    }
    var path = document.createElementNS(SVG_NS, 'path');
    path.setAttribute('d', d);
    path.setAttribute('fill', o.couleur || '#0f172a');
    svg.appendChild(path);
    svg.dataset.version = trame.version;
    return svg;
  }

  /* --- Divers ------------------------------------------------------------- */
  function debounce(fn, ms) {
    var t; return function () {
      var self = this, args = arguments;
      clearTimeout(t); t = setTimeout(function () { fn.apply(self, args); }, ms || 200);
    };
  }
  function groupBy(arr, key) {
    return arr.reduce(function (acc, item) {
      var k = typeof key === 'function' ? key(item) : item[key];
      (acc[k] = acc[k] || []).push(item); return acc;
    }, {});
  }
  function sum(arr, key) {
    return arr.reduce(function (a, x) { return a + (Number(typeof key === 'function' ? key(x) : x[key]) || 0); }, 0);
  }
  function sortBy(arr, key, dir) {
    var s = arr.slice(), d = dir === 'desc' ? -1 : 1;
    return s.sort(function (a, b) {
      var x = typeof key === 'function' ? key(a) : a[key];
      var y = typeof key === 'function' ? key(b) : b[key];
      if (x == null) return 1; if (y == null) return -1;
      if (typeof x === 'number' && typeof y === 'number') return (x - y) * d;
      return String(x).localeCompare(String(y), 'fr', { numeric: true }) * d;
    });
  }
  /** PRNG déterministe : les jeux de démonstration sont stables d'une session à l'autre. */
  function seeded(seed) {
    var s = seed || 42;
    return function () { s = (s * 9301 + 49297) % 233280; return s / 233280; };
  }
  function pick(rnd, arr) { return arr[Math.floor(rnd() * arr.length) % arr.length]; }
  function between(rnd, a, b) { return Math.floor(rnd() * (b - a + 1)) + a; }

  global.SIGH = global.SIGH || {};
  global.SIGH.core = {
    BRAND: BRAND, MOIS: MOIS, JOURS: JOURS,
    money: money, num: num, pct: pct, pad: pad,
    dateFR: dateFR, dateLong: dateLong, dateJour: dateJour, heure: heure, age: age,
    ageDe: ageDe, ageTexte: ageTexte, ageEstDeclare: ageEstDeclare,
    params: params, ancre: ancre,
    dateHeure: dateHeure, iso: iso, moisAnnee: moisAnnee, ilYA: ilYA,
    aujourdhui: aujourdhui, isoLocal: isoLocal,
    addDays: addDays, daysBetween: daysBetween, toDate: toDate,
    PERIODES: PERIODES, bornes: bornes, bornesLibres: bornesLibres,
    dansBornes: dansBornes, libellePeriode: libellePeriode,
    codePatient: codePatient, nextRef: nextRef, uid: uid,
    nombreEnLettres: nombreEnLettres, montantEnLettres: montantEnLettres,
    slug: slug, initials: initials, escapeHtml: escapeHtml, norm: norm, matches: matches,
    $: $, $$: $$, el: el, append: append, clear: clear, icon: icon, qr: qr,
    debounce: debounce, groupBy: groupBy, sum: sum, sortBy: sortBy,
    seeded: seeded, pick: pick, between: between,
  };
})(window);
