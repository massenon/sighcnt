/* Contenu du manuel d'utilisation SIGH-CNT (16/11/2026).
   Les libellés d'interface sont EXTRAITS de la maquette (prototype_html, écrans réels récoltés par recolte.js et recolte2.js),
   du poste (apps/poste/lib) et du mobile (apps/mobile/lib, prototype_html/mobile). Les droits par rôle sont CALCULÉS depuis
   packages/rbac/data/rbac.json (source unique), jamais recopiés à la main.
   Règle de rédaction du dépôt : pas de tiret cadratin ni demi-cadratin comme ponctuation dans le texte rédigé ; les libellés
   d'écran sont cités tels quels, en gras. */
'use strict';
const path = require('path');
const RBAC = require(path.resolve(__dirname, '../../../packages/rbac/data/rbac.json'));
global.window = global;
require(path.resolve(__dirname, '../../../prototype_html/assets/js/nav.js'));
const N = global.SIGH.nav;

const ROLES = RBAC.roles.filter((r) => !r.archive);
const LIB = Object.fromEntries(RBAC.roles.map((r) => [r.id, r.label]));

/* ---------- petites fabriques ---------- */
const b = (t) => `<b>${t}</b>`;
const chemin = (...p) => `<span class="chemin">${p.join(' ➔ ')}</span>`;
const enc = (cls, tete, t) => `<div class="encadre ${cls}"><span class="tete">${tete}</span>${/^<(p|ul|ol)/.test(t) ? t : '<p>' + t + '</p>'}</div>`;
const info = (t) => enc('info', 'ℹ️ Information', t);
const att = (t) => enc('attention', '⚠️ Attention', t);
const alerte = (t) => enc('alerte', '🛑 Alerte', t);
const astuce = (t) => enc('astuce', '✅ Astuce', t);
const fig = (id, legende, cls) => `<figure${cls ? ' class="' + cls + '"' : ''}><img src="captures/${id}.png" alt=""><figcaption>${legende}</figcaption></figure>`;
const duo = (a, la, c, lc) => `<figure class="duo mobile"><div><img src="captures/${a}.png" alt=""><figcaption>${la}</figcaption></div><div><img src="captures/${c}.png" alt=""><figcaption>${lc}</figcaption></div></figure>`;
const etapes = (...l) => `<ol class="etapes">${l.map((x) => '<li>' + x + '</li>').join('')}</ol>`;
const puces = (...l) => `<ul>${l.map((x) => '<li>' + x + '</li>').join('')}</ul>`;
const lib = (id) => (N.get(id) || {}).label || id;

/** Qui voit et qui agit, CALCULÉ depuis rbac.json pour une liste d'écrans. */
function qui(ecrans, note) {
  const agit = [], lit = [];
  ROLES.forEach((r) => {
    const d = RBAC.parRole[r.id] || {};
    let v = false, e = false;
    ecrans.forEach((x) => { const t = d[x]; if (t && t[0]) v = true; if (t && t[1]) e = true; });
    if (e) agit.push(r.label); else if (v) lit.push(r.label);
  });
  const ecr = ecrans.map((x) => '« ' + lib(x) + ' »').join(', ');
  return `<table class="qui"><tr><th colspan="2">Qui voit quoi : ${ecr} (droits d’origine de la clinique)</th></tr>
  <tr><td>Peut agir (créer, modifier)</td><td>${agit.join(', ') || 'aucun rôle'}</td></tr>
  <tr><td>Consulte seulement</td><td>${lit.join(', ') || 'aucun rôle'}</td></tr>
  <tr><td>Ne voit pas l’écran</td><td>tous les autres rôles${note ? ' ; ' + note : ''}</td></tr></table>`;
}

/** Matrice rôle x rangée du ruban, calculée depuis rbac.json : ● agit sur au moins un écran, ○ consulte seulement. */
function matrice() {
  const lignes = [];
  N.treeRuban('admin').forEach((d) => d.modules.forEach((m) => {
    if (m.code === 'MERE' || m.code === 'IMP') return;
    lignes.push({ nom: d.domain + ' : ' + m.label, ecrans: m.items.map((i) => i.id) });
  }));
  const tete = '<tr><th>Rangée du ruban</th>' + ROLES.map((r) => `<th class="v"><span>${r.short}</span></th>`).join('') + '</tr>';
  const corps = lignes.map((l) => '<tr><td>' + l.nom + '</td>' + ROLES.map((r) => {
    const d = RBAC.parRole[r.id] || {}; let v = false, e = false;
    l.ecrans.forEach((x) => { const t = d[x]; if (t && t[0]) v = true; if (t && t[1]) e = true; });
    return '<td>' + (e ? '<span class="ok">●</span>' : v ? '<span class="lec">○</span>' : '') + '</td>';
  }).join('') + '</tr>').join('');
  return `<table class="matrice"><thead>${tete}</thead><tbody>${corps}</tbody></table>`;
}

function tableRoles() {
  return '<table><tr><th>Rôle (libellé à l’écran)</th><th>Abréviation</th><th>Tableau de bord d’arrivée</th></tr>' + ROLES.map((r) => `<tr><td>${r.label}</td><td>${r.short}</td><td>${lib(r.home)}</td></tr>`).join('') + '</table>';
}

function tableGestes() {
  return '<table><tr><th>Geste réservé</th><th>Rôles qui le détiennent d’origine</th></tr>' + RBAC.gestes.jeux.map((g) => `<tr><td>${g.libelle}</td><td>${g.rolesDefaut.filter((r) => ROLES.some((x) => x.id === r)).map((r) => LIB[r]).join(', ')}</td></tr>`).join('') + '</table>';
}

