/* Captures ANNOTÉES du manuel d'utilisation, prises sur la maquette (exécutable de référence) servie par serveur.js.
   node captures.js [fragment] ; écrit captures/<id>.png (palette réduite par optimiser.py). Données de démonstration seulement,
   noms du personnel masqués (outils.masquer). */
'use strict';
const path = require('path');
const fs = require('fs');
const O = require('./outils');
const DOSSIER = path.join(__dirname, 'captures');
const clic = (texte) => async (page) => {
  const h = await O.trouver(page, 'texte:' + texte); const el = h && h.asElement();
  if (!el) throw new Error('bouton introuvable : ' + texte);
  await el.click(); await new Promise((r) => setTimeout(r, 1500)); await O.attendrePeinture(page); await new Promise((r) => setTimeout(r, 700));
};
const clicSel = (sel) => async (page) => { await page.click(sel); await new Promise((r) => setTimeout(r, 1500)); };

/* id, écran, rôle, cibles annotées (texte exact « texte: », texte contenu « contient: » ou sélecteur CSS), options. */
const PLAN = [
  { id: 'connexion', ecran: '/index.php', role: null, cibles: ['texte:Se connecter'], deconnecte: true },
  { id: 'barre-ruban', ecran: 'dash-receptionniste', role: 'reception', cibles: ['#pastille-sync', 'contient:Rechercher un patient'], ruban: true, h: 470 },
  { id: 'ruban-ouvert', ecran: 'm1-patients', role: 'reception', cibles: ['texte:Soins'], ruban: true, h: 470 },
  { id: 'tableau-bord-accueil', ecran: 'dash-receptionniste', role: 'reception', cibles: [] },
  { id: 'tableau-commun', ecran: 'm1-patients', role: 'admin', cibles: ['contient:Rechercher un patient', 'texte:Colonnes', 'texte:Exporter', 'texte:Nouveau', 'texte:Importer les données'], y: 380, h: 520 },
  { id: 'actions-ligne', ecran: 'm1-patients', role: 'admin', cibles: ['#page-content table tbody tr td:last-child'], y: 380, h: 520 },
  { id: 'onglet-archives', ecran: 'm1-patients', role: 'admin', cibles: ['contient:Archivés'], y: 380, h: 420 },
  { id: 'patient-nouveau', ecran: 'm1-patients', role: 'reception', avant: clic('Nouveau'), cibles: ['texte:Ouvrir le dossier'] },
  { id: 'patient-fiche', ecran: 'm1-patient-profil', role: 'medecin', cibles: ['texte:Modifier le dossier', 'texte:Imprimer la fiche'] },
  { id: 'constantes', ecran: 'm1-constantes', role: 'infirmier', avant: clic('Nouveau relevé'), cibles: ['texte:Créer'] },
  { id: 'patient-externe', ecran: 'm1-externe', role: 'reception', cibles: ['texte:Nouvelle demande externe'], y: 0, h: 620 },
  { id: 'rendez-vous', ecran: 'm2-rendezvous', role: 'reception', avant: clic('Nouveau'), cibles: ['texte:Créer'] },
  { id: 'file-attente', ecran: 'm2-file-attente', role: 'reception', cibles: ['texte:Inscrire un patient', 'texte:Appeler'] },
  { id: 'agenda', ecran: 'm2-agenda', role: 'reception', cibles: ['texte:Nouveau rendez-vous'] },
  { id: 'consultation-fiche', ecran: 'm2-consultation-fiche', role: 'medecin', avant: async (page) => {
    const id = await page.evaluate(() => { const L = window.SIGH.store.collection('dossiersConsultation').all().filter((d) => !d.archive); return (L.find((d) => /enregistr|ouvert|cours/i.test(d.etat || '')) || L[L.length - 1] || {}).id; });
    if (!id) throw new Error('aucun dossier de consultation');
    await page.goto(`http://127.0.0.1:${O.PORT}/pages/m2-consultation-fiche.php?r=1#onglet=${id}`, { waitUntil: 'domcontentloaded' });
    await O.attendrePeinture(page); await new Promise((r) => setTimeout(r, 1200));
  }, cibles: ['texte:Ajouter un médicament'] },
  { id: 'consultation-prescrire', ecran: 'm2-consultation-fiche', role: 'medecin', avant: async (page) => {
    const id = await page.evaluate(() => { const L = window.SIGH.store.collection('dossiersConsultation').all().filter((d) => !d.archive); return (L.find((d) => /enregistr|ouvert|cours/i.test(d.etat || '')) || L[L.length - 1] || {}).id; });
    if (!id) throw new Error('aucun dossier de consultation');
    await page.goto(`http://127.0.0.1:${O.PORT}/pages/m2-consultation-fiche.php?r=1#onglet=${id}`, { waitUntil: 'domcontentloaded' });
    await O.attendrePeinture(page); await new Promise((r) => setTimeout(r, 1200));
  }, cibles: ['texte:Enregistrer et prescrire'] },
  { id: 'prescriptions', ecran: 'm2-prescriptions', role: 'medecin', cibles: ['texte:Nouvelle prescription de soins'] },
  { id: 'salle-soins', ecran: 'm2-salle-soins', role: 'infirmier', cibles: ['texte:Administrer'] },
  { id: 'imagerie-demandes', ecran: 'm2-imagerie-demandes', role: 'medecin', cibles: ['texte:Nouvelle demande', 'texte:Saisir le CR'] },
  { id: 'admission', ecran: 'm3-admissions', role: 'infirmier', avant: clic('Nouveau'), cibles: ['texte:Créer'] },
  { id: 'plan-lits', ecran: 'm3-plan-lits', role: 'infirmier', cibles: [] },
  { id: 'sortie', ecran: 'm3-sorties', role: 'infirmier', avant: clic('Préparer la sortie'), cibles: ['texte:Finaliser la sortie'] },
  { id: 'maternite', ecran: 'm4-accouchements', role: 'infirmier', cibles: ['texte:Nouveau'] },
  { id: 'labo-prelevement', ecran: 'm5-prelevement', role: 'laborantin', cibles: ['contient:À prélever', 'contient:À transmettre', 'contient:Reçus au laboratoire'] },
  { id: 'labo-resultats', ecran: 'm5-resultats', role: 'laborantin', cibles: ['contient:À saisir', 'contient:À valider biologiquement', 'contient:Rendus au prescripteur'] },
  { id: 'labo-impression', ecran: 'm5-impression-resultats', role: 'laborantin', cibles: ['texte:Imprimer'] },
  { id: 'dispensation', ecran: 'm6-dispensation', role: 'caissier', cibles: ['#page-content table tbody tr td:last-child button'] },
  { id: 'stock-detail', ecran: 'm6-stock-detail', role: 'stock', cibles: ['texte:Éditer l’état'] },
  { id: 'transfert', ecran: 'm6-transferts', role: 'stock', avant: clic('Nouveau transfert'), cibles: ['texte:Valider le transfert'] },
  { id: 'inventaire', ecran: 'm6-inventaire', role: 'stock', avant: clic('Lancer un inventaire'), cibles: ['texte:Ouvrir la feuille de saisie'] },
  { id: 'pertes', ecran: 'm6-pertes', role: 'stock', avant: clic('Déclarer une perte'), cibles: ['texte:Déclarer la perte'] },
  { id: 'alertes-stock', ecran: 'm6-alertes', role: 'stock', cibles: ['contient:Sous le seuil', 'contient:Péremptions'] },
  { id: 'besoins', ecran: 'm7-besoins', role: 'stock', avant: clic('Nouveau bon'), cibles: ['texte:Créer le bon'] },
  { id: 'commande', ecran: 'm7-commandes', role: 'stock', cibles: ['texte:Nouvelle commande', 'contient:Validée par'] },
  { id: 'reception-commande', ecran: 'm7-receptions', role: 'stock', avant: clic('Réceptionner'), cibles: ['texte:Valider la réception'] },
  { id: 'facturation', ecran: 'm8-facturation', role: 'caissier', cibles: ['texte:Ajouter', 'texte:Enregistrer et encaisser'] },
  { id: 'encaisser', ecran: 'm8-paiements', role: 'caissier', avant: clic('Encaisser'), cibles: ['texte:Valider l’encaissement'] },
  { id: 'caisse', ecran: 'm8-caisse', role: 'caissier', cibles: ['texte:Éditer l’arrêté de caisse'] },
  { id: 'avoir', ecran: 'm8-facture-avoir', role: 'comptable', avant: clic('Émettre un avoir'), cibles: ['texte:Émettre l’avoir'] },
  { id: 'assures', ecran: 'm9-assures', role: 'caissier', cibles: ['contient:Validité (RG-09)', 'texte:Vérifier la carte'] },
  { id: 'mecef', ecran: 'mecef-factures', role: 'caissier', cibles: ['contient:Statut fiscal'] },
  { id: 'ecriture', ecran: 'm12-ecritures', role: 'comptable', avant: clic('Nouvelle écriture'), cibles: ['texte:Enregistrer en brouillon', 'texte:Valider l’écriture'] },
  { id: 'depense', ecran: 'm12-depenses', role: 'comptable', avant: clic('Nouvelle dépense'), cibles: ['texte:Enregistrer'] },
  { id: 'balance', ecran: 'm12-balance', role: 'comptable', cibles: ['texte:Imprimer la balance'] },
  { id: 'cloture', ecran: 'm12-cloture', role: 'comptable', cibles: ['contient:Circuit de clôture'] },
  { id: 'planning', ecran: 'm10-planning', role: 'da', cibles: ['texte:Imprimer le planning'] },
  { id: 'conges', ecran: 'm10-conges', role: 'da', avant: clic('Nouveau'), cibles: ['texte:Créer'] },
  { id: 'paie', ecran: 'm11-calcul', role: 'da', cibles: ['texte:Lancer le calcul', 'texte:Générer les bulletins'] },
  { id: 'courriers', ecran: 'm13-courriers', role: 'agentadmin', cibles: ['texte:Nouveau'] },
  { id: 'validations', ecran: 'adm-validations', role: 'da', cibles: [] },
  { id: 'etats', ecran: 'rapports-bibliotheque', role: 'direction', cibles: [] },
  { id: 'import', ecran: 'imp-accueil', role: 'admin', cibles: ['contient:Historique des lots'] },
  { id: 'tableau-direction', ecran: 'dash-direction', role: 'direction', cibles: [] },
  { id: 'notifications', ecran: 'dash-caissier', role: 'caissier', cibles: ['#cloche-notifications, button[aria-label*="otification"], button[title*="otification"]'], h: 470 },
  { id: 'exporter', ecran: 'm1-patients', role: 'admin', avant: clic('Exporter'), cibles: ['contient:Tout exporter', 'contient:Excel (.xlsx)'] },
  /* ---- Édition du 17/11/2026 : écrans des lots SMS-R, SAT, MECEF-M, IDENT, PLAN-INDIV, PTA, FISC-2, CLO-3, CMD, SURV, TIERS ---- */
  { id: 'fiche-equipe', ecran: 'm10-fiche-equipe', role: 'surveillant', avant: async (page) => {
    await page.evaluate(() => { const P = window.SIGH.store.collection('personnel').all(); const a = P.find((x) => /GARBA/i.test(x.nomComplet || x.nom || '')) || {};
      const s = JSON.parse(localStorage.getItem('sigh-cnt:session')); s.nom = a.nomComplet || (a.nom + ' ' + (a.prenom || '')); s.nomComplet = s.nom; localStorage.setItem('sigh-cnt:session', JSON.stringify(s)); });
    await page.reload({ waitUntil: 'domcontentloaded' }); await O.attendrePeinture(page); await new Promise((r) => setTimeout(r, 1500));
  }, cibles: [] },
  { id: 'factures-tiers', ecran: 'm8-factures-tiers', role: 'caissier', cibles: ['texte:Nouvelle facture à un tiers payeur', 'texte:Créances'] },
  { id: 'facture-tiers-nouvelle', ecran: 'm8-factures-tiers', role: 'caissier', avant: clic('Nouvelle facture à un tiers payeur'), cibles: [] },
  { id: 'sms-passerelle', ecran: 'cfg-sms', role: 'admin', cibles: ['texte:Enregistrer la passerelle', 'texte:Tester l’envoi'] },
  { id: 'sms-journal', ecran: 'm13-sms-journal', role: 'admin', cibles: ['contient:Tous les envois', 'contient:Sept derniers jours'] },
  { id: 'satisfaction', ecran: 'adm-satisfaction', role: 'direction', cibles: ['texte:Exporter'] },
  { id: 'enquetes-liens', ecran: 'adm-enquetes', role: 'direction', cibles: ['contient:Liens de partage', 'texte:Nouveau modèle'] },
  { id: 'mecef-modes', ecran: 'mecef-config', role: 'da', cibles: ['texte:Régler le mode', 'texte:Régler l’imprimante', 'texte:Voir la file'] },
  { id: 'identite-rccm', ecran: 'cfg-fiscalite', role: 'direction', cibles: ['texte:Enregistrer'] },
  { id: 'identite-papier', ecran: 'cfg-branding', role: 'direction', cibles: ['texte:Enregistrer', 'texte:Prévisualiser un état'] },
  { id: 'regime-individuel', ecran: 'm10-planning', role: 'da', cibles: ['texte:Nouveau régime', 'texte:Déroger pour un agent'] },
  { id: 'plan-annuel', ecran: 'm13-plan-annuel', role: 'direction', cibles: ['texte:Nouvelle action', 'texte:Imprimer le plan'] },
  { id: 'cnss-confirmation', ecran: 'cfg-comptabilite', role: 'da', cibles: ['texte:Confirmer'] },
  { id: 'aib-imputations', ecran: 'cfg-bareme-aib', role: 'comptable', avant: clic('Imputations'), cibles: [] },
  { id: 'commande-daf', ecran: 'm7-commandes', role: 'da', cibles: ['texte:Nouvelle commande'] },
  { id: 'validations-attente', ecran: 'adm-validations', role: 'da', cibles: [] },
  { id: 'menu-actions', ecran: 'dash-receptionniste', role: 'reception', avant: clic('Actions'), cibles: [], h: 620 },
];

