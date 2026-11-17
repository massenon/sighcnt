/* Liste des écrans que le manuel d'utilisation doit couvrir (17/11/2026).
   Source unique pour le manifeste : packages/referentiels/data/manifeste.json (382 entrées). Les écrans propres au poste de travail,
   au téléphone et au relais n'y figurent pas : ils sont listés ici, à la main, et vérifiés par controle.js. */
'use strict';
const path = require('path');
const M = require(path.resolve(__dirname, '../../../packages/referentiels/data/manifeste.json'));

const manifeste = M.ecrans.map((e) => ({ id: e.id, nom: e.label, groupe: 'manifeste', module: e.module, moduleLabel: e.moduleLabel, domaine: e.domaine }));

/* Écrans du poste de travail qui ne sont pas des écrans du manifeste (coque, fenêtres, états propres au poste). */
const poste = [
  { id: 'p-connexion', nom: 'Connexion au poste' },
  { id: 'p-ruban', nom: 'Barre supérieure et ruban' },
  { id: 'p-recherche', nom: 'Recherche globale' },
  { id: 'p-notifications', nom: 'Centre de notifications' },
  { id: 'p-exercice', nom: 'Choix de l’exercice' },
  { id: 'p-pastille', nom: 'Pastille des décisions en attente de la mère' },
  { id: 'p-non-porte', nom: 'Écran non porté au poste' },
  { id: 'p-activite-fermee', nom: 'Activité fermée' },
  { id: 'p-acces-rapides', nom: 'Accès rapides' },
].map((x) => Object.assign({ groupe: 'poste' }, x));

/* Le téléphone : écrans de la maquette mobile (prototype_html/mobile/ecrans/*.php) et de l'application Flutter (apps/mobile/lib/ui). */
const mobile = [
  ['appairage', 'Appairer ce téléphone'], ['verrou', 'Code PIN'], ['accueil-soignant', 'Ma tournée'], ['accueil-medecin', 'Mes visites'],
  ['accueil-sagefemme', 'Mes suivis'], ['accueil-reception', 'Accueil de secours'], ['dossier', 'Dossier du patient'],
  ['constantes', 'Constantes'], ['consultation', 'Consultation à domicile'], ['cpn', 'Visite prénatale (CPN)'], ['cpon', 'Visite post-natale (CPoN)'],
  ['demande-analyse', 'Demande d’analyses'], ['dossiers-crees', 'Dossiers ouverts'], ['lot', 'Lot de tournée'], ['nouveau-dossier', 'Nouveau dossier'],
  ['orientation', 'Orienter un patient'], ['parametres', 'Réglages'], ['prescription', 'Prescription'], ['surveillance', 'Surveillance mère-bébé'],
  ['sync', 'Synchronisation'], ['a-traiter', 'À traiter'],
].map(([id, nom]) => ({ id: 'mob-' + id, nom, groupe: 'mobile' }));

/* Le relais : écrans du panneau superadmin (routes de apps/web/routes/web.php) et page publique de satisfaction. */
const relais = [
  ['connexion', 'Connexion au panneau du relais'], ['tableau', 'Tableau de bord du relais'], ['appareils', 'Appareils du relais'], ['boites', 'Boîtes aux lettres du relais'],
  ['codes', 'Codes d’appairage du relais'], ['indicateurs', 'Indicateurs du relais'], ['synchronisation', 'Synchronisation du relais'], ['alertes', 'Alertes du relais'],
  ['journal', 'Journal du relais'], ['superadmin', 'Comptes superadmin du relais'], ['parametres', 'Paramètres du relais'], ['hebergement', 'Hébergement du relais'],
  ['sauvegarde', 'Sauvegarde du relais'], ['sms', 'Passerelle SMS du relais'], ['opacite', 'Preuve d’opacité du relais'], ['consultation', 'Consultation du relais'],
  ['smtp', 'Messagerie du relais'], ['satisfaction', 'Formulaire public de satisfaction'], ['indisponible', 'Lien de satisfaction indisponible'],
].map(([id, nom]) => ({ id: 'rls-' + id, nom, groupe: 'relais' }));

module.exports = { manifeste, poste, mobile, relais, tous: [].concat(manifeste, poste, mobile, relais) };