/* ======================================================================================= */
const CHAPITRES = [
{
  titre: 'À propos de ce manuel',
  chapeau: 'Ce manuel explique, geste par geste, comment les agents de la Clinique NASSIERA TOO utilisent SIGH-CNT au quotidien.',
  html: `
<h2>À qui s’adresse ce manuel</h2>
<p>Ce manuel s’adresse à tous les agents de la clinique qui utilisent SIGH-CNT : accueil, soignants, laboratoire, pharmacie et stock, caisse, comptabilité, ressources humaines, administration et Direction.</p>
<p>Il couvre trois outils :</p>
${puces(`le ${b('poste de travail')} : l’application de bureau installée sur les ordinateurs de la clinique ;`,
 `l’${b('application mobile')} : le téléphone du soignant en tournée et la réception de secours ;`,
 `le ${b('relais web')} : ce que vous en voyez, c’est-à-dire très peu (il transporte les données chiffrées entre les postes et les téléphones).`)}
<p>L’installation, les comptes, les droits, les sauvegardes et le réglage du relais sont traités dans le ${b('Manuel administrateur')}.</p>

<h2>D’où viennent les captures d’écran</h2>
<p>Les captures de ce manuel sont prises sur la ${b('maquette de référence')} de SIGH-CNT. La maquette est l’exécutable qui fait foi : l’interface du poste de travail la reproduit écran par écran, avec les mêmes libellés, les mêmes onglets et les mêmes boutons. Les captures du téléphone viennent du simulateur mobile de la maquette. Elles sont prises à la date du 17 novembre 2026, ce qui explique que l’identité imprimée porte le nouveau RCCM. Pour les écrans des derniers lots, une seconde capture montre le <b>poste de bureau</b> (application Flutter), rendue dans un banc de test avec le jeu sobre du poste : elle est légendée « Sur le poste de bureau » et porte les mêmes cadres rouges.</p>
${info('Les données visibles sur les captures sont des <b>données de démonstration</b>. Aucune donnée de santé réelle n’y figure. Le nom de l’utilisateur connecté et les noms du personnel sont remplacés par « AGENT Démonstration » ou « Agent de démonstration ».')}
${att('Le poste de travail est une application de bureau. Sa présentation peut différer légèrement de la maquette (polices, marges, position d’une icône). Les libellés, l’ordre des étapes et les règles restent les mêmes. Quand un écran n’est pas encore porté au poste, ce manuel le signale dans un encadré « Attention ».')}

<h2>Comment lire ce manuel</h2>
<p>Chaque chapitre correspond à un module du logiciel, dans l’ordre du ruban. Chaque section décrit une tâche courante, pas à pas.</p>
${puces(`Les éléments d’interface sont écrits en gras, exactement comme à l’écran : cliquez sur ${b('Enregistrer')}.`,
 `Un chemin de navigation s’écrit avec une flèche : ${chemin('Soins', 'Patients & Dossier médical', 'Répertoire des patients')}.`,
 `Les étapes d’une tâche sont numérotées 1, 2, 3 : suivez-les dans l’ordre.`,
 `Sur les captures, un ${b('cadre rouge')} montre le bouton à utiliser. Quand il y en a plusieurs, une pastille rouge numérotée indique l’ordre.`)}
<p>Quatre encadrés reviennent dans tout le manuel :</p>
${info('Une précision utile.')}
${att('Une erreur fréquente, une action à faire avec soin, une modification de rôle.')}
${alerte('Un risque de perte de données ou une action qui ne se défait pas.')}
${astuce('Un raccourci ou une bonne pratique.')}

<h2>Ce que ce manuel ne dit pas</h2>
<p>Ce manuel décrit l’état du logiciel au 17 novembre 2026. Certaines parties ne sont pas encore éprouvées en conditions réelles ; elles sont signalées là où elles jouent et récapitulées à l’annexe « Limites connues ».</p>
`},
{
  titre: 'Les rôles et ce qu’ils voient',
  chapeau: 'Chaque agent ouvre une session personnelle. Son rôle décide des écrans qu’il voit et des gestes qu’il peut faire.',
  html: `
<h2>Les rôles de la clinique</h2>
<p>SIGH-CNT connaît les rôles ci-dessous. Votre rôle est choisi par l’administrateur quand il crée votre compte. Il s’affiche sous votre nom, en haut à droite de l’écran.</p>
${tableRoles()}
${info('Le rôle « Biologiste médical » porte l’identifiant technique <span class="cle">laborantin</span> et le rôle « Assistant de Direction » l’identifiant <span class="cle">assistant_comptable</span>. Ces identifiants techniques n’apparaissent pas à l’écran ; vous voyez toujours le libellé.')}

<h2>Trois axes de droits</h2>
<p>Vos droits se règlent sur trois axes :</p>
${puces(`le ${b('rôle')} décide des écrans que vous ouvrez ;`, `la ${b('fonction')} décide de certaines capacités (par exemple signer comme prescripteur) ;`, `le ${b('secteur')} limite votre périmètre (Laboratoire, Pharmacie, Consultation, Imagerie médicale, Maternité, Hospitalisation et soins, Direction).`)}
<p>Sur chaque écran, un droit a trois niveaux : ${b('voir')}, ${b('éditer')} (créer, modifier) et ${b('annuler')} (archiver, annuler une pièce).</p>
${att('<b>Une commande absente veut dire « pas le droit ».</b> SIGH-CNT ne grise jamais un bouton interdit : il ne l’affiche pas. Si un collègue voit un bouton que vous ne voyez pas, c’est que vos rôles diffèrent. Demandez à l’administrateur si votre poste de travail l’exige ; ne partagez jamais votre session.')}
${info('Masquer un bouton ne suffit pas à protéger une donnée : le moteur de SIGH-CNT refuse aussi toute écriture non autorisée, même si elle arrive par un autre chemin. Un refus est toujours nommé, avec son motif et le geste qui le corrige.')}

<h2 class="saut">Matrice des rôles par rangée du ruban</h2>
<p>Le tableau ci-dessous est calculé à partir de la matrice des droits de la clinique (droits d’origine). ${'<span class="ok">●</span>'} : le rôle peut agir sur au moins un écran de la rangée. ${'<span class="lec">○</span>'} : il consulte seulement. Case vide : la rangée n’apparaît pas dans son ruban.</p>
${matrice()}
${att('L’administrateur peut ajuster ces droits pour un rôle (surcharge de la fiche du rôle). Une surcharge peut accorder comme restreindre. Ce tableau montre les droits d’origine : votre clinique a pu les modifier.')}

<h2>Les gestes réservés</h2>
<p>Quelques gestes sensibles sont réservés à certains rôles, quel que soit l’écran. Sans le geste, la commande est absente.</p>
${tableGestes()}
`},
{
  titre: 'Prise en main du poste de travail',
  chapeau: 'Se connecter, se repérer dans l’écran, retrouver un écran, suivre la synchronisation et les notifications.',
  html: `
<h2>Se connecter</h2>
<p>Chaque agent a son propre compte. Aucun compte n’est partagé : chaque action est enregistrée au nom de son auteur (règle RG-12, aucune action anonyme).</p>
${etapes(`Allumez le poste et ouvrez SIGH-CNT. L’écran ${b('Connexion')} s’affiche.`,
 `Saisissez votre ${b('Identifiant')} (de la forme <span class="cle">prenom.nom</span>).`,
 `Saisissez votre ${b('Mot de passe')}. L’icône en forme d’œil affiche le mot de passe pour le vérifier.`,
 `Cliquez sur ${b('Se connecter')}. Votre tableau de bord s’ouvre.`)}
${fig('connexion', 'L’écran de connexion. Le bouton Se connecter ouvre la session.')}
${info('À la première connexion, ou après une réinitialisation, SIGH-CNT vous demande de remplacer le mot de passe provisoire : « Le mot de passe provisoire doit être remplacé avant d’ouvrir la session. » Saisissez le <b>Nouveau mot de passe</b>, puis <b>Confirmer le mot de passe</b>, et validez.')}
<h3>Mot de passe oublié</h3>
${etapes(`Sur l’écran de connexion, cliquez sur ${b('Mot de passe oublié ?')}.`,
 `Renseignez votre ${b('Identifiant ou adresse électronique')}.`,
 `Envoyez la demande. Le message « Demande transmise à l’administrateur système. » confirme l’envoi.`,
 `L’administrateur vous remet un mot de passe provisoire, que vous remplacez à la connexion suivante.`)}

<h2>Se repérer dans l’écran</h2>
<p>L’écran se compose de trois zones : la barre supérieure, le ruban horizontal et le contenu de l’écran.</p>
${fig('barre-ruban', 'La barre supérieure (1 : pastille de synchronisation ; 2 : recherche globale) et le ruban, ici déplié sur Pilotage.')}
<p>La ${b('barre supérieure')} contient, de gauche à droite :</p>
${puces(`le logo et le nom de la clinique ;`,
 `la ${b('recherche globale')} (« Rechercher un patient, un produit, un employé… ») : elle s’ouvre aussi au clavier par ${b('Ctrl K')} ;`,
 `le menu ${b('Actions')} : les raccourcis vers les gestes les plus fréquents, filtrés selon votre rôle ;`,
 `le bouton plein écran ;`,
 `la ${b('pastille de synchronisation')} ;`,
 `la cloche des ${b('notifications')} ;`,
 `votre nom, votre rôle et le menu de votre compte.`)}
<p>Le ${b('ruban')} regroupe les écrans par domaine : ${b('Accueil')}, ${b('Soins')}, ${b('Logistique')}, ${b('Financier')}, ${b('RH')}, ${b('Administration')}, ${b('Système')} et ${b('Pilotage')}. Vous ne voyez que les domaines et les écrans permis à votre rôle.</p>

<h2>Utiliser le ruban</h2>
${etapes(`Cliquez sur un domaine du ruban (par exemple ${b('Soins')}). Le panneau se déplie et montre les rangées du domaine, chacune avec ses écrans.`,
 `Cliquez sur l’écran voulu. L’écran s’ouvre et le panneau se replie.`,
 `Pour replier le panneau sans changer d’écran, cliquez de nouveau sur le domaine actif, ou sur la flèche à droite du ruban.`)}
${fig('ruban-ouvert', 'Le ruban déplié sur le domaine Soins, vu par la Réception. Chaque rangée porte le nom de son module.')}
${astuce('À droite du ruban, les raccourcis <b>Patients</b> et <b>Consultations</b> ouvrent directement les deux écrans les plus utilisés. Le fil d’Ariane, sous le ruban (par exemple Accueil ➔ Soins ➔ Patients & Dossier médical ➔ Répertoire des patients), vous ramène d’un clic au niveau supérieur.')}
${info('L’onglet <b>Système</b> complet n’est affiché qu’à l’Administrateur système et à la DAF. Les autres rôles n’y voient que la rangée <b>Importation de données</b>, et seulement s’ils détiennent un droit sur un jeu d’import.')}

<h2>Votre tableau de bord</h2>
<p>À la connexion, SIGH-CNT ouvre le tableau de bord de votre rôle (par exemple ${b('Tableau de bord — Accueil')} pour la Réception). Il présente en premier ce qui demande votre attention (encadré ${b('À regarder en premier')}), puis vos ${b('Accès rapides')}.</p>
${fig('tableau-bord-accueil', 'Le tableau de bord de la Réception : le premier encadré dit ce qui attend, avec un bouton pour y aller.')}

<h2>La pastille de synchronisation</h2>
<p>Votre poste garde ses données sur place et les échange avec le poste mère de la clinique. Vous pouvez donc travailler même quand le réseau est coupé. La pastille de la barre supérieure dit toujours où en est l’échange :</p>
<table><tr><th>Libellé de la pastille</th><th>Ce que cela veut dire</th><th>Que faire</th></tr>
<tr><td>${b('Synchronisé')} (vert)</td><td>Le poste est à jour avec le poste mère.</td><td>Rien.</td></tr>
<tr><td>${b('Synchronisation…')}</td><td>Un échange est en cours.</td><td>Rien, continuez à travailler.</td></tr>
<tr><td>${b('En retard')}</td><td>Le dernier échange réussi date un peu.</td><td>Continuez ; signalez-le s’il dure.</td></tr>
<tr><td>${b('Hors ligne')} · depuis …</td><td>Le poste mère ne répond pas. Vos saisies sont gardées sur le poste.</td><td>Continuez à travailler. Vos gestes partiront au retour du réseau.</td></tr>
<tr><td>… · ${b('N en attente')}</td><td>N gestes saisis sur ce poste n’ont pas encore été acceptés par la mère.</td><td>Ne fermez pas le poste avant le retour de la connexion si possible.</td></tr>
<tr><td>… · ${b('N à traiter')}</td><td>La mère a refusé N gestes. Chaque refus porte sa cause et le geste qui le corrige.</td><td>Ouvrez l’écran « À traiter » et corrigez.</td></tr>
<tr><td>${b('Poste suspendu')} (rouge)</td><td>L’administrateur a suspendu ce poste.</td><td>Contactez l’administrateur.</td></tr></table>
${info('Sur la maquette, la pastille affiche des libellés voisins : « Synchronisé », « Envoi en cours… », « Synchronisé il y a N s » et « Hors ligne depuis N min, N geste(s) en attente ». Le sens est le même.')}
${info('<b>Ce qui change quand le poste est hors ligne.</b> Vous continuez à saisir, encaisser et imprimer. Deux limites protègent les règles : le poste ne sort du stock que <b>sa part</b> du stock connu (au-delà, refus nommé, jamais de stock négatif), et quand sa plage de numéros est épuisée, un dossier reçoit un <b>code provisoire</b>, jamais un numéro inventé. Une validation attendue d’un autre poste (DAF, Direction) attend le retour du réseau.')}
${astuce('Le guide <b>Panne de connexion</b> (docs/guides/PANNE-DE-CONNEXION.md) détaille ce qui continue, ce qui attend et ce qui se passe au retour. En résumé : continuez à saisir, n’effacez rien, et laissez le poste allumé au retour du réseau.')}

<h2>Les notifications</h2>
<p>La cloche de la barre supérieure annonce les alertes qui vous concernent : un résultat validé, une décision en attente, un produit sous le seuil, une péremption proche, etc. Le nombre d’alertes en attente s’affiche sur la cloche.</p>
${etapes(`Cliquez sur la cloche. La liste des alertes s’ouvre.`, `Cliquez sur une alerte pour ouvrir l’écran concerné.`, `Traitez l’alerte sur l’écran ; elle disparaît de la liste une fois acquittée.`)}
${fig('notifications', 'La cloche des notifications dans la barre supérieure (poste de la caisse).')}
${info('Aucune donnée de santé ne quitte la clinique dans une alerte, un son ou un message : une notification dit « un résultat est prêt », jamais le résultat lui-même.')}

<h2>Le menu Actions et la recherche globale</h2>
<p>Le menu ${b('Actions')} donne accès en un clic aux gestes fréquents : ${b('Nouveau dossier patient')}, ${b('Patient externe : analyses')}, ${b('Nouvelle consultation')}, ${b('Nouvelle admission')}, ${b('Nouvelle facture')}, ${b('Encaisser un paiement')}, ${b('Assurés & cartes')}, ${b('Demande d’analyse')}, ${b('Mouvement de stock')}, ${b('Bon d’expression de besoins')} et ${b('Éditer un état')}. Seuls ceux permis à votre rôle s’affichent.</p>
${fig('menu-actions', 'Le menu Actions ouvert par la Réception : seuls les raccourcis permis à ce rôle sont proposés.')}
<p>La ${b('recherche globale')} trouve un patient, un produit, un employé ou un écran. Elle connaît aussi le contenu des écrans : chercher « péremption » ouvre directement l’onglet ${b('Péremptions')} des alertes de stock.</p>

<h2>Verrouillage et fin de session</h2>
<p>Après quinze minutes sans activité, l’écran se verrouille (${b('Session verrouillée')}). Votre session n’est pas fermée : saisissez votre mot de passe et cliquez sur ${b('Déverrouiller')} pour retrouver l’écran exact où vous étiez.</p>
${att('Quand vous quittez votre poste, fermez votre session par le menu de votre compte (en haut à droite). Un poste de l’accueil ou de la caisse est partagé : la personne suivante doit ouvrir SA session, jamais travailler dans la vôtre.')}
`},
{
  titre: 'Les gestes communs à tous les écrans',
  chapeau: 'Tous les écrans de liste fonctionnent de la même façon : chercher, filtrer, créer, consulter, archiver, exporter, imprimer.',
  html: `
<h2>Chercher et filtrer dans un tableau</h2>
<p>Les écrans de liste (patients, factures, mouvements de stock…) partagent la même barre d’outils.</p>
${fig('tableau-commun', 'La barre d’outils d’un tableau : 1 recherche, 2 Colonnes, 3 Exporter, 4 Nouveau, 5 Importer les données.')}
${etapes(`Tapez quelques lettres dans le champ de recherche (par exemple « Rechercher un patient… »). Le tableau se filtre à mesure.`,
 `Affinez avec les listes de filtres placées à côté (par exemple ${b('Sexe')}, ${b('Couverture')}, ${b('Quartier')}).`,
 `Cliquez sur l’en-tête d’une colonne pour trier.`,
 `Cliquez sur ${b('Colonnes')} pour masquer ou réafficher des colonnes.`)}
${info('Beaucoup d’écrans ont aussi des filtres de période : <b>Aujourd’hui</b>, <b>Sept derniers jours</b>, <b>Toute la période</b>. Les onglets au-dessus du tableau (par exemple <b>Tous les patients</b> et <b>Archivés</b>) indiquent leur nombre de lignes.')}

<h2>Créer, consulter, modifier</h2>
${etapes(`Cliquez sur ${b('Nouveau')} (ou sur le bouton nommé de l’écran : ${b('Nouveau relevé')}, ${b('Nouvelle commande')}…).`,
 `Remplissez le formulaire. Les champs marqués d’un astérisque (*) sont obligatoires.`,
 `Validez avec le bouton du formulaire (${b('Créer')}, ${b('Enregistrer')} ou un bouton nommé comme ${b('Ouvrir le dossier')}).`)}
<p>Dans la colonne ${b('Actions')} de chaque ligne, des icônes donnent les gestes permis : ${b('Consulter')}, ${b('Imprimer l’état')}, ${b('Modifier')}, ${b('Archiver')}. Survolez une icône pour lire son nom.</p>
${fig('actions-ligne', 'La colonne Actions : les icônes Consulter, Imprimer l’état, Modifier et Archiver.')}

<h2>Archiver au lieu de supprimer</h2>
<p>Dans SIGH-CNT, ${b('rien ne se supprime')} (règle RG-14). Une fiche qui n’a plus lieu d’être s’${b('archive')} : elle quitte la liste courante mais reste consultable dans l’onglet ${b('Archivés')}, et l’archivage peut être annulé.</p>
${etapes(`Dans la ligne à retirer, cliquez sur l’icône ${b('Archiver')}.`, `Confirmez. La fiche passe dans l’onglet ${b('Archivés')}.`, `Pour la rétablir, ouvrez l’onglet ${b('Archivés')} et utilisez l’action de restauration de la ligne.`)}
${fig('onglet-archives', 'L’onglet Archivés garde les fiches retirées de la liste courante.')}
${att('Une pièce émise (facture, reçu, bon, résultat validé) ne se réécrit jamais. Pour corriger une facture, on émet un avoir ; pour corriger un résultat validé, on produit une version rectificative. Ces gestes sont décrits dans les chapitres concernés.')}

<h2>Exporter et imprimer les lignes d’un tableau</h2>
<p>Le bouton ${b('Exporter')} sort les lignes d’un tableau dans un fichier ou sur papier. Cochez d’abord les lignes voulues si vous ne voulez pas tout sortir : la sélection est gardée d’une page du tableau à l’autre.</p>
${etapes(`Cochez les lignes à sortir (case en début de ligne), ou aucune pour tout sortir.`,
 `Cliquez sur ${b('Exporter')}. La fenêtre ${b('Exporter les données')} s’ouvre.`,
 `Choisissez les lignes : ${b('Les N lignes cochées')}, ${b('Les N lignes filtrées')} (si un filtre est actif) ou ${b('Tout exporter')}.`,
 `Choisissez le format : ${b('Excel (.xlsx)')}, ${b('CSV')} ou ${b('PDF / Impression')}.`,
 `Validez. Le fichier se télécharge, ou l’aperçu d’impression s’ouvre.`)}
${fig('exporter', 'La fenêtre Exporter les données : choix des lignes, puis du format.')}
${info('L’export ne contient que ce que l’écran vous montre : les colonnes masquées ne sortent pas, et un rôle ne peut pas exporter ce qu’il ne voit pas. Chaque export est inscrit au journal (RG-12).')}
${att('Une limite de lignes par export est réglée par la clinique. Au-delà, l’export est <b>refusé en le disant</b>, jamais tronqué. Filtrez le tableau pour sortir moins de lignes. Exporter est un geste réservé (« exporter_donnees ») : sans lui, le bouton Exporter est absent.')}

<h2>Imprimer un document officiel</h2>
<p>Tout document édité par SIGH-CNT (facture, reçu, bon, ordonnance, résultat, état) porte l’en-tête officiel de la clinique et un pied normalisé : pagination, date, utilisateur et identifiant du document. Trois formats existent :</p>
${puces(`${b('A4')} : factures, ordonnances, résultats, états ;`, `${b('rouleau 80 mm')} : tickets de caisse, imprimés sur l’imprimante de la caisse ;`, `${b('carte CR80')} : badges du personnel.`)}
${etapes(`Cliquez sur le bouton d’impression de l’écran (${b('Imprimer')}, ${b('Éditer l’état')}, ${b('Imprimer la fiche')}…) ou sur l’icône d’impression de la ligne.`, `Vérifiez l’aperçu.`, `Choisissez l’imprimante et imprimez.`)}
${info('Les totaux d’un état sont toujours calculés à partir des lignes, jamais saisis. Si une valeur ne peut pas être calculée, l’état l’écrit « non calculable » : ce n’est pas zéro.')}

<h2>Importer des données</h2>
<p>Certains écrans portent le bouton ${b('Importer les données')} (répertoire des patients, stock gros, transferts, inventaires, courriers…). Il sert à reprendre des listes existantes depuis un classeur.</p>
${etapes(`Cliquez sur ${b('Importer les données')}.`, `Téléchargez le modèle proposé et remplissez-le.`, `Déposez le fichier : SIGH-CNT le vérifie ligne par ligne et affiche les erreurs avant toute écriture.`, `Confirmez l’import. Le lot apparaît dans l’historique des lots ; il peut être annulé.`)}
${fig('import', 'L’écran Jeux d’import et historique des lots (rangée Importation de données).')}
${info('Le même fichier importé deux fois est reconnu comme le même lot : il n’est pas écrit deux fois. Les droits d’import se règlent jeu par jeu.')}
`},
{
  titre: 'Accueil : rendez-vous, file d’attente, constantes',
  chapeau: 'Le domaine Accueil réunit ce que la Réception fait à l’arrivée d’un patient : rendez-vous, file d’attente, constantes, patients externes et courriers.',
  html: `
<h2>Prendre un rendez-vous</h2>
${etapes(`Ouvrez ${chemin('Accueil', 'RDV, Visites & Consultations', 'Rendez-vous & visites')}.`,
 `Cliquez sur ${b('Nouveau')}. La fenêtre ${b('Nouveau rendez-vous')} s’ouvre.`,
 `Choisissez le ${b('Dossier patient')}. Pour un nouveau venu sans dossier, renseignez ${b('Nom')}, ${b('Prénom(s)')}, ${b('Quartier / résidence')} et ${b('Numéro de téléphone')}.`,
 `Choisissez le ${b('Praticien')}, le ${b('Type')}, la ${b('Date et heure')} et le ${b('Motif')}.`,
 `Cliquez sur ${b('Créer')}.`)}
${fig('rendez-vous', 'La fenêtre Nouveau rendez-vous.')}
<p>L’onglet ${b('Agenda — à venir, reportés, non honorés')} liste les rendez-vous à suivre ; l’onglet ${b('Honorés (apurés de l’agenda)')} garde ceux qui ont eu lieu. L’écran ${b('Agenda')} présente la semaine en cours, avec le bouton ${b('Nouveau rendez-vous')}.</p>
${fig('agenda', 'L’Agenda de la semaine.')}
${qui(['m2-rendezvous'])}

<h2>Inscrire un patient dans la file d’attente</h2>
<p>La ${b('File d’attente')} suit le patient de poste en poste. Ses onglets sont les postes de la clinique : ${b('Accueil')}, ${b('Consultation')}, ${b('Caisse')}, ${b('Salle de prélèvement')}, ${b('Pharmacie')}, ${b('Salle de soins')}, ${b('Imagerie médicale')}.</p>
${etapes(`Ouvrez ${chemin('Accueil', 'RDV, Visites & Consultations', 'File d’attente')}.`,
 `Cliquez sur ${b('Inscrire un patient')}.`,
 `Choisissez le ${b('Patient')}, la ${b('Priorité de triage')} et le ${b('Motif')}, puis cliquez sur ${b('Inscrire')}.`,
 `Quand le poste suivant est libre, cliquez sur ${b('Appeler')} : le patient s’affiche sur l’${b('Écran d’appel des patients')}.`)}
${fig('file-attente', 'La file d’attente : 1 Inscrire un patient, 2 Appeler.')}
${info('L’ordre d’arrivée gouverne, sauf urgence : la priorité de triage se modifie par l’action <b>Modifier la priorité</b> de la ligne.')}

<h2>Relever les constantes à l’accueil</h2>
${etapes(`Ouvrez ${chemin('Accueil', 'Patients & constantes', 'Constantes à l’accueil')}.`,
 `Cliquez sur ${b('Nouveau relevé')}. La fenêtre ${b('Relever les constantes')} s’ouvre.`,
 `Choisissez le ${b('Patient')}, la ${b('Date et heure du relevé')} et le ${b('Moment')}.`,
 `Saisissez les mesures : ${b('Température (°C)')}, ${b('Tension systolique (cmHg)')} et ${b('Tension diastolique (cmHg)')}, ${b('Pouls (bpm)')}, ${b('Fréquence respiratoire (/min)')}, ${b('SpO₂ (%)')}, ${b('Diurèse (mL)')}, ${b('Poids (kg)')}, ${b('Taille (cm)')}.`,
 `Indiquez ${b('Relevé par')} et cliquez sur ${b('Créer')}.`)}
${fig('constantes', 'La fenêtre Relever les constantes.')}
${att('La tension se saisit en <b>deux nombres, en cmHg</b> (par exemple 12 et 8), et la diurèse en <b>mL</b>. Une valeur hors des bornes de contrôle est signalée dans la colonne <b>Contrôle</b>.')}

<h2>Accueillir un patient externe (analyses ou imagerie)</h2>
<p>Un patient adressé de l’extérieur pour une analyse ou un examen d’imagerie n’a pas besoin d’un dossier complet.</p>
${etapes(`Ouvrez ${chemin('Accueil', 'Patients & constantes', 'Patient externe')}.`,
 `Cliquez sur ${b('Nouvelle demande externe')}.`,
 `Renseignez le patient, l’examen et le prescripteur extérieur, puis enregistrez.`,
 `Suivez la demande dans les onglets ${b('Demandes — analyses')}, ${b('Demandes — imagerie médicale')} et ${b('Résultats')}.`)}
${fig('patient-externe', 'L’écran Patient externe et son bouton Nouvelle demande externe.')}
${qui(['m1-externe'])}

<h2>Enregistrer un courrier</h2>
<p>L’écran ${chemin('Accueil', 'Courriers & orientation', 'Courriers (départ / arrivée)')} tient le registre du courrier. Il est décrit au chapitre Administration.</p>
`},
{
  titre: 'Patients et dossier médical',
  chapeau: 'Le répertoire des patients est la porte d’entrée de tout le parcours : un patient, un dossier, un code unique.',
  html: `
<h2>Créer un dossier patient</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Patients & Dossier médical', 'Répertoire des patients')}, ou utilisez ${chemin('Actions', 'Nouveau dossier patient')}.`,
 `Vérifiez d’abord, avec la recherche, que le patient n’a pas déjà un dossier.`,
 `Cliquez sur ${b('Nouveau')}. La page ${b('Identité, coordonnées et couverture')} s’ouvre.`,
 `Renseignez ${b('Nom')}, ${b('Prénom(s)')}, ${b('Sexe')}, ${b('Date de naissance')} et ${b('Téléphone')} (obligatoires), puis ${b('Groupe sanguin')}, ${b('Quartier')}, ${b('Adresse')} et ${b('Personne à prévenir')}.`,
 `Cochez ${b('Accepte de recevoir des SMS de la clinique')} si le patient l’accepte.`,
 `Renseignez si besoin les ${b('Antécédents')}, les ${b('Allergies connues')} et le ${b('Traitement en cours')}.`,
 `Si le patient est assuré, renseignez ${b('Compagnie d’assurance')}, ${b('Numéro de police')}, ${b('Taux de prise en charge (%)')} et ${b('Expiration de la carte')}.`,
 `Cliquez sur ${b('Ouvrir le dossier')}. Le code dossier est attribué automatiquement.`)}
