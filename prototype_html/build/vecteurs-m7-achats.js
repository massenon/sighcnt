/* =============================================================================
 * VECTEURS M7 (achats) — PV de réception (consommables / réactifs), fournisseurs, factures fournisseurs
 * -----------------------------------------------------------------------------
 * Les écrans RÉELS sont montés dans la page d'extraction et PILOTÉS comme le fait l'agent : « Nouveau PV » → on remplit la modale → « Établir le
 * PV » ; « Nouveau » / « Modifier » des fournisseurs ; « Modifier » d'une facture fournisseur. Ce qui est né au magasin, les indicateurs, les
 * lignes du tableau, le texte du tiroir et la pièce imprimée (P.etat est interceptée) sont relevés.
 *   node build/vecteurs-m7-achats.js   →   packages/domaine/test/vecteurs/pv_reception.json
 *                                          packages/domaine/test/vecteurs/fournisseurs_m7.json
 *                                          packages/domaine/test/vecteurs/factures_fournisseurs.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

/* Tout ce qui suit s'exécute DANS la page. */
async function dansLaPage() {
  const S = SIGH.store, C = SIGH.core, U = SIGH.ui;
  const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
  const propre = (x) => JSON.parse(JSON.stringify(x));
  const net = (x) => { const c = Object.assign({}, x); ['id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe'].forEach((k) => delete c[k]); return propre(c); };
  const sansMeta = (x) => { const c = Object.assign({}, x); ['_creePar', '_creeLe', '_modifiePar', '_modifieLe'].forEach((k) => delete c[k]); return propre(c); };
  const feuilles = (n) => { const w = document.createTreeWalker(n, NodeFilter.SHOW_TEXT); const o = []; let t; while ((t = w.nextNode())) { const s = t.nodeValue.replace(/\s+/g, ' ').trim(); if (s) o.push(s); } return o; };
  const kpis = (root) => [...root.querySelectorAll('.kpi')].map((k) => [k.querySelector('.kpi-label').textContent, k.querySelector('.kpi-value').textContent]);
  const entetes = (root) => [...root.querySelectorAll('thead th')].map((th) => th.textContent.replace(/\s+/g, ' ').trim()).filter(Boolean);
  const lignesTable = (root) => [...root.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.textContent.replace(/\s+/g, ' ').trim()));
  const bouton = (portee, texte) => [...portee.querySelectorAll('button')].find((b) => b.textContent.trim() === texte);
  const boutonTitre = (portee, titre) => [...portee.querySelectorAll('button')].find((b) => (b.title || b.getAttribute('aria-label')) === titre);
  const poserChamp = (id, v) => {
    const e = document.getElementById('f_' + id); if (!e) throw new Error('champ ' + id);
    if (e.type === 'checkbox') { e.checked = !!v; } else { e.value = v; }
    e.dispatchEvent(new Event('input')); e.dispatchEvent(new Event('change'));
  };
  const valeurChamp = (id) => { const e = document.getElementById('f_' + id); if (!e) return null; return e.type === 'checkbox' ? !!e.checked : e.value; };
  const optionsChamp = (id) => { const e = document.getElementById('f_' + id); return e && e.options ? [...e.options].map((o) => o.textContent.replace(/\s+/g, ' ').trim()) : null; };
  const tousLesChamps = () => [...document.querySelectorAll('[id^="f_"]')].map((e) => e.id.slice(2));
  const fermer = () => { U.fermerCouches(); document.querySelectorAll('.modal-root, [role=dialog]').forEach((e) => e.remove()); document.body.style.overflow = ''; };

  /* Interception des messages et des pièces imprimées. */
  const toasts = [], imprimes = [];
  const toastOrig = U.toast;
  U.toast = function (m, o) { toasts.push({ message: m, type: (o && o.type) || null, detail: (o && o.detail) || null }); return toastOrig.apply(this, arguments); };
  SIGH.print.etat = function (o) {
    const contenu = [];
    const noeuds = o.contenu ? (o.contenu.children && o.contenu.tagName !== 'TABLE' ? [...o.contenu.children] : [o.contenu]) : [];
    noeuds.forEach((n) => {
      if (n.tagName === 'TABLE') contenu.push({ table: { entetes: [...n.querySelectorAll('thead th')].map((x) => x.textContent.replace(/\s+/g, ' ').trim()), lignes: [...n.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => td.textContent.replace(/\s+/g, ' ').trim())), pied: [...n.querySelectorAll('tfoot tr')].map((tr) => [...tr.children].map((td) => td.textContent.replace(/\s+/g, ' ').trim())) } });
      else contenu.push({ texte: n.textContent.replace(/\s+/g, ' ').trim() });
    });
    imprimes.push({ titre: o.titre, sousTitre: o.sousTitre || null, cartouche: propre(o.cartouche || []), contenu, signatures: propre(o.signatures || []) });
  };
  const vider = () => { toasts.length = 0; imprimes.length = 0; };

  SIGH.semerAchats(true);

  /* =========================================================================
   * 1. PV DE RÉCEPTION
   * ======================================================================= */
  const colPV = S.collection('pvReceptions'), colL = S.collection('livraisons'), colP = S.collection('produits');
  /* Le premier rendu amorce le registre (PV de démonstration) ; ensuite on écarte les livraisons du jeu pour que la liste des bons ne porte que
     celles que le vecteur pose, et on CITE les références des PV déjà là (la numérotation en dépend). */
  { const r0 = document.createElement('div'); document.body.appendChild(r0); SIGH.screens['m7-pv-reception-consommables'].render(r0); r0.remove(); }
  colL.active().forEach((l) => colL.archive(l.id));
  const prod = (cat, rang) => colP.active().filter((p) => p.categorie === cat)[rang || 0];
  const med1 = prod('conso_medical', 0), med2 = prod('conso_medical', 1), ent = prod('entretien', 0), rea = prod('reactif', 0), labo = prod('conso_labo', 0);
  const ligne = (p, q, l, ecart) => { const x = { produitId: p.id, produit: p.designation, unite: p.unite, quantite: q, prixUnitaire: 100, montant: q * 100, quantiteLivree: l }; if (ecart !== undefined) x.ecart = ecart; return x; };
  const livraison = (reference, date, fournisseur, lignes) => colL.insert({ reference, commandeRef: 'BC-TEST-' + reference.slice(-2), date, fournisseur: fournisseur.toUpperCase(), fournisseurNom: fournisseur, lignes, montant: 0, statutReception: 'conforme' }).record;
  const LV1 = livraison('LV-T01', '2026-10-20', 'SoBAPS SA', [ligne(med1, 100, 100, 0), ligne(rea, 20, 13, -7), ligne(med2, 50, 50, 0), ligne(labo, 30, 30, 0)]);
  const LV2 = livraison('LV-T02', '2026-10-25', 'NATI Fournitures', [ligne(ent, 10, 10, 0), ligne(med1, 40, 44, 4), { produitId: 'PRD-INCONNU', produit: 'ARTICLE HORS CATALOGUE', unite: 'Unité', quantite: 1, prixUnitaire: 1, montant: 1, quantiteLivree: 1, ecart: 0 }]);
  const LV3 = livraison('LV-T03', '2026-10-28', 'LABOTECH Réactifs', [ligne(rea, 12, 12), ligne(labo, 6, 6)]);
  const produitsCites = propre([med1, med2, ent, rea, labo]).map((p) => ({ id: p.id, designation: p.designation, unite: p.unite, categorie: p.categorie }));

  async function jouerPV(nature, nom, saisie, opts) {
    opts = opts || {};
    const root = document.createElement('div'); document.body.appendChild(root);
    SIGH.screens['m7-pv-reception-' + nature].render(root);
    await dormir(20);
    const avant = new Set(colPV.all().map((x) => x.id));
    const references = colPV.all().map((x) => x.reference);
    const livraisons = propre(colL.active());
    vider();
    bouton(document, 'Nouveau PV').click(); await dormir(30);
    const optionsLivraison = optionsChamp('livraisonRef');
    const champsModale = tousLesChamps();
    const valeursInitiales = { date: valeurChamp('date'), conclusion: valeurChamp('conclusion'), chaineFroid: valeurChamp('chaineFroid'), livraisonRef: valeurChamp('livraisonRef') };
    Object.keys(saisie).forEach((k) => poserChamp(k, saisie[k]));
    bouton(document, 'Établir le PV').click(); await dormir(60);
    const nouveaux = colPV.all().filter((x) => !avant.has(x.id));
    const pv = nouveaux.length ? net(nouveaux[0]) : null;
    const sortie = { pv, nbNouveaux: nouveaux.length, messages: propre(toasts), impression: imprimes.length ? propre(imprimes[0]) : null };
    fermer(); root.remove();
    return { nom, nature, entree: { nature, saisie, livraisons, produits: produitsCites, references, magasinier: null }, modale: { champs: champsModale, optionsLivraison, valeursInitiales }, sortie };
  }

  const pvCas = [];
  const base = { date: '2026-10-30', conclusion: 'Conforme', reserves: '', representantFournisseur: 'Livreur SoBAPS' };
  pvCas.push(await jouerPV('consommables', 'consommables : conforme sur un bon qui porte un écart (-> la conclusion n\'est PAS dérivée des écarts)', Object.assign({}, base, { livraisonRef: 'LV-T02' })));
  pvCas.push(await jouerPV('consommables', 'consommables : bon mixte, seules les lignes NON réactifs sont reprises', Object.assign({}, base, { livraisonRef: 'LV-T01' })));
  pvCas.push(await jouerPV('consommables', 'consommables : « avec réserves » sans réserves -> refus nommé', Object.assign({}, base, { livraisonRef: 'LV-T01', conclusion: 'Conforme avec réserves' })));
  pvCas.push(await jouerPV('consommables', 'consommables : réserves faites d\'espaces -> refus (le texte est rogné)', Object.assign({}, base, { livraisonRef: 'LV-T01', conclusion: 'Non conforme', reserves: '   ' })));
  pvCas.push(await jouerPV('consommables', 'consommables : non conforme avec réserves écrites', Object.assign({}, base, { livraisonRef: 'LV-T01', conclusion: 'Non conforme', reserves: 'Colis éventrés à la livraison.' })));
  pvCas.push(await jouerPV('consommables', 'consommables : conforme AVEC un texte de réserves -> le texte est conservé', Object.assign({}, base, { livraisonRef: 'LV-T02', reserves: 'Emballage extérieur légèrement humide.' })));
  pvCas.push(await jouerPV('consommables', 'consommables : millésime de la date (2027) -> série 2027, rang 0001', Object.assign({}, base, { livraisonRef: 'LV-T02', date: '2027-01-15' })));
  pvCas.push(await jouerPV('consommables', 'consommables : représentant du fournisseur absent -> formulaire en erreur, rien d\'écrit', Object.assign({}, base, { livraisonRef: 'LV-T02', representantFournisseur: '' })));
  pvCas.push(await jouerPV('reactifs', 'réactifs : chaîne du froid respectée, seules les lignes réactif / conso_labo sont reprises', Object.assign({}, base, { livraisonRef: 'LV-T01', chaineFroid: true })));
  pvCas.push(await jouerPV('reactifs', 'réactifs : chaîne du froid ROMPUE mais conclusion « Conforme » -> acceptée (aucun couplage)', Object.assign({}, base, { livraisonRef: 'LV-T03', chaineFroid: false })));
  pvCas.push(await jouerPV('reactifs', 'réactifs : chaîne rompue, non conforme avec réserves', Object.assign({}, base, { livraisonRef: 'LV-T03', chaineFroid: false, conclusion: 'Non conforme', reserves: 'Réactifs arrivés à 14 °C.' })));
  pvCas.push(await jouerPV('reactifs', 'réactifs : « avec réserves » sans réserves -> refus nommé', Object.assign({}, base, { livraisonRef: 'LV-T03', conclusion: 'Conforme avec réserves', chaineFroid: true })));

  /* Registre, indicateurs, tiroir et impression d'un PV existant, par nature. */
  const registres = [];
  for (const nature of ['consommables', 'reactifs']) {
    const root = document.createElement('div'); document.body.appendChild(root);
    SIGH.screens['m7-pv-reception-' + nature].render(root); await dormir(30);
    const pvs = propre(colPV.active().filter((p) => p.nature === nature));
    const tr = [...root.querySelectorAll('tbody tr')].find((t) => t.textContent.includes('Colis éventrés') || t.querySelector('td'));
    const lignesRegistre = lignesTable(root);
    const premier = colPV.active().filter((p) => p.nature === nature).sort((a, b) => String(b.date).localeCompare(String(a.date)))[0];
    const ligneCible = [...root.querySelectorAll('tbody tr')].find((t) => t.textContent.includes(premier.reference));
    vider();
    ligneCible.click(); await dormir(30);
    const tiroir = document.querySelector('.drawer-backdrop');
    const texteTiroir = tiroir ? feuilles(tiroir) : null;
    fermer();
    boutonTitre(ligneCible, 'Imprimer le PV').click(); await dormir(30);
    const imp = imprimes.length ? propre(imprimes[0]) : null;
    registres.push({ nature, pvs, kpis: kpis(root), entetes: entetes(root), lignes: lignesRegistre, pvOuvert: propre(premier), tiroir: texteTiroir, impression: imp });
    root.remove();
  }

  /* Registre sans livraison de cette nature : refus nommé. */
  const sansLivraison = [];
  [LV1, LV2, LV3].forEach((l) => colL.archive(l.id));
  for (const nature of ['consommables', 'reactifs']) {
    const root = document.createElement('div'); document.body.appendChild(root);
    SIGH.screens['m7-pv-reception-' + nature].render(root); await dormir(20);
    vider(); bouton(document, 'Nouveau PV').click(); await dormir(30);
    sansLivraison.push({ nature, messages: propre(toasts), modaleOuverte: !!document.querySelector('[id="f_livraisonRef"]') });
    fermer(); root.remove();
  }

  /* =========================================================================
   * 2. FOURNISSEURS
   * ======================================================================= */
  const colF = S.collection('fournisseurs'), colC = S.collection('commandes');
  const commandesLegeres = () => propre(colC.active()).map((c) => ({ id: c.id, reference: c.reference, date: c.date, fournisseur: c.fournisseur, montant: c.montant, statutCommande: c.statutCommande, lignes: (c.lignes || []).map(() => ({})) }));
  async function etatFournisseurs() {
    const root = document.createElement('div'); document.body.appendChild(root);
    SIGH.screens['m7-fournisseurs'].render(root); await dormir(30);
    const e = { kpis: kpis(root), entetes: entetes(root), lignes: lignesTable(root), onglets: [...root.querySelectorAll('[role=tab], .tab, button')].map((b) => b.textContent.replace(/\s+/g, ' ').trim()).filter((t) => /^(Tous les fournisseurs|Archivés)/.test(t)) };
    root.remove(); return e;
  }
  const fournisseursEtat = { jeu: await etatFournisseurs(), fournisseurs: propre(colF.active()), commandes: commandesLegeres() };

  async function jouerFournisseur(nom, mode, cible, saisie) {
    const root = document.createElement('div'); document.body.appendChild(root);
    SIGH.screens['m7-fournisseurs'].render(root); await dormir(20);
    const avant = new Set(colF.all().map((x) => x.id));
    const avantFiche = cible ? propre(colF.active().find((f) => f.code === cible)) : null;
    vider();
    let champsModale = null, valeursInitiales = null;
    if (mode === 'creer') bouton(document, 'Nouveau').click();
    else {
      const tr = [...root.querySelectorAll('tbody tr')].find((t) => t.textContent.includes(cible));
      boutonTitre(tr, 'Modifier').click();
    }
    await dormir(30);
    champsModale = tousLesChamps();
    valeursInitiales = {}; champsModale.forEach((c) => { valeursInitiales[c] = valeurChamp(c); });
    const optionsType = optionsChamp('type');
    Object.keys(saisie).forEach((k) => poserChamp(k, saisie[k]));
    bouton(document, mode === 'creer' ? 'Créer' : 'Enregistrer').click(); await dormir(60);
    const nouveaux = colF.all().filter((x) => !avant.has(x.id));
    const apres = cible ? propre(colF.all().find((f) => f.id === avantFiche.id)) : null;
    const sortie = { nouvelle: nouveaux.length ? net(nouveaux[0]) : null, modifiee: apres ? net(apres) : null, messages: propre(toasts) };
    fermer(); root.remove();
    const etat = await etatFournisseurs();
    return { nom, mode, cible, saisie, champsModale, valeursInitiales, optionsType, avant: avantFiche ? net(avantFiche) : null, sortie, apres: { kpis: etat.kpis, lignes: etat.lignes, onglets: etat.onglets }, entree: { fournisseurs: propre(colF.active()), commandes: commandesLegeres() } };
  }
  const fournisseursCas = [];
  const fSaisie = { code: 'TESTF', nom: 'Fournisseur d\'essai SARL', type: 'Matériel médical', ville: 'Natitingou', tel: '23 82 11 11', delai: '4', habilite: true };
  fournisseursCas.push(await jouerFournisseur('création complète : délai numérique, case cochée', 'creer', null, fSaisie));
  fournisseursCas.push(await jouerFournisseur('création sans délai ni case cochée : champs absents', 'creer', null, { code: 'TESTG', nom: 'Sans délai', type: 'Grossiste pharmaceutique', ville: '', tel: '', delai: '', habilite: false }));
  fournisseursCas.push(await jouerFournisseur('création : code DÉJÀ pris -> acceptée (aucun contrôle d\'unicité)', 'creer', null, { code: 'SOBAPS', nom: 'Doublon SoBAPS', type: 'Centrale d’achat', delai: '9', habilite: false }));
  fournisseursCas.push(await jouerFournisseur('création : raison sociale absente -> formulaire en erreur, rien d\'écrit', 'creer', null, { code: 'TESTH', nom: '' }));
  fournisseursCas.push(await jouerFournisseur('modification : délai et habilitation', 'modifier', 'CAME', { delai: '12', habilite: false }));
  fournisseursCas.push(await jouerFournisseur('modification : le code lui-même est modifiable', 'modifier', 'UBIPHARM', { code: 'UBIPHARM2' }));

  /* Tiroir et état imprimé : un fournisseur qui a des commandes, un qui n'en a pas. */
  const detailFournisseurs = [];
  for (const code of ['NATIFOURN', 'LABOTECH', 'TESTF']) {
    const root = document.createElement('div'); document.body.appendChild(root);
    SIGH.screens['m7-fournisseurs'].render(root); await dormir(20);
    const tr = [...root.querySelectorAll('tbody tr')].find((t) => t.textContent.includes(code)); if (!tr) continue;
    vider(); tr.click(); await dormir(30);
    const tiroir = document.querySelector('.drawer-backdrop');
    const texte = tiroir ? feuilles(tiroir) : null;
    const piedsTiroir = tiroir ? [...tiroir.querySelectorAll('button')].map((b) => b.textContent.trim()).filter(Boolean) : null;
    fermer();
    boutonTitre(tr, 'Imprimer l’état').click(); await dormir(30);
    detailFournisseurs.push({ code, fiche: propre(colF.active().find((f) => f.code === code)), tiroir: texte, boutonsTiroir: piedsTiroir, impression: imprimes.length ? propre(imprimes[0]) : null });
    root.remove();
  }

  /* =========================================================================
   * 3. FACTURES FOURNISSEURS
   * ======================================================================= */
  const colFF = S.collection('facturesFournisseurs');
  async function etatFactures() {
    const root = document.createElement('div'); document.body.appendChild(root);
    let erreur = null, e = null;
    try { SIGH.screens['m7-factures-fournisseurs'].render(root); await dormir(30);
      e = { kpis: kpis(root), note: (root.querySelector('.note, [class*="note"]') || {}).textContent || null, entetes: entetes(root), lignes: lignesTable(root), vide: /Aucune? /.test(root.textContent) };
      const notes = [...root.querySelectorAll('div')].filter((d) => /anomalie\(s\) de rapprochement/.test(d.textContent) && !d.querySelector('div .kpi'));
      e.noteTexte = notes.length ? notes[notes.length - 1].textContent.replace(/\s+/g, ' ').trim() : null;
    } catch (x) { erreur = String(x && x.message || x); }
    const rendu = { erreur, etat: e };
    root.remove(); return rendu;
  }
  const ffJeu = propre(colFF.active());
  const facturesJeu = await etatFactures();

  /* Jeux contrôlés : on écarte le jeu, on pose les pièces et on relit indicateurs + BFR (la même colonne). */
  colFF.active().forEach((f) => colFF.archive(f.id));
  const piece = (n, extra) => Object.assign({ reference: 'FF-T-' + n, numeroFournisseur: 'FN' + n, date: '2026-09-' + String(10 + n), blRef: 'BL' + n, commandeRef: 'BC' + n, fournisseur: 'SOBAPS', fournisseurNom: 'SoBAPS SA', montantLivraison: 1000, montantFacture: 1000, ecart: 0, statutRappro: 'rapproche', statutPaiement: 'impayee', echeance: '2026-10-' + String(10 + n) }, extra || {});
  const jeuxFF = [
    ['aucune facture', []],
    ['mélange : payée, impayée, partielle (anomalie), impayée (anomalie)', [
      piece(1, { statutPaiement: 'payee', montantFacture: 1000, montantLivraison: 1000 }),
      piece(2, { statutPaiement: 'impayee', montantFacture: 2000, montantLivraison: 2000 }),
      piece(3, { statutPaiement: 'partielle', statutRappro: 'anomalie', montantFacture: 3000, montantLivraison: 2500, ecart: 500 }),
      piece(4, { statutPaiement: 'impayee', statutRappro: 'anomalie', montantFacture: 500, montantLivraison: 800, ecart: -300 })]],
    ['une seule anomalie, tout est payé', [piece(5, { statutPaiement: 'payee', statutRappro: 'anomalie', montantFacture: 700, montantLivraison: 600, ecart: 100 })]],
    ['pièce de génération antérieure : « soldee » (le BFR l\'accepte, l\'écran ?)', [piece(6, { statutPaiement: 'soldee', montantFacture: 900 }), piece(7, { statutPaiement: 'impayee', montantFacture: 100 })]],
  ];
  const facturesCas = [];
  for (const [nom, pieces] of jeuxFF) {
    colFF.active().forEach((f) => colFF.archive(f.id));
    pieces.forEach((p) => colFF.insert(p));
    const rendu = await etatFactures();
    const bfr = SIGH.bfr.calculer();
    facturesCas.push({ nom, factures: propre(colFF.active()).map(sansMeta), rendu, bfr: { dettes: bfr.dettes, nbDettes: bfr.nbDettes, incomplet: bfr.incomplet || null } });
  }

  /* Édition : la modale « Modifier » d'une pièce — champs proposés, valeurs préremplies, ce qui est écrit. */
  colFF.active().forEach((f) => colFF.archive(f.id));
  const pEdit = colFF.insert(piece(8, { statutRappro: 'anomalie', montantFacture: 5000, montantLivraison: 4000, ecart: 1000 })).record;
  async function editerFacture(nom, saisie) {
    const root = document.createElement('div'); document.body.appendChild(root);
    SIGH.screens['m7-factures-fournisseurs'].render(root); await dormir(20);
    const avant = propre(colFF.get(pEdit.id));
    vider();
    const tr = [...root.querySelectorAll('tbody tr')].find((t) => t.textContent.includes(pEdit.reference));
    const actions = [...tr.querySelectorAll('button')].map((b) => b.title || b.getAttribute('aria-label') || b.textContent.trim());
    boutonTitre(tr, 'Modifier').click(); await dormir(30);
    const champsModale = tousLesChamps(); const valeursInitiales = {}; champsModale.forEach((c) => { valeursInitiales[c] = valeurChamp(c); });
    const optionsReglement = optionsChamp('statutPaiement');
    Object.keys(saisie).forEach((k) => poserChamp(k, saisie[k]));
    bouton(document, 'Enregistrer').click(); await dormir(60);
    const apres = propre(colFF.get(pEdit.id));
    const diff = {}; Object.keys(apres).forEach((k) => { if (JSON.stringify(apres[k]) !== JSON.stringify(avant[k]) && !k.startsWith('_')) diff[k] = apres[k]; });
    fermer(); root.remove();
    const rendu = await etatFactures();
    return { nom, saisie, actionsLigne: actions, champsModale, valeursInitiales, optionsReglement, avant: sansMeta(avant), diff, messages: propre(toasts), apres: { kpis: rendu.etat && rendu.etat.kpis, lignes: rendu.etat && rendu.etat.lignes } };
  }
  const editions = [];
  editions.push(await editerFacture('modifier le règlement seul : numéro (vide au départ) à ressaisir', { numero: 'F-2026-001', statutPaiement: 'partielle' }));
  editions.push(await editerFacture('modifier sans ressaisir le numéro -> formulaire en erreur', { statutPaiement: 'payee', numero: '' }));
  editions.push(await editerFacture('modifier le montant : le champ « montant » n\'est pas la colonne « montantFacture »', { numero: 'F-2026-002', montant: '4000', statutPaiement: 'payee' }));

  /* Tiroir de détail : une anomalie et une pièce conforme. */
  colFF.active().forEach((f) => colFF.archive(f.id));
  colFF.insert(piece(9, { statutRappro: 'anomalie', montantFacture: 5000, montantLivraison: 4000, ecart: 1000 }));
  colFF.insert(piece(10, { statutPaiement: 'payee' }));
  const tiroirs = [];
  for (const ref of ['FF-T-9', 'FF-T-10']) {
    const root = document.createElement('div'); document.body.appendChild(root);
    SIGH.screens['m7-factures-fournisseurs'].render(root); await dormir(20);
    const tr = [...root.querySelectorAll('tbody tr')].find((t) => t.textContent.includes(ref));
    tr.click(); await dormir(30);
    const tiroir = document.querySelector('.drawer-backdrop');
    tiroirs.push({ reference: ref, fiche: propre(colFF.active().find((f) => f.reference === ref)), texte: tiroir ? feuilles(tiroir) : null });
    fermer(); root.remove();
  }

  return {
    pv: { cas: pvCas, registres, sansLivraison },
    fournisseurs: { etat: fournisseursEtat, cas: fournisseursCas, detail: detailFournisseurs },
    factures: { jeu: { factures: ffJeu, rendu: facturesJeu }, cas: facturesCas, editions, tiroirs },
  };
}

