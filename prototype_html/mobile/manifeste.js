/* Manifeste des écrans du mobile — SOURCE UNIQUE : lu par le simulateur (index.php), par le montage de chaque page
   et par build/gen-mobile.js qui engendre mobile/ecrans/*.php. Aucun lien écrit à la main. */
(function (racine) {
  'use strict';
  var PROFILS = {
    soignant: { label: 'Soignant (infirmier)', agent: 'BADO BANI A. B. Zoulehath', accueil: 'accueil-soignant' },
    medecin: { label: 'Médecin', agent: 'Dr YENI M’PO Florent', accueil: 'accueil-medecin' },
    sagefemme: { label: 'Sage-femme', agent: 'Sage-femme de garde', accueil: 'accueil-sagefemme' },
    reception: { label: 'Réception de secours', agent: 'OROU YO Edmond', accueil: 'accueil-reception' },
  };
  var TOUS = ['soignant', 'medecin', 'sagefemme', 'reception'];
  var CLINIQUE = ['soignant', 'medecin', 'sagefemme'];
  var ECRANS = [
    { id: 'appairage', label: 'Appairage', icone: 'link', groupe: 'Démarrage', profils: TOUS, avantSession: true },
    { id: 'verrou', label: 'Code PIN', icone: 'lock', groupe: 'Démarrage', profils: TOUS, avantSession: true },
    { id: 'accueil-soignant', label: 'Ma tournée', icone: 'route', groupe: 'Soignant', profils: ['soignant'] },
    { id: 'accueil-medecin', label: 'Mes visites', icone: 'stethoscope', groupe: 'Médecin', profils: ['medecin'] },
    { id: 'accueil-sagefemme', label: 'Mes suivis', icone: 'baby', groupe: 'Sage-femme', profils: ['sagefemme'] },
    { id: 'accueil-reception', label: 'Accueil de secours', icone: 'hand-helping', groupe: 'Réception de secours', profils: ['reception'] },
    { id: 'dossier', label: 'Dossier du patient', icone: 'folder-open', groupe: 'Dossier', profils: CLINIQUE },
    { id: 'constantes', label: 'Constantes', icone: 'heart-pulse', groupe: 'Soins', profils: CLINIQUE },
    { id: 'consultation', label: 'Consultation à domicile', icone: 'clipboard-pen', groupe: 'Médecin', profils: ['medecin'] },
    { id: 'prescription', label: 'Prescription', icone: 'pill', groupe: 'Médecin', profils: ['medecin'] },
    { id: 'demande-analyse', label: 'Demande d’analyses', icone: 'test-tubes', groupe: 'Médecin', profils: ['medecin'] },
    { id: 'cpn', label: 'Visite prénatale (CPN)', icone: 'baby', groupe: 'Sage-femme', profils: ['sagefemme'] },
    { id: 'cpon', label: 'Visite post-natale (CPoN)', icone: 'heart-handshake', groupe: 'Sage-femme', profils: ['sagefemme'] },
    { id: 'surveillance', label: 'Surveillance mère-bébé', icone: 'activity', groupe: 'Sage-femme', profils: ['sagefemme'] },
    { id: 'nouveau-dossier', label: 'Nouveau dossier', icone: 'user-plus', groupe: 'Réception de secours', profils: ['reception'] },
    { id: 'dossiers-crees', label: 'Dossiers ouverts', icone: 'users', groupe: 'Réception de secours', profils: ['reception'] },
    { id: 'orientation', label: 'Orienter un patient', icone: 'signpost', groupe: 'Réception de secours', profils: ['reception'] },
    { id: 'sync', label: 'Synchronisation', icone: 'refresh-cw', groupe: 'Téléphone', profils: TOUS },
    { id: 'a-traiter', label: 'À traiter', icone: 'octagon-alert', groupe: 'Téléphone', profils: TOUS },
    { id: 'lot', label: 'Lot de tournée', icone: 'package', groupe: 'Téléphone', profils: CLINIQUE },
    { id: 'parametres', label: 'Réglages', icone: 'settings', groupe: 'Téléphone', profils: TOUS },
  ];
  var DEVICES = {
    iphone: { label: 'iPhone 14', os: 'iOS 18', ios: true, w: 390, h: 844 },
    pixel: { label: 'Pixel 8', os: 'Android 15', ios: false, w: 412, h: 880 },
  };
  var M = { PROFILS: PROFILS, ECRANS: ECRANS, DEVICES: DEVICES };
  if (typeof module !== 'undefined' && module.exports) module.exports = M; else racine.SIGHM_MANIFESTE = M;
})(typeof window !== 'undefined' ? window : this);