${fig('patient-nouveau', 'La page de création du dossier ; le bouton Ouvrir le dossier enregistre.')}
${info('<b>Le code patient est unique et non modifiable</b> (règle RG-01). Il est généré automatiquement au format <span class="cle">CNT/[n° d’ordre]/[année]</span>, par exemple <span class="cle">CNT/1/25</span>. Vous ne le saisissez jamais. Les anciens dossiers gardent leur code d’origine (forme <span class="cle">CNT530/25</span>).')}
${att('La date d’expiration de la carte d’assurance compte : la prise en charge ne s’applique que si la carte est valide à la date de la facture (RG-09). Sinon, le patient paie le prix non assuré.')}
${qui(['m1-patients'])}

<h2>Consulter la fiche patient</h2>
<p>La ${b('Fiche patient')} réunit tout le dossier dans des onglets : ${b('Administratif')}, ${b('Médical')}, ${b('Antécédents & allergies')}, ${b('Soins')}, ${b('Hospitalisations')}, ${b('Maternité')}, ${b('Analyses & résultats')}, ${b('Imagerie médicale')}, ${b('Ordonnances')}, ${b('À domicile')}, ${b('Financier')}, ${b('Assurance')} et ${b('Traçabilité')}.</p>
${etapes(`Dans le répertoire, cliquez sur l’icône ${b('Consulter')} de la ligne du patient.`, `Parcourez les onglets.`, `Utilisez ${b('Modifier le dossier')} pour corriger les coordonnées, ${b('Imprimer la fiche')} pour l’imprimer, ou ${b('Fiche de consultation')} pour ouvrir une consultation.`)}
${fig('patient-fiche', 'La fiche patient vue par un Médecin : 1 Modifier le dossier, 2 Imprimer la fiche.')}
${info('L’onglet <b>Traçabilité</b> montre qui a fait quoi sur le dossier, et quand (RG-12). Les onglets médicaux ne sont visibles que des soignants habilités (RG-13).')}

