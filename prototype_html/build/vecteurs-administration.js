/* =============================================================================
 * VECTEURS DE M13 — m13-courriers, m13-reunions, m13-evenements, m13-plan-annuel, m13-notes-service, m13-ambulance,
 * m13-repertoire-ambulances, m13-maintenance
 * -----------------------------------------------------------------------------
 * Les huit écrans RÉELS sont montés dans Chrome sur un magasin dont on pose les fiches, à une HORLOGE FIGÉE (30/10/2026 10:00), puis LUS comme
 * l'agent les lit (indicateurs, onglets, tableaux, cartes, boutons) et PILOTÉS (modales de création, de modification, d'archivage, impressions).
 *   node build/vecteurs-administration.js   →   packages/domaine/test/vecteurs/administration.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

/** Les deux notes de service (D.NS131, D.NS132) et les fonctions du barème de primes, ENGENDRÉES en Dart : jamais recopiées à la main. */
function ecrireDartNotes(n) {
  const q = (v) => (typeof v === 'string' ? "'" + v.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$') + "'" : String(v));
  let d = '// ENGENDRÉ par prototype_html/build/vecteurs-administration.js — NE PAS ÉDITER. Notes de service NS 131 et NS 132 (D.NS131, D.NS132 de la maquette),\n'
    + '// telles que `m13-notes-service` les affiche.\n\n'
    + '/// NS 131 : critères d’évaluation et sanctions (en %) aux niveaux « moyenne » et « faible à mauvaise ».\n'
    + 'class AdmCritereEvaluation {\n  const AdmCritereEvaluation(this.numero, this.id, this.libelle, this.moyenne, this.faible);\n  final String numero;\n  final String id;\n  final String libelle;\n  final num moyenne;\n  final num faible;\n}\n\n'
    + '/// NS 132 : une prime, son mode (`fixe` = forfait mensuel, `occurrence`) et les fonctions concernées (montants en FCFA).\n'
    + 'class AdmPrime {\n  const AdmPrime(this.id, this.libelle, this.mode, this.montants);\n  final String id;\n  final String libelle;\n  final String mode;\n  final Map<String, num> montants;\n}\n\n'
    + '/// Identité d’une note de service (`D.NS131` / `D.NS132`).\n'
    + 'class AdmNoteService {\n  const AdmNoteService({required this.reference, required this.objet, required this.version, required this.dateSignature, required this.dateEffet, required this.statut, required this.signataire, required this.source, required this.mention});\n'
    + '  final String reference;\n  final String objet;\n  final int version;\n  final String dateSignature;\n  final String dateEffet;\n  final String statut;\n  final String signataire;\n  final String source;\n  final String mention;\n}\n\n';
  const note = (nom, x) => `const AdmNoteService ${nom} = AdmNoteService(\n  reference: ${q(x.reference)},\n  objet: ${q(x.objet)},\n  version: ${x.version},\n  dateSignature: ${q(x.dateSignature)},\n  dateEffet: ${q(x.dateEffet)},\n  statut: ${q(x.statut)},\n  signataire: ${q(x.signataire)},\n  source: ${q(x.source)},\n  mention: ${q(x.mention)},\n);\n\n`;
  d += note('admNs131', n.ns131) + note('admNs132', n.ns132);
  d += 'const List<AdmCritereEvaluation> admCriteresNs131 = [\n' + n.ns131.criteres.map((c) => `  AdmCritereEvaluation(${q(c.num)}, ${q(c.id)}, ${q(c.label)}, ${c.sanctions.moyenne}, ${c.sanctions.faible}),`).join('\n') + '\n];\n\n';
  d += 'const List<AdmPrime> admPrimesNs132 = [\n' + n.ns132.primes.map((p) => `  AdmPrime(${q(p.id)}, ${q(p.label)}, ${q(p.mode)}, {${Object.entries(p.montants).map(([k, v]) => q(k) + ': ' + v).join(', ')}}),`).join('\n') + '\n];\n\n';
  d += '/// `D.FONCTIONS` : identifiant → libellé (la carte de la NS 132 n’en affiche que le premier mot).\nconst Map<String, String> admFonctions = {\n' + n.fonctions.map((f) => `  ${q(f.id)}: ${q(f.label)},`).join('\n') + '\n};\n';
  const fs = require('fs');
  const dir = path.join(ROOT, '..', 'packages', 'domaine', 'lib', 'src', 'administration');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'adm_notes_donnees.dart'), d);
  console.log('  écrit : packages/domaine/lib/src/administration/adm_notes_donnees.dart');
}

