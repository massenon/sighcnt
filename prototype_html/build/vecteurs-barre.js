/* =============================================================================
 * VECTEURS DE LA BARRE SUPÉRIEURE : recherche globale, actions rapides, moteur de notifications, fil d'Ariane
 * -----------------------------------------------------------------------------
 * Le moteur RÉEL de la maquette est interrogé sur le magasin amorcé, à une HORLOGE FIGÉE (16/08/2026 12:00), rôle par rôle :
 *   - `SIGH.notifications.collecter({ poste })` : ce que la cloche et le centre affichent (routé par rôle et par droits, regroupé au-delà de 3) ;
 *   - `SIGH.app.rechercher(q, role)` : les groupes de résultats de la recherche globale ;
 *   - `SIGH.app.actionsRapides(role)` : le menu « Actions » ;
 *   - le fil d'Ariane LU dans le DOM de pages réelles.
 *   node build/vecteurs-barre.js   →   packages/domaine/test/vecteurs/barre.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs de la barre supérieure');
  const m = await ouvrirMaquette();
  try {
    await m.page.evaluate(() => {
      const Reel = window.Date; const fige = new Reel(2026, 7, 16, 12, 0, 0).getTime();
      function F() { if (!(this instanceof F)) return String(new Reel(fige)); if (arguments.length === 0) return new Reel(fige); return new (Function.prototype.bind.apply(Reel, [null].concat(Array.prototype.slice.call(arguments))))(); }
      F.prototype = Reel.prototype; F.now = () => fige; F.UTC = Reel.UTC; F.parse = Reel.parse; window.Date = F;
    });
    /* LE JEU DE LA SONDE EST POSÉ PAR ELLE : les collections que lisent les sources sont remplacées par ces fiches, qui voyagent AVEC les vecteurs.
       Le poste les rejoue dans son propre magasin et doit rendre, rôle par rôle, la même liste (le jeu de démonstration, lui, diffère d'un état à
       l'autre de la maquette (une fiche créée par un geste d'écran n'y figure pas toujours)). */
    const FIXTURE = {
      patients: [
        { id: 'PAT1', code: 'CNT/1/26', nom: 'PADONOU', prenom: 'Amina', quartier: 'Péporiyakou' },
        { id: 'PAT2', code: 'CNT/2/26', nom: 'KOUAGOU', prenom: 'Paulin', quartier: 'Natitingou' },
        { id: 'PAT3', code: 'CNT/3/26', nom: 'TAMOU', prenom: 'Sanni', quartier: 'Yimporima' },
        { id: 'PAT4', code: 'CNT/4/26', nom: 'ARCHIVÉ', prenom: 'Pascal', quartier: 'Boriyoure', statut: 'archive' },
      ],
      personnel: [
        { id: 'PER1', nomComplet: 'BASSONGUI Chabi Séko', matricule: 'M001', poste: 'Médecin chirurgien' },
        { id: 'PER2', nomComplet: 'PADONOU Rachidatou', matricule: 'M014', poste: 'Sage-femme' },
        { id: 'PER3', nomComplet: 'GBEDJI Hervé', matricule: 'M020', poste: 'Assistant de Direction' },
      ],
      actes: [
        { id: 'ACT1', code: 'CS-GEN', libelle: 'Consultation généraliste', secteur: 'Consultation', prix: 3000, prixAssure: 4000 },
        { id: 'ACT2', code: 'AC-1', libelle: 'Accouchement par voie basse', secteur: 'Maternité', prix: 35000, tarifProvisoire: true },
        { id: 'ACT3', code: 'PF-1', libelle: 'Pose d’implant', secteur: 'Maternité', prix: 8000, nonCouvert: true },
        { id: 'ACT4', code: 'RX-1', libelle: 'Radiographie du thorax', secteur: 'Imagerie médicale', prix: null },
      ],
      assureurs: [
        { id: 'ASS1', nom: 'SANLAM ASSURANCE', sigle: 'SANLAM', convention: 'CNV-2026-01' },
        { id: 'ASS2', nom: 'NSIA ASSURANCE', sigle: 'NSIA' },
      ],
      comptes: [
        { id: 'CPT1', numero: '411000', intitule: 'Clients assurance' },
        { id: 'CPT2', numero: '571000', intitule: 'Caisse' },
        { id: 'CPT3', numero: '706000', intitule: 'Prestations de services' },
      ],
      produits: [
        { id: 'P1', code: 'MED001', designation: 'AMOXICILLINE 500 MG', unite: 'boîte', stock: 0, seuilAlerte: 10 },
        { id: 'P2', code: 'MED002', designation: 'PARACETAMOL 500 MG', unite: 'boîte', stock: 3, seuilAlerte: 20 },
        { id: 'P3', code: 'MED003', designation: 'SÉRUM GLUCOSÉ 5 %', unite: 'poche', stock: 5, seuilAlerte: 5 },
        { id: 'P4', code: 'CON001', designation: 'GANTS D’EXAMEN', unite: 'boîte', stock: 2, seuilAlerte: 30 },
        { id: 'P5', code: 'CON002', designation: 'COMPRESSES STÉRILES', unite: 'paquet', stock: 100, seuilAlerte: 10 },
        { id: 'P6', code: 'CON003', designation: 'ALCOOL 70°', unite: 'flacon', stock: 4, seuilAlerte: null },
      ],
      lots: [
        { id: 'L1', produit: 'AMOXICILLINE 500 MG', numeroLot: 'A1', statut: 'perime' },
        { id: 'L2', produit: 'PARACETAMOL 500 MG', numeroLot: 'P7', statut: 'alerte' },
        { id: 'L3', numero: 'Z9', numeroLot: 'Z9', statut: 'alerte' },
        { id: 'L4', produit: 'GANTS D’EXAMEN', numeroLot: 'G2', statut: 'actif' },
      ],
      factures: [
        { id: 'F1', numero: 'FAC-2026-00001', statutMecef: 'rejete', date: '2026-08-10' },
        { id: 'F2', numero: 'FAC-2026-00002', statutMecef: 'valide', date: '2026-04-01', assureur: 'SANLAM', partAssurance: 5000 },
        { id: 'F3', numero: 'FAC-2026-00003', statutMecef: 'valide', date: '2026-03-10', assureur: 'NSIA', partAssurance: 3000 },
        { id: 'F4', numero: 'FAC-2026-00004', statutMecef: 'valide', date: '2026-08-01', assureur: 'NSIA', partAssurance: 9000 },
      ],
      echeancesFiscales: [
        { id: 'E1', libelle: 'ITS de juillet', echeance: '2026-08-10', paye: false },
        { id: 'E2', libelle: 'AIB de juillet', echeance: '2026-07-20', paye: false },
        { id: 'E3', libelle: 'ITS d’août', echeance: '2026-09-10', paye: false },
        { id: 'E4', libelle: 'CNSS de juillet', echeance: '2026-08-01', paye: true },
      ],
      demandesAnalyses: [
        { id: 'D1', analyse: 'NFS', etatAnalyse: 'attente_prelevement' },
        { id: 'D2', analyse: 'Glycémie', etatAnalyse: 'attente_prelevement' },
        { id: 'D3', analyse: 'Widal', etatAnalyse: 'attente_prelevement' },
        { id: 'D4', analyse: 'CRP', etatAnalyse: 'en_cours', recuLaboLe: '2026-08-15' },
        { id: 'D5', analyse: 'Groupe sanguin', etatAnalyse: 'en_attente' },
      ],
      notifications: [
        { id: 'N1', type: 'demande_imagerie', poste: 'imagerie', libelle: 'Nouvelle demande d’imagerie', detail: 'Échographie pelvienne', priorite: 'normale', lue: false },
        { id: 'N2', type: 'prescription_soins', poste: 'salle_soins', libelle: 'Prescription de soins', detail: 'Pansement', priorite: 'normale', lue: false },
        { id: 'N3', type: 'information', poste: 'tous', libelle: 'Réunion de service', detail: 'Vendredi à 8 h', priorite: 'normale', lue: false },
        { id: 'N4', type: 'cloture', poste: 'direction', libelle: 'Clôture 2025 à valider', detail: 'Demandée par le comptable.', priorite: 'haute', lue: false },
        { id: 'N5', type: 'demande_imagerie', poste: 'imagerie', libelle: 'Demande déjà lue', priorite: 'normale', lue: true },
      ],
      besoins: [
        { id: 'B1', reference: 'BEX-001', etape: 'soumis', service: 'Laboratoire', motif: 'Réactifs' },
        { id: 'B2', reference: 'BEX-002', etape: 'validation_da', service: 'Pharmacie', motif: 'Gants' },
        { id: 'B3', reference: 'BEX-003', etape: 'accorde', service: 'Maternité', motif: 'Draps' },
      ],
      ecritures: [
        { id: 'W1', numero: 'OD-2026-00001', statut: 'brouillon', libelle: 'Achat de marchandises', compte: '601100', debit: 1000, credit: 0 },
        { id: 'W2', numero: 'OD-2026-00001', statut: 'brouillon', libelle: 'Achat de marchandises', compte: '401000', debit: 0, credit: 1000 },
        { id: 'W3', numero: 'OD-2026-00002', statut: 'brouillon', libelle: 'Loyer', compte: '622000', debit: 500, credit: 0 },
        { id: 'W4', numero: 'OD-2026-00002', statut: 'brouillon', libelle: 'Loyer', compte: '571000', debit: 0, credit: 500 },
        { id: 'W5', numero: 'OD-2026-00003', statut: 'validee', libelle: 'Recette', compte: '571000', debit: 300, credit: 0 },
        { id: 'W6', numero: 'OD-2026-00003', statut: 'validee', libelle: 'Recette', compte: '706000', debit: 0, credit: 300 },
      ],
    };
    const sortie = await m.page.evaluate(async (FIXTURE) => {
      const S = SIGH.store, N = SIGH.nav, NT = SIGH.notifications, A = SIGH.app;
      const db = S.raw();
      Object.entries(FIXTURE).forEach(([nom, fiches]) => {
        db[nom] = [];
        const c = S.collection(nom);
        [...fiches].reverse().forEach((f) => c.insert(Object.assign({}, f)));
      });
      /* Les acquittements du navigateur de la sonde ne comptent pas. */
      try { S.storage.remove('sigh-cnt:notifications-acquittees'); } catch (e) { /* aucun */ }
      const roles = Object.keys(N.ROLES);
      const notifications = {};
      roles.forEach((r) => {
        notifications[r] = NT.collecter({ poste: r }).filter((n) => n.categorie === 'metier').map((n) => ({
          source: n.source, domaine: n.domaine, priorite: n.priorite, titre: n.titre, detail: n.detail, lien: n.lien || null,
          groupe: !!n.groupe, nombre: n.nombre || 1,
        }));
      });
      const actions = {};
      roles.forEach((r) => { actions[r] = A.actionsRapides(r).map((a) => ({ libelle: a[0], icone: a[1], ecran: a[2] })); });
      const requetes = ['pa', 'actes', 'bilan', 'cnt', 'amox', 'sage', '411', 'accou', 'hemo', 'paludisme', 'radio', 'x'];
      const recherche = {};
      ['admin', 'caissier', 'reception', 'laborantin', 'comptable', 'medecin', 'direction', 'stock', 'aide_soignant'].forEach((r) => {
        recherche[r] = {};
        requetes.forEach((q) => {
          recherche[r][q] = A.rechercher(q, r).map((g) => ({ groupe: g[0], resultats: g[1].map((x) => ({ label: x.label, detail: x.detail, icone: x.icon, ecran: x.ecran, onglet: x.onglet || null })) }));
        });
      });
      return { roles, notifications, actions, recherche, version: S.VERSION || null };
    }, FIXTURE);
    /* Fil d'Ariane lu dans le DOM de pages réelles (le rôle de la session du banc voit tout). */
    const fil = {};
    for (const id of ['m2-agenda', 'm1-patients', 'm6-lots', 'm8-caisse', 'dash-admin', 'hub-m2', 'm12-ecritures', 'cfg-tarifs', 'm14-roles']) {
      await m.page.goto(`http://127.0.0.1:${require("./_banc").PORT_PHP}/pages/${id}.php`);
      try { await m.page.waitForSelector(`nav[aria-label="Fil d’Ariane"]`, { timeout: 30000 }); } catch (e) { console.log(id, m.page.url(), m.erreurs.slice(-3), (await m.page.evaluate(() => document.body.innerText)).slice(0, 300)); throw e; }
      fil[id] = await m.page.evaluate(() => [...document.querySelector('nav[aria-label="Fil d’Ariane"]').children].filter((e) => e.tagName !== 'svg').map((e) => e.textContent.trim()));
    }
    if (m.erreurs.length) console.log('  (erreurs de page : ' + m.erreurs.length + ')');
    ecrire('packages/domaine/test/vecteurs/barre.json', {
      _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-barre.js depuis la maquette RÉELLE (horloge figée au 16/08/2026 12:00), ne pas éditer.',
      horloge: '2026-08-16T12:00:00', jeu: FIXTURE, ...sortie, fil,
    });
    const n = Object.values(sortie.notifications).reduce((a, l) => a + l.length, 0);
    console.log(`  ${sortie.roles.length} rôles · ${n} lignes de notification · fil : ${Object.keys(fil).length} pages`);
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