<h2>Délivrer un certificat ou une attestation</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Patients & Dossier médical', 'Certificats & attestations')}.`,
 `Cliquez sur ${b('Délivrer une pièce')}.`,
 `Choisissez le ${b('Type de pièce')}, puis le patient (${b('Patient (dossier du répertoire)')}) ou, pour un patient adressé de l’extérieur, renseignez son identité.`,
 `Choisissez le ${b('Médecin signataire')}, la ${b('Date de délivrance')} et complétez les ${b('Mentions portées sur la pièce')}.`,
 `Cliquez sur ${b('Créer')}, puis imprimez avec l’icône ${b('Imprimer la pièce')}.`)}
${info('Le prix de chaque certificat vient du référentiel des tarifs de la clinique ; il n’est jamais saisi à la main.')}

<h2>Ajouter un document numérisé</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Patients & Dossier médical', 'Documents numérisés')}.`, `Cliquez sur ${b('Ajouter un document')}.`, `Choisissez le dossier, le type de document et le fichier, puis enregistrez.`)}
${info('Le texte d’un scan peut être lu par la machine (lecture locale, sur le poste : rien ne sort de la clinique). Une correction de ce texte est une version signée et journalisée ; elle est réservée au geste « Corriger le texte lu par machine d’un scan ».')}
`},
{
  titre: 'Consultations et prescriptions',
  chapeau: 'Le médecin consulte, prescrit, et la prescription suit le patient vers la caisse, la pharmacie, le laboratoire ou la salle de soins.',
  html: `
<h2>Le parcours d’une consultation</h2>
<p>La fiche de consultation affiche l’${b('Enchaînement du parcours')}, en cinq étapes :</p>
${etapes(`${b('Accueil, Zone 1')} : identité, couverture et constantes saisies à l’accueil.`,
 `${b('Dossier de consultation')} : anamnèse, antécédents, examen clinique, enregistrés d’abord.`,
 `${b('Fiche de consultation')} : synthèse, diagnostic, conduite à tenir.`,
 `${b('Prescription')} : médicaments, analyses, imagerie, prescrits ici seulement.`,
 `${b('Caisse')} : une facture globale (part assureur et part patient) ; la délivrance, le prélèvement et l’imagerie se débloquent au règlement.`)}
${info('Chaque ligne de prescription porte un prix strictement positif, lu au référentiel des tarifs à la date de la pièce. Quand un prix manque, la ligne l’affiche « prix à définir » avec sa cause : ce n’est jamais zéro. Les médicaments sont facturés au prix d’achat, sans marge (RG-02).')}

<h2>Ouvrir une consultation</h2>
${etapes(`Ouvrez ${chemin('Accueil', 'RDV, Visites & Consultations', 'Consultations')}.`,
 `Cliquez sur ${b('Nouveau')}.`,
 `Renseignez ${b('Dossier patient')}, ${b('Praticien')}, ${b('Type')}, ${b('Date et heure')}, ${b('Motif')} et ${b('Statut')} ; le ${b('Diagnostic')} peut être complété plus tard.`,
 `Cliquez sur ${b('Créer')}.`)}
${qui(['m2-consultations'])}

<h2>Prescrire depuis la fiche de consultation</h2>
${etapes(`Ouvrez d’abord ${chemin('Soins', 'Consultations & prescriptions', 'Dossiers de consultation')} et enregistrez l’anamnèse et l’examen clinique du patient.`,
 `Ouvrez la ${b('Fiche de consultation')} sur ce dossier (depuis le dossier, ou par ${b('Fiche de consultation')} sur la fiche patient). Vérifiez le ${b('Dossier patient')} affiché.`,
 `Remplissez ${b('Synthèse, diagnostic et conduite à tenir')}.`,
 `Pour chaque médicament, choisissez-le dans la liste ${b('Médicament')}, précisez la posologie, puis cliquez sur ${b('Ajouter un médicament')}. Ajoutez de même les analyses et les examens d’imagerie.`,
 `Cliquez sur ${b('Enregistrer et prescrire')}. Les prescriptions partent vers la caisse puis vers les postes d’exécution.`,
 `Imprimez avec ${b('Éditer l’ordonnance')} et ${b('Éditer le bulletin d’analyses')}.`)}
${fig('consultation-fiche', 'La section Prescription de la fiche : Ajouter un médicament ajoute une ligne. Analyses et imagerie se choisissent dessous.')}
${fig('consultation-prescrire', 'Le bouton Enregistrer et prescrire, en bas de la fiche.')}
${att('Sans dossier de consultation enregistré, la fiche refuse et le dit : « Fiche impossible sans dossier ». Le bouton <b>Ouvrir les dossiers de consultation</b> vous y conduit. Les constantes ne se saisissent pas sur la fiche : elles se relèvent à l’accueil.')}
${att('Une ordonnance enregistrée est une pièce émise : elle ne se réécrit pas. Pour changer un traitement, faites une nouvelle prescription.')}

<h2>Suivre les prescriptions et les ordonnances</h2>
<p>L’écran ${chemin('Soins', 'Consultations & prescriptions', 'Prescriptions')} liste toutes les prescriptions, avec les onglets ${b('Toutes')}, ${b('Prescriptions de soins')}, ${b('Ordonnances')} et ${b('En cours')}. Les colonnes ${b('Destinataire')} et ${b('Règlement')} disent où en est chaque ligne. Le bouton ${b('Nouvelle prescription de soins')} prescrit un acte infirmier hors consultation.</p>
${fig('prescriptions', 'L’écran Prescriptions et son bouton Nouvelle prescription de soins.')}
<p>L’écran ${b('Ordonnances')} montre, pour chaque ordonnance, l’état à la ${b('Caisse')} et à la ${b('Pharmacie')}.</p>

<h2>Administrer un soin en salle de soins</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Consultations & prescriptions', 'Salle de soins')}.`,
 `Repérez la ligne (colonnes ${b('Prescription')}, ${b('Patient')}, ${b('Acte ou produit')}).`,
 `Cliquez sur ${b('Administrer')} et confirmez ce qui a été fait.`)}
${fig('salle-soins', 'La salle de soins : le bouton Administrer enregistre l’acte réalisé.')}
${qui(['m2-salle-soins'])}

<h2>Demander et rendre un examen d’imagerie</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Imagerie médicale', 'Demandes d’imagerie médicale')}.`,
 `Cliquez sur ${b('Nouvelle demande')}, choisissez le patient, l’examen et la modalité, puis enregistrez.`,
 `Une fois l’examen réalisé, l’opérateur clique sur ${b('Saisir le CR')} (ou ${b('Poursuivre le CR')}) pour rédiger le compte rendu.`,
 `Cliquez sur ${b('Rendre')} pour mettre le compte rendu à disposition du prescripteur.`)}
${fig('imagerie-demandes', 'Les demandes d’imagerie : 1 Nouvelle demande, 2 Saisir le CR.')}
<p>Les tableaux ${b('Tableau Échographie')}, ${b('Tableau Radiographie')}, ${b('Tableau Mammographie')}, ${b('Tableau Scanner')} et ${b('Tableau IRM')} listent les comptes rendus par modalité ; la ${b('Galerie des clichés')} regroupe les images.</p>
`},
{
  titre: 'Hospitalisation',
  chapeau: 'Admettre un patient dans un lit, suivre ses soins, puis organiser sa sortie dans les règles.',
  html: `
<h2>Admettre un patient</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Hospitalisation', 'Admissions')}, ou utilisez ${chemin('Actions', 'Nouvelle admission')}.`,
 `Cliquez sur ${b('Nouveau')}. La fenêtre ${b('Nouveau admission')} s’ouvre.`,
 `Choisissez le ${b('Dossier patient')}, le ${b('Lit')} et l’${b('Infirmier référent')}.`,
 `Renseignez la ${b('Date d’entrée')}, le ${b('Type de prise en charge')}, le ${b('Diagnostic d’entrée')} et les ${b('Symptômes constatés')}.`,
 `Cliquez sur ${b('Créer')}.`)}
${fig('admission', 'La fenêtre d’admission.')}
${info('Un lit ne porte qu’une seule admission active. Un lit occupé n’est pas proposé.')}
${qui(['m3-admissions'])}

<h2>Voir les lits</h2>
<p>Le ${b('Plan des lits')} montre chaque chambre et chaque lit, avec le patient et la durée du séjour, ou la mention ${b('Disponible')}. L’écran ${b('Chambres & lits')} tient la liste des chambres.</p>
${fig('plan-lits', 'Le plan des lits.')}

<h2>Suivre les soins du patient hospitalisé</h2>
<p>Plusieurs écrans de la rangée ${b('Hospitalisation')} servent au suivi quotidien :</p>
${puces(`${b('Feuille de soins')} : chaque acte réalisé (bouton ${b('Nouveau')}) ;`,
 `${b('Administration des traitements')} : les onglets ${b('À administrer')} et ${b('Historique')}, avec le bouton ${b('Administrer')} ;`,
 `${b('Feuille de température')}, ${b('Fiche de surveillance')}, ${b('Score de Glasgow')}, ${b('Surveillance transfusionnelle')} ;`,
 `${b('Consultation pré-anesthésique')}, ${b('Comptes rendus opératoires')}, ${b('Comptes rendus d’anesthésie')}, ${b('Check-listes du bloc')} ;`,
 `${b('Demande d’examen')}, ${b('Bons de pansement')}, ${b('Rapport médical')}, ${b('Visites aux hospitalisés')}.`)}
${att('Certaines check-listes et bornes de surveillance portent la mention « à valider » : elles attendent la validation écrite du professionnel désigné. Utilisez-les comme aide, pas comme référence définitive.')}

<h2>Organiser la sortie d’un patient</h2>
<p>Une sortie d’hospitalisation exige quatre conditions (règles RG-06 à RG-08) : le ${b('solde apuré')}, la ${b('signature du patient')}, la ${b('signature de l’infirmier')} et le ${b('constat du gardien')}.</p>
${etapes(`Ouvrez ${chemin('Soins', 'Hospitalisation', 'Sorties d’hospitalisation')}. La colonne ${b('Solde (RG-06)')} montre ce qui reste dû.`,
 `Si le solde n’est pas nul, envoyez la famille à la caisse avant d’aller plus loin.`,
 `Dans la ligne du patient, cliquez sur ${b('Préparer la sortie')}.`,
 `Renseignez la ${b('Date de sortie')}, l’${b('État à la sortie')} et les ${b('Consignes de sortie et suivi')}.`,
 `Cochez ${b('Signature du patient recueillie')}, ${b('Signature de l’infirmier traitant')} et ${b('Constat du gardien effectué')} au fur et à mesure.`,
 `Imprimez le bon avec ${b('Éditer le bon de sortie')}, puis cliquez sur ${b('Finaliser la sortie')}. Le lit redevient disponible.`)}
${fig('sortie', 'La fenêtre Sortie d’hospitalisation ; Finaliser la sortie clôt le séjour.')}
${att('Si le solde n’est pas apuré, la sortie demande une <b>Dérogation de la Direction (si solde non apuré)</b>. Sans elle, la sortie ne se finalise pas.')}

<h2>Sortie contre avis médical</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Hospitalisation', 'Sortie contre avis médical')}.`, `Renseignez le patient et le motif de la sortie (obligatoire), et consignez l’avis du Procureur s’il a été requis.`, `Cliquez sur ${b('Enregistrer')}.`)}
${alerte('Une sortie contre avis médical engage la clinique. Le motif doit être précis et complet : le document enregistré ne se réécrit pas.')}
`},
{
  titre: 'Maternité, naissances et décès',
  chapeau: 'Du suivi de grossesse au registre des naissances.',
  html: `
