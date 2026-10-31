/* Engendre `packages/domaine/lib/src/configuration/cfb_donnees.dart` : les référentiels statiques que lisent les neuf écrans de CFG (B), TIRÉS des vecteurs
   de la maquette (`cfb.json › constantes`) et des lignes de règles de gestion de `configuration.js` — jamais recopiés à la main.
     node build/gen-cfb-donnees.js     (après build/vecteurs-cfg-b.js) */
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const REPO = path.resolve(ROOT, '..');
const v = JSON.parse(fs.readFileSync(path.join(REPO, 'packages/domaine/test/vecteurs/cfb.json'), 'utf8'));
const c = v.constantes;
const q = (s) => (s == null ? 'null' : "'" + String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$') + "'");
const n = (x) => (x == null ? 'null' : String(x));
const L = [];
L.push(`/// ENGENDRÉ par prototype_html/build/gen-cfb-donnees.js depuis packages/domaine/test/vecteurs/cfb.json — NE PAS ÉDITER À LA MAIN.
/// Les référentiels statiques (\`D.*\` de la maquette) que lisent cfg-regles, cfg-fiscalite, cfg-comptabilite, cfg-notifications, cfg-modules, cfg-systeme.
/// Gardés par \`test/cfb_regles_test.dart\` (égalité avec les vecteurs).
library;
`);

/* ---- SOURCES_VERITE ---- */
L.push(`class CfbSource {
  const CfbSource(this.document, this.devient, this.module, this.ecran, this.statut);
  final String document, devient, module, statut;
  final String? ecran;
}
`);
L.push('const cfbSourcesVerite = <CfbSource>[');
for (const s of c.sourcesVerite) L.push(`  CfbSource(${q(s.document)}, ${q(s.devient)}, ${q(s.module)}, ${q(s.ecran)}, ${q(s.statut)}),`);
L.push('];\n');

/* ---- règles de gestion RG-01..14 : lues dans la source de l'écran ---- */
const src = fs.readFileSync(path.join(ROOT, 'assets/js/modules/configuration.js'), 'utf8');
const bloc = src.slice(src.indexOf('var RG = ['), src.indexOf("].map(function (r) { return { code: r[0]"));
const rg = [...bloc.matchAll(/\['(RG-\d+)', '((?:[^'\\]|\\.)*)', '([^']*)', '([^']*)'\]/g)].map((m) => [m[1], m[2].replace(/\\'/g, "'"), m[3], m[4]]);
if (rg.length !== 14) throw new Error('RG attendues : 14, lues : ' + rg.length);
L.push(`class CfbRegleGestion {
  const CfbRegleGestion(this.code, this.regle, this.module, this.ecran);
  final String code, regle, module, ecran;
}
`);
L.push('const cfbReglesGestion = <CfbRegleGestion>[');
for (const r of rg) L.push(`  CfbRegleGestion(${q(r[0])}, ${q(r[1])}, ${q(r[2])}, ${q(r[3])}),`);
L.push('];\n');

/* ---- valorisation, familles, groupes, notes de service ---- */
L.push('/// `D.PARAM_STOCK.options` : (identifiant, libellé, note).');
L.push('const cfbOptionsValorisation = <(String, String, String)>[');
for (const o of c.paramStock.options) L.push(`  (${q(o.id)}, ${q(o.label)}, ${q(o.note)}),`);
L.push('];');
L.push(`const cfbValorisationDefaut = ${q(c.paramStock.valorisationSortie)};\n`);
L.push('/// `D.FAMILLES_ARTICLES` : (identifiant, libellé, groupe).');
L.push('const cfbFamillesArticles = <(String, String, String)>[');
for (const f of c.famillesArticles) L.push(`  (${q(f.id)}, ${q(f.label)}, ${q(f.groupe)}),`);
L.push('];');
L.push('/// `D.GROUPES_ARTICLES` : (identifiant, libellé).');
L.push('const cfbGroupesArticles = <(String, String)>[');
for (const f of c.groupesArticles) L.push(`  (${q(f.id)}, ${q(f.label)}),`);
L.push('];\n');
L.push(`class CfbNoteService {
  const CfbNoteService(this.reference, this.version, this.dateEffet, this.statut, this.objet);
  final String reference, dateEffet, statut, objet;
  final int version;
}
`);
L.push(`/// \`D.NS131\` / \`D.NS132\` (référence, version, date d'effet, statut, objet).`);
L.push(`const cfbNs131 = CfbNoteService(${q(c.ns131.reference)}, ${c.ns131.version}, ${q(c.ns131.dateEffet)}, ${q(c.ns131.statut)}, ${q(c.ns131.objet)});`);
L.push(`const cfbNs132 = CfbNoteService(${q(c.ns132.reference)}, ${c.ns132.version}, ${q(c.ns132.dateEffet)}, ${q(c.ns132.statut)}, ${q(c.ns132.objet)});\n`);

