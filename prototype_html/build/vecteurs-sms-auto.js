/* =============================================================================
 * VECTEURS DES ENVOIS AUTOMATIQUES DE SMS (lot SMS-R) : le calcul que la mère fait avant de déposer au relais.
 * -----------------------------------------------------------------------------
 * Les fonctions RÉELLES de la maquette (`SIGH.parcours.planifierSmsAuto`, `smsVerifierModele`) sont appelées dans Chrome sur des fiches posées, à une heure donnée en argument (aucune
 * horloge, aucun réglage dans le moteur). Limite dite : on appelle le MOTEUR, pas un écran (la maquette n'a pas de relais ni d'écran de planification).
 *   node build/vecteurs-sms-auto.js   →   packages/domaine/test/vecteurs/sms_auto.json
 * ========================================================================== */
'use strict';
const { ouvrirMaquette, ecrire } = require('./extraire');

(async () => {
  console.log('▶ Vecteurs des envois automatiques de SMS');
  const m = await ouvrirMaquette();
  try {
    const sortie = await m.page.evaluate(() => {
      const PR = SIGH.parcours;
      const propre = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
      const defaut = {
        rappelHeure: 18, rappelJoursAvant: 1, anniversaireHeure: 9, calmeDebut: 21, calmeFin: 7, horizonJours: 2, toleranceMinutes: 120,
        modeleRappel: '{{clinique}} : rappel de votre rendez-vous le {{date}} à {{heure}}. Pour le modifier, appelez le {{telephone}}.',
        modeleAnniversairePatient: '{{clinique}} vous souhaite un joyeux anniversaire, {{nom}}. Portez-vous bien.',
        modeleAnniversairePersonnel: '{{clinique}} vous souhaite un joyeux anniversaire, {{nom}}. Merci pour votre engagement.',
      };
      const pat = (id, plus) => Object.assign({ id, nom: 'DOSSOU', prenom: 'Awa', telephone: '01 97 00 00 01', dateNaissance: '1990-01-15' }, plus || {});
      const rdv = (id, patientId, date, plus) => Object.assign({ id, patientId, date, statut: 'planifiee', medecin: 'Dr SECRET', motif: 'paludisme' }, plus || {});
      const base = { maintenant: '2026-11-16T17:00', clinique: 'Clinique Nassièra Too', telephone: '+22901000000', reglage: defaut, consultations: [], patients: [], deces: [], employes: [] };
      const cas = [];
      const planifier = (nom, plus) => {
        const entree = Object.assign({}, propre(base), propre(plus));
        cas.push({ op: 'planifier', nom, entree, attendu: propre(PR.planifierSmsAuto(entree)) });
      };
      const modele = (nom, texte) => cas.push({ op: 'modele', nom, entree: { modele: texte }, attendu: propre(PR.smsVerifierModele(texte)) });

      planifier('rappel la veille à 18 h, sans médecin ni motif', { patients: [pat('P1')], consultations: [rdv('C1', 'P1', '2026-11-17T10:30')] });
      planifier('consentement retiré : écarté et nommé', { patients: [pat('P1', { consentementSms: false })], consultations: [rdv('C1', 'P1', '2026-11-17T10:30')] });
      planifier('consentement coché explicitement : envoyé', { patients: [pat('P1', { consentementSms: true })], consultations: [rdv('C1', 'P1', '2026-11-17T10:30')] });
      planifier('patient inconnu', { consultations: [rdv('C1', 'PX', '2026-11-17T10:30')] });
      planifier('rendez-vous annulé : rien', { patients: [pat('P1')], consultations: [rdv('C1', 'P1', '2026-11-17T10:30', { statut: 'annulee' })] });
      planifier('personne non enregistrée : rien', { patients: [pat('P1')], consultations: [rdv('C1', 'P1', '2026-11-17T10:30', { nonPatient: true })] });
      planifier('numéro invalide', { patients: [pat('P1', { telephone: '12' })], consultations: [rdv('C1', 'P1', '2026-11-17T10:30')] });
      planifier('numéro avec indicatif', { patients: [pat('P1', { telephone: '+229 97 00 00 02' })], consultations: [rdv('C1', 'P1', '2026-11-17T10:30')] });
      planifier('rendez-vous hors horizon : rien', { patients: [pat('P1')], consultations: [rdv('C1', 'P1', '2026-11-25T10:30')] });
      planifier('dans la tolérance après 18 h', { maintenant: '2026-11-16T19:30', patients: [pat('P1')], consultations: [rdv('C1', 'P1', '2026-11-17T10:30')] });
      planifier('au-delà de la tolérance : heure passée', { maintenant: '2026-11-16T21:30', patients: [pat('P1')], consultations: [rdv('C1', 'P1', '2026-11-17T10:30')] });
      planifier('rappel réglé dans les heures calmes : reporté à 7 h', { reglage: Object.assign({}, defaut, { rappelHeure: 22 }), patients: [pat('P1')], consultations: [rdv('C1', 'P1', '2026-11-17T10:30')] });
      planifier('anniversaire du patient demain à 9 h', { patients: [pat('P1', { dateNaissance: '1990-11-17' })] });
      planifier('anniversaire aujourd’hui déjà passé', { patients: [pat('P1', { dateNaissance: '1990-11-16' })] });
      planifier('patient décédé : pas de vœux', { patients: [pat('P1', { dateNaissance: '1990-11-17' })], deces: [{ patientId: 'P1' }] });
      planifier('personnel sans accord : écarté', { employes: [{ id: 'E1', prenom: 'Koffi', telephone: '0197000003', dateNaissance: '1985-11-17' }] });
      planifier('personnel avec accord : envoyé', { employes: [{ id: 'E1', prenom: 'Koffi', telephone: '0197000003', dateNaissance: '1985-11-17', consentementSms: true }] });
      planifier('29 février fêté le 28 en année non bissextile', { maintenant: '2027-02-27T10:00', patients: [pat('P1', { dateNaissance: '2000-02-29' })] });
      planifier('mot médical dans le modèle : écarté à la composition', { reglage: Object.assign({}, defaut, { modeleAnniversairePatient: 'Bonne fête {{nom}}, votre test est positif.' }), patients: [pat('P1', { dateNaissance: '1990-11-17' })] });
      planifier('texte trop long : écarté', { reglage: Object.assign({}, defaut, { modeleAnniversairePatient: 'x'.repeat(330) }), patients: [pat('P1', { dateNaissance: '1990-11-17' })] });
      planifier('deux rendez-vous, ordre par heure puis clé', { patients: [pat('P1'), pat('P2', { prenom: 'Koffi', telephone: '0197000004' })], consultations: [rdv('C2', 'P2', '2026-11-17T08:00'), rdv('C1', 'P1', '2026-11-17T10:30')] });
      modele('modèle valide', defaut.modeleRappel);
      modele('variable médecin refusée', 'Rendez-vous avec {{medecin}} le {{date}}');
      modele('variable service refusée', 'Service {{service}}');
      modele('mot médical refusé', 'Votre résultat est positif');
      modele('mot médical sans accent ni casse', 'Résultat NÉGATIF disponible');
      modele('mot entier seulement', 'Votre rendez-vous de palucheur');
      modele('modèle vide', '   ');
      return cas;
    });
    ecrire('packages/domaine/test/vecteurs/sms_auto.json', { source: 'prototype_html/build/vecteurs-sms-auto.js (moteur SIGH.parcours.planifierSmsAuto)', cas: sortie });
    if (m.erreurs.length) { console.error('Erreurs JS : ' + m.erreurs.join(' | ')); process.exitCode = 1; }
  } finally { await m.fermer(); }
})().catch((e) => { console.error(e); process.exit(1); });