<h2>Les écrans de la maternité</h2>
<p>La rangée ${chemin('Soins', 'Maternité, Naissances & Décès')} réunit : ${b('Dossier obstétrical')}, ${b('Suivi maternité')}, ${b('CPN & carte maternelle')}, ${b('Partogramme')}, ${b('Accouchements')}, ${b('Dossier bébé & soins du nouveau-né')}, ${b('Consultations post-natales (CPoN)')}, ${b('Planification familiale')}, ${b('Registre SONUB / SONUC')}, ${b('Registre PTME')}, ${b('Soins curatifs & urgences maternité')}, ${b('Comptes rendus de maternité')}, ${b('Registre des naissances')} et ${b('Registre des décès')}.</p>
${qui(['m4-accouchements'])}

<h2>Suivre une grossesse (CPN)</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Maternité, Naissances & Décès', 'CPN & carte maternelle')}.`, `Cliquez sur ${b('Nouveau')} pour une nouvelle grossesse suivie, ou sur l’action de la ligne pour ajouter une visite.`, `Renseignez le terme, la date prévue d’accouchement et les traitements préventifs (colonnes ${b('SP (TPI)')}, ${b('MILDA')}, ${b('Mébendazole')}).`, `Enregistrez.`)}

<h2>Enregistrer un accouchement</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Maternité, Naissances & Décès', 'Accouchements')}.`,
 `Cliquez sur ${b('Nouveau')}.`,
 `Renseignez la parturiente, la date et l’heure, le type d’accouchement, les actes associés, la durée du travail, les complications, le praticien et l’issue.`,
 `Enregistrez, puis déclarez le nouveau-né dans le ${b('Registre des naissances')} (bouton ${b('Nouveau')}) : sexe, poids, Apgar, périmètres.`)}
${fig('maternite', 'L’écran Accouchements et son bouton Nouveau.')}
${info('Les statistiques de la maternité (<b>Statistiques maternité & naissances</b>, domaine Pilotage) sont calculées à partir de ces registres.')}
`},
{
  titre: 'Laboratoire',
  chapeau: 'Une analyse passe par quatre étapes : demande, prélèvement, saisie du résultat, validation biologique.',
  html: `
<h2>Le circuit d’une analyse</h2>
${etapes(`La ${b('demande')} arrive du médecin (prescription), de la maternité, de l’hospitalisation ou d’un patient externe.`,
 `Le patient ${b('règle')} à la caisse : le prélèvement n’est possible qu’après règlement.`,
 `Le préleveur ${b('enregistre le prélèvement')} et le ${b('transmet au laboratoire')}.`,
 `Le laboratoire ${b('saisit le résultat')}, puis le biologiste le ${b('valide biologiquement')} : il devient visible du prescripteur.`)}
${qui(['m5-resultats'])}

<h2>Prélever et transmettre</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Laboratoire', 'Salle de prélèvement')}. Trois onglets : ${b('À prélever')}, ${b('À transmettre')}, ${b('Reçus au laboratoire')}.`,
 `Dans l’onglet ${b('À prélever')}, imprimez si besoin le bon (icône ${b('Imprimer le bon d’analyse')}).`,
 `Cliquez sur l’icône ${b('Enregistrer le prélèvement')} de la ligne.`,
 `Dans l’onglet ${b('À transmettre')}, cliquez sur ${b('Transmettre au laboratoire')}.`)}
${fig('labo-prelevement', 'La salle de prélèvement et ses trois onglets.')}
${info('Un cadenas <b>Règlement requis avant prélèvement</b> remplace l’action tant que la caisse n’a pas encaissé. Envoyez le patient à la caisse.')}

<h2>Saisir et valider les résultats</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Laboratoire', 'Saisie des résultats')}. Trois onglets : ${b('À saisir')}, ${b('À valider biologiquement')}, ${b('Rendus au prescripteur')}.`,
 `Dans ${b('À saisir')}, cliquez sur ${b('Saisir le résultat')}, renseignez les valeurs et enregistrez.`,
 `Le biologiste ouvre ${b('À valider biologiquement')}, relit l’ensemble et clique sur ${b('Valider biologiquement')} (ou ${b('Valider la sélection')} pour plusieurs lignes).`,
 `Le résultat passe dans ${b('Rendus au prescripteur')}.`)}
${fig('labo-resultats', 'La saisie des résultats : les trois onglets du circuit.')}
${alerte('Une fois validés, les résultats sont visibles du prescripteur. Au-delà, une correction produit une <b>version rectificative</b> et le prescripteur en est averti : relisez avant de valider.')}
${att('En l’absence du biologiste médical, la validation se fait <b>par intérim</b> (bouton <b>Valider par intérim</b>) et le dit. Valider un seuil de variation brutale est un geste réservé au Biologiste médical. Les bornes marquées « à valider » attendent la validation écrite du biologiste.')}

<h2>Imprimer les résultats</h2>
${etapes(`Ouvrez ${chemin('Soins', 'Laboratoire', 'Impression des résultats')}.`, `Sélectionnez la ligne (colonne ${b('Règlement')} à jour).`, `Cliquez sur ${b('Imprimer')}.`)}
${fig('labo-impression', 'Impression des résultats.')}
<p>Les autres écrans du laboratoire : ${b('Catalogue des analyses')}, ${b('Unités de mesure')}, ${b('Valeurs de référence')}, ${b('Comparatif des résultats')}, ${b('Réactifs & consommables')}, ${b('Banque de sang')}, ${b('Donneurs & transfusions')} et les statistiques.</p>
`},
{
  titre: 'Pharmacie et stocks',
  chapeau: 'Délivrer les médicaments, tenir le stock gros et le stock détail, transférer, inventorier, déclarer une perte.',
  html: `
<h2>Les règles du stock</h2>
${puces(`${b('Le stock ne devient jamais négatif')} (RG-03) : une sortie supérieure au stock est refusée.`,
 `${b('Toute sortie a un justificatif')} : ordonnance, bon de transfert, constat de perte (colonne ${b('Justificatif (RG-03)')}).`,
 `${b('FEFO')} (RG-05) : le premier lot à périmer sort le premier. L’onglet ${b('Ordre de sortie FEFO')} de l’écran ${b('Lots & péremptions (FEFO)')} le montre.`,
 `${b('Prix d’achat, sans marge')} (RG-02) : un médicament est facturé au prix d’achat ; le coût moyen (CUMP) est calculé automatiquement.`)}
${qui(['m6-stock-detail', 'm6-dispensation'])}

<h2>Délivrer une ordonnance encaissée</h2>
${etapes(`Ouvrez ${chemin('Logistique', 'Pharmacie & Stocks', 'Dispensation')}. La liste ${b('File des délivrances (ordonnances encaissées)')} montre ce qui attend.`,
 `Repérez le patient (colonnes ${b('Origine')}, ${b('Patient')}, ${b('À faire')}).`,
 `Cliquez sur ${b('Délivrer')} dans la ligne.`,
 `Vérifiez les produits et les quantités, puis confirmez. Le stock détail est débité, lot par lot, dans l’ordre FEFO.`)}
${fig('dispensation', 'La dispensation, vue de la caisse du dispensaire : le bouton Délivrer de la ligne.')}
${info('Les écrans <b>Pharmacie interne — urgences</b> et <b>Pharmacie externe — voie orale</b> présentent les mêmes délivrances par circuit ; le bouton <b>Délivrer</b> y demande une confirmation produit par produit.')}

<h2>Consulter le stock gros et le stock détail</h2>
<p>Le ${b('Stock gros (magasin)')} et le ${b('Stock détail (pharmacie)')} listent chaque article : quantité, seuil, CUMP, valeur et emplacement. Le bouton ${b('Éditer l’état')} imprime l’état du stock.</p>
${fig('stock-detail', 'Le stock détail ; Éditer l’état imprime l’état valorisé.')}

<h2>Transférer du stock gros vers le stock détail</h2>
${etapes(`Ouvrez ${chemin('Logistique', 'Pharmacie & Stocks', 'Transferts gros → détail')}.`,
 `Cliquez sur ${b('Nouveau transfert')}. La fenêtre ${b('Nouveau transfert de stock')} s’ouvre.`,
 `Renseignez la ${b('Date du transfert')}, le ${b('Service demandeur')} et le ${b('Motif du transfert')}.`,
 `Pour chaque article, choisissez-le (${b('Choisir un article…')}), saisissez la ${b('Quantité')} et cliquez sur ${b('Ajouter')}.`,
 `Cliquez sur ${b('Valider le transfert')}. Imprimez le bon avec l’icône ${b('Imprimer le bon')} de la ligne.`)}
${fig('transfert', 'La fenêtre Nouveau transfert de stock.')}

<h2>Faire un inventaire</h2>
${etapes(`Ouvrez ${chemin('Logistique', 'Pharmacie & Stocks', 'Inventaires')}.`,
 `Cliquez sur ${b('Lancer un inventaire')}.`,
 `Choisissez le ${b('Magasin inventorié')}, le ${b('Type d’inventaire')}, la ${b('Date')}, le ${b('Périmètre')} (par exemple ${b('Tous les articles')}) et ${b('Réalisé par')}.`,
 `Cliquez sur ${b('Ouvrir la feuille de saisie')} et saisissez les quantités comptées.`,
 `Validez l’inventaire : les écarts deviennent des mouvements justifiés.`)}
${fig('inventaire', 'La fenêtre Lancer un inventaire.')}
${astuce('Un comptage fait sur papier ou sur tableur peut être repris par <b>Importer les données</b> (jeu « Importation d’un comptage d’inventaire »).')}

<h2>Déclarer une perte, une casse ou une péremption</h2>
${etapes(`Ouvrez ${chemin('Logistique', 'Pharmacie & Stocks', 'Pertes, casses & rebuts')}.`,
 `Cliquez sur ${b('Déclarer une perte')}.`,
 `Renseignez ${b('Article')}, ${b('Nature de la perte')}, ${b('Magasin concerné')}, ${b('Quantité perdue')}, ${b('Date du constat')}, ${b('Justificatif')}, ${b('Constaté par')} et les ${b('Circonstances')}.`,
 `Cliquez sur ${b('Déclarer la perte')}, puis imprimez le constat avec ${b('Éditer le constat')}.`)}
${fig('pertes', 'La fenêtre Déclarer une perte.')}

<h2>Surveiller les alertes de stock</h2>
<p>L’écran ${b('Alertes & seuils')} a trois onglets : ${b('Ruptures')}, ${b('Sous le seuil')} et ${b('Péremptions')}. Le bouton ${b('Ouvrir les bons de besoins (M7)')} enchaîne sur une demande d’achat.</p>
${fig('alertes-stock', 'Les alertes de stock : produits sous le seuil et péremptions.')}
${info('Le préavis de péremption est un réglage de la clinique, enregistré en base.')}
<p>Les autres écrans : ${b('Tableau de bord stock')}, ${b('Référentiel produits')}, ${b('Mouvements de stock')}, ${b('Lots & péremptions (FEFO)')}, ${b('Étiquetage & emplacements')}, ${b('Suivi des ventes')}, ${b('Point du stock valorisé')}.</p>
`},
{
  titre: 'Achats et fournisseurs',
  chapeau: 'Du besoin exprimé par un service à la réception contrôlée de la livraison.',
  html: `
<h2>Exprimer un besoin</h2>
${etapes(`Ouvrez ${chemin('Logistique', 'Achats & Fournisseurs', 'Bons d’expression de besoins')}.`,
 `Cliquez sur ${b('Nouveau bon')}.`,
 `Renseignez ${b('Date')}, ${b('Service demandeur')}, ${b('Demandeur')}, ${b('Catégorie du besoin')} et le ${b('Motif de la demande')} ; cochez ${b('Besoin urgent')} si nécessaire.`,
 `Ajoutez chaque article avec sa ${b('Qté demandée')} (bouton ${b('Ajouter')}).`,
 `Cliquez sur ${b('Créer le bon')}.`)}
${fig('besoins', 'La fenêtre Nouveau bon d’expression de besoins.')}
<p>Les onglets suivent le circuit : ${b('Mes demandes')}, ${b('Arbitrage & validation DAF')}, ${b('Besoins validés — achats & logistique')}, ${b('Tous les bons')}. La DAF fixe la ${b('Qté accordée')}.</p>

<h2>Passer une commande</h2>
${etapes(`Ouvrez ${chemin('Logistique', 'Achats & Fournisseurs', 'Bons de commande')}.`,
 `Cliquez sur ${b('Nouvelle commande')}.`,
 `Renseignez ${b('Date de la commande')}, ${b('Fournisseur')} et ${b('Statut')}.`,
 `Ajoutez les articles (${b('Article')}, ${b('Quantité')}, ${b('Prix unitaire')}, puis ${b('Ajouter')}).`,
 `Cliquez sur ${b('Créer la commande')}.`)}