/* Le téléphone : le simulateur de la maquette (mobile/ecrans/*.php), profil choisi par l'adresse. */
const PLAN_MOBILE = [
  { id: 'mob-appairage', ecran: 'appairage', profil: 'soignant' },
  { id: 'mob-verrou', ecran: 'verrou', profil: 'soignant' },
  { id: 'mob-tournee', ecran: 'accueil-soignant', profil: 'soignant' },
  { id: 'mob-dossier', ecran: 'dossier', profil: 'soignant' },
  { id: 'mob-constantes', ecran: 'constantes', profil: 'soignant' },
  { id: 'mob-visites', ecran: 'accueil-medecin', profil: 'medecin' },
  { id: 'mob-prescription', ecran: 'prescription', profil: 'medecin' },
  { id: 'mob-suivis', ecran: 'accueil-sagefemme', profil: 'sagefemme' },
  { id: 'mob-reception', ecran: 'accueil-reception', profil: 'reception' },
  { id: 'mob-nouveau-dossier', ecran: 'nouveau-dossier', profil: 'reception' },
  { id: 'mob-sync', ecran: 'sync', profil: 'soignant' },
  { id: 'mob-a-traiter', ecran: 'a-traiter', profil: 'soignant' },
  { id: 'mob-lot', ecran: 'lot', profil: 'soignant' },
  { id: 'mob-reglages', ecran: 'parametres', profil: 'soignant' },
];

