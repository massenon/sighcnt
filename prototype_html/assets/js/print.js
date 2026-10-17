/* =============================================================================
 * SIGH-CNT — Moteur d'impression des états officiels
 * -----------------------------------------------------------------------------
 * CDCT §4.2 / §21 — draf1 §10.14 « Modèle officiel des documents ».
 * Tout état édité reprend automatiquement le papier à en-tête de la clinique :
 * logo, dénomination, BP, téléphones, autorisation d'ouverture, IFU, RCCM,
 * e-mail ; et un pied de page normalisé : pagination, date/heure d'impression,
 * utilisateur générateur et identifiant unique du document.
 *
 * Parcours imposé : prévisualiser → imprimer / exporter PDF → archiver.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui;
  var el = C.el, B = C.BRAND;
  var compteur = 0;

  /* --- Racine d'impression ------------------------------------------------ */
  function root() {
    var r = document.getElementById('print-root');
    if (!r) {
      r = el('div#print-root');
      document.body.appendChild(r);
    }
    return r;
  }

  /** Chemin du logo, ajusté à la profondeur de la page courante. */
  function logoSrc() {
    var base = document.documentElement.getAttribute('data-root') || '';
    return base + B.logo;
  }

  /* ==========================================================================
   * EN-TÊTE OFFICIEL — reproduction fidèle du papier à en-tête
   * ======================================================================== */
  function entete() {
    var head = el('header.print-entete.border-b-\\[3px\\].border-navy-900.pb-2');
    var top = el('div.flex.items-center.justify-center.gap-4');

    top.appendChild(el('img.h-16.w-16.shrink-0.object-contain', {
      src: logoSrc(), alt: 'Logo ' + B.sigle,
      onerror: function () { this.style.visibility = 'hidden'; },
    }));

    var mid = el('div.text-center');
    mid.appendChild(el('p.text-\\[22px\\].font-bold.leading-tight.tracking-tight.text-navy-950', { text: 'CLINIQUE NASSIERA TOO' }));
    mid.appendChild(el('p.text-\\[10px\\].leading-snug.text-slate-700', {
      text: B.bp + '   TÉL. : ' + B.telephones.join('  /  '),
    }));
    mid.appendChild(el('p.text-\\[9px\\].leading-snug.text-slate-700', {
      text: 'AUTORISATION D’OUVERTURE ' + B.autorisation,
    }));
    mid.appendChild(el('p.text-\\[9px\\].font-semibold.leading-snug.text-slate-800', {
      text: 'IFU : ' + B.ifu + '   RCCM : ' + B.rccm,
    }));
    mid.appendChild(el('p.text-\\[9px\\].leading-snug.text-slate-700', { text: 'E-mail : ' + B.email }));
    /* La devise de la clinique, dictée par la Direction le 24/08/2026.
       Elle figure sur les états parce que c'est ce que le patient emporte
       chez lui — et qu'une devise qui ne se lit nulle part n'en est pas une. */
    mid.appendChild(el('p.text-\\[9px\\].font-semibold.italic.leading-snug.text-navy-800', { text: B.slogan }));
    top.appendChild(mid);

    top.appendChild(el('img.h-16.w-16.shrink-0.object-contain', {
      src: logoSrc(), alt: '',
      onerror: function () { this.style.visibility = 'hidden'; },
    }));

    head.appendChild(top);
    return head;
  }

  /* ==========================================================================
   * PIED DE PAGE NORMALISÉ
   * ======================================================================== */
  function pied(ref) {
    var f = el('footer.print-pied.mt-6.border-t.border-slate-300.pt-2');
    var row = el('div.flex.items-end.justify-between.gap-4.text-\\[8px\\].text-slate-500');
    row.appendChild(el('div', null, [
      el('p', { text: B.nom + ' — ' + B.rccm + ' — IFU ' + B.ifu }),
      el('p', { text: 'Document généré par ' + global.SIGH.store.currentUser() + ' le ' + C.dateHeure(new Date()) }),
    ]));
    row.appendChild(el('div.text-right', null, [
      el('p.font-mono', { text: 'Réf. document : ' + ref }),
      el('p', { text: 'Édité depuis le SIGH-CNT' }),
    ]));
    f.appendChild(row);
    return f;
  }

  /* ==========================================================================
   * BLOCS RÉUTILISABLES
   * ======================================================================== */
  /** Bloc de signatures — CDCT §10.4 (sortie : patient + infirmier + gardien). */
  function signatures(liste) {
    var grid = el('div.mt-8.grid.gap-6', { class: 'grid-cols-' + Math.min(liste.length, 4) });
    liste.forEach(function (s) {
      var box = el('div.text-center');
      box.appendChild(el('p.text-\\[10px\\].font-semibold.text-slate-700', { text: s.role }));
      if (s.nom) box.appendChild(el('p.text-\\[9px\\].text-slate-500', { text: s.nom }));
      box.appendChild(el('div.mx-auto.mt-10.w-full.border-b.border-dotted.border-slate-400'));
      box.appendChild(el('p.mt-1.text-\\[8px\\].text-slate-400', { text: s.mention || 'Signature' }));
      grid.appendChild(box);
    });
    return grid;
  }

  /** Tableau normalisé pour les états. */
  function tableau(colonnes, lignes, options) {
    var o = options || {};
    var t = el('table.w-full.border-collapse.text-\\[10px\\]');
    var thead = el('thead'), htr = el('tr');
    colonnes.forEach(function (c) {
      htr.appendChild(el('th.border.border-slate-400.bg-slate-100.px-2.py-1.text-left.font-semibold.text-slate-800', {
        class: c.align === 'right' ? 'text-right' : '', text: c.label,
      }));
    });
    thead.appendChild(htr); t.appendChild(thead);
    var tb = el('tbody');
    lignes.forEach(function (r) {
      var tr = el('tr');
      colonnes.forEach(function (c) {
        var v = typeof c.value === 'function' ? c.value(r) : r[c.key];
        tr.appendChild(el('td.border.border-slate-300.px-2.py-1.align-top', {
          class: c.align === 'right' ? 'text-right num' : '',
          text: v == null || v === '' ? '' : String(v),
        }));
      });
      tb.appendChild(tr);
    });
    t.appendChild(tb);
    /* Une colonne qui déclare `somme` fait totaliser les lignes RÉELLEMENT
       imprimées. C'est le seul moyen d'empêcher un total de diverger de son
       tableau : la somme n'est pas transmise, elle est refaite. */
    function sommeDe(c) {
      if (!c.somme) return null;
      var lire = typeof c.somme === 'function' ? c.somme
        : function (r) { return r[c.key]; };
      return lignes.reduce(function (n, r) {
        var v = lire(r);
        return n + (typeof v === 'number' && isFinite(v) ? v : 0);
      }, 0);
    }

    var colonnesSommees = colonnes.filter(function (c) { return c.somme; });
    /* `total: true` suffit dès qu'une colonne sait se totaliser : l'appelant
       n'a plus à recopier des montants qu'il aurait pu se tromper à calculer. */
    var afficherTotal = o.total === true ? colonnesSommees.length > 0 : !!o.total;

    if (afficherTotal) {
      var tf = el('tfoot'), ftr = el('tr');
      colonnes.forEach(function (c, i) {
        var texte = '';
        if (i === 0) {
          texte = o.totalLabel || 'TOTAL';
        } else if (c.somme) {
          var v = sommeDe(c);
          texte = c.formatTotal ? c.formatTotal(v) : C.money(v, false);
        } else if (o.total && o.total !== true && o.total[c.key] != null) {
          /* Mention de pied qui n'est pas une somme : solde reporté, renvoi
             réglementaire. Elle reste possible et prime sur le vide. */
          texte = o.total[c.key];
        }
        ftr.appendChild(el('td.border.border-slate-400.bg-slate-50.px-2.py-1.font-bold', {
          class: c.align === 'right' ? 'text-right num' : '',
          text: texte,
        }));
      });
      tf.appendChild(ftr); t.appendChild(tf);
    }
    return t;
  }

  /* ==========================================================================
   * LES FILTRES EN FORCE, RELEVÉS SUR LA PAGE
   * --------------------------------------------------------------------------
   * Un état imprimé depuis un écran filtré ne montre qu'une PARTIE des
   * données, et rien ne le disait : deux tirages du même état, à deux minutes
   * d'intervalle et sur deux filtres différents, sortaient identiques de
   * présentation et différents de contenu. Impossible, une semaine plus tard,
   * de savoir lequel disait quoi.
   *
   * Le relevé est fait SUR LA PAGE plutôt que déclaré par chaque appelant :
   * il y a plus de cent trente états imprimés, et un mécanisme qu'il faut
   * penser à câbler cent trente fois est un mécanisme qui manquera quelque
   * part. On lit donc les commandes de filtre réellement affichées — listes,
   * dates, recherche — et l'on ne retient que celles qui portent une valeur.
   *
   * Les modales et les tiroirs vivent hors de `#page-content` : leurs champs
   * de saisie ne sont pas des filtres et ne doivent pas paraître ici.
   * ======================================================================== */
  function libelleDuChamp(ctrl) {
    if (ctrl.id) {
      var lab = document.querySelector('label[for="' + ctrl.id + '"]');
      if (lab && lab.textContent.trim()) return lab.textContent.trim();
    }
    var wrap = ctrl.closest ? ctrl.closest('div') : null;
    for (var i = 0; wrap && i < 3; i++) {
      var l = wrap.querySelector('label');
      if (l && l.textContent.trim()) return l.textContent.trim();
      wrap = wrap.parentElement;
    }
    var aria = ctrl.getAttribute('aria-label');
    if (aria) return aria;
    if (ctrl.tagName === 'SELECT' && ctrl.options.length) return ctrl.options[0].textContent.trim();
    return ctrl.getAttribute('placeholder') || 'Filtre';
  }

  function filtresDeLaPage() {
    var hote = document.getElementById('page-content');
    if (!hote) return [];
    var out = [];
    var vus = {};
    function ajouter(label, valeur) {
      var cle = label + '=' + valeur;
      if (!label || !valeur || vus[cle]) return;
      vus[cle] = true;
      out.push([label, valeur]);
    }
    /* Une commande masquée (onglet non affiché) n'est pas un filtre en force. */
    function visible(x) { return x.offsetParent !== null || x.getClientRects().length > 0; }

    Array.prototype.forEach.call(hote.querySelectorAll('select'), function (sel) {
      if (!visible(sel) || !sel.value) return;
      var opt = sel.options[sel.selectedIndex];
      ajouter(libelleDuChamp(sel), opt ? opt.textContent.trim() : sel.value);
    });
    Array.prototype.forEach.call(hote.querySelectorAll('input[type="date"]'), function (inp) {
      if (!visible(inp) || !inp.value) return;
      ajouter(libelleDuChamp(inp), C.dateFR(inp.value));
    });
    Array.prototype.forEach.call(hote.querySelectorAll('input[type="search"]'), function (inp) {
      if (!visible(inp) || !String(inp.value).trim()) return;
      ajouter('Recherche', String(inp.value).trim());
    });
    /* La liste déroulante à recherche n'est pas un <select> : elle expose sa
       valeur et son libellé sur le bouton qui la déclenche. */
    Array.prototype.forEach.call(hote.querySelectorAll('.combo'), function (cb) {
      if (!visible(cb) || !cb.value || (Array.isArray(cb.value) && !cb.value.length)) return;
      var btn = cb.querySelector('.combo-input');
      var texte = btn ? btn.textContent.trim() : String(cb.value);
      if (/^—/.test(texte)) return; /* « — Sélectionner — » n'est pas un choix */
      ajouter(libelleDuChamp(cb), texte);
    });
    return out;
  }

  /** Cartouche « informations » à deux colonnes. */
  function cartouche(pairs) {
    var box = el('div.mb-4.grid.grid-cols-2.gap-x-8.gap-y-1.rounded.border.border-slate-300.bg-slate-50.px-3.py-2.text-\\[10px\\]');
    pairs.forEach(function (p) {
      if (!p) return;
      var row = el('div.flex.gap-2');
      row.appendChild(el('span.shrink-0.font-semibold.text-slate-600', { text: p[0] + ' :' }));
      row.appendChild(el('span.text-slate-800', { text: p[1] == null || p[1] === '' ? '—' : String(p[1]) }));
      box.appendChild(row);
    });
    return box;
  }

  /* ==========================================================================
   * COMPOSITION ET PRÉVISUALISATION DE L'ÉTAT
   * ======================================================================== */
  /**
   * etat({ titre, sousTitre, contenu, cartouche, signatures, filigrane, lieuDate })
   * Affiche la prévisualisation ; l'impression (ou « Enregistrer en PDF » du
   * navigateur) est déclenchée depuis la barre d'action.
   */
  function etat(options) {
    var o = Object.assign({
      titre: 'État', sousTitre: null, contenu: null, cartouche: null,
      signatures: null, filigrane: null, lieuDate: true, archive: true,
    }, options);

    compteur++;
    var ref = 'CNT-' + C.iso(new Date()).replace(/-/g, '') + '-' + C.pad(compteur, 4);

    /* --- Feuille A4 --- */
    var sheet = el('article.print-sheet.relative.mx-auto.bg-white.text-slate-900', {
      style: 'width:210mm;min-height:297mm;padding:12mm;box-sizing:border-box;',
    });

    if (o.filigrane) {
      sheet.appendChild(el('div.pointer-events-none.absolute.inset-0.grid.place-items-center', null,
        el('span.select-none.text-\\[70px\\].font-bold.uppercase.tracking-widest.text-slate-900\\/5', {
          style: 'transform:rotate(-35deg);', text: o.filigrane,
        })));
    }

    var inner = el('div.relative.flex.min-h-full.flex-col');
    inner.appendChild(entete());

    var titleBlock = el('div.my-4.text-center');
    titleBlock.appendChild(el('h1.inline-block.border-b-2.border-navy-900.px-6.pb-1.text-\\[15px\\].font-bold.uppercase.tracking-wide.text-navy-950', { text: o.titre }));
    if (o.sousTitre) titleBlock.appendChild(el('p.mt-1.text-\\[10px\\].text-slate-600', { text: o.sousTitre }));
    inner.appendChild(titleBlock);

    if (o.cartouche) inner.appendChild(cartouche(o.cartouche));

    /* LES FILTRES EN FORCE, SUR LA PIÈCE. `filtres: false` les retire — un
       état qui ne dépend d'aucun écran filtré (un certificat, une facture)
       n'a pas à porter la liste déroulante qui traînait sur la page. */
    if (o.filtres !== false) {
      var appliques = o.filtres && o.filtres.length ? o.filtres : filtresDeLaPage();
      if (appliques.length) {
        var boite = el('div.mb-4.rounded.border.border-slate-300.bg-white.px-3.py-2.text-\\[10px\\]');
        boite.appendChild(el('p.mb-1.font-semibold.uppercase.tracking-wide.text-slate-600',
          { text: 'Filtres appliqués à cet état' }));
        var liste = el('div.flex.flex-wrap.gap-x-4.gap-y-1');
        appliques.forEach(function (f) {
          liste.appendChild(el('span.text-slate-800', null, [
            el('span.font-semibold', { text: f[0] + ' : ' }),
            el('span', { text: String(f[1]) }),
          ]));
        });
        boite.appendChild(liste);
        boite.appendChild(el('p.mt-1.italic.text-slate-500', {
          text: 'L’état ne porte que les enregistrements retenus par ces filtres.',
        }));
        inner.appendChild(boite);
      }
    }

    var body = el('div.flex-1.text-\\[10px\\].leading-relaxed');
    C.append(body, o.contenu);
    inner.appendChild(body);

    if (o.lieuDate) {
      inner.appendChild(el('p.mt-6.text-right.text-\\[10px\\].italic.text-slate-700', {
        text: 'Fait à Natitingou, le ' + C.dateLong(new Date()),
      }));
    }
    if (o.signatures) inner.appendChild(signatures(o.signatures));
    inner.appendChild(pied(ref));
    sheet.appendChild(inner);

    return afficher(sheet, o.titre, ref, false, o.archive);
  }

  /* --------------------------------------------------------------------------
   * Prévisualisation commune au A4 et au rouleau : la feuille vit dans
   * #print-root — seul élément imprimable — et s'affiche dans une surcouche.
   * ----------------------------------------------------------------------- */
  function afficher(sheet, titre, ref, etroit, archivable) {
    /* --- Prévisualisation --- */
    var host = root();
    C.clear(host);
    host.appendChild(sheet);

    var overlay = el('div.print-chrome.fixed.inset-0.z-\\[70\\].flex.flex-col.bg-slate-800\\/80.no-print');
    var bar = el('div.flex.flex-wrap.items-center.gap-2.border-b.border-slate-700.bg-slate-900.px-4.py-2.5');
    bar.appendChild(el('span.mr-auto.flex.items-center.gap-2.text-sm.font-medium.text-white', null, [
      C.icon('file-text', 'h-4 w-4'), titre,
    ]));
    bar.appendChild(el('span.hidden.text-xs.text-slate-400.sm\\:block', { text: 'Réf. ' + ref }));
    bar.appendChild(el('button.btn.btn-sm.btn-secondary', {
      type: 'button',
      onclick: function () { U.exportCSV ? imprimer() : imprimer(); },
    }, [C.icon('printer', 'h-4 w-4'), 'Imprimer / Enregistrer en PDF']));
    if (archivable !== false) {
      bar.appendChild(el('button.btn.btn-sm.btn-secondary', {
        type: 'button',
        onclick: function () {
          global.SIGH.store.log('Impression', 'RAP', 'Document', ref, null, { titre: titre });
          U.toast('Document archivé dans la GED.', { type: 'success', detail: 'Réf. ' + ref });
        },
      }, [C.icon('archive', 'h-4 w-4'), 'Archiver']));
    }
    bar.appendChild(el('button.btn.btn-sm.btn-primary', { type: 'button', onclick: fermer }, [C.icon('x', 'h-4 w-4'), 'Fermer']));
    overlay.appendChild(bar);

    var scroll = el('div.flex-1.overflow-auto.p-6');
    /* Trois gabarits cohabitent : le A4 des états, le rouleau 80 mm de la
       caisse et la carte CR80 des badges. Une largeur passée en toutes
       lettres suffit à en ajouter un quatrième sans toucher à ce cadre. */
    var largeurCadre = typeof etroit === 'string' ? etroit : (etroit ? '80mm' : '210mm');
    var frame = el('div.mx-auto.shadow-pop', { style: 'width:' + largeurCadre + ';' });
    scroll.appendChild(frame);
    overlay.appendChild(scroll);
    document.body.appendChild(overlay);
    document.body.style.overflow = 'hidden';

    /* La feuille vit dans #print-root (imprimable) et est affichée dans l'overlay. */
    frame.appendChild(sheet);
    U.icons(overlay);

    function imprimer() {
      /* On replace la feuille dans #print-root le temps de l'impression. */
      host.appendChild(sheet);
      document.body.classList.add('printing');
      var restore = function () {
        document.body.classList.remove('printing');
        frame.appendChild(sheet);
        global.removeEventListener('afterprint', restore);
      };
      global.addEventListener('afterprint', restore);
      global.print();
      setTimeout(restore, 1500);
    }
    function fermer() {
      overlay.remove();
      C.clear(host);
      document.body.style.overflow = '';
    }

    document.addEventListener('keydown', function esc(e) {
      if (e.key === 'Escape' && document.body.contains(overlay)) { fermer(); document.removeEventListener('keydown', esc); }
    });

    return { ref: ref, imprimer: imprimer, fermer: fermer, sheet: sheet };
  }

  /* ==========================================================================
   * TICKET DE CAISSE — gabarit rouleau
   * --------------------------------------------------------------------------
   * Relevé sur le ticket n° 22118 réellement émis par la clinique : rouleau
   * étroit, bloc MECeF, OPÉRATEUR, TYPE VENTE, ASSUREUR, ASSURÉ, lignes,
   * montant total, montant en lettres, puis PART ASSUREUR / PART ASSURÉ.
   * Le A4 ne convient pas ici : la caisse imprime sur une bande de 80 mm.
   * ======================================================================== */
  function ticket(o) {
    o = o || {};
    compteur++;
    var ref = 'CNT-' + C.iso(new Date()).replace(/-/g, '') + '-' + C.pad(compteur, 4);

    var sheet = el('article.print-sheet.mx-auto.bg-white.text-slate-900', {
      style: 'width:80mm;padding:4mm;box-sizing:border-box;font-family:ui-monospace,Menlo,Consolas,monospace;',
    });

    function ligneTexte(texte, classe) {
      return el('p', { class: classe || 'text-[9px] leading-snug', text: texte });
    }
    function separateur() {
      return el('p.my-1.text-\\[9px\\].leading-none.text-slate-400', { text: '--------------------------------' });
    }
    function paire(g, d, gras) {
      return el('div.flex.justify-between.gap-2', { class: gras ? 'font-bold' : '' }, [
        el('span.text-\\[9px\\]', { text: g }),
        el('span.text-\\[9px\\].text-right', { text: d }),
      ]);
    }

    /* En-tête de la clinique, resserré */
    sheet.appendChild(el('p.text-center.text-\\[11px\\].font-bold.leading-tight', { text: 'CLINIQUE NASSIERA TOO' }));
    sheet.appendChild(ligneTexte(B.bp, 'text-[8px] text-center leading-snug'));
    sheet.appendChild(ligneTexte('TÉL. ' + B.telephones.join(' / '), 'text-[8px] text-center leading-snug'));
    sheet.appendChild(ligneTexte('IFU ' + B.ifu, 'text-[8px] text-center leading-snug'));
    /* Les pièces de caisse portent l'autre RCCM (voir core.js). */
    sheet.appendChild(ligneTexte('RCCM ' + B.rccm, 'text-[8px] text-center leading-snug'));
    sheet.appendChild(separateur());

    /* Bloc MECeF — structure du ticket réel */
    if (o.mecef) {
      sheet.appendChild(el('div.flex.items-start.gap-2', null, [
        el('div.shrink-0.border.border-slate-800', {
          style: 'width:18mm;height:18mm;background:repeating-conic-gradient(#0f172a 0% 25%, #ffffff 0% 50%) 0 0/3mm 3mm;',
          title: 'Code QR MECeF',
        }),
        el('div.min-w-0.flex-1', null, [
          ligneTexte('NIM : ' + (o.mecef.nim || '—'), 'text-[8px] leading-snug'),
          ligneTexte('CODE DGI : ' + (o.mecef.code || '—'), 'text-[8px] leading-snug break-all'),
          ligneTexte('CPT : ' + (o.mecef.compteurs || '—'), 'text-[8px] leading-snug'),
          ligneTexte('HEURE : ' + (o.mecef.heure || C.heure(new Date().toISOString())), 'text-[8px] leading-snug'),
        ]),
      ]));
      sheet.appendChild(separateur());
    }

    sheet.appendChild(paire('OPÉRATEUR', o.operateur || S().currentUser()));
    sheet.appendChild(paire('TYPE VENTE', o.typeVente || 'COMPTANT'));
    if (o.assureur) sheet.appendChild(paire('ASSUREUR', o.assureur));
    if (o.assure) sheet.appendChild(paire('ASSURÉ', o.assure));
    /* L'opération de caisse est DISSOCIÉE du dossier patient : une vente au
       comptoir — un carnet, un certificat — n'oblige pas à ouvrir un dossier.
       La pièce le dit plutôt que de laisser une ligne vide, qui se lirait
       comme un oubli de saisie. */
    sheet.appendChild(paire('DOSSIER', o.dossier || 'VENTE AU COMPTOIR — sans dossier'));
    sheet.appendChild(paire('N° PIÈCE', o.numero || ref));
    sheet.appendChild(paire('DATE', C.dateFR(o.date || new Date()) + ' ' + C.heure(o.date || new Date().toISOString())));
    sheet.appendChild(separateur());

    (o.lignes || []).forEach(function (l) {
      sheet.appendChild(ligneTexte(l.designation, 'text-[9px] leading-snug'));
      sheet.appendChild(paire(
        '  ' + C.num(l.quantite) + ' x ' + C.money(l.prixUnitaire, false),
        C.money(l.montant, false)));
    });
    sheet.appendChild(separateur());

    sheet.appendChild(paire('MONTANT TOTAL', C.money(o.total || 0, false), true));
    if (o.remise) sheet.appendChild(paire('REMISE', '- ' + C.money(o.remise, false)));
    if (o.partAssureur) sheet.appendChild(paire('PART ASSUREUR', C.money(o.partAssureur, false)));
    /* La PART NON ASSURÉE se distingue de la part assuré : elle porte les
       lignes qu'AUCUNE compagnie ne couvre. C'est elle qui explique au guichet
       pourquoi un assuré règle intégralement certaines prestations. */
    if (o.partNonAssuree) {
      sheet.appendChild(paire('DONT PART NON ASSURÉE', C.money(o.partNonAssuree, false)));
    }
    sheet.appendChild(paire(o.assureur ? 'PART ASSURÉ' : 'NET À PAYER', C.money(o.partPatient || 0, false), true));
    if (o.regle != null) sheet.appendChild(paire('RÉGLÉ', C.money(o.regle, false)));
    if (o.rendu) sheet.appendChild(paire('RENDU', C.money(o.rendu, false)));
    /* Le TOTAL DÛ est ce qui reste après le versement. Sur un règlement
       partiel — que la caisse pratique — son absence laissait le patient
       repartir sans savoir ce qu'il devait encore. */
    var duRestant = o.reste != null ? o.reste
      : (o.regle != null ? Math.max(0, (o.partPatient || 0) - o.regle) : null);
    if (duRestant != null) {
      sheet.appendChild(paire('TOTAL DÛ', C.money(duRestant, false), true));
    }
    /* La base MECeF est portée sur la pièce : le cahier de charge exige que la
       facture normalisée ne porte QUE ce que le patient règle — ni la part
       assureur, ni les remises. L'imprimer permet de le vérifier sans ouvrir
       le logiciel. */
    if (o.baseMecef != null) {
      sheet.appendChild(paire('BASE MECeF', C.money(o.baseMecef, false)));
    }

    sheet.appendChild(separateur());
    sheet.appendChild(ligneTexte(B.formuleArrete + ' :', 'text-[8px] leading-snug'));
    sheet.appendChild(ligneTexte(C.montantEnLettres(o.partPatient || 0), 'text-[8px] font-semibold leading-snug'));
    sheet.appendChild(separateur());
    sheet.appendChild(ligneTexte(B.formulePolitesse, 'text-[9px] font-bold text-center leading-snug'));
    sheet.appendChild(ligneTexte('Réf. ' + ref, 'text-[7px] text-center text-slate-400 mt-1'));

    afficher(sheet, o.titre || 'Ticket de caisse', ref, true);
    return ref;
  }

  /* ==========================================================================
   * BADGE DU PERSONNEL — troisième gabarit : la carte CR80
   * --------------------------------------------------------------------------
   * 85,6 × 54 mm : le format des imprimantes à cartes et des porte-badges du
   * commerce. Ni A4, ni rouleau — un badge composé en A4 puis découpé au juge
   * ne rentre dans aucun porte-badge.
   *
   * L'EN-TÊTE OFFICIEL NE S'APPLIQUE PAS TEL QUEL. Un badge n'est pas un état
   * administratif : il porte le logo, la dénomination et la devise ; l'IFU et
   * le RCCM n'ont rien à y faire — ce sont des mentions FISCALES, destinées à
   * une pièce comptable, pas à une carte qu'on accroche à une blouse.
   *
   * AUCUNE COULEUR EN DUR : les classes viennent du design system (navy-*).
   * Changer la charte de l'établissement — c'est ce que fait la dérivation
   * vers une autre clinique — change le badge sans qu'on y retouche.
   * ======================================================================== */
  var CR80 = { largeur: 85.6, hauteur: 54 };

  function mm(v) { return v + 'mm'; }

  /** Une face de carte. `face` vaut 'recto' ou 'verso'. */
  function carteBadge(o, face) {
    var m = o.modele || {};
    var zones = m.zones || {};
    var portrait = m.orientation === 'portrait';
    var L = portrait ? CR80.hauteur : CR80.largeur;
    var H = portrait ? CR80.largeur : CR80.hauteur;

    var carte = el('div.relative.overflow-hidden.bg-white.text-slate-900', {
      style: 'width:' + mm(L) + ';height:' + mm(H) + ';box-sizing:border-box;'
        + 'border:0.2mm solid #cbd5e1;border-radius:2.5mm;',
    });

    if (face === 'verso') {
      var dos = el('div.flex.h-full.flex-col.px-3.py-2');
      dos.appendChild(el('p.text-\\[7px\\].font-bold.uppercase.tracking-wide.text-navy-900',
        { text: B.nom }));
      dos.appendChild(el('div.mt-1.border-t.border-slate-200'));
      var mentions = el('div.mt-1.flex-1.space-y-0\\.5');
      (m.mentionsVerso || []).forEach(function (t) {
        mentions.appendChild(el('p.text-\\[6px\\].leading-snug.text-slate-600', { text: t }));
      });
      dos.appendChild(mentions);
      dos.appendChild(el('div.flex.items-end.justify-between.gap-2', null, [
        el('div', null, [
          el('p.text-\\[6px\\].text-slate-500', { text: 'N° de série' }),
          el('p.font-mono.text-\\[7px\\].font-bold.text-slate-800', { text: o.badge.numero || '—' }),
        ]),
        el('div.text-right', null, [
          el('p.text-\\[6px\\].text-slate-500', { text: 'Valable jusqu’au' }),
          el('p.text-\\[7px\\].font-bold.text-slate-800', {
            text: o.badge.expireLe ? C.dateFR(o.badge.expireLe) : 'non fixée',
          }),
        ]),
      ]));
      dos.appendChild(el('p.mt-1.text-center.text-\\[6px\\].italic.text-navy-800', { text: B.slogan }));
      carte.appendChild(dos);
      return carte;
    }

    /* --- Recto --- */
    var bandeau = el('div.flex.items-center.gap-1\\.5.bg-navy-900.px-2.py-1', {
      style: 'height:11mm;',
    });
    bandeau.appendChild(el('img.h-7.w-7.shrink-0.rounded.bg-white.object-contain', {
      src: logoSrc(), alt: '', onerror: function () { this.style.visibility = 'hidden'; },
    }));
    bandeau.appendChild(el('div.min-w-0.flex-1', null, [
      el('p.truncate.text-\\[8px\\].font-bold.uppercase.leading-tight.text-white', { text: 'Clinique Nassiera Too' }),
      el('p.truncate.text-\\[6px\\].italic.leading-tight.text-navy-100', { text: B.slogan }),
    ]));
    carte.appendChild(bandeau);

    var corps = el('div.flex.gap-2.px-2.py-1\\.5', { style: 'height:' + mm(H - 11) + ';' });

    if (zones.photo !== false) {
      var cadrePhoto = el('div.shrink-0.overflow-hidden.rounded.border.border-slate-300.bg-slate-100', {
        style: 'width:20mm;height:26mm;',
      });
      if (o.badge.photo) {
        cadrePhoto.appendChild(el('img.h-full.w-full.object-cover', { src: o.badge.photo, alt: '' }));
      } else {
        /* Une photo manquante SE DIT : un cadre vide se lirait comme un
           défaut d'impression, et le badge partirait tel quel. */
        cadrePhoto.appendChild(el('div.flex.h-full.w-full.flex-col.items-center.justify-center.text-center', null, [
          el('p.text-\\[6px\\].leading-tight.text-slate-400', { text: 'PHOTO' }),
          el('p.text-\\[6px\\].leading-tight.text-slate-400', { text: 'À COLLER' }),
        ]));
      }
      corps.appendChild(cadrePhoto);
    }

    var infos = el('div.min-w-0.flex-1.flex.flex-col');
    if (zones.nom !== false) {
      infos.appendChild(el('p.truncate.text-\\[11px\\].font-bold.uppercase.leading-tight.text-navy-950',
        { text: o.agent ? o.agent.nomComplet : (o.badge.agent || '—') }));
    }
    if (zones.fonction !== false) {
      infos.appendChild(el('p.text-\\[7px\\].font-semibold.leading-tight.text-navy-700',
        { text: o.badge.poste || (o.agent ? o.agent.poste : '') || '—' }));
    }
    if (zones.service !== false) {
      infos.appendChild(el('p.text-\\[7px\\].leading-tight.text-slate-600',
        { text: 'Service : ' + (o.badge.service || (o.agent ? o.agent.service : '') || '—') }));
    }
    infos.appendChild(el('p.mt-0\\.5.font-mono.text-\\[7px\\].leading-tight.text-slate-700',
      { text: 'Matricule ' + (o.badge.matricule || '—') }));
    infos.appendChild(el('div.flex-1'));
    infos.appendChild(el('p.font-mono.text-\\[6px\\].leading-tight.text-slate-500',
      { text: o.badge.numero || '' }));
    corps.appendChild(infos);

    if (zones.qr !== false) {
      var bloc = el('div.flex.shrink-0.flex-col.items-center.justify-end');
      bloc.appendChild(C.qr(PR().badgeQR(o.badge), { taille: '17mm', marge: 2, alt: 'Code du badge' }));
      bloc.appendChild(el('p.mt-0\\.5.text-\\[5px\\].text-slate-400', { text: 'Contrôle SIGH' }));
      corps.appendChild(bloc);
    }
    carte.appendChild(corps);
    return carte;
  }

  function PR() { return global.SIGH.parcours; }

  /**
   * badge({ badge, agent, modele }) — une carte, recto et verso côte à côte.
   * L'aperçu est commun aux trois gabarits : c'est la même barre d'action.
   */
  function badge(o) {
    compteur++;
    var ref = 'CNT-' + C.iso(new Date()).replace(/-/g, '') + '-' + C.pad(compteur, 4);
    var portrait = (o.modele || {}).orientation === 'portrait';
    var L = portrait ? CR80.hauteur : CR80.largeur;

    var sheet = el('article.print-sheet.mx-auto.bg-white', {
      style: 'width:' + mm(L + 8) + ';padding:4mm;box-sizing:border-box;',
    });
    sheet.appendChild(el('p.mb-1.text-\\[7px\\].uppercase.tracking-wide.text-slate-400', { text: 'Recto' }));
    sheet.appendChild(carteBadge(o, 'recto'));
    sheet.appendChild(el('p.mb-1.mt-3.text-\\[7px\\].uppercase.tracking-wide.text-slate-400', { text: 'Verso' }));
    sheet.appendChild(carteBadge(o, 'verso'));
    sheet.appendChild(el('p.mt-2.text-\\[6px\\].text-slate-400', {
      text: 'Réf. ' + ref + ' — ' + global.SIGH.store.currentUser() + ' — ' + C.dateHeure(new Date()),
    }));
    afficher(sheet, 'Badge — ' + (o.badge.agent || ''), ref, mm(L + 8));
    return ref;
  }

  /**
   * planche({ badges, modele }) — la feuille A4 pour les cliniques SANS
   * imprimante à cartes : dix badges par feuille, avec des repères de découpe.
   * Le pied normalisé (date, utilisateur, identifiant) va sur la PLANCHE et
   * non sur les cartes : un badge n'a pas à porter l'heure de son impression.
   */
  function planche(o) {
    compteur++;
    var ref = 'CNT-' + C.iso(new Date()).replace(/-/g, '') + '-' + C.pad(compteur, 4);
    var sheet = el('article.print-sheet.mx-auto.bg-white.text-slate-900', {
      style: 'width:210mm;min-height:297mm;padding:12mm;box-sizing:border-box;',
    });
    var inner = el('div.flex.min-h-full.flex-col');
    inner.appendChild(el('p.mb-2.text-\\[10px\\].font-semibold.uppercase.tracking-wide.text-navy-900', {
      text: 'Planche de badges — ' + C.num((o.badges || []).length) + ' carte(s)',
    }));
    var grille = el('div.flex.flex-wrap', { style: 'gap:0;' });
    (o.badges || []).forEach(function (b) {
      var cellule = el('div.relative', { style: 'padding:1.5mm;' });
      /* Repères de découpe : quatre traits d'angle, hors de la carte. */
      ['top:0;left:0;border-top:0.2mm solid #94a3b8;border-left:0.2mm solid #94a3b8;',
        'top:0;right:0;border-top:0.2mm solid #94a3b8;border-right:0.2mm solid #94a3b8;',
        'bottom:0;left:0;border-bottom:0.2mm solid #94a3b8;border-left:0.2mm solid #94a3b8;',
        'bottom:0;right:0;border-bottom:0.2mm solid #94a3b8;border-right:0.2mm solid #94a3b8;',
      ].forEach(function (coin) {
        cellule.appendChild(el('span.absolute', { style: 'width:3mm;height:3mm;' + coin }));
      });
      cellule.appendChild(carteBadge({ badge: b.badge, agent: b.agent, modele: o.modele }, 'recto'));
      grille.appendChild(cellule);
    });
    inner.appendChild(grille);
    inner.appendChild(el('div.flex-1'));
    inner.appendChild(pied(ref));
    sheet.appendChild(inner);
    afficher(sheet, 'Planche de badges', ref, false);
    return ref;
  }

  function S() { return global.SIGH.store; }

  global.SIGH.print = {
    etat: etat, entete: entete, pied: pied, ticket: ticket,
    tableau: tableau, cartouche: cartouche, signatures: signatures,
    filtresDeLaPage: filtresDeLaPage,
    badge: badge, planche: planche, carteBadge: carteBadge, CR80: CR80,
  };
})(window);