${fig('commande', 'Les bons de commande : la colonne Validée par (RG-04) dit qui a validé.')}
${att('<b>Une commande de stock gros doit être validée par la Directrice Administrative avant d’être transmise au fournisseur</b> (RG-04). La colonne <b>Validée par (RG-04)</b> le montre. Ne transmettez jamais une commande non validée.')}
${qui(['m7-commandes'])}

<h2>Réceptionner une livraison</h2>
${etapes(`Ouvrez ${chemin('Logistique', 'Achats & Fournisseurs', 'Réceptions & contrôles')}.`,
 `Dans la ligne de la commande, cliquez sur ${b('Réceptionner')}.`,
 `Renseignez le ${b('N° bordereau de livraison')}, la ${b('Date de réception')} et les contrôleurs (${b('Contrôleur 1')}, ${b('Contrôleur 2')}, ${b('Contrôleur 3 (facultatif)')}).`,
 `Cliquez sur ${b('Valider la réception')}. Le stock est crédité.`)}
${fig('reception-commande', 'La réception d’une commande, contrôlée par plusieurs personnes.')}
<p>Un écart entre commande et livraison se suit dans ${b('Écarts de livraison')} ; les procès-verbaux se dressent dans ${b('PV de réception — consommables')} et ${b('PV de réception — réactifs')}. Les factures du fournisseur se saisissent dans ${b('Factures fournisseurs')}.</p>
`},
{
  titre: 'Facturation et caisse',
  chapeau: 'Facturer, encaisser, rendre la monnaie juste, arrêter la caisse chaque jour.',
  html: `
<h2>Établir une facture</h2>
${etapes(`Ouvrez ${chemin('Financier', 'Facturation & Caisse', 'Nouvelle facture')}, ou ${chemin('Actions', 'Nouvelle facture')}.`,
 `Choisissez le patient et la nature de la facture (par exemple ${b('Consultation généraliste')}).`,
 `Ajoutez les prestations avec ${b('Ajouter')}. Les prix viennent du référentiel des tarifs : vous ne les saisissez pas.`,
 `Cliquez sur ${b('Enregistrer et encaisser')} pour encaisser tout de suite, ou sur ${b('Facture pro-forma')} pour un devis.`,
 `Imprimez le ${b('Ticket de caisse')} sur l’imprimante 80 mm.`)}
${fig('facturation', 'La nouvelle facture : 1 Ajouter, 2 Enregistrer et encaisser.')}
${info('La grille de prix porte deux prix : non assuré et assuré. SIGH-CNT applique le prix assuré et la part de l’assurance seulement si la carte est valide à la date de la facture (RG-09).')}
${qui(['m8-facturation', 'm8-paiements'])}

<h2>Encaisser un paiement</h2>
${etapes(`Ouvrez ${chemin('Financier', 'Facturation & Caisse', 'Paiements')}. L’onglet ${b('À encaisser')} liste les factures dues.`,
 `Cliquez sur ${b('Encaisser')} dans la ligne de la facture.`,
 `Saisissez le ${b('Montant encaissé (FCFA)')} et le ${b('Mode de règlement')} ; ajoutez la ${b('Référence de la transaction')} pour un paiement mobile ou bancaire.`,
 `Cliquez sur ${b('Valider l’encaissement')}. La pièce de caisse est émise et le reçu s’imprime.`)}
${fig('encaisser', 'La fenêtre Encaissement.')}
${info('Un paiement partiel laisse un reste dû : il se suit dans <b>Reliquats</b> et se solde par <b>Régler l’encaissement partiel</b>. L’onglet <b>Historique des règlements</b> garde tous les reçus.')}
${att('Le MECeF est le boîtier fiscal physique branché à la caisse. La facture normalisée y est certifiée localement. Le branchement du boîtier réel attend les réponses du fournisseur : voir le chapitre MECeF.')}

<h2>Arrêter la caisse du jour</h2>
${etapes(`Ouvrez ${chemin('Financier', 'Facturation & Caisse', 'État de caisse journalier')}.`, `Contrôlez les totaux par ${b('Mode de règlement')} avec l’argent et les reçus réels.`, `Cliquez sur ${b('Éditer l’arrêté de caisse')}, imprimez et signez.`)}
${fig('caisse', 'L’état de caisse journalier et son bouton Éditer l’arrêté de caisse.')}

<h2>Corriger une facture : l’avoir</h2>
<p>Une facture émise ne se modifie pas. Pour la corriger ou l’annuler, on émet une ${b('facture d’avoir')}.</p>
${etapes(`Ouvrez ${chemin('Financier', 'Facturation & Caisse', 'Factures d’avoir')}.`,
 `Cliquez sur ${b('Émettre un avoir')}.`,
 `Cliquez sur ${b('Choisir la facture à rectifier')}, puis renseignez le ${b('Motif de l’avoir')} et la ${b('Suite donnée')}.`,
 `Cliquez sur ${b('Émettre l’avoir')}.`)}
${fig('avoir', 'La fenêtre Émettre une facture d’avoir (vue par le Comptable).')}
${att('Le Caissier consulte les avoirs mais ne les émet pas : le bouton <b>Émettre un avoir</b> est absent de son écran. Adressez-vous au Comptable ou à la DAF.')}
<p>Les remboursements et annulations se saisissent dans ${b('Remboursements & annulations')} (bouton ${b('Nouvelle opération')}). Les autres écrans : ${b('Tableau de bord facturation')}, ${b('Factures')}, ${b('Factures pro-forma')}, ${b('Opérations de caisse')}, ${b('Recettes par période')}.</p>
`},
{
  titre: 'Assurances et créances',
  chapeau: 'Vérifier la carte, appliquer la prise en charge, facturer l’assureur chaque mois.',
  html: `
<h2>Vérifier la carte d’un assuré</h2>
${etapes(`Ouvrez ${chemin('Financier', 'Assurances & Créances', 'Assurés & cartes')}.`,
 `Cherchez le bénéficiaire. La colonne ${b('Validité (RG-09)')} dit si la carte est valide aujourd’hui.`,
 `Cliquez sur ${b('Vérifier la carte')} pour voir l’${b('Historique des couvertures')} et les ${b('Prises en charge accordées')}.`,
 `Si la couverture a changé, cliquez sur ${b('Mettre à jour la couverture')}.`)}
${fig('assures', 'Assurés & cartes : 1 colonne Validité (RG-09), 2 Vérifier la carte.')}
${att('Une carte expirée à la date de facturation entraîne la facturation intégrale au patient (RG-09). Vérifiez la carte à l’enregistrement, pas à la sortie.')}
${qui(['m9-assures'])}

<h2>Suivre les prises en charge et facturer l’assureur</h2>
${etapes(`L’écran ${b('Prises en charge')} détaille, par facture, la ${b('Part assureur')} et la ${b('Part patient')}.`,
 `En fin de mois, ouvrez ${b('Factures mensuelles assureur')} et choisissez la compagnie.`,
 `Contrôlez l’onglet ${b('Relevé des prestations')}, puis cliquez sur ${b('Éditer le relevé')} et ${b('Éditer la facture mensuelle')}.`,
 `Suivez le paiement dans ${b('Créances')} et ${b('Relances')}.`)}
${info('Une garantie et une couverture sont des versions datées : SIGH-CNT lit celle qui était en vigueur à la date de la pièce.')}
`},
{
  titre: 'MECeF : facture normalisée',
  chapeau: 'Le suivi fiscal des factures certifiées par le boîtier MECeF de la caisse.',
  html: `
<h2>Suivre les factures normalisées</h2>
<p>La rangée ${chemin('Financier', 'MECeF — Facture normalisée')} comprend : ${b('Tableau de bord fiscal')}, ${b('Factures normalisées')}, ${b('Transmission & réponses')}, ${b('Avoirs & annulations')}, ${b('Journal des transactions')} et ${b('Configuration fiscale')}.</p>
${etapes(`Ouvrez ${b('Factures normalisées')}.`, `Lisez la colonne ${b('Statut fiscal')} de chaque facture.`, `Ouvrez ${b('Transmission & réponses')} pour traiter les transmissions en attente et les rejets.`)}
${fig('mecef', 'Les factures normalisées et leur statut fiscal.')}
${qui(['mecef-factures'])}
${att('Le MECeF est un boîtier physique branché à la caisse, avec certification locale. Le pilotage du boîtier réel n’est pas encore éprouvé : il attend les réponses du fournisseur. Les écrans existent ; la certification réelle reste à vérifier sur site.')}
`},
{
  titre: 'Comptabilité SYSCOHADA',
  chapeau: 'Écritures, dépenses journalières, balance, états financiers et clôture de l’exercice.',
  html: `
<h2>Saisir une écriture comptable</h2>
${etapes(`Ouvrez ${chemin('Financier', 'Comptabilité SYSCOHADA', 'Écritures comptables')}.`,
 `Cliquez sur ${b('Nouvelle écriture')}.`,
 `Renseignez ${b('Date de l’opération')}, ${b('Journal')}, ${b('Libellé de l’opération')}, ${b('Centre de coûts')} et ${b('Référence de la pièce justificative')}.`,
 `Pour chaque ligne, choisissez le ${b('Compte')} et saisissez le ${b('Débit')} ou le ${b('Crédit')} ; cliquez sur ${b('Ajouter la ligne')}.`,
 `Cliquez sur ${b('Enregistrer en brouillon')} pour finir plus tard, ou sur ${b('Valider l’écriture')}.`)}
${fig('ecriture', 'La fenêtre Nouvelle écriture comptable : 1 Enregistrer en brouillon, 2 Valider l’écriture.')}
${att('Une écriture ne se valide que si elle est <b>équilibrée : total débit = total crédit</b> (RG-10). Une écriture validée ne se réécrit plus : une erreur se corrige par une écriture de contrepassation.')}
${info('La plupart des écritures (ventes, encaissements, achats, paie) sont produites automatiquement par les autres modules ; la colonne <b>Origine</b> le dit.')}
${qui(['m12-ecritures'])}

<h2>Enregistrer une dépense journalière</h2>
${etapes(`Ouvrez ${chemin('Financier', 'Comptabilité SYSCOHADA', 'Dépenses journalières')}.`,
 `Cliquez sur ${b('Nouvelle dépense')}.`,
 `Renseignez ${b('Date de la transaction')}, ${b('Compte de trésorerie')} et ${b('Catégorie de dépenses')} ; joignez la photo du ${b('Reçu / facture (photo)')}.`,
 `Ajoutez les lignes (${b('Ajouter une ligne')}) puis cliquez sur ${b('Enregistrer')}.`,
 `Imprimez la pièce avec l’icône ${b('Imprimer la pièce')} ; ${b('État des dépenses')} imprime le récapitulatif.`)}
${fig('depense', 'La fenêtre Nouvelle dépense.')}
${qui(['m12-depenses'])}

<h2>Consulter la balance et les états</h2>
<p>L’écran ${b('Balance générale & âgée')} a deux onglets : ${b('Balance générale')} et ${b('Balance âgée (tiers)')}. Le bouton ${b('Imprimer la balance')} l’imprime.</p>
${fig('balance', 'La balance générale.')}
<p>Les autres états : ${b('Grand livre')}, ${b('Compte de résultat')}, ${b('Tableau des flux de trésorerie')}, ${b('États financiers')}, ${b('Seuil de rentabilité')}, ${b('Comptabilité analytique')}, ${b('Budgets')}, ${b('Immobilisations & amortissements')}, ${b('Banques & rapprochements')}, ${b('Échéances fiscales & paiements')}, ${b('Calendrier fiscal mensuel')}.</p>
${info('Le sélecteur d’exercice de la barre supérieure n’apparaît que sur les écrans qui suivent une année (comptabilité). Choisissez l’exercice avant de lire un état.')}

