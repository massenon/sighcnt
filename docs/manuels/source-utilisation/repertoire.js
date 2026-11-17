/* Annexe C : répertoire de TOUS les écrans (manifeste, poste, téléphone, relais). Les contenus viennent de la récolte réelle
   (recolte-ecrans.json, rôle administrateur sur la maquette) ; les droits sont calculés depuis packages/rbac/data/rbac.json. */
'use strict';
const path = require('path');
const fs = require('fs');
const MAN = require(path.resolve(__dirname, '../../../packages/referentiels/data/manifeste.json'));
const REC = JSON.parse(fs.readFileSync(path.join(__dirname, 'recolte-ecrans.json'), 'utf8'));
const GENERIQUES = /^(Colonnes|Exporter|Importer les données|Actions|Effacer les filtres|Mois précédent|Mois suivant|Aujourd’hui|Retour à l’accueil|Y aller|Ouvrir|\d+)$/;
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const sansNombre = (t) => t.replace(/\d+$/, '').trim();
const coupe = (t, n) => (t.length > n ? t.slice(0, n - 1).replace(/\s+\S*$/, '') + '…' : t);

module.exports = function (H) {
  const { RBAC, ROLES } = H;
  function droits(id) {
    const agit = [], lit = [];
    ROLES.forEach((r) => { const t = (RBAC.parRole[r.id] || {})[id]; if (t && t[1]) agit.push(r.short); else if (t && t[0]) lit.push(r.short); });
    const f = (l) => (l.length > 7 ? l.slice(0, 7).join(', ') + ' et ' + (l.length - 7) + ' autres' : l.join(', '));
    const e = MAN.ecrans.find((x) => x.id === id) || {};
    let h = '';
    if (agit.length) h += '<b>Agit :</b> ' + f(agit) + '. ';
    if (lit.length) h += '<b>Lit :</b> ' + f(lit) + '.';
    if (!h) h = e.parGeste || e.universel ? 'Ouvert à tous les rôles ou par un geste réservé de la fiche des droits.' : 'Selon la fiche du rôle.';
    return h;
  }
  function contenu(id) {
    const r = REC[id] || {};
    const aides = (r.aide || []).filter((t) => t.length >= 40 && !/^(\d|Affichage|Aucun|Utiliser le bouton)/.test(t) && !/\(s\)/.test(t));
    const parts = [];
    if (aides.length) parts.push(esc(coupe(aides[0], 170)));
    const ong = (r.onglets || []).map(sansNombre).filter(Boolean);
    if (ong.length) parts.push('<b>Onglets :</b> ' + esc(ong.join(', ')) + '.');
    else if ((r.colonnes || []).length && !aides.length) parts.push('<b>Colonnes :</b> ' + esc([...new Set(r.colonnes)].slice(0, 8).join(', ')) + '.');
    const btn = [...new Set((r.boutons || []).map(sansNombre).filter((t) => t && !GENERIQUES.test(t) && !ong.includes(t)))].slice(0, 6);
    return parts.join(' ') + (btn.length ? '<span class="btns"><b>Boutons :</b> ' + esc(btn.join(', ')) + '.</span>' : '');
  }
  const groupes = [];
  MAN.ecrans.forEach((e) => { let g = groupes.find((x) => x.code === e.module); if (!g) { g = { code: e.module, label: e.moduleLabel, domaine: e.domaine, ecrans: [] }; groupes.push(g); } g.ecrans.push(e); });
  let html = `<p>Ce répertoire nomme <b>tous les écrans</b> du logiciel : ceux du manifeste (${MAN.ecrans.length}, groupés par module), puis ceux qui sont propres au poste de travail, au téléphone et au relais. Les colonnes viennent de l’écran réel de la maquette, vu par l’administrateur ; les droits viennent de la matrice de la clinique (droits d’origine, abréviations du chapitre « Les rôles et ce qu’ils voient »). « Lit » veut dire que le rôle consulte sans pouvoir créer ni modifier.</p>`;
  groupes.forEach((g) => {
    html += `<h3 class="groupe-ecrans">${esc(g.code)} : ${esc(g.label)} <span style="font-weight:400;color:#64748b">(${esc(g.domaine)}, ${g.ecrans.length} écran${g.ecrans.length > 1 ? 's' : ''})</span></h3>`;
    html += '<table class="repertoire"><tr><th>Écran</th><th>Ce que l’écran contient</th><th>Droits d’origine</th></tr>' +
      g.ecrans.map((e) => `<tr><td><b>${esc(e.label)}</b><span class="chem">${esc(e.domaine)} ➔ ${esc(e.moduleLabel)}</span></td><td>${contenu(e.id)}</td><td class="qui-agit">${droits(e.id)}</td></tr>`).join('') + '</table>';
  });
  return html;
};
module.exports.partiesPropres = function () {
  const E = require('./ecrans.js');
  const BLOC = {
    poste: ['Écrans propres au poste de travail', 'Ces éléments n’ont pas de ligne dans le manifeste : ils appartiennent à la coque de l’application de bureau.', {
      'Connexion au poste': 'Identifiant et mot de passe, sans compte partagé ; vérification en deux étapes si elle est activée.',
      'Barre supérieure et ruban': 'Recherche, menu Actions, pastille de synchronisation, cloche, nom et rôle, puis le ruban des domaines (chapitre « Prise en main »).',
      'Recherche globale': 'Raccourci Ctrl K : trouve un patient, un produit ou un employé.',
      'Centre de notifications': 'Cloche de la barre : alertes et tâches, avec un son pour les alertes sans donnée de santé.',
      'Choix de l’exercice': 'Sélecteur de l’exercice de travail (le jour par défaut) dans la barre supérieure.',
      'Pastille des décisions en attente de la mère': 'Compte les décisions signées sur un fileul que la mère n’a pas encore appliquées.',
      'Écran non porté au poste': 'Message nommé quand un écran de la maquette n’est pas encore porté au poste : il dit lequel et pourquoi.',
      'Activité fermée': 'Message quand l’exercice ou l’activité est clos : les écritures y sont refusées avec leur motif.',
      'Accès rapides': 'Raccourcis de la barre vers les écrans du rôle.' }],
    mobile: ['Écrans du téléphone', 'Application du soignant, du médecin, de la sage-femme et de la réception de secours (voir le chapitre « L’application mobile »).', {
      'Appairer ce téléphone': 'Scan du QR de la mère et choix du profil.', 'Code PIN': 'Verrou du téléphone par un code.', 'Ma tournée': 'Visites du jour du soignant.',
      'Mes visites': 'Visites du médecin, avec consultation, prescription et demande d’analyses.', 'Mes suivis': 'Suivis de la sage-femme : CPN, CPoN, surveillance.',
      'Accueil de secours': 'Réception de secours : nouveau dossier, dossiers ouverts, orientation.', 'Dossier du patient': 'Identité, couverture, allergies, constantes.',
      'Constantes': 'Saisie des constantes.', 'Consultation à domicile': 'Fiche de consultation à domicile.', 'Visite prénatale (CPN)': 'Examen et prévention.',
      'Visite post-natale (CPoN)': 'Mère et nouveau-né.', 'Demande d’analyses': 'Demande d’examens de laboratoire.', 'Dossiers ouverts': 'Dossiers créés au téléphone.',
      'Lot de tournée': 'Dossiers confiés au téléphone pour une durée limitée.', 'Nouveau dossier': 'Ouverture d’un dossier de secours.', 'Orienter un patient': 'Orientation vers un service.',
      'Réglages': 'Verrouillage automatique, effacement à distance, réinitialisation de l’appairage.', 'Prescription': 'Ordonnance du médecin.', 'Surveillance mère-bébé': 'Suivi mère et bébé.',
      'Synchronisation': 'État et bouton Synchroniser maintenant.', 'À traiter': 'Pièces refusées ou en attente, à reprendre.' }],
    relais: ['Écrans du relais', 'Le panneau est réservé au superadministrateur (Manuel administrateur). Seule la page de satisfaction est vue d’un patient.', {
      'Connexion au panneau du relais': 'Identification du superadministrateur.', 'Tableau de bord du relais': 'Vue d’ensemble.', 'Appareils du relais': 'Postes et téléphones appairés.',
      'Boîtes aux lettres du relais': 'Enveloppes chiffrées en attente.', 'Codes d’appairage du relais': 'Codes à usage unique.', 'Indicateurs du relais': 'Indicateurs reçus.',
      'Synchronisation du relais': 'Exploitation de la synchronisation.', 'Alertes du relais': 'Alertes et notifications.', 'Journal du relais': 'Journal d’audit.',
      'Comptes superadmin du relais': 'Comptes du panneau.', 'Paramètres du relais': 'Réglages.', 'Hébergement du relais': 'Hébergement.', 'Sauvegarde du relais': 'Sauvegarde hors site.',
      'Passerelle SMS du relais': 'Envoi des SMS déposés par la mère.', 'Preuve d’opacité du relais': 'Preuve que le relais ne lit pas les données.', 'Consultation du relais': 'Appareils, enveloppes, réglage.',
      'Messagerie du relais': 'Réglage SMTP.', 'Formulaire public de satisfaction': 'Questionnaire sans cookie, réponse chiffrée dans le navigateur du patient.', 'Lien de satisfaction indisponible': 'Page « Ce lien n’est plus valable ».' }],
  };
  let h = '';
  ['poste', 'mobile', 'relais'].forEach((g) => {
    const [t, intro, desc] = BLOC[g];
    h += `<h3 class="groupe-ecrans">${t}</h3><p>${intro}</p><table class="repertoire"><tr><th>Écran</th><th>Ce que l’écran contient</th></tr>` +
      E[g].map((e) => `<tr><td><b>${esc(e.nom)}</b></td><td>${esc(desc[e.nom] || '')}</td></tr>`).join('') + '</table>';
  });
  return h;
};