async function capturesMobiles(browser, filtre, bilan) {
  const page = await browser.newPage();
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
  for (const c of PLAN_MOBILE) {
    if (filtre && !c.id.includes(filtre)) continue;
    try {
      await page.goto(`http://127.0.0.1:${O.PORT}/mobile/ecrans/${c.ecran}.php?os=android&profil=${c.profil}`, { waitUntil: 'domcontentloaded' });
      await new Promise((r) => setTimeout(r, 1200));
      await page.evaluate(() => {
        const P = (window.SIGHM_MANIFESTE && window.SIGHM_MANIFESTE.PROFILS) || {};
        const noms = Object.values(P).map((p) => p.agent).filter((n) => n && !/de garde/.test(n));
        const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); const ns = []; while (w.nextNode()) ns.push(w.currentNode);
        ns.forEach((t) => { let v = t.nodeValue; noms.forEach((n) => { v = v.split(n).join('Agent de démonstration'); }); if (v !== t.nodeValue) t.nodeValue = v; });
        document.querySelectorAll('input').forEach((i) => { noms.forEach((n) => { if (i.value.includes(n)) i.value = i.value.split(n).join('Agent de démonstration'); }); });
      });
      await page.screenshot({ path: path.join(DOSSIER, c.id + '.png') });
      bilan.push(c.id + '  ok');
    } catch (e) { bilan.push(c.id + '  ÉCHEC : ' + String(e.message).slice(0, 160)); }
  }
  await page.close();
}

