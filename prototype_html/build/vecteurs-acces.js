/* =============================================================================
 * VECTEURS DES ÉCRANS D'ACCÈS ET DE SUPPORT — les écrans RÉELS pilotés comme le fait l'agent
 * -----------------------------------------------------------------------------
 * Dix écrans : index (connexion), auth-forgot, auth-reset, auth-2fa, auth-lock, error-404, error-403, plan-du-site (autonomes, sans coquille) ;
 * aide-apropos, contact-editeur (module SUP, hors ruban). Chaque cas monte l'écran dans Chrome, saisit, clique, et relève ce que l'agent voit
 * (textes, messages, destination de la navigation). Les navigations (`location.href = …`) sont INTERCEPTÉES par l'API Navigation du navigateur :
 * on relève l'adresse visée sans quitter l'écran.
 *   SIGH_PORT_PHP=10873 flock /tmp/sigh-banc.lock node build/vecteurs-acces.js   →   packages/domaine/test/vecteurs/acces.json
 * L'horloge est fixée au 30/10/2026 10 h : `C.aujourdhui()` ET `new Date()`.
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des écrans d’accès et de support');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      SIGH.core.aujourdhui = () => new Date(2026, 9, 30, 10, 0, 0);
      const Vrai = Date;
      const FIXE = new Vrai(2026, 9, 30, 10, 0, 0).getTime();
      class Faux extends Vrai { constructor(...a) { if (a.length === 0) super(FIXE); else super(...a); } static now() { return FIXE; } }
      window.Date = Faux;
      window.__nav = [];
      navigation.addEventListener('navigate', (e) => { if (e.cancelable) { e.preventDefault(); window.__nav.push(e.destination.url.replace(location.origin + '/', '')); } });
    });
    for (const f of ['auth.js', 'support.js']) await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules', f) });

    const sortie = await m.page.evaluate(async () => {
      const S = SIGH.store, C = SIGH.core, N = SIGH.nav;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x, (k, v) => (v === undefined ? null : v)));
      const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
      const norm = (t) => String(t || '').replace(/\s+/g, ' ').trim();
      const nettoyer = () => { document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove()); document.querySelectorAll('#toast-host > div').forEach((e) => e.remove()); };
      const monter = async (id) => { nettoyer(); document.querySelectorAll('[data-vec]').forEach((e) => e.remove()); const root = document.createElement('div'); root.setAttribute('data-vec', id); document.body.appendChild(root); SIGH.screens[id].render(root); await dormir(120); return root; };
      const toasts = () => [...document.querySelectorAll('#toast-host > div')].map((t) => ({ titre: norm((t.querySelector('p') || {}).textContent), detail: norm(((t.querySelectorAll('p')[1]) || {}).textContent) }));
      const textes = (root) => [...root.querySelectorAll('h1,h2,h3,label,button,a,p,li,summary,th,.card-title,.kpi-label')].map((e) => norm(e.textContent)).filter(Boolean);
      const navs = () => { const v = window.__nav.slice(); window.__nav.length = 0; return v; };
      const clic = (b) => b.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
      const soumettre = (f) => f.dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
      const sortieG = {};
      const sessionOrigine = S.session();

      /* ========================================================================== CONNEXION */
      {
        const root = await monter('index');
        const form = root.querySelector('form');
        const erreur = () => { const e = root.querySelector('p.text-xs.text-danger-900'); return { texte: norm(e.textContent), visible: !e.parentElement.classList.contains('hidden') }; };
        const essais = [];
        for (let i = 0; i < 3; i++) { soumettre(form); await dormir(40); essais.push(erreur()); }
        const mdp = form.querySelector('#motdepasse');
        const typeAvant = mdp.type;
        clic(mdp.parentElement.querySelector('button')); const typeApres = mdp.type;
        clic(mdp.parentElement.querySelector('button'));
        // identifiants refusés par le serveur (même message que l'identifiant soit inconnu ou le mot de passe faux)
        form.querySelector('#identifiant').value = 'inconnu.xyz'; mdp.value = 'faux';
        soumettre(form); await dormir(900);
        const refus = erreur();
        sortieG.connexion = propre({
          textes: textes(root), essaisVides: essais, refusServeur: refus,
          champs: [...form.querySelectorAll('input')].map((i) => ({ id: i.id || null, type: i.type, valeur: i.value, placeholder: i.placeholder, requis: i.required, autocomplete: i.autocomplete || null })),
          nbSelect: root.querySelectorAll('select').length,
          nbLiens: [...root.querySelectorAll('a')].map((a) => ({ texte: norm(a.textContent), href: a.getAttribute('href') })),
          bascule: { avant: typeAvant, apres: typeApres },
          mentions: [...root.querySelectorAll('aside p, aside li, aside h1')].map((e) => norm(e.textContent)),
        });
      }

      /* ========================================================================== MOT DE PASSE OUBLIÉ */
      {
        const root = await monter('auth-forgot');
        const f = root.querySelector('form'); const champ = f.querySelector('input');
        const avant = { requis: champ.required, placeholder: champ.placeholder };
        champ.value = 'a.kassa'; soumettre(f); await dormir(150);
        const t = toasts(); await dormir(1400);
        sortieG.oubli = propre({ textes: textes(root), champ: avant, toasts: t, navigation: navs() });
      }

      /* ========================================================================== RÉINITIALISATION */
      {
        const root = await monter('auth-reset');
        const f = root.querySelector('form'); const [a, b] = f.querySelectorAll('input');
        a.value = 'Motdepasse#2026'; b.value = 'autre'; soumettre(f); await dormir(150);
        const discordance = toasts(); const navD = navs(); nettoyer();
        a.value = 'a'; b.value = 'a'; soumettre(f); await dormir(150);
        const faible = toasts(); await dormir(1200); const navF = navs(); nettoyer();
        a.value = 'Motdepasse#2026'; b.value = 'Motdepasse#2026'; soumettre(f); await dormir(150);
        const ok = toasts(); await dormir(1200);
        sortieG.reinit = propre({
          textes: textes(root), discordance, navDiscordance: navD, faible, navFaible: navF, ok, navigation: navs(),
          regles: [...root.querySelectorAll('ul.space-y-1\\.5 li')].map((l) => norm(l.textContent)),
        });
      }

      /* ========================================================================== DOUBLE FACTEUR */
      {
        S.setSession({ jeton: sessionOrigine && sessionOrigine.jeton, role: 'reception', nom: 'Agent de test', poste: 'Réception', identifiant: 'e.orou' });
        const root = await monter('auth-2fa');
        const f = root.querySelector('form'); const cases = [...f.querySelectorAll('input')];
        cases[0].value = '1'; cases[0].dispatchEvent(new Event('input')); const focusApresSaisie = document.activeElement === cases[1];
        soumettre(f); await dormir(120); const t = toasts(); await dormir(1100);
        sortieG.doubleFacteur = propre({
          textes: textes(root), nbCases: cases.length, maxlength: cases[0].maxLength, mode: cases[0].inputMode,
          etiquettes: cases.map((c) => c.getAttribute('aria-label')), focusApresSaisie, toasts: t, navigation: navs(),
          retourSansSession: null,
        });
        S.setSession({ jeton: sessionOrigine.jeton, role: 'admin', nom: 'Admin', poste: 'Administrateur', identifiant: 'admin.systeme' });
      }

      /* ========================================================================== PAGES D'ERREUR */
      {
        const pages = {};
        for (const id of ['error-404', 'error-403']) {
          S.setSession({ jeton: sessionOrigine.jeton, role: 'reception', nom: 'Agent de test', poste: 'Réception', identifiant: 'e.orou' });
          const r1 = await monter(id);
          const liens = [...r1.querySelectorAll('a')].map((a) => ({ texte: norm(a.textContent), href: a.getAttribute('href') }));
          const textesAvec = textes(r1);
          S.setSession(null);
          const r2 = await monter(id);
          pages[id] = { textes: textesAvec, liensConnecte: liens, lienAccueilDeconnecte: [...r2.querySelectorAll('a')].map((a) => ({ texte: norm(a.textContent), href: a.getAttribute('href') })), roleAccueil: N.ROLES.reception.home };
        }
        sortieG.erreurs = propre(pages);
        S.setSession({ jeton: sessionOrigine.jeton, role: 'admin', nom: 'Admin', poste: 'Administrateur', identifiant: 'admin.systeme' });
      }

      /* ========================================================================== ÉCRAN VERROUILLÉ */
      {
        const A = SIGH.app; const cle = A.VERROU_RETOUR;
        const session = { jeton: sessionOrigine.jeton, role: 'reception', nom: 'EZIN Orou', poste: 'Réception', identifiant: 'e.orou' };
        const cas = {};
        // 1) avec une adresse de retour (écran + onglet)
        S.setSession(session);
        S.storage.set(cle, 'm2-agenda' + N.EXT + '#onglet=semaine');
        const r1 = await monter('auth-lock');
        const f = r1.querySelector('form');
        cas.avecRetour = { textes: textes(r1), retourPresentAvant: !!S.storage.get(cle) };
        f.querySelector('input').value = 'x'; soumettre(f); await dormir(120);
        cas.avecRetour.navigation = navs(); cas.avecRetour.retourConsommeApres = !S.storage.get(cle);
        const audit = S.collection('audit', {}).all()[0];
        cas.avecRetour.journal = { action: audit.action, module: audit.module, entite: audit.entite, reference: audit.reference, apres: audit.apres || audit.nouvelle || null };
        // 2) sans adresse de retour : retour à l'accueil du rôle
        S.storage.remove(cle);
        const r2 = await monter('auth-lock');
        const f2 = r2.querySelector('form'); f2.querySelector('input').value = 'x'; soumettre(f2); await dormir(120);
        cas.sansRetour = { textes: textes(r2), navigation: navs() };
        // 3) adresse de retour inconnue du manifeste : pas de message de retour
        S.storage.set(cle, 'page-inexistante' + N.EXT);
        const r3 = await monter('auth-lock'); cas.retourInconnu = { textes: textes(r3) };
        S.storage.remove(cle);
        // 4) sans session : renvoi à la connexion
        S.setSession(null);
        navs(); await monter('auth-lock'); cas.sansSession = { navigation: navs() };
        // 5) « Se connecter avec un autre compte » efface la session et l'adresse de retour
        S.setSession(session); S.storage.set(cle, 'm2-agenda' + N.EXT);
        const r5 = await monter('auth-lock');
        const lien = [...r5.querySelectorAll('a')].find((a) => /autre compte/.test(a.textContent));
        clic(lien); await dormir(60);
        cas.autreCompte = { href: lien.getAttribute('href'), sessionApres: S.session() === null || S.session() === undefined, retourApres: !S.storage.get(cle), navigation: navs() };
        cas.delaiDefautMinutes = Math.round(A.delaiVerrou() / 60000);
        cas.cleRetour = cle;
        sortieG.verrou = propre(cas);
        S.setSession({ jeton: sessionOrigine.jeton, role: 'admin', nom: 'Admin', poste: 'Administrateur', identifiant: 'admin.systeme' });
      }

      /* ========================================================================== PLAN DU SITE */
      {
        const root = await monter('plan-du-site');
        const sections = [...root.querySelectorAll('section')].map((s) => ({
          titre: norm((s.querySelector('h2') || {}).textContent),
          modules: [...s.querySelectorAll('.card')].map((c) => ({
            titre: norm(c.querySelector('.text-sm.font-semibold').textContent), code: norm(c.querySelector('.badge').textContent),
            ecrans: [...c.querySelectorAll('li a')].map((a) => ({ label: norm(a.textContent), href: a.getAttribute('href') })),
          })),
          liensSysteme: [...s.querySelectorAll('.flex-wrap a')].map((a) => ({ label: norm(a.textContent), href: a.getAttribute('href') })),
        }));
        sortieG.plan = propre({
          entete: textes(root).slice(0, 3), sections, pied: norm(root.querySelector('p.text-xs.text-slate-400').textContent),
          retour: norm([...root.querySelectorAll('a.btn-primary')][0].textContent), homeAdmin: N.ROLES.admin.home,
        });
      }

      /* ========================================================================== AIDE & À PROPOS */
      {
        const root = await monter('aide-apropos');
        const kpis = [...root.querySelectorAll('.kpi')].map((k) => ({ label: norm(k.querySelector('.kpi-label').textContent), valeur: norm(k.querySelector('.kpi-value').textContent) }));
        const faq = [...root.querySelectorAll('details')].map((d) => ({ q: norm(d.querySelector('summary').textContent), r: norm(d.querySelector('p').textContent), ouvert: d.open }));
        const modules = [...root.querySelectorAll('a.hub-card')].map((a) => ({ titre: norm(a.querySelector('.text-sm.font-semibold').textContent), code: norm(a.querySelector('.badge').textContent), resume: norm(a.querySelectorAll('span.block')[0].textContent), domaine: norm(a.querySelectorAll('span.block')[1].textContent), href: a.getAttribute('href') }));
        const apropos = [...root.querySelectorAll('.card')].filter((c) => /À propos/.test(c.textContent)).map((c) => [...c.querySelectorAll('.border-b')].map((l) => [...l.children].map((x) => norm(x.textContent))))[0] || [];
        sortieG.aide = propre({
          kpis, faq, modules, apropos, textes: textes(root).slice(0, 12),
          nbRoles: Object.keys(N.ROLES).length, rolesArchives: Object.keys(N.ROLES).filter((r) => N.roleArchive(r)),
          appel: norm(root.querySelector('.border-navy-200 .text-navy-900').textContent), lienContact: [...root.querySelectorAll('a')].filter((a) => /Contacter/.test(a.textContent)).map((a) => a.getAttribute('href')),
        });
      }

      /* ========================================================================== CONTACTEZ L'ÉDITEUR */
      {
        const col = S.collection('support', { module: 'SUP', entite: 'DemandeSupport' });
        col.all().splice(0);
        const root = await monter('contact-editeur');
        const boutons = [...root.querySelectorAll('button')];
        const btn = (t) => boutons.find((b) => norm(b.textContent) === t);
        const cartes = [...root.querySelectorAll('.card-title')].map((c) => norm(c.textContent));
        const champ = (id) => document.getElementById('f_' + id);
        const poser = (id, v) => { const e = champ(id); if (!e) throw new Error('champ ' + id); e.value = v; e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change')); };
        // refus : formulaires vides
        clic(btn('Envoyer le message')); await dormir(80); const refusMessage = toasts(); nettoyer();
        clic(btn('Signaler l’anomalie')); await dormir(80); const refusAnomalie = toasts(); nettoyer();
        const champs = [...root.querySelectorAll('[id^=f_]')].map((e) => ({ id: e.id.slice(2), balise: e.tagName.toLowerCase(), requis: e.required, placeholder: e.placeholder || null }));
        const libelles = [...root.querySelectorAll('label')].map((l) => norm(l.textContent));
        // envoi d'un message
        poser('objet', 'Question sur la comptabilité'); poser('message', 'Comment lire la balance ?');
        clic(btn('Envoyer le message')); await dormir(100);
        const toastMessage = toasts(); nettoyer();
        const apresMessage = { objet: champ('objet').value, message: champ('message').value };
        // signalement d'une anomalie
        poser('module', 'M8'); poser('description', 'Le reçu ne se détaille pas'); poser('etapes', '1. Encaisser 2. Imprimer');
        clic(btn('Signaler l’anomalie')); await dormir(100);
        const toastAnomalie = toasts(); nettoyer();
        const fiches = propre(col.all().map((f) => { const c = Object.assign({}, f); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe'].forEach((k) => delete c[k]); return c; }));
        const optionsModule = N.NAV.flatMap((dom) => dom.modules.map((mod) => ({ valeur: mod.code, label: mod.code + ' — ' + mod.label, domaine: dom.domain }))).concat([{ valeur: 'AUTRE', label: 'AUTRE — Autre / je ne sais pas', domaine: null }]);
        // le tableau des demandes envoyées
        const lignes = [...root.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => norm(td.textContent)));
        const entetes = [...root.querySelectorAll('thead th')].map((th) => norm(th.textContent));
        // annulation du dernier envoi (le toast propose « Annuler »)
        const cartesCoord = [...root.querySelectorAll('.card')].filter((c) => /Coordonnées/.test(c.textContent)).map((c) => [...c.querySelectorAll('p')].map((p) => norm(p.textContent)))[0];
        sortieG.contact = propre({
          cartes, champs, libelles, refusMessage, refusAnomalie, toastMessage, toastAnomalie, apresMessage, fiches, lignes, entetes, optionsModule,
          coordonnees: cartesCoord, textes: textes(root).slice(0, 10),
          note: norm(root.querySelector('.note, [class*=info-50]') ? root.querySelector('.note, [class*=info-50]').textContent : ''),
        });
      }
      return sortieG;
    });
    if (m.erreurs.length) console.log('  erreurs de page :', m.erreurs.slice(0, 5));
    ecrire('packages/domaine/test/vecteurs/acces.json', sortie);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
