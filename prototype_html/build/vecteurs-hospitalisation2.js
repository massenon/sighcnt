/* =============================================================================
 * VECTEURS DE L HOSPITALISATION (M3), SECOND LOT — m3-rapport, m3-visites-patients
 * -----------------------------------------------------------------------------
 * Les dix écrans sont montés TELS QUELS dans la page d'extraction, sur des jeux d'essai posés au magasin jetable ; on lit ce qu'ils AFFICHENT
 * (KPI, tableaux, cartes, graphiques et dessins interceptés), on PILOTE les modales et les tiroirs comme le fait l'agent, on intercepte les
 * pièces imprimées, et l'on appelle les moteurs exposés (relais d'administration). La banque de sang est fermée dans la maquette : la
 * surveillance transfusionnelle, elle, reste ouverte (la clinique pose du sang venu de l'extérieur).
 *
 *   node build/vecteurs-hospitalisation2.js   →   packages/domaine/test/vecteurs/hospitalisation2.json
 *
 * L'horloge est fixée au 16/08/2026 : `C.aujourdhui()` ET `new Date()` à 10 h 00 locale.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs hospitalisation (M3)');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      SIGH.core.aujourdhui = () => new Date(2026, 7, 16, 10, 0, 0);
      /* new Date() sans argument : 16/08/2026 10 h 00 locale (durée d'observation, relevés « du jour »). */
      const Vrai = Date;
      const FIXE = new Vrai(2026, 7, 16, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(FIXE); else super(...a); } static now() { return FIXE; } }
      window.Date = Faux;
      window.__graphiques = [];
      window.__etats = [];
      const G = SIGH.charts;
      ['barres', 'ligne'].forEach((t) => {
        const orig = G[t];
        G[t] = function () {
          window.__graphiques.push({ type: t, args: JSON.parse(JSON.stringify(Array.prototype.slice.call(arguments, 0, 3))) });
          return orig.apply(this, arguments);
        };
      });
      SIGH.print.etat = function (o) {
        const tab = [];
        const c = o.contenu;
        if (c && c.querySelectorAll) {
          c.querySelectorAll('table').forEach((t) => tab.push({
            entetes: [...t.querySelectorAll('thead th')].map((x) => x.innerText.replace(/\s+/g, ' ').trim()),
            lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.innerText.replace(/\s+/g, ' ').trim())),
          }));
        }
        window.__etats.push(JSON.parse(JSON.stringify({
          titre: o.titre, sousTitre: o.sousTitre || null, cartouche: o.cartouche || null, signatures: o.signatures || null,
          texte: c && c.innerText ? c.innerText.replace(/\s+/g, ' ').trim() : null, tableaux: tab,
        })));
      };
      /* Le tiroir et la modale : on lit ce qu'ils portent. */
    });
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m3-hospitalisation.js') });

    /* Aides communes, posées dans la page. */
    await m.page.evaluate(() => {
      const norm = (t) => String(t == null ? '' : t).replace(/[\n\t\r]+/g, ' ').replace(/\s+/g, ' ').trim();
      window.H = {
        norm,
        propre: (x) => JSON.parse(JSON.stringify(x)),
        dormir: (ms) => new Promise((r) => setTimeout(r, ms)),
        net: (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', '_archivePar', '_archiveLe'].forEach((k) => delete c[k]); return JSON.parse(JSON.stringify(c)); },
        kpis: (root) => [...root.querySelectorAll('.kpi')].map((k) => {
          const p = k.querySelectorAll('p');
          return { libelle: norm(p[0].innerText), valeur: norm(p[1].innerText), indice: p[2] ? norm(p[2].innerText) : null };
        }),
        tableaux: (root) => [...root.querySelectorAll('table')].map((t) => ({
          entetes: [...t.querySelectorAll('thead th')].map((x) => norm(x.innerText)),
          lignes: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.innerText))),
        })),
        cartes: (root) => [...root.querySelectorAll('.card')].map((c) => {
          const h = c.querySelector('.card-header, .card-head, h3, h2');
          return h ? norm(h.innerText) : null;
        }).filter(Boolean),
        notes: (root) => [...root.querySelectorAll('.rounded-lg.border')].map((n) => norm(n.innerText)).filter((t) => t.length > 20),
        fermerTout: () => document.querySelectorAll('[role=dialog], .modal-root, .drawer-root').forEach((x) => x.remove()),
        toasts: () => [...document.querySelectorAll('#toast-host > div')].map((n) => [...n.querySelectorAll('p')].map((p) => p.textContent.trim())),
        viderToasts: () => { const h = document.getElementById('toast-host'); if (h) h.innerHTML = ''; },
        bouton: (racine, texte) => [...racine.querySelectorAll('button')].find((b) => b.textContent.trim() === texte || b.getAttribute('aria-label') === texte || b.title === texte),
        poser: (id, v) => { const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id); if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; } e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); },
        champs: () => [...document.querySelectorAll('[role=dialog] label, .modal-root label')].map((l) => norm(l.innerText)),
        optsDe: (id) => { const e = document.getElementById('f_' + id); if (!e || !e.options) return null; if (typeof e.options === 'function') return e.options().map((o) => [o.value, norm(o.label)].concat(o.detail ? [norm(o.detail)] : [])); return [...e.options].map((o) => [o.value, norm(o.textContent)]); },
        cliquer: (texte) => [...document.querySelectorAll('button')].find((b) => b.textContent.trim() === texte).click(),
        icone: (ligne, nom) => [...ligne.querySelectorAll('button')].find((b) => (b.getAttribute('aria-label') || b.title) === nom),
        boutons: (racine) => [...racine.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean),
        tiroir: () => { const t = document.querySelector('[role=dialog], .drawer-root') || document.body; return { texte: norm(t.innerText), boutons: [...t.querySelectorAll('button')].map((b) => norm(b.textContent || b.getAttribute('aria-label') || b.title)).filter(Boolean) }; },
        monter: async (id) => {
          const root = document.createElement('div'); document.body.appendChild(root);
          window.__graphiques.length = 0; window.__etats.length = 0;
          SIGH.screens[id].render(root);
          await new Promise((r) => setTimeout(r, 300));
          return root;
        },
        retirer: (root) => { root.remove(); H.fermerTout(); },
        mettreDeCote: (cols) => { const sauve = {}; cols.forEach((c) => { sauve[c.name] = c.all().splice(0); }); return sauve; },
        remettre: (cols, sauve) => { cols.forEach((c) => { c.all().splice(0); (sauve[c.name] || []).forEach((x) => c.all().push(x)); }); },
        J: (n) => { const d = new Date(2026, 7, 16 + n); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); },
      };
    });

    const sortie = { _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-hospitalisation2.js — ne pas éditer. Horloge : 16/08/2026.' };
    const groupe = (nom, fn) => m.page.evaluate(fn).then((r) => { sortie[nom] = r; });

    /* ------------------------------------------------------------------ visites aux hospitalisés */
    await groupe('visites', async () => {
      const S = SIGH.store, J = H.J;
      const colAdm = S.collection('admissions'), col = S.collection('visitesHospi', { module: 'M3', entite: 'visite', prefix: 'VIS' });
      const sauve = H.mettreDeCote([colAdm, col]);
      const pats = S.collection('patients').active();
      const adm = (n, i, lit, statut) => ({ id: 'ADM' + n, statut, reference: 'H0000' + n, patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom, patientCode: pats[i].code, chambre: lit.split(' ')[0], lit, typeChambre: 'standard', dateEntree: J(-5), dateSortie: null, infirmier: 'GARBA Yahouza' });
      const admissions = [adm(1, 0, 'A1 LIT1', 'en_cours'), adm(2, 1, 'C1 LIT1', 'en_cours'), adm(3, 2, 'A2 LIT1', 'sortie')];
      admissions.forEach((x) => colAdm.all().push(x));
      const vis = (n, a, d, h, type, visiteur, obs, extra) => Object.assign({ id: 'VIS000' + n, statut: 'actif', date: J(d), heure: h, admissionId: 'ADM' + a, patient: admissions[a - 1].patient, patientCode: admissions[a - 1].patientCode, lit: admissions[a - 1].lit, type, visiteur, observation: obs }, extra || {});
      const jeu = [vis(1, 1, -1, '09:00', 'Famille', 'Accompagnant déclaré', 'Apport de repas'), vis(2, 1, -2, '14:30', 'Personnel traitant', 'GARBA Yahouza', 'Visite médicale'),
        vis(3, 2, 0, '10:00', 'Famille', 'Sœur de la patiente', ''), vis(4, 2, -3, '08:00', 'Personnel traitant', 'GARBA Yahouza', 'Contrôle des constantes'), vis(5, 1, -4, '19:30', 'Famille', 'Voisin', 'Visite de courtoisie', { statut: 'archive' })];
      jeu.forEach((x) => col.all().push(x));
      const out = { admissions: H.propre(admissions), jeu: H.propre(jeu) };
      let racine = await H.monter('m3-visites-patients');
      out.ecran = { kpis: H.kpis(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 16), notes: H.notes(racine), texte: H.norm(racine.innerText).slice(0, 1200) };
      const lig = (t) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(t));
      out.ecran.boutonsLigne = [...lig('Sœur de la patiente').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      out.ecran.badges = [...racine.querySelectorAll('tbody tr')].map((tr) => { const b = tr.querySelector('.badge, span[class*=badge]'); return b ? [H.norm(b.innerText), b.className] : null; });
      const onglet = (re) => [...racine.querySelectorAll('button')].find((b) => re.test(H.norm(b.textContent)));
      onglet(/^Archivés/).click(); await H.dormir(200);
      out.archives = { tableaux: H.tableaux(racine), boutonsLigne: racine.querySelector('tbody tr') ? [...racine.querySelector('tbody tr').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title) : [] };
      onglet(/^Tous/).click(); await H.dormir(200);
      H.icone(lig('Sœur de la patiente'), 'Consulter').click(); await H.dormir(300);
      out.detail = Object.assign(H.tiroir(), { tables: H.tableaux(document.querySelector('[role=dialog], .drawer-root') || document.body) });
      H.fermerTout();
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      out.creation = { titre: H.tiroir().texte.slice(0, 80), champs: H.champs(), defauts: {}, boutons: H.tiroir().boutons };
      for (const n of ['admissionId', 'date', 'heure', 'type', 'visiteur', 'observation']) { const e = document.getElementById('f_' + n); out.creation.defauts[n] = e ? e.value : '(absent)'; }
      out.creation.optionsAdmission = H.optsDe('admissionId');
      out.creation.optionsType = H.optsDe('type');
      H.poser('visiteur', '');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refusSansVisiteur = { toasts: H.toasts(), total: col.all().length };
      H.poser('admissionId', 'ADM2'); H.poser('date', '2026-08-16'); H.poser('heure', '11:15'); H.poser('type', 'Personnel traitant'); H.poser('visiteur', 'Dr TAKI'); H.poser('observation', 'Réévaluation');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.cree = { toasts: H.toasts(), fiche: H.net(col.all().find((r) => r.observation === 'Réévaluation')), total: col.all().length, premier: col.all()[0].observation };
      out.apres = { kpis: H.kpis(racine), tableaux: H.tableaux(racine) };
      H.bouton(racine, 'Nouveau').click(); await H.dormir(300);
      H.poser('visiteur', 'Mère'); H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.defautsFiche = H.net(col.all().find((r) => r.visiteur === 'Mère'));
      H.icone(lig('Sœur de la patiente'), 'Modifier').click(); await H.dormir(300);
      out.modification = { titre: H.tiroir().texte.slice(0, 80), champs: H.champs(), valeurs: {}, boutons: H.tiroir().boutons };
      for (const n of ['admissionId', 'date', 'heure', 'type', 'visiteur', 'observation']) { const e = document.getElementById('f_' + n); out.modification.valeurs[n] = e ? e.value : '(absent)'; }
      H.poser('admissionId', 'ADM1'); H.poser('observation', 'Corrigée');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((r) => r.id === 'VIS0003')) };
      H.icone(lig('Contrôle des constantes'), 'Archiver').click(); await H.dormir(300);
      out.archivage = { dialogue: H.tiroir().texte, boutons: H.tiroir().boutons };
      H.viderToasts(); [...document.querySelectorAll('[role=dialog]')].pop().querySelectorAll('button').forEach((b) => { if (b.textContent.trim() === 'Archiver') b.click(); }); await H.dormir(300);
      out.archivage.fait = { toasts: H.toasts(), statut: col.all().find((r) => r.id === 'VIS0004').statut, kpis: H.kpis(racine) };
      H.retirer(racine);
      col.all().splice(0);
      racine = await H.monter('m3-visites-patients');
      out.vide = { kpis: H.kpis(racine), texte: H.norm(racine.innerText).slice(0, 700) };
      H.retirer(racine);
      H.remettre([colAdm, col], sauve);
      return out;
    });

    /* ------------------------------------------------------------------ rapport médical */
    await groupe('rapport', async () => {
      const S = SIGH.store, J = H.J;
      const col = S.collection('rapportsMedicaux', { module: 'M3', entite: 'rapport médical', prefix: 'RAP' });
      const sauve = H.mettreDeCote([col]);
      const pats = S.collection('patients').active();
      const out = {};
      let racine = await H.monter('m3-rapport');
      out.vide = { kpis: H.kpis(racine), texte: H.norm(racine.innerText).slice(0, 700) };
      H.retirer(racine);
      const rap = (n, i, entree, sortie, extra) => Object.assign({ id: 'RAP' + n, statut: 'actif', reference: 'RAP-000' + n, patientCode: pats[i].code, patientId: pats[i].id, patient: pats[i].nom + ' ' + pats[i].prenom,
        age: 30 + n, sexe: pats[i].sexe, adresse: pats[i].quartier, telephone: pats[i].telephone, dateEntree: J(entree), dateSortie: sortie == null ? null : J(sortie),
        motif: 'Motif ' + n, anamnese: 'Anamnèse ' + n, examenPhysique: 'Examen ' + n, hypotheses: 'Hypothèse ' + n, traitementEntree: 'Traitement entrée ' + n,
        examensParacliniques: n === 1 ? '' : 'NFS, CRP', diagnosticRetenu: 'Retenu ' + n, traitementReajuste: '', evolution: n === 1 ? '' : 'Favorable', traitementSortie: n === 1 ? '' : 'Paracétamol', diagnosticSortie: 'Sortie ' + n,
        medecinId: 'SOI01', medecin: 'BASSONGUI Chabi Séko' }, extra || {});
      const jeu = [rap(1, 0, -10, null), rap(2, 1, -20, -15), rap(3, 2, -5, -2), rap(4, 0, -30, -25, { statut: 'archive' })];
      jeu.forEach((x) => col.all().push(x));
      out.jeu = H.propre(jeu);
      racine = await H.monter('m3-rapport');
      out.ecran = { kpis: H.kpis(racine), tableaux: H.tableaux(racine), boutons: H.boutons(racine).slice(0, 14), notes: H.notes(racine),
        badges: [...racine.querySelectorAll('tbody tr')].map((tr) => { const b = tr.querySelector('.badge, span[class*=badge]'); return b ? [H.norm(b.innerText), b.className] : null; }) };
      const lig = (t) => [...racine.querySelectorAll('tbody tr')].find((tr) => tr.innerText.includes(t));
      out.ecran.boutonsLigne = [...lig('RAP-0001').querySelectorAll('button')].map((b) => b.getAttribute('aria-label') || b.title);
      H.icone(lig('RAP-0003'), 'Consulter').click(); await H.dormir(300);
      out.detail = H.tiroir(); out.detail.tables = H.tableaux(document.querySelector('[role=dialog], .drawer-root') || document.body);
      H.fermerTout();
      H.icone(lig('RAP-0001'), 'Consulter').click(); await H.dormir(300);
      out.detailEnCours = H.tiroir();
      H.fermerTout();
      H.icone(lig('RAP-0003'), 'Imprimer le rapport').click(); await H.dormir(300);
      out.impression = H.propre(window.__etats.slice(-1)[0]);
      H.icone(lig('RAP-0001'), 'Imprimer le rapport').click(); await H.dormir(300);
      out.impressionEnCours = H.propre(window.__etats.slice(-1)[0]);
      H.fermerTout();
      H.bouton(racine, 'Nouveau rapport').click(); await H.dormir(300);
      const champsIds = ['patientCode', 'dateEntree', 'dateSortie', 'motif', 'anamnese', 'examenPhysique', 'hypotheses', 'traitementEntree', 'examensParacliniques', 'diagnosticRetenu', 'traitementReajuste', 'evolution', 'traitementSortie', 'diagnosticSortie', 'medecinId'];
      out.creation = { titre: H.tiroir().texte.slice(0, 60), champs: H.champs(), defauts: {}, boutons: H.tiroir().boutons };
      for (const n of champsIds) { const e = document.getElementById('f_' + n); out.creation.defauts[n] = e ? e.value : '(absent)'; }
      out.creation.optionsPatient = H.optsDe('patientCode').slice(0, 3);
      out.creation.nbOptionsPatient = H.optsDe('patientCode').length;
      out.creation.optionsMedecin = H.optsDe('medecinId');
      out.creation.aides = [...document.querySelectorAll('[role=dialog] p, .modal-root p')].map((p) => H.norm(p.innerText)).filter((t) => /Ce que|Tient compte/.test(t));
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(200);
      out.creation.refusVide = { toasts: H.toasts(), total: col.all().length };
      H.poser('patientCode', pats[1].code); H.poser('dateEntree', '2026-08-12'); H.poser('motif', 'Fièvre'); H.poser('anamnese', 'Depuis 3 jours'); H.poser('examenPhysique', 'T° 39'); H.poser('hypotheses', 'Paludisme');
      H.poser('traitementEntree', 'Artésunate'); H.poser('diagnosticRetenu', 'Paludisme grave'); H.poser('diagnosticSortie', 'Guérison');
      H.viderToasts(); H.cliquer('Créer'); await H.dormir(300);
      out.creation.cree = { toasts: H.toasts(), fiche: H.net(col.all().find((r) => r.motif === 'Fièvre')), total: col.all().length, premier: col.all()[0].motif, naissance: pats[1].dateNaissance };
      out.apres = { kpis: H.kpis(racine), tableaux: H.tableaux(racine) };
      H.icone(lig('RAP-0001'), 'Modifier').click(); await H.dormir(300);
      out.modification = { titre: H.tiroir().texte.slice(0, 60), valeurs: {} };
      for (const n of champsIds) { const e = document.getElementById('f_' + n); out.modification.valeurs[n] = e ? e.value : '(absent)'; }
      H.poser('dateSortie', '2026-08-15'); H.poser('diagnosticSortie', 'Sortie corrigée');
      H.viderToasts(); H.cliquer('Enregistrer'); await H.dormir(300);
      out.modification.enregistre = { toasts: H.toasts(), fiche: H.net(col.all().find((r) => r.id === 'RAP1')) };
      H.icone(lig('RAP-0002'), 'Archiver').click(); await H.dormir(300);
      out.archivage = { dialogue: H.tiroir().texte };
      H.viderToasts(); [...document.querySelectorAll('[role=dialog]')].pop().querySelectorAll('button').forEach((b) => { if (b.textContent.trim() === 'Archiver') b.click(); }); await H.dormir(300);
      out.archivage.fait = { toasts: H.toasts(), kpis: H.kpis(racine) };
      H.retirer(racine);
      H.remettre([col], sauve);
      return out;
    });

    ecrire('packages/domaine/test/vecteurs/hospitalisation2.json', sortie);
    if (m.erreurs.length) console.log('  erreurs JS de la page : ' + m.erreurs.slice(0, 5).join(' | '));
  } finally {
    await m.fermer();
  }
})().catch((e) => { console.error(e); process.exit(1); });
