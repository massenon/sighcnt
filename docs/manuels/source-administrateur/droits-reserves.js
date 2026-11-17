/* Chapitre « Droits réservés » : TOUS les gestes réservés de packages/rbac/data/rbac.json (clé `gestes`), engendrés depuis le fichier, jamais écrits à la main.
 * Une surcharge de fiche accorde autant qu'elle restreint ; le défaut est la liste `rolesDefaut`. Un geste absent du tableau des groupes tombe dans « Autres gestes » :
 * aucun geste n'est omis (le contrôle `ecrans-controle.js` le vérifie dans le PDF). */
'use strict';
const fs = require('fs');
const path = require('path');
const RACINE = path.resolve(__dirname, '../../..');
const rbac = JSON.parse(fs.readFileSync(path.join(RACINE, 'packages/rbac/data/rbac.json'), 'utf8'));
const manifeste = JSON.parse(fs.readFileSync(path.join(RACINE, 'packages/referentiels/data/manifeste.json'), 'utf8'));

const GROUPES = [
  ['Clôture, fiscalité et prix', ['regler_circuit_cloture', 'decider_prix', 'dater_prix_passe', 'valider_configuration_fiscale', 'confirmer_obligation_fiscale', 'imputer_aib', 'ecrire_bareme_aib']],
  ['Caisse, MECeF et factures aux tiers', ['regler_mode_mecef', 'regler_imprimante_caisse', 'retransmettre_mecef', 'retransmettre_mecef_sans_limite', 'poste_caisse', 'poste_pharmacie', 'emettre_facture_tiers', 'corriger_facture_tiers']],
  ['Achats et stock', ['valider_commande_stock', 'arbitrer_besoins', 'traiter_besoins_accordes']],
  ['Personnel et plannings', ['regler_regime_individuel', 'regler_planning_personnalise', 'ouvrir_fiche_personnel_equipe', 'confirmer_valeur_attente_personnel', 'valider_etape_surveillant', 'valider_etape_daf']],
  ['Réglages de la clinique', ['regler_parametres_clinique', 'regler_passerelle_sms', 'regler_fichiers', 'regler_lecture_scans', 'adopter_plan_annuel']],
  ['Laboratoire, documents et sorties de tableaux', ['valider_seuil_labo', 'corriger_texte_ocr', 'exporter_donnees']],
  ['Synchronisation entre postes', ['trancher_pair', 'valider_pair']],
  ['Centre des validations (vue complète)', ['voir_toutes_les_validations', 'voir_toutes_les_familles_validation']],
  ['Centre des validations (une famille de référentiel par geste)', rbac.gestes.jeux.filter((g) => g.id.startsWith('valider_famille_')).map((g) => g.id)],
];

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const roles = Object.fromEntries(rbac.roles.map((r) => [r.id, r]));
const ecrans = Object.fromEntries(manifeste.ecrans.map((e) => [e.id, e]));
const tousLesRoles = rbac.roles.map((r) => r.id);

function listeRoles(g) {
  const ids = g.rolesDefaut;
  if (tousLesRoles.every((id) => ids.includes(id))) return 'Tous les rôles';
  const noms = ids.map((id) => (roles[id] ? roles[id].label.replace(/ — /g, ', ') : id) + (roles[id] && roles[id].archive ? ' (rôle archivé : ne détient rien tant qu’il l’est)' : ''));
  return noms.join(' ; ') + (g.defautSiEcritSur ? ' (défaut : les rôles qui écrivent sur les modules ' + g.defautSiEcritSur.join(' et ') + ')' : '');
}

function cequiOuvre(g) {
  const e = g.ecran ? ecrans[g.ecran] : null;
  if (e) return esc(g.libelle) + '<br><span class="note">Écran concerné : <strong>' + esc(e.label) + '</strong> (<code>' + e.id + '</code>). Le droit n’ouvre pas l’écran : l’écran se règle à part.</span>';
  return esc(g.libelle) + '<br><span class="note">Aucun écran propre : le droit commande ce geste dans les écrans qui le portent.</span>';
}

function html() {
  const dits = new Set();
  let out = '';
  const parId = Object.fromEntries(rbac.gestes.jeux.map((g) => [g.id, g]));
  const groupes = GROUPES.map(([t, ids]) => [t, ids.filter((i) => parId[i])]);
  const classes = new Set(groupes.flatMap((g) => g[1]));
  const autres = rbac.gestes.jeux.map((g) => g.id).filter((i) => !classes.has(i));
  if (autres.length) groupes.push(['Autres gestes', autres]);
  for (const [titre, ids] of groupes) {
    if (!ids.length) continue;
    out += '<h3>' + esc(titre) + ' (' + ids.length + ')</h3>\n<table class="tab droits"><tr><th style="width:33%">Geste (code)</th><th>Ce qu’il ouvre</th><th style="width:25%">Défaut semé</th></tr>\n';
    for (const id of ids) {
      const g = parId[id];
      dits.add(id);
      out += '<tr><td><code>' + id + '</code></td><td>' + cequiOuvre(g) + '</td><td>' + esc(listeRoles(g)) + '</td></tr>\n';
    }
    out += '</table>\n';
  }
  return { html: out, nombre: rbac.gestes.jeux.length, ids: rbac.gestes.jeux.map((g) => g.id), classes: dits.size, groupes: groupes.length };
}
module.exports = { html, rbac };
if (require.main === module) { const r = html(); console.log(r.nombre + ' gestes, ' + r.groupes + ' groupes, ' + r.classes + ' rangées.'); }