(async () => {
  const filtre = process.argv[2];
  fs.mkdirSync(DOSSIER, { recursive: true });
  const { browser, page } = await O.ouvrirNavigateur();
  const bilan = [];
  for (const c of PLAN) {
    if (filtre && !c.id.includes(filtre)) continue;
    if (filtre === 'mob') break;
    try {
      if (c.deconnecte) {
        await page.goto(`http://127.0.0.1:${O.PORT}/pages/aide-apropos.php`, { waitUntil: 'domcontentloaded' });
        await page.evaluate(() => { localStorage.removeItem('sigh-cnt:session'); });
        await page.goto(`http://127.0.0.1:${O.PORT}${c.ecran}`, { waitUntil: 'domcontentloaded' });
        await new Promise((r) => setTimeout(r, 2500));
      } else {
        await O.ouvrir(page, c.ecran, c.role, { ruban: c.ruban });
      }
      if (c.avant) await c.avant(page);
      await O.masquer(page);
      await page.evaluate(() => { const h = document.querySelector('#toast-host'); if (h) h.style.display = 'none'; });
      const manq = await O.annoter(page, c.cibles);
      await new Promise((r) => setTimeout(r, 200));
      const sy = await page.evaluate(() => window.scrollY);
      const clip = { x: 0, y: sy + (c.y || 0), width: 1440, height: Math.min(c.h || 900, 900 - (c.y || 0)) };
      await page.screenshot({ path: path.join(DOSSIER, c.id + '.png'), clip, captureBeyondViewport: false });
      await O.effacerAnnotations(page);
      bilan.push(c.id + (manq.length ? '  CIBLES MANQUANTES : ' + manq.join(' ; ') : '  ok'));
    } catch (e) { bilan.push(c.id + '  ÉCHEC : ' + String(e.message).slice(0, 160)); }
    if (c.deconnecte) await page.evaluate(() => { localStorage.removeItem('sigh-cnt:session'); }).catch(() => {});
  }
  await capturesMobiles(browser, filtre, bilan);
  await browser.close();
  console.log(bilan.join('\n'));
})();
