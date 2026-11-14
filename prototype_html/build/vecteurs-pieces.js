/* =============================================================================
 * VECTEURS DE LA VUE UNIFIÉE DU DOSSIER (lot 8, Direction 14/11/2026) : « Pièces produites par le logiciel ».
 * -----------------------------------------------------------------------------
 * La vue ne fait que des RENVOIS vers les pièces que le logiciel produit (ordonnances, résultats rendus, comptes rendus opératoires et d'imagerie, et, depuis ce lot, comptes rendus de
 * maternité et fiches de consultation) : jamais une copie. Ce script pose un magasin CONTRÔLÉ, ouvre la maquette et interroge `SIGH.piecesProduites` (la fonction même que la vue appelle,
 * exposée par `m1-patients.js`) sous plusieurs profils : le renvoi n'existe que si le profil ouvre l'écran, et la zone médicale ne se lit que par les profils cliniques.
 *   node build/vecteurs-pieces.js   →   packages/domaine/test/vecteurs/pieces_produites.json
 * ========================================================================== */
'use strict';
const path = require('path');
const { ouvrirMaquette, ecrire, ROOT } = require('./extraire');

const MAGASIN = {
  ordonnances: [
    { id: 'O1', numero: 'ORD-0001', patientId: 'P1', date: '2026-10-01T09:00', diagnostic: 'Paludisme simple', statut: 'actif' },
    { id: 'O2', numero: 'ORD-0002', patientId: 'P2', date: '2026-10-02T09:00', diagnostic: 'Autre patient', statut: 'actif' },
    { id: 'O3', numero: 'ORD-0003', patientId: 'P1', date: '2026-09-01T09:00', statut: 'archive' },
  ],
  demandesAnalyses: [
    { id: 'A1', reference: 'DA-0001', patientId: 'P1', dateHeure: '2026-10-03T10:00', analyse: 'NFS', resultat: 'Hb 12', etatAnalyse: 'valide', statut: 'actif' },
    { id: 'A2', reference: 'DA-0002', patientId: 'P1', dateHeure: '2026-10-04T10:00', analyse: 'Glycémie', resultat: '5,1', etatAnalyse: 'en_cours', statut: 'actif' },
  ],
  crOperatoires: [{ id: 'C1', reference: 'CRO-0001', patientId: 'P1', dateOperation: '2026-09-15', intervention: 'Césarienne', statut: 'actif' }],
  resultatsImagerie: [
    { id: 'R1', reference: 'IMG-0001', patientId: 'P1', statut: 'rendu', date: '2026-10-05', examen: 'Échographie obstétricale', statut2: 'x' },
    { id: 'R2', reference: 'IMG-0002', patientId: 'P1', statut: 'brouillon', date: '2026-10-06', examen: 'Radiographie' },
  ],
  crMaternite: [
    { id: 'M1', reference: 'CRM-0001', patientId: 'P1', dateHeure: '2026-10-20T08:30', typeLabel: 'Compte rendu d’accouchement', statut: 'actif' },
    { id: 'M2', reference: 'CRM-0002', patientId: 'P1', dateHeure: '2026-10-20T10:00', statut: 'actif' },
    { id: 'M3', reference: 'CRM-0003', patientId: 'P2', dateHeure: '2026-10-20T11:00', typeLabel: 'Compte rendu d’AMIU', statut: 'actif' },
    { id: 'M4', reference: 'CRM-0004', patientId: 'P1', dateHeure: '2026-10-19T11:00', typeLabel: 'Archivé', statut: 'archive' },
  ],
  dossiersConsultation: [
    { id: 'D1', reference: 'DOS-00001', patientId: 'P1', dateArrivee: '2026-10-21', motifVenue: 'Contrôle tensionnel', statut: 'actif' },
    { id: 'D2', reference: 'DOS-00002', patientId: 'P1', dateArrivee: '2026-10-20', statut: 'actif' },
    { id: 'D3', reference: 'DOS-00003', patientId: 'P2', dateArrivee: '2026-10-21', motifVenue: 'Autre patient', statut: 'actif' },
  ],
};
const PROFILS = [
  { role: 'medecin', fonction: 'medecin', secteur: 'consultation', id: 'EMP01', nom: 'Dr TEST' },
  { role: 'admin', id: 'ADM', nom: 'ADMIN TEST' },
  { role: 'laborantin', fonction: 'biologiste', secteur: 'laboratoire', id: 'EMP02', nom: 'LABO TEST' },
  { role: 'reception', id: 'REC', nom: 'ACCUEIL TEST' },
];

(async () => {
  console.log('▶ Vecteurs de la vue unifiée du dossier (pièces produites)');
  const m = await ouvrirMaquette();
  try {
    await m.page.addScriptTag({ path: path.join(ROOT, 'assets/js/modules/m1-patients.js') });
    const sortie = await m.page.evaluate(([MAG, PROFILS]) => {
      const S = SIGH.store, PR = SIGH.parcours;
      const propre = (x) => JSON.parse(JSON.stringify(x));
      Object.keys(MAG).forEach((n) => { const a = S.collection(n).all(); a.splice(0, a.length); MAG[n].forEach((f) => a.push(propre(f))); });
      const sess0 = S.session();
      const out = { magasin: propre(MAG), cas: [] };
      PROFILS.forEach((p) => {
        S.setSession(Object.assign({}, sess0, p));
        try {
          out.cas.push({
            profil: p,
            session: propre(S.session()),
            zone2: PR.peutVoirDocument('Compte rendu médical').autorise,
            pieces: ['P1', 'P2', 'P3'].map((id) => ({ patientId: id, lignes: SIGH.piecesProduites(id).map((x) => ({ famille: x.famille, reference: x.reference, date: x.date, resume: x.resume, ecran: x.ecran })) })),
          });
        } finally { S.setSession(sess0); }
      });
      return out;
    }, [MAGASIN, PROFILS]);
    ecrire('packages/domaine/test/vecteurs/pieces_produites.json', Object.assign({ _doc: 'ENGENDRÉ par prototype_html/build/vecteurs-pieces.js : `SIGH.piecesProduites` (la fonction de la vue unifiée du dossier) sur un magasin contrôlé, sous plusieurs profils. Ne pas éditer.' }, sortie));
    sortie.cas.forEach((c) => console.log('  ' + c.profil.role + ' : zone 2 ' + c.zone2 + ', P1 ' + c.pieces[0].lignes.length + ' renvoi(s)'));
    if (m.erreurs.length) console.log('  erreurs JS de la page : ' + m.erreurs.join(' | '));
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