/* ---- calendrier fiscal ---- */
L.push(`class CfbObligation {
  const CfbObligation(this.code, this.libelle, this.periodicite, this.jour, this.mois, this.part, this.declaration, this.note, this.source);
  final String code, libelle, periodicite, note, source;
  final int jour;

  /// 0 (janvier) à 11 ; \`null\` pour une obligation mensuelle.
  final int? mois;

  /// Part réglée (en %) ; \`null\` : sans objet (déclaration, solde).
  final int? part;
  final String? declaration;
}
`);
L.push('/// `D.CALENDRIER_FISCAL`, dans l\'ordre de la maquette.');
L.push('const cfbCalendrierFiscal = <CfbObligation>[');
for (const e of c.calendrierFiscal) L.push(`  CfbObligation(${q(e.code)}, ${q(e.libelle)}, ${q(e.periodicite)}, ${e.jour}, ${n(e.mois)}, ${n(e.part)}, ${q(e.declaration)}, ${q(e.note)}, ${q(e.source)}),`);
L.push('];');
L.push(`const cfbCcibTotal = ${c.montantsFiscaux.ccib.total};\n`);

/* ---- tableaux littéraux de cfg-fiscalite (numérotation, obligations déclaratives) ---- */
const tf = v.fiscalite.reference.lecture.tableaux;
const hrefs = v.fiscalite.reference.hrefs.filter((h) => h[0] === 'Éditer').map((h) => h[1].replace(/^pages\//, '').replace(/\.php$/, ''));
const mec = v.fiscalite.reference.hrefs.find((h) => h[0] === 'Configuration MECeF')[1].replace(/^pages\//, '').replace(/\.php$/, '');
L.push('/// Numérotation des documents (littéral de l\'écran) : type, préfixe, format, séquence.');
L.push('const cfbNumerotation = <(String, String, String, String)>[');
for (const r of tf[0].lignes) L.push(`  (${q(r[0])}, ${q(r[1])}, ${q(r[2])}, ${q(r[3])}),`);
L.push('];');
L.push('/// Obligations déclaratives (littéral de l\'écran) : déclaration, périodicité, échéance, écran producteur.');
L.push('const cfbObligationsDeclaratives = <(String, String, String, String)>[');
tf[1].lignes.forEach((r, i) => L.push(`  (${q(r[0])}, ${q(r[1])}, ${q(r[2])}, ${q(hrefs[i])}),`));
L.push('];');
L.push(`const cfbEcranMecefConfig = ${q(mec)};\n`);

/* ---- notifications ---- */
const ids = ['admission', 'sortie', 'rupture', 'peremption', 'resultat', 'facture', 'commande', 'paie', 'carte', 'mecef', 'securite', 'sauvegarde'];
const mat = v.notifications.matrice;
if (mat.length !== ids.length) throw new Error('notifications : ' + mat.length);
L.push(`class CfbNotification {
  const CfbNotification(this.id, this.libelle, this.detail, this.destinataires, this.app, this.sms, this.mail);
  final String id, libelle, detail, destinataires;
  final bool app, sms, mail;
}
`);
L.push('/// `NOTIFS` de cfg-notifications : un événement, ses destinataires et ses canaux par défaut.');
L.push('const cfbNotifications = <CfbNotification>[');
mat.forEach((r, i) => L.push(`  CfbNotification(${q(ids[i])}, ${q(r.libelle)}, ${q(r.detail)}, ${q(r.dest)}, ${r.canaux[0]}, ${r.canaux[1]}, ${r.canaux[2]}),`));
L.push('];\n');
L.push('/// `NT.PROFILS_AUDIO` : (identifiant, libellé, volume, répétition, note).');
L.push('const cfbProfilsAudio = <(String, String, double, int, String)>[');
for (const p of c.profilsAudio) L.push(`  (${q(p.id)}, ${q(p.label)}, ${Number(p.volume).toFixed(1)}, ${p.repetition}, ${q(p.note)}),`);
L.push('];');
L.push(`/// \`NT.DEFAUTS\`.`);
L.push(`const cfbParamsNotifDefaut = <String, Object>{'visuel': ${c.defautsNotif.visuel}, 'son': ${c.defautsNotif.son}, 'profil': ${q(c.defautsNotif.profil)}, 'volume': ${Number(c.defautsNotif.volume).toFixed(1)}, 'temporisation': ${c.defautsNotif.temporisation}};\n`);

/* ---- système ---- */
L.push('/// `S.COLLECTIONS_ESSENTIELLES` : ce que le vidage des jeux de test CONSERVE toujours.');
L.push('const cfbEssentielles = <String>[');
for (const e of c.essentielles) L.push(`  ${q(e)},`);
L.push('];\n');
L.push('/// `S.libelleCollection` pour les collections du jeu du poste : (module, entité) — « — » / nom technique si la table de la maquette n\'en porte pas.');
L.push('const cfbLibellesCollections = <String, (String, String)>{');
for (const k of Object.keys(c.libelles).sort()) L.push(`  ${q(k)}: (${q(c.libelles[k].module)}, ${q(c.libelles[k].entite)}),`);
L.push('};\n');
L.push(`/// \`NOYAU\` de cfg-modules : les modules qui ne se ferment pas, et pourquoi.
const cfbNoyau = <String, String>{
  'CFG': 'porte cet interrupteur — un interrupteur qui se coupe lui-même ne se rallume plus',
  'DASH': 'porte la page d’accueil de chaque rôle — la fermer laisserait la connexion sans destination',
};`);
fs.writeFileSync(path.join(REPO, 'packages/domaine/lib/src/configuration/cfb_donnees.dart'), L.join('\n') + '\n');
console.log('  écrit : packages/domaine/lib/src/configuration/cfb_donnees.dart (' + L.length + ' lignes)');