<h2>Clôturer un exercice</h2>
<p>L’écran ${b('Exercices & clôtures')} conduit la clôture annuelle. Ses onglets : ${b('Exercices')}, ${b('Périodes de l’exercice')}, ${b('Lettrage des tiers')}, ${b('Comptes de résultat')}, ${b('Circuit de clôture')}.</p>
${etapes(`Vérifiez dans ${b('Circuit de clôture')} qui démarre, qui passe l’inventaire, qui clôture et qui peut rouvrir.`, `Lancez la ${b('Pré-clôture')} et traitez les avertissements.`, `Faites clôturer par la personne désignée.`, `Ouvrez l’exercice suivant dans ${b('Bilan d’ouverture & à-nouveaux')}.`)}
${fig('cloture', 'Exercices & clôtures : l’onglet Circuit de clôture.')}
${alerte('Un exercice clos n’accepte plus aucune pièce : même une pièce saisie sur un autre poste et datée de cet exercice est refusée à la synchronisation. Avant de clôturer, assurez-vous que tous les postes sont synchronisés (pastille « Synchronisé »).')}
${info('Les soldes d’ouverture inconnus sont affichés « inconnus », jamais zéro. Le circuit de clôture est un réglage daté, réservé au geste « Régler le circuit de la clôture annuelle ».')}
`},
{
  titre: 'Ressources humaines et paie',
  chapeau: 'Planning et gardes, congés, badges, paie et primes.',
  html: `
<h2>Établir le planning et les gardes</h2>
${etapes(`Ouvrez ${chemin('RH', 'Ressources humaines', 'Planning & gardes')}.`,
 `Choisissez la semaine et le service ; le tableau montre chaque agent et ses vacations (${b('Garde 24h')}, ${b('Repos 24h')}, ${b('Repos 48h')}, ${b('Garde soins')}, ${b('Garde hospitalisation')}, ${b('Perm.')}, ${b('Soirée')}…).`,
 `Posez ou changez une vacation dans la case de l’agent et du jour.`,
 `Pour une exception, utilisez ${b('Déroger pour un agent')} ; pour un nouveau cycle, ${b('Nouveau régime')}.`,
 `Imprimez avec ${b('Imprimer le planning')}.`)}
${fig('planning', 'Le planning des gardes (noms du personnel masqués).')}
${info('Les primes de garde et de permanence sont calculées depuis le <b>planning validé</b> et la grille en vigueur (RG-11). Un planning non validé ne produit pas de prime.')}
${qui(['m10-planning'])}

<h2>Enregistrer un congé</h2>
${etapes(`Ouvrez ${chemin('RH', 'Ressources humaines', 'Congés')}.`, `Cliquez sur ${b('Nouveau')}.`, `Renseignez ${b('Agent')}, ${b('Nature du congé')}, ${b('Date de début')}, ${b('Date de fin')}, ${b('Remplaçant désigné')} et ${b('Motif')}.`, `Cliquez sur ${b('Créer')}. La décision s’inscrit dans la colonne ${b('Décision')}.`)}
${fig('conges', 'La fenêtre Nouveau congé.')}

<h2>Émettre un badge</h2>
<p>L’écran ${b('Badges du personnel')} a les onglets ${b('Badges en cours')}, ${b('Retirés')}, ${b('Agents sans badge')} et ${b('À décider par la Direction')}. Le bouton ${b('Émettre un badge')} crée le badge, imprimé au format carte CR80 (sans IFU ni RCCM). L’écran ${b('Vérifier un badge')} contrôle un badge présenté.</p>

<h2>Calculer la paie</h2>
${etapes(`Ouvrez ${chemin('RH', 'Paie & Primes', 'Calcul de la paie')}.`,
 `Cliquez sur ${b('Lancer le calcul')}. Le tableau montre, par agent, la base, les primes, le brut, les retenues (${b('CNSS')}, ${b('ITS')}, avances) et le ${b('Net à payer')}.`,
 `Contrôlez, puis cliquez sur ${b('Générer les bulletins')}.`,
 `Faites valider par la Direction (${b('Validation Direction')}) et imprimez ${b('Éditer le journal de paie')}.`)}
${fig('paie', 'Le calcul de la paie : 1 Lancer le calcul, 2 Générer les bulletins.')}
${info('Les cotisations sociales sont calculées automatiquement : part patronale 16,4 %, part ouvrière 3,6 %.')}
${att('Les écrans RH et paie sont réservés aux profils RH et comptables (RG-13). Le rôle « Responsable RH » est archivé dans la configuration actuelle : ces écrans sont tenus par la DAF, la Direction et l’administrateur.')}
`},
{
  titre: 'Administration, documents et états',
  chapeau: 'Courrier, réunions, validations en attente, enquêtes, gestion documentaire et bibliothèque des états.',
  html: `
<h2>Enregistrer un courrier</h2>
${etapes(`Ouvrez ${chemin('Administration', 'Administration & Ambulance', 'Courriers (départ / arrivée)')}.`,
 `Cliquez sur ${b('Nouveau')}.`,
 `Renseignez le sens (départ ou arrivée), la date, le correspondant, l’objet, la nature et la personne à qui il est affecté.`,
 `Enregistrez ; joignez le scan du courrier.`)}
${fig('courriers', 'Le registre des courriers.')}
${qui(['m13-courriers'])}

<h2>Traiter les validations en attente</h2>
<p>L’écran ${b('Validations en attente')} réunit tout ce qui attend une décision : changements de prix, bons de besoins, référentiels. Chaque carte porte un bouton ${b('Ouvrir')} ou ${b('Y aller')} vers l’écran où se prend la décision.</p>
${fig('validations', 'Le centre des validations en attente, vu par la DAF.')}
${info('Une décision peut se prendre sur n’importe quel poste. Prise sur un poste autre que la mère, elle est signée, déposée, puis appliquée par la mère : une pastille « N décisions en attente de la mère » le rappelle. Ce n’est jamais un blocage.')}

<h2>Éditer un état</h2>
${etapes(`Ouvrez ${chemin('Administration', 'Rapports & Impression', 'Bibliothèque des états')}, ou ${chemin('Actions', 'Éditer un état')}.`, `Choisissez l’état et cliquez sur ${b('Éditer')}.`, `Réglez la période et les filtres, puis imprimez ou exportez.`)}
${fig('etats', 'La bibliothèque des états, vue par la Direction.')}
<p>Les autres écrans : ${b('Réunions')}, ${b('Notes de service')}, ${b('Plan annuel de travail')}, ${b('Interventions ambulance')}, ${b('Répertoire des ambulances')}, ${b('Parc technique & maintenance')}, ${b('Enquêtes & questionnaires')}, ${b('Satisfaction des patients')}, ${b('Bibliothèque documentaire')}, ${b('Workflow de validation')}, ${b('Archivage & conservation')}, ${b('Générateur de rapports')}, ${b('Historique des éditions')}.</p>
`},
{
  titre: 'Système et pilotage',
  chapeau: 'Ce que les utilisateurs voient du domaine Système, et les tableaux de bord du Pilotage.',
  html: `
<h2>Le domaine Système</h2>
<p>Le domaine ${b('Système')} (utilisateurs, rôles, sauvegardes, configuration de la clinique, poste mère) est réservé à l’Administrateur système et à la DAF. Il est décrit dans le ${b('Manuel administrateur')}.</p>
<p>Les autres rôles n’y voient que la rangée ${b('Importation de données')}, limitée aux jeux sur lesquels ils ont un droit (chapitre « Les gestes communs »).</p>
${info('Chaque agent peut demander à l’administrateur la réinitialisation de son mot de passe (lien <b>Mot de passe oublié ?</b>). Pour changer de rôle, de secteur ou obtenir un droit, adressez-vous à l’administrateur : un agent ne modifie jamais ses propres droits.')}

<h2>Les tableaux de bord du pilotage</h2>
<p>Le domaine ${b('Pilotage')} réunit les tableaux de bord de la Direction (${b('Direction')}, ${b('Statistiques de la Direction')}, ${b('Tableau de bord dynamique croisé')}, ${b('Tableau de bord décisionnel')}), les statistiques par activité et les tableaux de bord de chaque poste.</p>
${fig('tableau-direction', 'Le tableau de bord de la Direction.')}
${info('Chaque indicateur est calculé à partir des données saisies. Un indicateur qui ne peut pas être calculé (donnée manquante) est affiché « non calculable », jamais zéro.')}
${qui(['dash-direction', 'dash-da', 'dash-croise'])}
`},
{
  titre: 'L’application mobile',
  chapeau: 'Le téléphone du soignant en tournée, du médecin et de la sage-femme à domicile, et la réception de secours.',
  html: `
<h2>Les profils du téléphone</h2>
<p>Le téléphone est attribué à un agent. Son accueil dépend de son profil, et chaque profil ne voit que ses écrans :</p>
<table><tr><th>Profil</th><th>Accueil</th><th>Ce qu’il fait</th></tr>
<tr><td>Soignant (infirmier)</td><td>${b('Ma tournée')}</td><td>Agenda du jour, dossiers du lot, constantes, notes de soins.</td></tr>
<tr><td>Médecin</td><td>${b('Mes visites')}</td><td>${b('Consultation à domicile')}, ${b('Prescription')}, ${b('Demande d’analyses')}.</td></tr>
<tr><td>Sage-femme</td><td>${b('Mes suivis')}</td><td>${b('Visite prénatale (CPN)')}, ${b('Visite post-natale (CPoN)')}, ${b('Surveillance mère-bébé')}.</td></tr>
<tr><td>Réception de secours</td><td>${b('Accueil de secours')}</td><td>Ouvrir un dossier, ${b('Orienter un patient')}, quand le poste de l’accueil est indisponible.</td></tr></table>
${att('Les captures de ce chapitre viennent du simulateur mobile de la maquette. L’application Flutter (dossier apps/mobile) reprend ces écrans ; son accueil soignant s’intitule <b>Ma tournée</b> avec les onglets <b>Agenda du jour</b> et <b>Dossiers du lot</b>, et la réception s’intitule <b>Réception de secours</b>. Elle n’a pas été éprouvée sur un téléphone réel.')}
${info('Le téléphone ne parle jamais directement au poste mère : il passe par le relais web, et tout ce qu’il envoie est chiffré. Il ne travaille que sur le <b>lot de tournée</b> que la mère lui a préparé.')}

<h2>Appairer le téléphone</h2>
<p>L’appairage relie le téléphone à la clinique. Il se fait une seule fois, avec l’administrateur.</p>
${etapes(`Ouvrez l’application. L’écran ${b('Appairer ce téléphone')} s’affiche.`,
 `Saisissez le ${b('Code d’appairage')} remis par l’administrateur (il le crée sur le poste mère, écran ${b('Appareils et appairage')}).`,
 `Touchez ${b('Scanner le QR')} et visez la ${b('Clé de clinique')} affichée sur le poste mère.`,
 `Vérifiez le ${b('Profil de ce téléphone')} (Soignant, Médecin, Sage-femme ou Réception) et, dans l’application de production, le ${b('Nom de l’agent')}.`,
 `Touchez ${b('Appairer')}.`,
 `Choisissez votre ${b('Code PIN')} : il protège l’application à chaque ouverture.`)}
${duo('mob-appairage', 'L’écran Appairage.', 'mob-verrou', 'Le code PIN protège l’application.')}
${alerte('Un téléphone perdu doit être signalé tout de suite à l’administrateur : il le suspend depuis le poste mère. Le bandeau du téléphone affiche alors « Téléphone suspendu, contactez la clinique ».')}

<h2>Le bandeau d’état</h2>
<p>En haut de chaque écran, un bandeau dit toujours l’état du téléphone : ${b('Connecté')} ou ${b('Hors ligne')}, suivi s’il y a lieu de « N en attente d’envoi », « N à traiter » ou « lot de tournée expiré ». Touchez le bandeau quand il annonce des refus : l’écran ${b('À traiter')} s’ouvre.</p>

<h2>Faire sa tournée (soignant)</h2>
${etapes(`Ouvrez l’accueil ${b('Ma tournée')}. L’agenda du jour s’affiche en premier.`,
 `Touchez un patient pour ouvrir son ${b('Dossier du patient')}.`,
 `Touchez ${b('Saisir les constantes')} et renseignez les mesures, puis ${b('Enregistrer')}.`,
 `Les saisies partent à la prochaine connexion ; le bandeau compte celles « en attente d’envoi ».`)}