(async () => {
  console.log('▶ Vecteurs M7 (PV de réception, fournisseurs, factures fournisseurs)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m7-achats.js') });
    const r = await m.page.evaluate(dansLaPage);
    r.pv.cas.forEach((c) => console.log('  PV · ' + c.nom + ' → ' + (c.sortie.pv ? c.sortie.pv.reference : 'refus : ' + JSON.stringify(c.sortie.messages.map((x) => x.message)))));
    r.fournisseurs.cas.forEach((c) => console.log('  F · ' + c.nom + ' → ' + JSON.stringify(c.sortie.messages.map((x) => x.message))));
    r.factures.cas.forEach((c) => console.log('  FF · ' + c.nom + ' → ' + (c.rendu.erreur || JSON.stringify(c.rendu.etat.kpis))));
    r.factures.editions.forEach((c) => console.log('  FF édition · ' + c.nom + ' → ' + JSON.stringify(c.diff)));
    const doc = (nom) => 'ENGENDRÉ par prototype_html/build/vecteurs-m7-achats.js — ' + nom + ' pilotés dans la maquette. Ne pas éditer.';
    ecrire('packages/domaine/test/vecteurs/pv_reception.json', Object.assign({ _doc: doc('les écrans de PV de réception') }, r.pv));
    ecrire('packages/domaine/test/vecteurs/fournisseurs_m7.json', Object.assign({ _doc: doc('l\'écran m7-fournisseurs') }, r.fournisseurs));
    ecrire('packages/domaine/test/vecteurs/factures_fournisseurs.json', Object.assign({ _doc: doc('l\'écran m7-factures-fournisseurs') }, r.factures));
    if (m.erreurs.length) console.log('  (erreurs de page : ' + m.erreurs.slice(0, 3).join(' | ') + ')');
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