(async () => {
  console.log('▶ Vecteurs de M13 (administration, ambulance, parc technique)');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Vrai = Date;
      window.__FIXE = new Vrai(2026, 9, 30, 10, 0, 0).getTime(); window.__Vrai = Vrai;
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(window.__FIXE); else super(...a); } static now() { return window.__FIXE; } }
      window.Date = Faux;
      SIGH.core.aujourdhui = () => new Faux();
      window.__etats = []; window.__erreurs = []; window.addEventListener('error', (e) => window.__erreurs.push(String(e.message)));
      const setTimeoutReel = window.setTimeout.bind(window);
      window.setTimeout = (fn, ms, ...a) => (String(fn).includes('location.reload') ? 0 : setTimeoutReel(fn, ms, ...a));
      SIGH.ui.sonner = () => {};
      window.__alertes = [];
      SIGH.ui.alerter = (msg, o) => { window.__alertes.push({ message: msg, type: (o || {}).type || null, son: (o || {}).son || null }); return { close() {} }; };
      SIGH.print.etat = function (o) {
        const tab = [];
        const c = o.contenu;
        if (c && c.querySelectorAll) {
          c.querySelectorAll('table').forEach((t) => tab.push({
            entetes: [...t.querySelectorAll('thead th')].map((x) => x.innerText.replace(/\s+/g, ' ').trim()),
            lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
            pied: [...t.querySelectorAll('tfoot tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
          }));
        }
        window.__etats.push(JSON.parse(JSON.stringify({
          titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null,
          texte: c && c.innerText ? c.innerText.replace(/\s+/g, ' ').trim() : null, tableaux: tab,
        })));
      };
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m13-administration.js') });

    await m.page.evaluate(() => {
      const norm = (t) => String(t == null ? '' : t).replace(/[\n\t\r]+/g, ' ').replace(/\s+/g, ' ').trim();
      window.H = {
        norm,
        propre: (x) => JSON.parse(JSON.stringify(x === undefined ? null : x)),
        dormir: (ms) => new Promise((r) => setTimeout(r, ms)),
        net: (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return JSON.parse(JSON.stringify(c)); },
        kpis: (root) => [...root.querySelectorAll('.kpi')].map((k) => {
          const p = k.querySelectorAll('p');
          return { libelle: norm(p[0].innerText), valeur: norm(p[1].innerText), indice: p[2] ? norm(p[2].innerText) : null };
        }),
        tableaux: (root) => [...root.querySelectorAll('table')].map((t) => ({
          entetes: [...t.querySelectorAll('thead th')].map((x) => norm(x.innerText)).filter((s) => s !== ''),
          lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.innerText)).filter((s, i) => i > 0 || s !== '')),
        })),
        cartes: (root) => [...root.querySelectorAll('.card')].map((c) => {
          const h = c.querySelector('.card-header, .card-head, h3, h2');
          return h ? norm(h.innerText) : null;
        }).filter(Boolean),
        onglets: (root) => [...root.querySelectorAll('.tab')].map((t) => norm(t.innerText)),
        notes: (root) => [...root.querySelectorAll('.rounded-lg.border')].map((n) => norm(n.innerText)).filter((t) => t.length > 20),
        fermerTout: () => document.querySelectorAll('[role=dialog], .modal-root, .drawer-root, .drawer-backdrop').forEach((x) => x.remove()),
        toasts: () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim())),
        viderToasts: () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; window.__alertes.length = 0; },
        bouton: (racine, texte) => [...racine.querySelectorAll('button')].find((b) => b.textContent.trim() === texte || b.getAttribute('aria-label') === texte || b.title === texte),
        poser: (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); },
        champs: () => [...document.querySelectorAll('[role=dialog] label, .modal-root label')].map((l) => norm(l.innerText)),
        optsDe: (id) => { const e = document.getElementById('f_' + id); if (!e) return null; if (typeof e.options === 'function') return e.options().map((o) => [o.value, norm(o.label)]); return [...e.options].map((o) => [o.value, norm(o.textContent)]); },
        valeur: (id) => { const e = document.getElementById('f_' + id); return e ? (e.type === 'checkbox' ? e.checked : e.value) : '(absent)'; },
        cliquer: (texte) => { const bs = [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === texte); bs[bs.length - 1].click(); },
        icone: (ligne, nom) => [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === nom),
        boutons: (racine) => [...racine.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean),
        tiroir: () => { const t = document.querySelector('[role=dialog], .drawer-root') || document.body; return { texte: norm(t.innerText), boutons: [...t.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean) }; },
        modale: () => norm((document.querySelector('.modal-root, [role=dialog]') || { innerText: '' }).innerText),
        monter: async (id) => {
          const root = document.createElement('div'); document.body.appendChild(root);
          window.__etats.length = 0;
          SIGH.screens[id].render(root);
          await new Promise((r) => setTimeout(r, 300));
          return root;
        },
        retirer: (root) => { root.remove(); H.fermerTout(); },
        vider: (col) => { col.all().splice(0); },
        ligne: (racine, texte) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(texte)),
        confirmer: async (motif) => {
          await H.dormir(250);
          const zone = document.querySelector('[role=dialog], .modal-root');
          const ta = zone && (zone.querySelector('textarea') || zone.querySelector('input[type=text]'));
          if (ta) { ta.value = motif; ta.dispatchEvent(new Event('input')); }
          const btns = zone ? [...zone.querySelectorAll('button')] : [];
          const ok = btns.find((b) => b.textContent.trim() === 'Archiver');
          if (ok) ok.click();
          await H.dormir(250);
        },
        lireEcran: (root) => ({ kpis: H.kpis(root), onglets: H.onglets(root), cartes: H.cartes(root), tableaux: H.tableaux(root), notes: H.notes(root), boutons: H.boutons(root).slice(0, 14) }),
        // jours relatifs à AUJ (30/10/2026), en date ISO locale
        J: (n) => { const d = new Date(2026, 9, 30 + n); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); },
      };
    });

    const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-administration.js — ne pas éditer. Horloge : 30/10/2026 10 h.' };

    /* ------------------------------------------------------------------ référentiels : les notes de service */
    sortie.notes = await m.page.evaluate(async () => {
      const D = SIGH.data, S = SIGH.store;
      const out = { ns131: H.propre(D.NS131), ns132: H.propre(D.NS132), fonctions: H.propre(D.FONCTIONS.map((f) => ({ id: f.id, label: f.label }))) };
      const col = S.collection('personnel');
      out.agents = col.active().length;
      const root = await H.monter('m13-notes-service');
      out.ecran = H.lireEcran(root);
      out.titresCartes = [...root.querySelectorAll('.card-title')].map((t) => H.norm(t.innerText));
      out.badges = [...root.querySelectorAll('.card')].map((c) => [...c.querySelectorAll('.card-head span, .card-head a')].map((b) => H.norm(b.innerText)).filter(Boolean));
      out.descListes = [...root.querySelectorAll('.card')].map((c) => H.norm((c.querySelector('dl') || { innerText: '' }).innerText));
      out.badgesFonctions = [...root.querySelectorAll('.card')].map((c) => [...c.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => H.norm(td.innerText))));
      out.liens = [...root.querySelectorAll('a')].map((a) => [H.norm(a.innerText), a.getAttribute('href')]);
      H.retirer(root);
      return out;
    });

    /* ------------------------------------------------------------------ COURRIERS */
    sortie.courriers = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const col = S.collection('courriers');
      H.vider(col);
      const c = (n, sens, dj, corr, objet, nature, aff, trait, ar, num, extra) => Object.assign({ id: 'COU' + n, statut: 'actif', reference: (sens === 'arrivee' ? 'ARR-' : 'DEP-') + '2026-' + String(n).padStart(4, '0'),
        sens, date: J(dj), correspondant: corr, objet, nature, affecteA: aff, traitement: trait, accuseReception: ar, numerise: num }, extra || {});
      [c(1, 'arrivee', -40, 'DGI — Centre des impôts', 'Notification de contrôle fiscal', 'Convocation', 'Direction Administrative', 'traite', true, true),
        c(2, 'depart', -35, 'SoBAPS SA', 'Bon de commande de médicaments', 'Courriel', 'Comptabilité', 'traite', true, false),
        c(3, 'arrivee', -30, 'CNSS', 'Appel de cotisations', 'Lettre', 'Ressources humaines', 'en_cours', false, true),
        c(4, 'arrivee', -12, 'Ministère de la Santé', 'Circulaire sur la vaccination', 'Note', 'Direction Médicale', 'en_attente', false, false),
        c(5, 'depart', -9, 'NSIA Assurances', 'Facture mensuelle', 'Facture', 'Comptabilité', 'en_attente', true, true),
        c(6, 'arrivee', -3, 'CHD Atacora', 'Demande de transfert de dossier', 'Lettre', 'Direction Médicale', 'en_attente', false, false),
        c(7, 'depart', 0, 'Zone sanitaire', 'Rapport mensuel d’activité', 'Rapport', 'Direction Administrative', 'en_cours', true, true, { observations: 'À signer avant envoi' }),
        c(8, 'arrivee', 0, 'Fournisseur DIPHARM', 'Livraison annoncée', 'Courriel', 'Gestion des stocks', 'traite', false, true),
        c(9, 'depart', -100, 'Mairie de Natitingou', 'Autorisation d’affichage', 'Lettre', 'Direction Administrative', 'traite', true, true)].forEach((x) => col.all().push(x));
      col.archive('COU9', 'test');
      const out = { jeu: H.propre(col.all()) };
      let racine = await H.monter('m13-courriers');
      out.ecran = H.lireEcran(racine);
      out.boutonsLigne = [...H.ligne(racine, 'ARR-2026-0003').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      // tri : défaut date décroissante ; en-têtes
      out.filtres = [...racine.querySelectorAll('select')].map((s) => [s.getAttribute('aria-label'), [...s.options].map((o) => [o.value, H.norm(o.textContent)])]);
      // filtres pilotés
      out.filtreCas = [];
      for (const s of [...racine.querySelectorAll('select')]) {
        const nomF = s.getAttribute('aria-label');
        for (const o of [...s.options].filter((x) => x.value !== '')) {
          s.value = o.value; s.dispatchEvent(new Event('change')); await H.dormir(50);
          out.filtreCas.push({ filtre: nomF, valeur: o.value, lignes: H.tableaux(racine)[0].lignes.map((l) => l[0]) });
        }
        s.value = ''; s.dispatchEvent(new Event('change')); await H.dormir(40);
      }
      // détail
      H.icone(H.ligne(racine, 'DEP-2026-0007'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      // fiche imprimée
      H.icone(H.ligne(racine, 'DEP-2026-0007'), 'Imprimer l’état') && H.icone(H.ligne(racine, 'DEP-2026-0007'), 'Imprimer l’état').click();
      await H.dormir(150);
      out.etatFiche = H.propre(window.__etats[0] || null);
      // registre imprimé
      window.__etats.length = 0;
      SIGH.screens['m13-courriers'].actions().find((b) => b.textContent.trim() === 'Imprimer le registre').click(); await H.dormir(150);
      out.etatRegistre = H.propre(window.__etats[0] || null);
      // création
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs() };
      out.creation.defauts = {};
      ['sens', 'date', 'correspondant', 'objet', 'nature', 'affecteA', 'traitement', 'accuseReception', 'numerise', 'observations'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      out.creation.options = { sens: H.optsDe('sens'), nature: H.optsDe('nature'), affecteA: H.optsDe('affecteA'), traitement: H.optsDe('traitement') };
      // refus : correspondant et objet vides
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('correspondant', 'DGI Natitingou'); H.poser('objet', 'Déclaration TVM'); H.poser('affecteA', 'Comptabilité');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.arrivee = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length };
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      H.poser('sens', 'depart'); H.poser('correspondant', 'SOS Assurances'); H.poser('objet', 'Relance de paiement'); H.poser('nature', 'Lettre'); H.poser('affecteA', 'Comptabilité'); H.poser('traitement', 'traite'); H.poser('accuseReception', true); H.poser('numerise', true); H.poser('observations', 'Urgent');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.depart = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length };
      out.creation.apres = H.lireEcran(racine);
      // modification : la référence est gardée
      H.icone(H.ligne(racine, 'ARR-2026-0004'), 'Modifier').click(); await H.dormir(300);
      out.modification = { modale: H.modale().slice(0, 120), valeurs: {} };
      ['sens', 'date', 'correspondant', 'objet', 'nature', 'affecteA', 'traitement', 'accuseReception', 'numerise', 'observations'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('traitement', 'traite'); H.poser('numerise', true);
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.id === 'COU4')) };
      // archivage avec motif
      H.icone(H.ligne(racine, 'DEP-2026-0005'), 'Archiver').click(); await H.confirmer('Doublon');
      out.archivage = { fiche: H.net(col.all().find((x) => x.id === 'COU5')), onglets: H.onglets(racine), toasts: H.toasts() };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ RÉUNIONS */
    sortie.reunions = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const col = S.collection('reunions');
      H.vider(col);
      const pres = S.collection('personnel').active()[0].nomComplet;
      const r = (n, dj, type, heure, cr, part, extra) => Object.assign({ id: 'REU' + n, statut: 'actif', reference: 'RU-2026-' + String(n).padStart(3, '0'), date: J(dj), heure, type, lieu: 'Salle de réunion',
        president: pres, participants: part, ordreDuJour: 'Ordre du jour ' + n, compteRendu: cr }, extra || {});
      [r(1, -60, 'Réunion de direction', '09:00', true, 8), r(2, -20, 'Comité d’hygiène', '10:30', false, 12, { resolutions: 'Renforcer le lavage des mains' }),
        r(3, -2, 'Réunion de service', '14:00', false, 6), r(4, 0, 'Revue mensuelle d’activité', '08:00', false, 10),
        r(5, 1, 'Réunion du personnel', '15:00', false, 30), r(6, 15, 'Comité de gestion des stocks', '11:00', false, 5),
        r(7, -90, 'Réunion de direction', '09:00', true, 7), r(8, 0, 'Réunion de service', '15:00', false, 9)].forEach((x) => col.all().push(x));
      col.archive('REU7', 'test');
      const out = { jeu: H.propre(col.all()), president: pres };
      const racine = await H.monter('m13-reunions');
      out.ecran = H.lireEcran(racine);
      out.filtres = [...racine.querySelectorAll('select')].map((s) => [s.getAttribute('aria-label'), [...s.options].map((o) => [o.value, H.norm(o.textContent)])]);
      for (const ref of ['RU-2026-004', 'RU-2026-005', 'RU-2026-002']) {
        window.__etats.length = 0;
        H.icone(H.ligne(racine, ref), 'Imprimer l’état').click(); await H.dormir(150);
        (out.etats = out.etats || {})[ref] = H.propre(window.__etats[0]);
      }
      H.icone(H.ligne(racine, 'RU-2026-005'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: { type: H.optsDe('type'), lieu: H.optsDe('lieu') } };
      ['type', 'date', 'heure', 'lieu', 'president', 'participants', 'ordreDuJour', 'compteRendu', 'resolutions'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('ordreDuJour', 'Budget 2027'); H.poser('type', 'Réunion de direction');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.creee = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length };
      out.creation.apres = H.lireEcran(racine);
      H.icone(H.ligne(racine, 'RU-2026-003'), 'Modifier').click(); await H.dormir(300);
      H.poser('compteRendu', true); H.poser('resolutions', 'RAS');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification = { fiche: H.net(col.all().find((x) => x.id === 'REU3')), kpis: H.kpis(racine) };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ ÉVÉNEMENTS */
    sortie.evenements = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const col = S.collection('evenementsEtablissement');
      H.vider(col);
      const pers = S.collection('personnel').active();
      const e = (n, dj, lib, cat, notif, canaux, extra) => Object.assign({ id: 'EVT' + String(n).padStart(3, '0'), statut: 'actif', reference: 'EV-2026-' + String(n).padStart(3, '0'), libelle: lib, categorie: cat,
        date: J(dj), heure: '09:00', lieu: 'Clinique', responsable: pers[n % pers.length].nomComplet, notifier: notif, canaux }, extra || {});
      [e(1, -30, 'Journée de vaccination', 'Santé publique', true, ['In-app', 'SMS']), e(2, 0, 'Audit qualité interne', 'Qualité', true, ['In-app']),
        e(3, 1, 'Formation aux gestes d’urgence', 'Formation', true, ['In-app', 'SMS', 'Courriel']), e(4, 5, 'Inventaire annuel', 'Logistique', false, []),
        e(5, 8, 'Contrôle des extincteurs', 'Sécurité', true, ['In-app']), e(6, 20, 'Journée portes ouvertes', 'Communication', true, ['In-app', 'Courriel']),
        e(7, 30, 'Maintenance de l’échographe', 'Technique', false, []), e(8, 45, 'Campagne de dépistage du diabète', 'Santé publique', true, ['In-app']),
        e(9, 60, 'Réception des nouveaux équipements', 'Logistique', true, ['In-app', 'SMS']), e(10, 90, 'Formation au nouveau logiciel SIGH', 'Formation', false, [])].forEach((x) => col.all().push(x));
      const out = { jeu: H.propre(col.all()) };
      const racine = await H.monter('m13-evenements');
      out.ecran = H.lireEcran(racine);
      // les cartes « Prochains événements »
      const grille = [...racine.querySelectorAll('.grid.gap-3')].find((g) => /sm:grid-cols-2/.test(g.className) && g.querySelector('.rounded-xl'));
      out.prochains = grille ? [...grille.children].map((c) => [...c.querySelectorAll('p, span, div > span')].map((x) => H.norm(x.innerText)).filter(Boolean)) : [];
      out.prochainsBrut = grille ? [...grille.children].map((c) => H.norm(c.innerText)) : [];
      out.prochainsRouges = grille ? [...grille.children].map((c) => !!c.querySelector('.text-danger-600')) : [];
      // paramétrage des notifications
      out.notifications = H.tableaux(racine).slice(-1)[0];
      out.liens = [...racine.querySelectorAll('a')].map((a) => [H.norm(a.innerText), a.getAttribute('href')]);
      out.filtres = [...racine.querySelectorAll('select')].map((s) => [s.getAttribute('aria-label'), [...s.options].map((o) => [o.value, H.norm(o.textContent)])]);
      out.boutonsLigne = [...H.ligne(racine, 'EV-2026-003').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: { categorie: H.optsDe('categorie') } };
      ['libelle', 'categorie', 'date', 'heure', 'lieu', 'responsable', 'notifier', 'observations'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('libelle', 'Dépistage du cancer du sein'); H.poser('categorie', 'Santé publique'); H.poser('lieu', 'Salle de réunion');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(400);
      out.creation.avecNotif = { toasts: H.toasts(), alertes: H.propre(window.__alertes), fiche: H.net(col.all()[0]), total: col.all().length };
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      H.poser('libelle', 'Réunion sans annonce'); H.poser('notifier', false); H.poser('date', H.J(3));
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(400);
      out.creation.sansNotif = { fiche: H.net(col.all()[0]), total: col.all().length };
      // modification : pas de transform, canaux inchangés même si « notifier » change
      H.icone(H.ligne(racine, 'EV-2026-004'), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['libelle', 'categorie', 'date', 'heure', 'lieu', 'responsable', 'notifier', 'observations'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('notifier', true); H.poser('lieu', 'Extérieur');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { fiche: H.net(col.all().find((x) => x.id === 'EVT004')) };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ PLAN ANNUEL */
    sortie.planAnnuel = await m.page.evaluate(async () => {
      const S = SIGH.store;
      const col = S.collection('planAnnuel');
      H.vider(col);
      const a = (n, action, axe, d, f, av, resp) => ({ id: 'PAT' + String(n).padStart(3, '0'), statut: 'actif', reference: 'PA-2026-' + String(n).padStart(3, '0'), action, axe, trimestreDebut: d, trimestreFin: f, avancement: av, responsable: resp });
      [a(1, 'Déploiement du SIGH-CNT', 'Digitalisation', 1, 4, 'En cours', 'TAKI Alimatou'), a(2, 'Inventaire général des stocks', 'Logistique', 1, 1, 'Réalisée', 'MAMAN Zoukanéri'),
        a(3, 'Formation du personnel', 'Formation', 3, 4, 'Planifiée', 'TAKI Alimatou'), a(4, 'Clôture comptable de l’exercice', 'Finance', 4, 4, 'Planifiée', 'KASSA Augustin'),
        a(5, 'Renouvellement des conventions', 'Partenariats', 1, 2, 'Réalisée', 'TAKI Alimatou'), a(6, 'Campagne de dépistage', 'Santé publique', 2, 3, 'En cours', 'TAKI Alimatou'),
        a(7, 'Audit qualité', 'Qualité', 4, 4, 'Planifiée', 'TAKI Alimatou')].forEach((x) => col.all().push(x));
      const out = { jeu: H.propre(col.all()) };
      const racine = await H.monter('m13-plan-annuel');
      out.ecran = H.lireEcran(racine);
      // le diagramme : ordre des lignes et cellules actives par ligne (classe de la barre)
      const gantt = racine.querySelector('table.min-w-\\[48rem\\]') || racine.querySelectorAll('table')[0];
      out.gantt = [...gantt.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td, i) => (i >= 2 && i <= 5 ? ((td.querySelector('div') || {}).className || '').replace(/^.*(bg-[a-z]+-\d+).*$/, '$1') : H.norm(td.innerText))));
      out.filtres = [...racine.querySelectorAll('select')].map((s) => [s.getAttribute('aria-label'), [...s.options].map((o) => [o.value, H.norm(o.textContent)])]);
      out.boutonsLigne = [...racine.querySelectorAll('tbody tr')].slice(-1)[0] ? null : null;
      window.__etats.length = 0;
      H.bouton(racine, 'Imprimer le plan').click(); await H.dormir(150);
      out.etat = H.propre(window.__etats[0]);
      // modification d'une ligne du tableau détaillé
      const tables = [...racine.querySelectorAll('.card')].filter((c) => /Détail des actions/.test(c.innerText));
      const detail = tables[tables.length - 1];
      const ligne = [...detail.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes('PA-2026-006'));
      out.boutonsLigne = [...ligne.querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      const bc = H.icone(ligne, 'Consulter'); if (bc) { bc.click(); await H.dormir(300); }
      out.detail = H.tiroir(); H.fermerTout();
      H.icone(ligne, 'Modifier').click(); await H.dormir(300);
      out.modification = { modale: H.modale().slice(0, 140), champs: H.champs(), valeurs: {} };
      ['action', 'responsable', 'echeance', 'avancement', 'tauxAvancement', 'observations'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('action', 'Campagne de dépistage communautaire'); H.poser('echeance', '2026-12-15');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((x) => x.id === 'PAT006')) };
      out.modification.apres = { kpis: H.kpis(racine) };
      // avancement saisi : le champ « Avancement (%) » est numérique mais la colonne lit un texte
      const ligne2 = [...[...racine.querySelectorAll('.card')].filter((c) => /Détail des actions/.test(c.innerText)).pop().querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes('PA-2026-006'));
      H.icone(ligne2, 'Modifier').click(); await H.dormir(300);
      H.poser('tauxAvancement', '60'); H.poser('avancement', 'Réalisée');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.avancementNumerique = { fiche: H.net(col.all().find((x) => x.id === 'PAT006')), kpis: H.kpis(racine), tableau: H.tableaux(racine).slice(-1)[0].lignes.filter((l) => l[0] === 'PA-2026-006') };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ AMBULANCE (interventions) */
    sortie.ambulance = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const col = S.collection('ambulance');
      H.vider(col);
      const pats = S.collection('patients').active();
      const pers = S.collection('personnel').active();
      const chauffeur = (pers.find((x) => x.fonction === 'chauffeur') || pers[0]).nomComplet;
      const acc = pers[1].nomComplet;
      const iso = (dj, h, mi) => { const d = new Date(2026, 9, 30 + dj, h, mi, 0); return d.toISOString(); };
      const p = (i) => ({ patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code });
      const a = (n, i, dj, h, motif, dest, km, etat, tarif, fact) => Object.assign({ id: 'AMB' + n, statut: 'actif', reference: 'AM-2026-' + String(n).padStart(4, '0'), dateHeure: iso(dj, h, 15), motif, destination: dest, kilometrage: km,
        chauffeur, accompagnant: acc, etat, tarif, facture: fact }, p(i));
      [a(1, 0, -50, 8, 'Urgence médicale', 'CHD Atacora', 12, 'terminee', 11000, true), a(2, 1, -20, 22, 'Transfert inter-hospitalier', 'CNHU-HKM Cotonou', 480, 'terminee', 245000, true),
        a(3, 2, -29, 14, 'Retour à domicile', 'Domicile — Tchirimina', 7, 'terminee', 8500, false), a(4, 3, -3, 3, 'Urgence obstétricale', 'Hôpital de zone de Tanguiéta', 52, 'terminee', 31000, true),
        a(5, 4, 0, 7, 'Évacuation sanitaire', 'CHD Atacora', 15, 'en_cours', 12500, false), a(6, 5, 0, 9, 'Accident de la voie publique', 'Clinique', 4, 'demandee', 7000, false),
        a(7, 6, -5, 18, 'Urgence médicale', 'CHD Atacora', 10, 'terminee', 10000, true)].forEach((x) => col.all().push(x));
      const out = { jeu: H.propre(col.all()), chauffeur, accompagnant: acc, patients: H.propre(pats.slice(0, 3).map((x) => ({ code: x.code, nom: x.nom, prenom: x.prenom, id: x.id }))) };
      const racine = await H.monter('m13-ambulance');
      out.ecran = H.lireEcran(racine);
      out.boutonsLigne = [...H.ligne(racine, 'AM-2026-0002').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      out.filtres = [...racine.querySelectorAll('select')].map((s) => [s.getAttribute('aria-label'), [...s.options].map((o) => [o.value, H.norm(o.textContent)])]);
      out.filtreCas = [];
      for (const s of [...racine.querySelectorAll('select')]) {
        const nomF = s.getAttribute('aria-label');
        for (const o of [...s.options].filter((x) => x.value !== '')) {
          s.value = o.value; s.dispatchEvent(new Event('change')); await H.dormir(50);
          out.filtreCas.push({ filtre: nomF, valeur: o.value, lignes: H.tableaux(racine)[0].lignes.map((l) => l[0]) });
        }
        s.value = ''; s.dispatchEvent(new Event('change')); await H.dormir(40);
      }
      window.__etats.length = 0;
      H.icone(H.ligne(racine, 'AM-2026-0002'), 'Imprimer l’état').click(); await H.dormir(150);
      out.etat = H.propre(window.__etats[0]);
      H.icone(H.ligne(racine, 'AM-2026-0002'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: { motif: H.optsDe('motif'), etat: H.optsDe('etat'), chauffeur: (H.optsDe('chauffeur') || []).slice(0, 3), patientCode: (H.optsDe('patientCode') || []).slice(0, 3), nbPatients: (H.optsDe('patientCode') || []).length, nbAgents: (H.optsDe('chauffeur') || []).length } };
      ['patientCode', 'dateHeure', 'motif', 'destination', 'kilometrage', 'etat', 'chauffeur', 'accompagnant', 'tarif', 'facture'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('patientCode', pats[7].code); H.poser('dateHeure', '2026-10-30T09:30'); H.poser('destination', 'Centre de santé de Perma'); H.poser('kilometrage', '20');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.tarifCalcule = { toasts: H.toasts(), fiche: H.net(col.all()[0]), total: col.all().length, kpis: H.kpis(racine) };
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      H.poser('patientCode', pats[8].code); H.poser('dateHeure', '2026-11-02T16:00'); H.poser('destination', 'CHD Atacora'); H.poser('kilometrage', '5'); H.poser('tarif', '9000'); H.poser('facture', true); H.poser('etat', 'terminee');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.tarifSaisi = { fiche: H.net(col.all()[0]), kpis: H.kpis(racine) };
      // modification : le patient change → nom et id suivent ; le tarif nul reste recalculé
      H.icone(H.ligne(racine, 'AM-2026-0003'), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['patientCode', 'dateHeure', 'motif', 'destination', 'kilometrage', 'etat', 'chauffeur', 'accompagnant', 'tarif', 'facture'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('patientCode', pats[9].code); H.poser('facture', true);
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { fiche: H.net(col.all().find((x) => x.id === 'AMB3')), patient: { code: pats[9].code, id: pats[9].id, nom: pats[9].nom + ' ' + pats[9].prenom } };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ RÉPERTOIRE DES AMBULANCES */
    sortie.repertoire = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const col = S.collection('ambulances');
      H.vider(col);
      const out = { brand: H.propre(SIGH.core.BRAND.telephones) };
      // amorçage à froid (collection vide) : ce que l'écran sème lui-même
      let racine = await H.monter('m13-repertoire-ambulances');
      out.amorcage = { fiches: H.propre(col.all().map(H.net)), ecran: H.lireEcran(racine) };
      H.retirer(racine);
      H.vider(col);
      const f = (n, lib, type, tel, tel2, contact, base, dispo, verif, extra) => Object.assign({ id: 'AMBR' + n, statut: 'actif', libelle: lib, type, telephone: tel || undefined, telephone2: tel2 || undefined, contact, base, disponibilite: dispo,
        verifieLe: verif, aCompleter: !tel }, extra || {});
      [f(1, 'Ambulance CNT 01', 'clinique', '+229 01 23 45 67', null, 'Chauffeur de garde', 'Natitingou — clinique', 'en_course', J(-2)),
        f(2, 'Ambulance CNT 02', 'clinique', '+229 01 23 45 68', '+229 97 00 00 02', 'Chauffeur de garde', 'Natitingou — clinique', 'disponible', J(0)),
        f(3, 'CHD Atacora — ambulance', 'publique', null, null, 'Régulation du CHD', 'Natitingou', 'indisponible', undefined),
        f(4, 'Ambulance Alpha', 'prive', '+229 96 00 00 01', null, 'M. Alpha', 'Tanguiéta', 'disponible', J(-120), { capacite: 'Brancard, oxygène' }),
        f(5, 'Hôpital partenaire', 'partenaire', '+229 95 00 00 05', null, 'Standard', 'Boukoumbé', 'disponible', J(-89), { observations: 'Appeler avant 20 h' }),
        f(6, 'Ambulance Bravo', 'prive', '+229 96 00 00 06', null, 'M. Bravo', 'Natitingou', 'disponible', J(-90)),
        f(7, 'Ambulance Charlie', 'prive', '+229 96 00 00 07', null, '', 'Natitingou', 'disponible', J(-91)),
        f(8, 'Ambulance Delta', 'inconnu', '+229 96 00 00 08', null, '', '', 'inconnue', undefined)].forEach((x) => col.all().push(x));
      out.jeu = H.propre(col.all());
      racine = await H.monter('m13-repertoire-ambulances');
      out.ecran = H.lireEcran(racine);
      out.cartes = [...racine.querySelectorAll('.card')].filter((c) => /Appel rapide/.test(c.innerText)).map((c) => {
        const grille = c.querySelector('.grid');
        return [...grille.children].map((k) => ({ texte: H.norm(k.innerText), classe: /bg-emerald-50/.test(k.className) ? 'vert' : 'blanc', liens: [...k.querySelectorAll('a')].map((a) => [H.norm(a.innerText), a.getAttribute('href'), /text-2xl/.test(a.className)]) }));
      })[0];
      out.notesDit = [...racine.querySelectorAll('[class*=bg-]')].map((n) => H.norm(n.innerText)).filter((t) => /fiche\(s\) sans numéro|disponibles remontent/.test(t)).slice(0, 4);
      out.tableau = H.tableaux(racine).slice(-1)[0];
      out.boutonsLigne = [...H.ligne(racine, 'Ambulance CNT 02').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      out.boutonsLigneSansNumero = [...H.ligne(racine, 'CHD Atacora — ambulance').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(H.ligne(racine, 'Ambulance Alpha'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      H.icone(H.ligne(racine, 'CHD Atacora — ambulance'), 'Consulter').click(); await H.dormir(300);
      out.detailSansNumero = H.tiroir(); H.fermerTout();
      // vérification : la date du jour est posée, avec le vérificateur
      H.viderToasts();
      H.icone(H.ligne(racine, 'Ambulance Alpha'), 'Confirmer que ce numéro est à jour').click(); await H.dormir(300);
      out.verification = { fiche: H.net(col.all().find((x) => x.id === 'AMBR4')), toasts: H.toasts(), kpis: H.kpis(racine) };
      // disponibilité
      H.icone(H.ligne(racine, 'Ambulance CNT 02'), 'Changer la disponibilité').click(); await H.dormir(300);
      out.bascule = { modale: H.modale().slice(0, 200), options: H.optsDe('disponibilite'), valeur: H.valeur('disponibilite') };
      H.poser('disponibilite', 'en_course'); H.poser('observations', 'Sortie à Tanguiéta');
      H.viderToasts(); H.cliquer('Appliquer'); await H.dormir(300);
      out.bascule.apres = { fiche: H.net(col.all().find((x) => x.id === 'AMBR2')), toasts: H.toasts(), kpis: H.kpis(racine), cartes: [...racine.querySelectorAll('.card')].filter((c) => /Appel rapide/.test(c.innerText)).map((c) => [...c.querySelector('.grid').children].map((k) => H.norm(k.innerText.split('\n')[0])))[0] };
      // création
      H.bouton(document.body, 'Ajouter une ambulance').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: { type: H.optsDe('type'), disponibilite: H.optsDe('disponibilite') } };
      ['libelle', 'type', 'telephone', 'telephone2', 'contact', 'base', 'disponibilite', 'capacite', 'observations'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('libelle', 'Sapeurs-pompiers'); H.poser('telephone', '');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.sansNumero = { toasts: H.toasts(), total: col.all().length, derniere: col.all().length ? H.net(col.all()[0]) : null };
      H.bouton(document.body, 'Ajouter une ambulance').click(); await H.dormir(300);
      H.poser('libelle', 'Sapeurs-pompiers 2'); H.poser('telephone', '+229 90 00 00 09'); H.poser('type', 'publique'); H.poser('base', 'Natitingou');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.avecNumero = { toasts: H.toasts(), total: col.all().length, derniere: H.net(col.all()[0]), kpis: H.kpis(racine) };
      // modification : on retire le numéro
      H.icone(H.ligne(racine, 'Ambulance Bravo'), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['libelle', 'type', 'telephone', 'telephone2', 'contact', 'base', 'disponibilite', 'capacite', 'observations'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('telephone', '+229 96 11 11 11');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { fiche: H.net(col.all().find((x) => x.id === 'AMBR6')), toasts: H.toasts() };
      H.icone(H.ligne(racine, 'Ambulance Charlie'), 'Archiver').click(); await H.confirmer('Doublon');
      out.archivage = { fiche: H.net(col.all().find((x) => x.id === 'AMBR7')), kpis: H.kpis(racine) };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ PARC TECHNIQUE & MAINTENANCE */
    sortie.maintenance = await m.page.evaluate(async () => {
      const S = SIGH.store, J = H.J;
      const col = S.collection('materiel');
      H.vider(col);
      const out = {};
      // amorçage à froid : ce que l'écran sème (dates relatives à l'horloge)
      let racine = await H.monter('m13-maintenance');
      out.amorcage = { fiches: H.propre(col.all().map(H.net)), ecran: H.lireEcran(racine) };
      H.retirer(racine);
      H.vider(col);
      const e = (n, lib, cat, loc, etat, dernier, per, extra) => Object.assign({ id: 'MAT' + String(n).padStart(3, '0'), statut: 'actif', reference: 'EQ-' + String(n).padStart(3, '0'), libelle: lib, categorie: cat, localisation: loc, etat,
        periodiciteMois: per, dernierEntretien: dernier, aCompleter: true }, extra || {});
      [e(1, 'Automate d’hématologie', 'Automate de laboratoire', 'Laboratoire', 'service', J(-200), 6, { marque: 'Sysmex XN', numeroSerie: 'SN-001', miseEnService: '2022-03-01', aCompleter: false }),
        e(2, 'Échographe', 'Imagerie', 'Salle d’échographie', 'service', J(-100), 12), e(3, 'Aspirateur chirurgical', 'Bloc opératoire', 'Bloc opératoire', 'panne', J(-30), 12, { observation: 'Panne signalée par le bloc.' }),
        e(4, 'Groupe électrogène', 'Énergie & froid', 'Local technique', 'service', J(-183), 6),
        e(5, 'Table d’accouchement', 'Matériel de soins', 'Maternité', 'reforme', J(-400), 12), e(6, 'Ambulance de la clinique', 'Véhicule', 'Local technique', 'service', undefined, 12),
        e(7, 'Microscope optique', 'Automate de laboratoire', 'Laboratoire', 'service', J(-182), null),
        e(8, 'Serveur et onduleur', 'Bureautique & réseau', 'Administration', 'service', J(-366), 12, { marque: 'APC', numeroSerie: 'X', miseEnService: '2023-01-01', aCompleter: false })].forEach((x) => col.all().push(x));
      out.jeu = H.propre(col.all());
      racine = await H.monter('m13-maintenance');
      out.ecran = H.lireEcran(racine);
      out.filtres = [...racine.querySelectorAll('select')].map((s) => [s.getAttribute('aria-label'), [...s.options].map((o) => [o.value, H.norm(o.textContent)])]);
      out.filtreCas = [];
      const sel = [...racine.querySelectorAll('select')].find((s) => s.getAttribute('aria-label') === 'Suivi');
      for (const o of [...sel.options].filter((x) => x.value !== '')) {
        sel.value = o.value; sel.dispatchEvent(new Event('change')); await H.dormir(50);
        out.filtreCas.push({ valeur: o.value, lignes: H.tableaux(racine)[0].lignes.map((l) => l[0]) });
      }
      sel.value = ''; sel.dispatchEvent(new Event('change')); await H.dormir(40);
      out.badgesEchu = [...racine.querySelectorAll('tbody tr')].map((tr) => [H.norm(tr.children[1] ? tr.innerText.split('\n')[0] : ''), /échu/.test(tr.innerText)]);
      window.__etats.length = 0;
      H.icone(H.ligne(racine, 'EQ-003'), 'Imprimer l’état').click(); await H.dormir(150);
      out.etat = H.propre(window.__etats[0]);
      window.__etats.length = 0;
      H.icone(H.ligne(racine, 'EQ-001'), 'Imprimer l’état').click(); await H.dormir(150);
      out.etatRenseigne = H.propre(window.__etats[0]);
      H.icone(H.ligne(racine, 'EQ-003'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); H.fermerTout();
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { modale: H.modale().slice(0, 160), champs: H.champs(), defauts: {}, options: { categorie: H.optsDe('categorie'), localisation: H.optsDe('localisation'), etat: H.optsDe('etat') } };
      ['libelle', 'categorie', 'localisation', 'etat', 'marque', 'numeroSerie', 'miseEnService', 'periodiciteMois', 'dernierEntretien', 'observation'].forEach((n) => { out.creation.defauts[n] = H.valeur(n); });
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refus = { toasts: H.toasts(), total: col.all().length };
      H.poser('libelle', 'Autoclave 2'); H.poser('categorie', 'Bloc opératoire'); H.poser('localisation', 'Bloc opératoire');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.aCompleter = { toasts: H.toasts(), fiche: H.net(col.all()[0]), kpis: H.kpis(racine) };
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      H.poser('libelle', 'Réfrigérateur 3'); H.poser('categorie', 'Énergie & froid'); H.poser('localisation', 'Pharmacie'); H.poser('marque', 'Liebherr'); H.poser('numeroSerie', 'LB-3'); H.poser('miseEnService', '2024-05-01'); H.poser('periodiciteMois', '6');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.complet = { fiche: H.net(col.all()[0]), kpis: H.kpis(racine) };
      // modification : renseigner une fiche fait tomber « à compléter »
      H.icone(H.ligne(racine, 'EQ-002'), 'Modifier').click(); await H.dormir(300);
      out.modification = { valeurs: {} };
      ['libelle', 'categorie', 'localisation', 'etat', 'marque', 'numeroSerie', 'miseEnService', 'periodiciteMois', 'dernierEntretien', 'observation'].forEach((n) => { out.modification.valeurs[n] = H.valeur(n); });
      H.poser('marque', 'Samsung'); H.poser('numeroSerie', 'SS-77'); H.poser('miseEnService', '2023-02-02'); H.poser('etat', 'panne');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { fiche: H.net(col.all().find((x) => x.id === 'MAT002')), kpis: H.kpis(racine) };
      H.retirer(racine);
      return out;
    });

    /* ------------------------------------------------------------------ L'APRÈS-MIDI (15 h) : tout se compte PAR JOUR (E540) */
    sortie.apresMidi = await m.page.evaluate(async () => {
      const S = SIGH.store;
      window.__FIXE = new window.__Vrai(2026, 9, 30, 15, 0, 0).getTime();
      const out = {};
      let racine = await H.monter('m13-evenements');
      const grille = [...racine.querySelectorAll('.grid.gap-3')].find((g) => /sm:grid-cols-2/.test(g.className) && g.querySelector('.rounded-xl'));
      out.evenements = { jeu: H.propre(S.collection('evenementsEtablissement').all()), kpis: H.kpis(racine), prochainsBrut: grille ? [...grille.children].map((c) => H.norm(c.innerText)) : [],
        prochainsRouges: grille ? [...grille.children].map((c) => !!c.querySelector('.text-danger-600')) : [] };
      H.retirer(racine);
      racine = await H.monter('m13-reunions');
      out.reunions = { jeu: H.propre(S.collection('reunions').all()), kpis: H.kpis(racine), tableau: H.tableaux(racine)[0] };
      H.retirer(racine);
      racine = await H.monter('m13-repertoire-ambulances');
      out.repertoire = { jeu: H.propre(S.collection('ambulances').all()), kpis: H.kpis(racine), tableau: H.tableaux(racine).slice(-1)[0] };
      H.retirer(racine);
      window.__FIXE = new window.__Vrai(2026, 9, 30, 10, 0, 0).getTime();
      return out;
    });

    sortie.erreurs = await m.page.evaluate(() => window.__erreurs);
    ecrireDartNotes(sortie.notes);
    ecrire('packages/domaine/test/vecteurs/administration.json', sortie);
    console.log('  erreurs de page : ' + sortie.erreurs.length);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