${duo('mob-tournee', 'L’accueil Ma tournée.', 'mob-dossier', 'Le dossier du patient.')}
${fig('mob-constantes', 'La saisie des constantes sur le téléphone.', 'mobile')}

<h2>Visites du médecin et suivis de la sage-femme</h2>
${etapes(`Le médecin ouvre ${b('Mes visites')}, choisit le patient, puis ${b('Consultation à domicile')}.`,
 `Pour prescrire, il ouvre ${b('Prescription')}, choisit le ${b('Médicament du catalogue')} ou les ${b('Examens demandés')}, coche ${b('Urgence')} si besoin et enregistre.`,
 `La sage-femme ouvre ${b('Mes suivis')} et choisit la visite (CPN, CPoN, surveillance mère-bébé).`)}
${duo('mob-visites', 'L’accueil Mes visites (médecin).', 'mob-prescription', 'La prescription depuis le téléphone.')}

<h2>Réception de secours</h2>
<p>Quand le poste de l’accueil est indisponible, la réception de secours ouvre les dossiers sur le téléphone.</p>
${etapes(`Ouvrez ${b('Accueil de secours')}. L’écran montre les ${b('Numéros réservés restants')} et le ${b('Numéro suivant')}.`, `Touchez ${b('Nouveau dossier')} et renseignez ${b('Nom')}, ${b('Prénom')}, ${b('Âge déclaré')}, ${b('Téléphone')}, ${b('Quartier')}.`, `Touchez ${b('Ouvrir le dossier')}. Le dossier rejoint le répertoire de la clinique par le relais.`, `Retrouvez vos dossiers dans ${b('Dossiers ouverts')} ; si besoin, touchez ${b('Orienter un patient')}.`)}
${info('Le téléphone de secours numérote dans une plage de numéros réservée à l’avance. Si la plage est épuisée, le dossier reçoit un code provisoire (badge « PROV »). Un dossier qui ressemble à un dossier existant est marqué « Doublon ? » et attend l’arbitrage de la clinique : il n’est jamais fusionné en silence. La caisse et le dossier médical complet ne sont pas couverts par ce profil.')}
${duo('mob-reception', 'L’accueil de secours.', 'mob-nouveau-dossier', 'L’ouverture d’un dossier.')}
${info('La réception de secours ne voit pas le lot de tournée ni les écrans de soins : ce que son profil ne couvre pas n’est pas proposé, et le serveur le refuserait de toute façon.')}

<h2>Synchronisation, refus et réglages</h2>
${puces(`${b('Synchronisation')} : ce qui est parti, ce qui attend, et le bouton ${b('Synchroniser maintenant')}.`, `${b('À traiter')} : les refus de la clinique, chacun avec « À faire : » et le geste qui corrige.`, `${b('Lot de tournée')} : les dossiers confiés à ce téléphone et leur date d’expiration (bouton ${b('Rafraîchir')}).`, `${b('Réglages')} : l’agent, le profil, le code PIN et ${b('Réinitialiser l’appairage')} (à ne faire qu’avec l’administrateur).`)}
${duo('mob-sync', 'L’écran Synchronisation.', 'mob-a-traiter', 'L’écran À traiter.')}
${duo('mob-lot', 'Le lot de tournée.', 'mob-reglages', 'Les réglages du téléphone.')}
`},
{
  titre: 'Le relais web',
  chapeau: 'Ce que l’agent voit, et ne voit pas, du relais en ligne de la clinique.',
  html: `
<h2>À quoi sert le relais</h2>
<p>Le relais web est un service hébergé en ligne (adresse de la clinique : <span class="cle">sighcnt.nassieratoo.com</span>). Il transporte des paquets ${b('chiffrés')} entre le poste mère, les postes de la clinique et les téléphones. Il ne sait pas les lire : la clé reste à la clinique.</p>
${puces(`Vous ne vous connectez jamais au relais pour travailler : le travail se fait sur le poste ou sur le téléphone.`,
 `Vous voyez le relais seulement à travers la ${b('pastille de synchronisation')} du poste et le ${b('bandeau')} du téléphone.`,
 `Les SMS de la clinique (rappels de rendez-vous, vœux d’anniversaire, si la personne l’a accepté) partent par le relais.`,
 `Un lien de partage ou un code QR d’une ${b('enquête de satisfaction')} peut être remis à un patient ; il ouvre un questionnaire sans aucun accès au dossier, et la réponse est chiffrée dans son navigateur.`)}
${info('Le panneau du relais (adresse /panneau) est réservé au superadministrateur. Un agent n’y a pas de compte. Il est décrit dans le Manuel administrateur.')}
${att('Le relais réel sur l’hébergement de la clinique n’a pas été éprouvé en conditions de production au moment de cette édition. Aucune donnée de santé ne transite en clair : si le relais est indisponible, les postes continuent de travailler entre eux et les téléphones gardent leurs saisies jusqu’au retour du service.')}
`},
{
  titre: 'Limites connues et points non vérifiés',
  annexe: 'A',
  html: `
<p>Cette annexe récapitule ce que le manuel ne garantit pas encore, au 17 novembre 2026. Elle est écrite pour que chaque agent sache ce qui est éprouvé et ce qui ne l’est pas.</p>
${puces(`${b('Poste Windows')} : le poste de bureau n’a pas été compilé ni éprouvé sous Windows pour cette édition. Les captures sont celles de la maquette de référence, pas du poste compilé.`,
 `${b('Captures du poste de bureau')} : onze écrans des derniers lots sont aussi montrés tels que le poste Flutter les dessine, mais dans un banc de test sous Linux, avec le jeu sobre du poste (listes vides, pastille « Hors ligne »). Le rendu natif sous Windows n’a pas été vu.`,
 `${b('Application mobile')} : captures du simulateur de la maquette ; l’application Flutter n’a pas été éprouvée sur un téléphone réel.`,
 `${b('SMS réels')} : aucun SMS réel n’a été envoyé à un vrai numéro avec un vrai compte de fournisseur. La couverture du Bénin, l’expéditeur alphanumérique, le coût d’un message et les codes d’erreur des deux fournisseurs restent à vérifier sur site, la première semaine, avec un plafond bas. Les envois automatiques sont désactivés au départ.`,
 `${b('Satisfaction en ligne')} : la page publique et le chiffrement des réponses dans le navigateur n’ont pas été éprouvés sur les téléphones du terrain ; un navigateur ancien (avant Chrome 133, Firefox 130, Safari 17) ne peut pas répondre. La collecte est désactivée au départ.`,
 `${b('Relais web')} : non éprouvé sur l’hébergement réel de la clinique, ni avec deux machines et une vraie charge.`,
 `${b('MECeF')} : le boîtier physique n’est pas encore piloté et le dossier d’interface e-MECeF de la DGI manque : aucun numéro fiscal n’est produit, une vente reste en attente de certification. Le modèle, l’interface et le protocole du boîtier restent à obtenir du fournisseur.`,
 `${b('Imprimante de caisse')} : le modèle Xprinter XP-Q800 est semé ; sa liaison (USB ou Ethernet) est à constater sur l’appareil, l’impression en pixels n’est pas vérifiée.`,
 `${b('Chiffrement de la base locale')} (SQLCipher) : non branché à la date de cette édition.`,
 `${b('Taux de l’AIB')} : les taux de retenue sur la facture d’un tiers (3 % pour une personne physique, 5 % pour une personne morale) sont des hypothèses à confirmer ; les textes officiels n’ont pas été relus. L’imputation n’écrit aucune écriture comptable pour l’instant.`,
 `${b('Factures aux tiers payeurs')} : le montant dû est la base plus l’AIB décidé ; la caisse du patient n’est pas encore ajustée à la part restante ; l’avoir est total seulement, sans certification MECeF ; aucune écriture comptable n’est produite.`,
 `${b('Dates et valeurs à confirmer')} : la date d’effet du RCCM (16 novembre 2026), les heures des SMS (rappel de la veille à 18 h, du matin à 7 h, vœux à 9 h), les valeurs d’attente de la fiche du personnel (salaire, catégorie, date d’embauche, CNSS), le délai d’alerte d’une décision qui attend la mère (4 heures).`,
 `${b('Plusieurs postes')} : deux postes coupés de la mère peuvent attribuer le même numéro à deux factures aux tiers ou à deux actions du plan annuel ; la commande de stock gros, elle, porte une référence provisoire par poste. Les régimes individuels ne voyagent pas encore d’un poste à l’autre.`,
 `${b('Seuils du laboratoire')} : la validation d’un seuil de variation et son délai entre deux mesures existent sur la maquette ; le poste de bureau ne les porte pas encore.`,
 `${b('Libellés')} : extraits de la maquette ; quelques titres de fenêtre gardent une tournure brute qui sera corrigée à l’écran.`,
 `${b('Droits')} : les tableaux « Qui voit quoi » et le répertoire montrent les droits d’origine ; votre clinique a pu les ajuster. Les noms des signataires de plusieurs états imprimés sont encore écrits dans le logiciel et seront lus de l’organigramme.`,
 `${b('Données de démonstration')} : toutes les captures montrent des données de démonstration, les noms du personnel sont masqués ; le répertoire patients de démonstration porte des noms fictifs.`,
 `${b('Répertoire des écrans')} : l’annexe C décrit chaque écran en une ligne, extraite de l’écran réel ; les écrans principaux sont détaillés en fiches pas à pas dans les chapitres. Les écrans de statistiques, de la gestion documentaire et des registres annexes ne sont décrits que par cette ligne.`)}
`},
{
  titre: 'Glossaire',
  annexe: 'B',
  html: `
<table><tr><th>Terme</th><th>Définition</th></tr>
<tr><td>Archiver</td><td>Retirer une fiche de la liste courante sans la détruire (RG-14). L’archivage s’annule.</td></tr>
<tr><td>Avoir</td><td>Facture qui corrige ou annule une facture émise, qui elle ne se modifie jamais.</td></tr>
<tr><td>Code patient</td><td>Identifiant unique <span class="cle">CNT/[n°]/[année]</span>, attribué automatiquement (RG-01).</td></tr>
<tr><td>CUMP</td><td>Coût unitaire moyen pondéré d’un article, calculé automatiquement.</td></tr>
<tr><td>FEFO</td><td>« Premier périmé, premier sorti » : ordre de sortie des lots (RG-05).</td></tr>
<tr><td>Fileul</td><td>Poste de la clinique rattaché au poste mère.</td></tr>
<tr><td>Lot de tournée</td><td>Ensemble des dossiers confiés à un téléphone pour une durée limitée.</td></tr>
<tr><td>MECeF</td><td>Boîtier fiscal de la caisse qui certifie la facture normalisée.</td></tr>
<tr><td>Poste mère</td><td>Poste central de la clinique : il consolide les données de tous les postes et téléphones.</td></tr>
<tr><td>Relais web</td><td>Service en ligne qui transporte les données chiffrées entre la mère, les fileuls et les téléphones.</td></tr>
<tr><td>Geste réservé</td><td>Action sensible permise seulement aux rôles qui la détiennent ; sans elle, la commande est absente.</td></tr>
<tr><td>RG-xx</td><td>Règle de gestion de la clinique, appliquée par le logiciel (par exemple RG-03 : le stock ne devient jamais négatif).</td></tr>
<tr><td>SYSCOHADA</td><td>Référentiel comptable de l’espace OHADA, suivi par la comptabilité de la clinique.</td></tr>
</table>
`},
];

/* ---- Édition du 17/11/2026 : ajouts par chapitre, répertoire des écrans (annexe C) ---- */
const NOUV = require('./contenu-nouveau.js')({ b, chemin, info, att, alerte, astuce, fig, duo, etapes, puces, qui, lib, N, RBAC, ROLES, LIB });
const REP = require('./repertoire.js');
CHAPITRES.forEach((c) => { if (NOUV.ajouts[c.titre]) c.html += NOUV.ajouts[c.titre]; });
Object.keys(NOUV.ajouts).forEach((t) => { if (!CHAPITRES.some((c) => c.titre === t)) throw new Error('chapitre inconnu : ' + t); });
const glossaire = CHAPITRES.pop();
CHAPITRES.push(glossaire);
CHAPITRES.push({ titre: 'Répertoire de tous les écrans', annexe: 'C', html: REP({ RBAC, ROLES }) + REP.partiesPropres() });
module.exports = CHAPITRES;
