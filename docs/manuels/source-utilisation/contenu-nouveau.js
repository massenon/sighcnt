/* Ajouts de l'édition du 17/11/2026 au manuel d'utilisation : lots SMS-R, SAT, MECEF-M, IDENT, PLAN-INDIV, PTA, FISC-2, VAL, CLO-3, CMD,
   SURV, TIERS, CONT, TARIF-FIX-2, INVENT-NC, PARAM-CLINIQUE. Chaque entrée de `ajouts` est ajoutée à la fin du chapitre du même titre.
   Les libellés d'écran sont ceux récoltés sur la maquette (recolte-ecrans.json) et lus dans le code des écrans ; les droits par défaut
   sont lus de packages/rbac/data/rbac.json (clé gestes), jamais recopiés à la main. */
'use strict';
const path = require('path');
const fs = require('fs');
const MAN = require(path.resolve(__dirname, '../../../packages/referentiels/data/manifeste.json'));
const REC = JSON.parse(fs.readFileSync(path.join(__dirname, 'recolte-ecrans.json'), 'utf8'));
const ECR = require('./ecrans.js');

module.exports = function (H) {
  const { b, chemin, info, att, alerte, astuce, fig, etapes, puces, qui, RBAC, ROLES, LIB } = H;
  const ecran = (id) => MAN.ecrans.find((e) => e.id === id) || { label: id, domaine: '', moduleLabel: '' };
  const ch = (id) => { const e = ecran(id); return chemin(e.domaine, e.moduleLabel, e.label); };
  /** Rôles qui détiennent d'origine un geste réservé (libellés), lus de la fiche RBAC. */
  const detenteurs = (id) => { const g = RBAC.gestes.jeux.find((x) => x.id === id); return g ? g.rolesDefaut.filter((r) => ROLES.some((x) => x.id === r)).map((r) => LIB[r]).join(', ') : 'à lire dans la fiche des droits'; };
  const geste = (id) => { const g = RBAC.gestes.jeux.find((x) => x.id === id); return g ? '« ' + g.libelle.replace(/ \(.*$/, '') + ' »' : id; };
  const droit = (id) => `<p class="droit">Geste réservé ${geste(id)} : détenu d’origine par ${detenteurs(id)}. Sans ce geste, la commande est absente de l’écran et le moteur refuse aussi.</p>`;

  const ajouts = {};

  /* ---------------------------------------------------------------- À propos */
  ajouts['À propos de ce manuel'] = `
<h2>Ce qui est nouveau dans l’édition du 17 novembre 2026</h2>
<p>Cette édition ajoute les écrans et les gestes des lots livrés les 16 et 17 novembre 2026. Le tableau dit où les trouver.</p>
<table><tr><th>Nouveauté</th><th>Où la lire</th></tr>
<tr><td>Messages SMS automatiques (rappel de rendez-vous, vœux), passerelle SMS, journal des envois, consentement</td><td>Chapitre « Système et pilotage » et chapitre « Le relais web »</td></tr>
<tr><td>Satisfaction en ligne : lien public, code QR, affiche A4, analyse</td><td>Chapitre « Administration, documents et états »</td></tr>
<tr><td>Mode de certification MECeF, état de la caisse, imprimante de caisse</td><td>Chapitre « MECeF : facture normalisée »</td></tr>
<tr><td>Identité de la clinique datée (RCCM NAT/2021/M02-020) propagée à tous les postes</td><td>Chapitre « Système et pilotage »</td></tr>
<tr><td>Régime individuel (déroge ou remplace), planning personnalisé, valeurs d’attente, fiche de mon équipe</td><td>Chapitre « Ressources humaines et paie »</td></tr>
<tr><td>Plan annuel de travail par exercice</td><td>Chapitre « Administration, documents et états »</td></tr>
<tr><td>Confirmation du versement CNSS, AIB imputé par le comptable, facture de patient sans AIB</td><td>Chapitre « Comptabilité SYSCOHADA » et chapitre « Facturation et caisse »</td></tr>
<tr><td>Factures aux tiers payeurs</td><td>Chapitre « Facturation et caisse »</td></tr>
<tr><td>Commande de stock gros validée par la Directrice Administrative, commande qui voyage entre les postes</td><td>Chapitre « Achats et fournisseurs »</td></tr>
<tr><td>Décisions en attente de la mère</td><td>Chapitre « Prise en main du poste de travail »</td></tr>
<tr><td>Droits propres par réglage, pharmacie et caisse séparables</td><td>Chapitre « Les rôles et ce qu’ils voient »</td></tr>
<tr><td>Répertoire de tous les écrans (maquette, poste, téléphone, relais)</td><td>Annexe C</td></tr></table>
`;

  /* ---------------------------------------------------------------- Rôles */
  ajouts['Les rôles et ce qu’ils voient'] = `
<h2>Les droits propres par réglage</h2>
<p>Quand un réglage est sensible, il a son propre droit dans la fiche du rôle, au lieu de dépendre d’un nom de rôle écrit dans le logiciel. Ce sont les gestes réservés du tableau ci-dessus : valider une commande de stock gros, régler le mode MECeF, régler l’imprimante de caisse, régler la passerelle SMS, adopter le plan annuel de travail, confirmer une obligation fiscale, imputer l’AIB, émettre ou corriger une facture à un tiers payeur, ouvrir la fiche de son équipe, etc.</p>
${puces(`Le droit est <b>posé à l’installation</b> comme il l’était avant : rien ne change pour vous tant que l’administrateur n’y touche pas.`,
 `L’administrateur ajoute ou retire un geste à un rôle dans ${ch('m14-roles')}, onglet des gestes. Un rôle créé en exploitation part de zéro : aucun geste réservé n’y est ouvert d’office.`,
 `Quand un refus tombe, le message cite le droit manquant. Demandez-le à l’administrateur ; ne cherchez pas un autre chemin.`,
 `L’agent enregistré comme validateur ou signataire est <b>toujours l’agent de la session</b> : personne ne valide au nom d’un autre.`)}
${att('Un droit de geste n’ouvre pas d’écran. Un rôle qui valide les commandes de stock gros doit aussi lire l’écran <b>Bons de commande</b> pour voir le bouton.')}

<h2>Pharmacie et caisse séparables</h2>
<p>La caisse et la pharmacie se tiennent par deux droits distincts de la fiche du rôle : ${b('Tenir le poste de la caisse')} (reçoit la tâche « Encaisser la prescription » et les notifications de la caisse) et ${b('Tenir le poste de la pharmacie')} (reçoit la tâche « Délivrer les médicaments » et les notifications de la pharmacie). D’origine, le Caissier tient la caisse ; la pharmacie n’a pas de poste propre et son travail de dispensation passe par les écrans du Caissier. Si la clinique rouvre un rôle pharmacien avec le seul droit de la pharmacie, il reçoit les tâches de dispensation et la caisse reste au Caissier.</p>
${info('La retransmission d’une vente refusée par le MECeF suit la même logique : le Caissier peut retransmettre <b>une seule fois</b> ; au-delà, il faut le droit « sans limite », détenu d’origine par la Directrice Administrative et l’administrateur.')}
`;

  /* ---------------------------------------------------------------- Prise en main */
  ajouts['Prise en main du poste de travail'] = `
<h2>Décisions en attente de la mère</h2>
<p>Une décision de validation (par exemple valider une commande de stock gros) se prend sur <b>n’importe quel poste</b>. Sur le poste mère, elle s’applique tout de suite. Sur un poste fileul, elle est <b>signée puis déposée</b> pour la mère, qui l’applique mécaniquement sous le rôle de son auteur dès qu’elle est joignable.</p>
${etapes(`Prenez la décision comme d’habitude sur l’écran concerné (par exemple ${ch('adm-validations')}).`,
 `Sur un fileul, une pastille indique <b>« N décisions en attente de la mère »</b> : la décision est enregistrée, elle n’est pas encore appliquée.`,
 `Dès que la mère est joignable, elle applique la décision et la pastille retombe. Rien ne se perd et rien ne se refait.`)}
${fig('validations-attente', 'Le centre « Validations en attente » (vue de la Directrice Administrative).')}
${info('Si une décision attend la mère plus de <b>4 heures</b> (délai réglable par la clinique), une alerte le dit. L’attente ne bloque jamais le travail : vous pouvez continuer à soigner, facturer et encaisser.')}
${att('La mère revérifie que le compte signataire existe avec le bon rôle. Si ce n’est pas le cas, la décision est refusée et le refus est nommé : la personne qui l’a prise la reprend sur un poste habilité.')}
`;

  /* ---------------------------------------------------------------- Consultations */
  ajouts['Consultations et prescriptions'] = `
<h2>Prescrire un acte ou un médicament dont le prix n’est pas fixé</h2>
<p>Le médecin prescrit <b>toujours</b>. Si un acte, une analyse ou un médicament n’a pas encore de prix dans le référentiel des tarifs, la ligne n’est pas bloquée et n’est jamais mise à zéro.</p>
${puces(`La ligne porte la mention ${b('prix à définir')} (ou ${b('prix à valoriser')} pour un médicament). Son prix et les totaux affichent ${b('Non calculable')}.`,
 `La pièce prend l’état « en attente de prix ».`,
 `Une alerte « prix manquant » part, une seule par code de prestation, vers les agents qui peuvent modifier l’écran des prix.`,
 `Dès que le prix est posé au référentiel, la ligne se valorise <b>à la date de la pièce</b>.`)}
${alerte('Seul l’<b>encaissement</b> est refusé : la caisse ne peut pas encaisser une pièce dont une ligne n’a pas de prix. La commande est absente, rien n’est envoyé au MECeF et le refus est nommé (ENCAISSEMENT_PRIX_MANQUANT). Par défaut, c’est la pièce entière qui attend ; la clinique peut régler d’encaisser la partie chiffrée seulement (réglage daté, « non » au départ).')}
${info('Un code de prestation ne se réutilise pas, même écrit autrement : un « Certificat d’aptitude » (5 000 FCFA) et un certificat d’aptitude à la conduite (7 000 FCFA) sont deux prestations distinctes.')}
`;

  /* ---------------------------------------------------------------- Pharmacie */
  ajouts['Pharmacie et stocks'] = `
<h2>Les articles non comptés d’un inventaire</h2>
<p>La feuille d’inventaire part <b>vide</b> : aucune quantité n’est préremplie. Vous comptez ce que vous avez réellement en main.</p>
${puces(`Un article que vous ne comptez pas est enregistré <b>« non compté »</b>. Ce n’est jamais « compté, écart zéro ».`,
 `Le stock d’un article non compté n’est <b>jamais régularisé</b> : il reste ce qu’il était (le stock ne peut pas devenir négatif, RG-03).`,
 `Vous pouvez quand même <b>valider</b> l’inventaire. Le registre et l’état imprimé disent combien d’articles ne sont pas comptés et lesquels.`)}
${astuce('Avant de valider, ouvrez la carte « Articles non comptés (stock inchangé) » : elle liste les articles à reprendre au prochain passage.')}

<h2>Les préavis de péremption : un paramètre de la clinique</h2>
<p>Le préavis avant péremption et les tranches de la balance âgée ne sont plus écrits dans le logiciel : ce sont des <b>paramètres de clinique</b> datés. Les alertes du stock (${b('Péremptions')}), les écrans et les tableaux de bord les lisent à la date du jour. Un changement s’applique à partir de sa date d’effet.</p>
${droit('regler_parametres_clinique')}
`;

  /* ---------------------------------------------------------------- Achats */
  ajouts['Achats et fournisseurs'] = `
<h2>Valider une commande de stock gros (RG-04)</h2>
<p>Une commande de stock gros doit être validée par la <b>Directrice Administrative</b> avant d’être transmise au fournisseur. C’est un geste réservé : seul le rôle qui le détient voit le bouton de validation.</p>
${etapes(`Ouvrez ${ch('m7-commandes')}.`,
 `Repérez la commande en attente ; sa ligne affiche son état.`,
 `Cliquez sur l’icône ${b('Valider la commande')} de la ligne, puis confirmez ${b('Valider la commande')}. Le validateur enregistré est <b>vous</b>, l’agent de la session.`,
 `Une fois validée, la commande peut être transmise au fournisseur, puis livrée et soldée.`)}
${fig('commande-daf', 'Les bons de commande vus par la Directrice Administrative.')}
${fig('poste-commandes', 'Le même écran sur le poste de bureau (capture du poste Flutter, jeu de test) : 1 Nouvelle commande.', 'poste')}
${droit('valider_commande_stock')}
${att('Les états « Validée », « Transmise », « Livrée » et « Soldée » ne se choisissent pas dans le formulaire : ils ne s’obtiennent que par le geste de validation. Un autre rôle, même administrateur, ne peut pas valider une commande si la fiche de son rôle ne lui donne pas ce geste.')}
<p>Deux autres gestes réservés complètent le circuit des besoins : ${geste('arbitrer_besoins')} (détenu d’origine par ${detenteurs('arbitrer_besoins')}) et ${geste('traiter_besoins_accordes')} (détenu d’origine par ${detenteurs('traiter_besoins_accordes')}, qui reçoit la tâche « besoin accordé »).</p>

<h2>La commande voyage entre les postes</h2>
<p>Une commande créée sur un poste fileul est transmise au poste mère comme le reste de l’activité. Trois points à connaître :</p>
${puces(`Tant que la mère n’a pas répondu, la commande porte une <b>référence provisoire</b> du type <span class="cle">BC-2026-P&lt;poste&gt;-0001</span>. La mère la remplace par le <b>rang définitif</b> (<span class="cle">BC-2026-0001</span>). Une référence définitive ne se réécrit plus.`,
 `La Directrice Administrative valide depuis n’importe quel poste : sur un fileul, la décision est signée et déposée, la mère l’applique (voir « Décisions en attente de la mère »).`,
 `Deux postes qui saisissent exactement la même commande (même fournisseur, même jour, mêmes lignes) n’en font qu’une. Si deux numéros identiques sont attribués par hasard, la commande est <b>marquée en doublon</b> et jamais corrigée en silence : signalez-le à l’administrateur.`)}
${info('Les commandes, les prix d’achat et les fournisseurs ne vont jamais sur un téléphone.')}
`;

  /* ---------------------------------------------------------------- Facturation */
  ajouts['Facturation et caisse'] = `
<h2>La facture d’un patient ne porte ni AIB ni IFU d’acheteur</h2>
<p>La facture d’un <b>patient</b> n’a ni IFU d’acheteur, ni nom d’entreprise, ni AIB, et le bloc « Facture normalisée » d’un document d’entreprise n’y figure pas. Si un moteur reçoit quand même un AIB pour un patient, il refuse (AIB_FACTURE_PATIENT). La fenêtre d’encaissement ne demande donc que le montant, le mode de règlement, la référence de la transaction et une observation.</p>
${info('Quand une entreprise, un assureur ou une convention prend un patient en charge, la clinique émet une <b>facture distincte au tiers payeur</b> : voir la fiche suivante.')}

<h2>Facturer un tiers payeur</h2>
<p>Le tiers payeur est l’entreprise, l’assureur ou la convention qui prend un patient en charge. Sa facture est une pièce propre, avec l’IFU (13 chiffres) et le nom de l’acheteur. L’AIB est <b>proposé par le logiciel et décidé par le comptable</b>.</p>
${etapes(`Ouvrez ${ch('m8-factures-tiers')}. L’écran a quatre onglets : ${b('Factures')}, ${b('Tiers payeurs')}, ${b('Règlements et lettrage')}, ${b('Créances')}.`,
 `Onglet ${b('Tiers payeurs')} : cliquez sur ${b('Nouveau tiers payeur')} et renseignez ${b('Nom')}, ${b('Type')}, ${b('IFU (13 chiffres)')}, ${b('Adresse')}, ${b('Délai de paiement (jours)')} et ${b('Conditions')}. Une modification crée une nouvelle version datée.`,
 `Onglet ${b('Factures')} : cliquez sur ${b('Nouvelle facture à un tiers payeur')}. Sans tiers enregistré, l’écran vous renvoie à l’onglet ${b('Tiers payeurs')}.`,
 `Choisissez le ${b('Tiers payeur')}, la ${b('Facture du patient')} et, pour chaque prestation prise en charge, le ${b('Montant pris en charge')} (un montant partiel est permis). Le brouillon est créé.`,
 `Cliquez sur ${b('Décider de l’AIB')}. Le comptable répond à ${b('Appliquer l’AIB à cette facture ?')} (${b('Oui, appliquer')} ou ${b('Non, ne pas appliquer')}), choisit la ${b('Ligne du barème (situation de l’acheteur)')}, confirme le ${b('Taux retenu (%)')}, donne un ${b('Motif')} et clique sur ${b('Enregistrer la décision')}.`,
 `Émettez la facture : elle devient une facture normalisée (colonne ${b('MECeF')}) avec le ${b('Net à payer')} (base plus AIB décidé). Imprimez avec ${b('Imprimer la facture (A4)')}.`,
 `Quand le tiers paie : onglet ${b('Règlements et lettrage')}, ${b('Enregistrer un règlement reçu')} (${b('Montant reçu (FCFA)')}, ${b('Mode')}, ${b('Référence du paiement')}), puis ${b('Lettrer')} le règlement sur la facture. Le ${b('Reste dû')} diminue.`)}
${fig('factures-tiers', 'Les factures aux tiers payeurs : 1 Nouvelle facture, 2 Créances.')}
${fig('poste-factures-tiers', 'Sur le poste de bureau : 1 Nouvelle facture à un tiers payeur, 2 Créances.', 'poste')}
${puces(`<b>Corriger</b> : une facture émise ne se modifie pas. La correction est un avoir total, avec lettrage ou délettrage d’un règlement, réservé au geste ${geste('corriger_facture_tiers')}.`,
 `<b>Créances</b> : le montant dû moins les lettrages, par tiers, en tranches (30 et 90 jours à l’origine). Sans délai convenu, l’échéance est « non calculable » et l’écran le dit.`,
 `Un tiers n’est jamais facturé deux fois pour la même prestation. Un trop-perçu reste non lettré : le remboursement ne se gère pas ici.`)}
${droit('emettre_facture_tiers')}
${att('Le caissier propose et émet ; il ne décide jamais de l’AIB. La décision de l’AIB appartient au geste « Imputer l’AIB » (comptable, Directrice Administrative, administrateur). La caisse du patient n’est pas modifiée : la <b>part restante du patient</b> se calcule et s’imprime, mais l’encaissement de la facture du patient encaisse toujours la pièce entière.')}
${qui(['m8-factures-tiers'])}
`;

  /* ---------------------------------------------------------------- MECeF */
  ajouts['MECeF : facture normalisée'] = `
<h2>Choisir le mode de certification</h2>
<p>La clinique certifie ses factures par le <b>boîtier MECeF physique</b> (mode d’origine) ou, plus tard, par l’e-MECeF. Le mode se règle sur l’écran de configuration fiscale.</p>
${etapes(`Ouvrez ${ch('mecef-config')}.`,
 `La carte ${b('Mode de certification')} dit le ${b('Mode en vigueur')} : ${b('Boîtier physique')} par défaut.`,
 `Cliquez sur ${b('Régler le mode')}, choisissez le mode et validez.`)}
${fig('mecef-modes', 'La configuration fiscale : 1 Régler le mode, 2 Régler l’imprimante (plus bas), 3 Voir la file.')}
${fig('poste-mecef-config', 'Sur le poste de bureau : la configuration fiscale et le réglage du mode.', 'poste')}
${droit('regler_mode_mecef')}
${alerte('Aucun numéro n’est jamais fabriqué comme s’il était fiscal. Tant que l’appareil réel n’est pas branché, le mode boîtier dit « en attente des réponses du fournisseur » et une vente reste <b>en attente de certification</b> ; le mode e-MECeF dit « non configuré : dossier d’interface DGI requis ». Le bouton « Tester la connexion au dispositif » le dit aussi au lieu d’annoncer une connexion qui n’existe pas.')}

<h2>Lire l’état de la caisse</h2>
<p>La carte ${b('État de la caisse')} compte ce qui est encaissé sans être encore normalisé :</p>
${puces(`${b('Ventes encaissées non normalisées')} et leur ${b('Montant encaissé non normalisé')} : une vente encaissée dont la facture n’est pas encore certifiée.`,
 `${b('Avoirs en attente de certification (à part)')} et leur montant : comptés à part, jamais mélangés aux ventes.`,
 `Si un montant n’est pas connu, l’écran écrit ${b('Non calculable')} : ce n’est pas zéro et le total n’est pas affirmé.`)}
<p>Le bouton ${b('Voir la file')} ouvre ${ch('mecef-transmission')}, où l’on suit et retransmet les ventes.</p>

<h2>Régler l’imprimante de caisse</h2>
<p>La carte ${b('Imprimante de caisse')} montre le ${b('Nom')}, le ${b('Modèle')} (Xprinter XP-Q800), le ${b('Type')} (thermique, rouleau 80 mm), la ${b('Liaison')} et la date d’entrée en vigueur.</p>
${etapes(`Regardez à l’arrière de l’appareil si la liaison est USB ou Ethernet : l’écran la marque « à vérifier » tant que personne ne l’a constatée.`,
 `Cliquez sur ${b('Régler l’imprimante')}, renseignez le nom et la liaison, et choisissez la <b>date d’effet</b>.`,
 `Validez. Le réglage est daté et se garde en historique.`)}
${droit('regler_imprimante_caisse')}
${att('Un réglage ne s’insère pas dans le passé : la date d’effet est aujourd’hui ou une date à venir, car des tickets sont déjà imprimés.')}
`;

  /* ---------------------------------------------------------------- Comptabilité */
  ajouts['Comptabilité SYSCOHADA'] = `
<h2>Confirmer le versement CNSS</h2>
<p>Le versement CNSS est marqué « à confirmer, non arrêté » tant que la CNSS n’a pas confirmé la règle. La confirmation se fait par un bouton, avec une référence obligatoire.</p>
${etapes(`Ouvrez ${ch('cfg-comptabilite')} et repérez l’obligation ${b('CNSS-VERSEMENT')} (versement dans les quinze jours, employeur de plus de vingt salariés : mensuel).`,
 `Cliquez sur ${b('Confirmer')} dans sa ligne.`,
 `Saisissez la ${b('Référence de la confirmation')} (obligatoire : courrier, e-mail ou page de la CNSS qui confirme, avec sa date), puis validez. La confirmation est signée, journalisée et versionnée par date.`)}
${fig('cnss-confirmation', 'Les obligations fiscales : 1 Confirmer, dans la ligne CNSS-VERSEMENT.')}
${fig('poste-obligations', 'Sur le poste de bureau : 1 Confirmer la ligne CNSS-VERSEMENT.', 'poste')}
${droit('confirmer_obligation_fiscale')}
${info('Le calendrier fiscal mensuel (' + ch('m12-calendrier-fiscal') + ') affiche ensuite l’échéance du versement avec sa date confirmée. Les assiettes des cotisations (CNSS part patronale 16,4 %, part ouvrière 3,6 %, VPS 4 %) sont celles du cahier des charges.')}

<h2>Imputer l’AIB opération par opération</h2>
<p>L’AIB ne s’applique pas tout seul : le comptable l’<b>impute opération par opération</b>. Le logiciel propose le taux du barème à la date de l’opération ; il ne décide jamais.</p>
${etapes(`Ouvrez ${ch('cfg-bareme-aib')} et cliquez sur l’onglet ${b('Imputations')} (les autres onglets sont ${b('Barème par version')}, ${b('Situations et lignes')}, ${b('Réglages')}, ${b('Achats à écrire')}).`,
 `Choisissez l’opération : un achat auprès d’un fournisseur, le règlement d’un prescripteur ou d’un prestataire externe, ou un règlement reçu d’un assureur.`,
 `Saisissez la base (montant hors taxes), acceptez ou changez le taux proposé, indiquez le compte et le motif, et enregistrez.`,
 `Une imputation se corrige par une <b>annulation motivée</b> (archivage) : elle ne s’efface pas.`)}
${fig('aib-imputations', 'L’onglet Imputations du barème de l’AIB (vue du Comptable).')}
${fig('poste-aib', 'Sur le poste de bureau : 1 onglet Imputations du barème de l’AIB.', 'poste')}
${droit('imputer_aib')}
${att('Deux barèmes datés coexistent : la situation de l’acheteur (1 %, 5 %, 3 %) et la retenue sur la facture d’un tiers (3 % pour une personne physique, 5 % pour une personne morale). Ces derniers taux sont des <b>hypothèses à confirmer</b> par la Direction : les textes officiels n’ont pas été relus. L’imputation n’écrit aucune écriture comptable pour l’instant.')}
<p>Le droit d’écrire une version du barème est ${geste('ecrire_bareme_aib')} (détenu d’origine par ${detenteurs('ecrire_bareme_aib')}) ; l’onglet ${b('Nouvelle version')} demande un motif. <b>Tout changement du validateur d’une famille</b> exige aussi un motif.</p>
`;

  /* ---------------------------------------------------------------- RH */
  ajouts['Ressources humaines et paie'] = `
<h2>Ouvrir la fiche de mon équipe (Surveillant)</h2>
<p>Le Surveillant n’ouvre pas la fiche complète du personnel (elle porte le salaire, la CNSS, l’assurance et les primes). Il ouvre une fiche <b>restreinte</b>, limitée aux agents de son service, sans lui-même.</p>
${etapes(`Ouvrez ${ch('m10-fiche-equipe')}.`,
 `Dans ${b('Agent de l’équipe')}, choisissez l’agent. Le bandeau dit « Équipe : N agent(s) ».`,
 `Lisez l’onglet ${b('Informations')} (matricule, nom, sexe, fonction, poste, service), ${b('Planning personnalisé')} et ${b('Planning du mois')}.`)}
${fig('fiche-equipe', 'La fiche de mon équipe (Surveillant), noms masqués.')}
${droit('ouvrir_fiche_personnel_equipe')}
${puces(`<b>Lecture seule</b> : aucune donnée de paie, aucun bouton de création, de modification ou d’archivage.`,
 `Si votre session n’est pas celle d’un agent du personnel rattaché à un service, l’écran refuse en le disant : jamais « tout le personnel ».`,
 `Le Surveillant gère aussi le planning de son équipe : voir la fiche « Planning personnalisé d’un agent ». Il ne règle pas son propre planning (c’est à la Directrice Administrative ou à l’administrateur).`)}

<h2>Régime individuel : déroger ou remplacer</h2>
<p>Chaque catégorie suit son régime de travail. Un agent peut avoir un régime individuel en <b>deux modes</b>, choisis dans le formulaire :</p>
${puces(`${b('Déroge')} : seuls les champs renseignés changent, le reste suit la catégorie.`,
 `${b('Remplace')} : rien n’est hérité. Les vacations et le repos sont exigés ; ce qui n’est pas dit reste « non défini ».`)}
${etapes(`Ouvrez ${ch('m10-planning')}. Sous les régimes par catégorie, la section des régimes individuels liste les agents concernés avec leur ${b('Mode')}.`,
 `Cliquez sur ${b('Déroger pour un agent')} (ou sur ${b('Régler')} dans la ligne d’un agent).`,
 `Choisissez le ${b('Mode')}, les vacations, le repos, le cycle, l’honoraire, la <b>date d’effet</b> (jamais dans le passé) et validez.`)}
${fig('regime-individuel', 'Planning et gardes : 1 Nouveau régime (régimes par catégorie). Le bouton Déroger pour un agent est plus bas.')}
${droit('regler_regime_individuel')}
${info('Chaque version est datée et ne se réécrit pas. Les vacations déjà posées gardent le régime sous lequel elles l’ont été. Un régime individuel ne voyage pas encore d’un poste à l’autre.')}

<h2>Planning personnalisé d’un agent</h2>
<p>Le planning personnalisé est un <b>modèle</b> (une semaine type ou un mois type) rattaché à un agent. Il ne compte pour <b>aucune prime</b> : seules les vacations validées du planning comptent (RG-11).</p>
${etapes(`Ouvrez la fiche de l’agent (${ch('m10-employe-profil')}, bouton ${b('Choisir un agent')}) puis l’onglet ${b('Planning personnalisé')}.`,
 `Cliquez sur la commande de définition, choisissez un modèle hebdomadaire ou mensuel, remplissez les jours et la date d’effet, et enregistrez : une <b>version datée</b> est créée.`,
 `Cliquez sur ${b('Appliquer le planning personnalisé')} et choisissez la période (92 jours au plus). Les vacations sont écrites <b>validées</b>.`,
 `Lisez le compte rendu : les jours <b>déjà occupés</b> ne sont jamais écrasés et sont listés ; un jour refusé par le contrôle de la grille (repos, double affectation) est nommé sans bloquer les autres.`)}
${droit('regler_planning_personnalise')}
${att('Dans un modèle hebdomadaire, la semaine se lit en boucle : une garde le dimanche et une garde le lundi se heurtent. Dans un modèle mensuel, le 31 puis le 1er ne se heurtent pas.')}

<h2>Les valeurs d’attente de la fiche du personnel</h2>
<p>Quatre valeurs de la fiche d’un agent peuvent être des <b>valeurs d’attente</b>, c’est-à-dire des valeurs tirées en attendant la bonne : le ${b('salaire')}, la ${b('catégorie')}, la ${b('date d’embauche')} et le numéro ${b('CNSS')}. Chaque champ concerné porte une marque qui le dit.</p>
${puces(`La marque disparaît quand vous <b>modifiez le champ</b>, ou quand vous cliquez sur ${b('Confirmer')} et donnez un <b>motif</b>.`,
 `Un agent créé sans ces valeurs n’en porte aucune, et aucune marque.`,
 `La paie ne compte que les vacations <b>validées</b> : recalculez le mois par ${ch('m11-calcul')} si des bulletins ont été calculés avant la correction.`)}
${droit('confirmer_valeur_attente_personnel')}
${info('Un Surveillant, depuis la fiche de son équipe, ne voit ni ne confirme jamais une valeur d’attente (refus VALEUR_ATTENTE_HORS_PORTEE).')}
`;

  /* ---------------------------------------------------------------- Administration */
  ajouts['Administration, documents et états'] = `
<h2>Le plan annuel de travail</h2>
<p>Le plan annuel de travail se tient <b>par exercice</b> : celui du jour s’ouvre par défaut. Chaque action a une référence <span class="cle">PA-AAAA-NNN</span>, un axe, des trimestres, un responsable <b>choisi dans le personnel ou l’organigramme</b> (jamais un texte libre), un budget prévu et un indicateur.</p>
${etapes(`Ouvrez ${ch('m13-plan-annuel')} ; choisissez l’exercice.`,
 `Cliquez sur ${b('Nouvelle action')}, renseignez l’action, l’axe, les trimestres T1 à T4, le responsable, le budget prévu, l’indicateur et la cible, puis enregistrez.`,
 `Suivez l’avancement (état, pourcentage, budget réalisé, valeur atteinte, observations). Un budget non renseigné s’affiche « non renseigné », jamais zéro.`,
 `Quand le plan est arrêté, la Direction l’<b>adopte</b>. Le contenu ne change plus ensuite que par version datée ; le suivi reste libre.`,
 `Imprimez avec ${b('Imprimer le plan')} ou ${b('Imprimer le bilan')}. Les signataires se règlent avec ${b('Signataires de l’impression')} (un à quatre, par fonction).`)}
${fig('plan-annuel', 'Le plan annuel de travail : 1 Nouvelle action, 2 Imprimer le plan.')}
${fig('poste-plan-annuel', 'Sur le poste de bureau : 1 Nouvelle action, 2 Imprimer le plan.', 'poste')}
${puces(`${b('Reconduire les actions non réalisées')} copie, une seule fois par action, celles d’un exercice précédent vers le nouveau, suivi remis à zéro.`,
 `Une action non réalisée dont le dernier jour du trimestre de fin est passé déclenche une <b>alerte de retard</b> (une seule par action), qui retombe quand l’action est réalisée ou replanifiée.`,
 `Pour ajouter une action à un plan déjà adopté, utilisez « Ajouter après adoption » et donnez un motif.`)}
${droit('adopter_plan_annuel')}
${info('Le plan annuel se synchronise entre les postes mais ne va jamais sur un téléphone. Le jeu de démonstration de la maquette sème douze actions ; le poste de bureau part avec un plan vide.')}

<h2>Recueillir l’avis des patients en ligne (satisfaction)</h2>
<p>Un questionnaire de satisfaction peut être rempli <b>sur le téléphone du patient</b>, par une adresse publique ou par un <b>code QR</b>. La page est un formulaire seul : ce n’est pas un portail patient. Les réponses sont <b>chiffrées dans le navigateur du patient</b> avant d’être envoyées ; le relais ne les lit jamais, seul le poste mère les ouvre.</p>
${etapes(`Ouvrez ${ch('adm-enquetes')}. Onglet ${b('Modèles')} : choisissez l’enquête, cliquez sur ${b('Partager à un tiers')} (icône de partage de la ligne).`,
 `Dans ${b('Recueil')}, choisissez ${b('Anonyme')} (aucun lien vers un dossier patient) ou ${b('Nominatif')}. Dans ${b('Où le tiers répond-il ?')}, choisissez ${b('En ligne : adresse publique ou code QR')}, le ${b('Point de collecte')} (accueil, consultation, laboratoire, pharmacie, maternité, hospitalisation, sortie) et la date d’expiration du lien.`,
 `L’onglet ${b('Liens de partage')} liste le lien. Cliquez sur ${b('Afficher le lien et le QR')}.`,
 `Cliquez sur ${b('Imprimer l’affiche (A4)')} : le bloc « À afficher en salle d’attente » donne l’affiche avec le code QR. ${b('Copier l’adresse')} copie le lien.`,
 `Pour arrêter la collecte, cliquez sur ${b('Révoquer le lien')} : la page répond « Ce lien n’est plus valable ».`)}
${fig('enquetes-liens', 'Enquêtes et questionnaires : 1 Liens de partage, 2 Nouveau modèle.')}
${fig('poste-enquetes', 'Sur le poste de bureau : 1 Nouveau modèle.', 'poste')}
${fig('satisfaction', 'La satisfaction des patients : notes par question, taux et commentaires.')}
${fig('poste-satisfaction', 'Sur le poste de bureau : la satisfaction des patients.', 'poste')}
<p>L’écran ${ch('adm-satisfaction')} donne l’analyse : ${b('Réponses recueillies')}, ${b('Note moyenne globale')}, ${b('Recommanderaient la clinique')}, ${b('Avec commentaire libre')}, la note par question, l’évolution par mois et le résultat par point de collecte.</p>
${info('Le taux de satisfaction compte les notes 4 ou 5 sur les notes valides. Le taux de réponse est « non calculable » tant que les passages à l’accueil ne sont pas comptés : ce n’est pas zéro.')}
${att('La collecte en ligne est <b>désactivée par défaut</b> : une page publique ne s’ouvre pas sans geste. La page exige un navigateur récent (Chrome 133, Firefox 130, Safari 17) et le dit sinon ; un téléphone plus ancien ne peut pas répondre. Aucun nom, aucun numéro de dossier ni aucune donnée de santé ne doit figurer dans une réponse : le poste mère refuse la réponse qui en contient.')}
`;

  /* ---------------------------------------------------------------- Système */
  ajouts['Système et pilotage'] = `
<h2>Les SMS automatiques de la clinique</h2>
<p>La clinique envoie deux sortes de SMS, <b>calculés par le poste mère</b> et envoyés par le relais :</p>
${puces(`le <b>rappel de rendez-vous</b>, la veille à 18 h (et, pour un rendez-vous vu après cet envoi, le matin même à 7 h, heure à valider) ;`,
 `les <b>vœux d’anniversaire</b>, à 9 h, pour les patients et pour le personnel.`)}
<p>Les modèles ont cinq variables au plus et <b>aucun mot médical</b> : le SMS ne dit ni le médecin, ni le service, ni le motif. Seuls les patients reçoivent des SMS ; les alertes du personnel passent par la cloche et le son du poste.</p>
${etapes(`Ouvrez ${ch('cfg-sms')}. Les cartes d’en-tête disent la ${b('Passerelle')} (configurée ou non), l’${b('Activation')}, le ${b('Dernier test')} et les ${b('Envois aujourd’hui')}.`,
 `Dans ${b('Réglages de la passerelle')}, choisissez le ${b('Fournisseur')} (Twilio par défaut, ou Vonage), le ${b('Plafond par jour')}, l’${b('Expéditeur')} et les heures calmes (21 h à 7 h à l’origine : un message non urgent attend la fin des heures calmes).`,
 `Cliquez sur ${b('Enregistrer la passerelle')}. Les identifiants du fournisseur (Account SID, jeton, clé API) ne s’affichent jamais : l’écran dit seulement « défini » ou « non défini ».`,
 `Dans ${b('Test d’envoi')}, saisissez un numéro de test au format international et cliquez sur ${b('Tester l’envoi')}. L’écran dit « accepté par le fournisseur » avec son identifiant, ou un refus nommé avec le geste qui le corrige. <b>Accepté ne veut pas dire reçu</b> : vérifiez sur le téléphone.`,
 `Cochez ${b('Passerelle active')} pour activer les envois automatiques.`)}
${fig('sms-passerelle', 'La passerelle SMS : 1 Enregistrer la passerelle, 2 Tester l’envoi.')}
${fig('poste-cfg-sms', 'Sur le poste de bureau : la passerelle SMS et ses cartes d’état.', 'poste')}
${droit('regler_passerelle_sms')}
${alerte('Les envois automatiques sont <b>désactivés par défaut</b> : activez-les seulement quand la passerelle est testée. La couverture du Bénin, l’expéditeur alphanumérique et le coût d’un message n’ont jamais été vérifiés avec un vrai compte : la première semaine, gardez un plafond bas.')}
<p>Le <b>consentement</b> se règle sur la fiche : la case ${b('Accepte de recevoir des SMS de la clinique')} du dossier patient (cochée par défaut) et la case ${b('Accepte de recevoir les vœux d’anniversaire par SMS')} de la fiche du personnel, <b>décochée par défaut</b>. Sans consentement, aucun SMS ne part.</p>
<p>${ch('m13-sms-journal')} garde une ligne par envoi tenté : motif, statut, code du refus, fournisseur et numéro <b>masqué</b> (les quatre derniers chiffres seulement). Filtres : ${b('Aujourd’hui')}, ${b('Sept derniers jours')}, ${b('Toute la période')} ; onglets ${b('Tous les envois')} et ${b('Archivés')}.</p>
${fig('sms-journal', 'Le journal des envois SMS.')}
${fig('poste-sms-journal', 'Sur le poste de bureau : le journal des envois SMS.', 'poste')}
${info('Un rendez-vous pris juste avant un rappel qui part trop tard n’est pas rappelé à l’heure du rendez-vous ni après. Un message est refusé s’il a plus de 3 heures de retard sur son heure.')}

<h2>L’identité de la clinique sur les pièces (RCCM)</h2>
<p>L’identité imprimée est <b>unique</b> et <b>versionnée par date</b> : IFU 3201642748214 et RCCM <b>NAT/2021/M02-020</b> à partir du 16 novembre 2026 (date à confirmer par la Direction). L’ancien numéro RB/NAT/2016-B-268 est la version 1, close au 15 novembre 2026. Une pièce lit l’identité de <b>sa propre date</b> : une facture d’octobre garde l’ancien numéro, une facture de décembre porte le nouveau.</p>
${etapes(`Ouvrez ${ch('cfg-fiscalite')} (paramètres fiscaux) ou ${ch('cfg-branding')} (identité et papier à en-tête).`,
 `Modifiez la mention, choisissez la <b>date d’effet</b>, puis cliquez sur ${b('Enregistrer')}.`,
 `Si la mention est une première configuration, cliquez sur ${b('Valider l’identité légale')} : la validation appartient à la Direction, à la DAF ou à l’administrateur.`,
 `Contrôlez avec ${b('Prévisualiser un état')}.`)}
${fig('identite-rccm', 'Les paramètres fiscaux : 1 Enregistrer.')}
${fig('poste-identite-rccm', 'Sur le poste de bureau : les paramètres fiscaux, version 2 en force (RCCM NAT/2021/M02-020).', 'poste')}
${fig('identite-papier', 'Identité et papier à en-tête : 1 Enregistrer, 2 Prévisualiser un état.')}
${puces(`Le droit de poser l’identité est celui d’<b>écrire</b> l’un de ces deux écrans (administrateur, Direction, DAF d’origine). Sur un poste <b>fileul</b>, la modification est signée et déposée ; la mère la revérifie sous le rôle de l’auteur et la propage à tous les postes.`,
 `Les options d’impression (logo de part et d’autre, filigrane) sont un réglage de clinique qui voyage avec l’identité.`,
 `Un poste déjà installé qui n’avait que la version 1 reçoit la version 2 <b>au démarrage</b>, sans réécrire la version 1. Un fileul rattaché ne migre pas : il la reçoit de la mère.`,
 `Rien de l’identité ne part vers un téléphone.`)}
${droit('valider_configuration_fiscale')}
`;

  /* ---------------------------------------------------------------- Mobile */
  ajouts['L’application mobile'] = `
<h2>Ce que le téléphone ne reçoit jamais</h2>
<p>Le téléphone ne reçoit que ce qu’il lui faut pour la tournée. Les données de gestion de la clinique ne vont <b>jamais</b> sur un téléphone, quel que soit le profil :</p>
${puces(`la configuration de la clinique : identité, fiscalité, barèmes, paramètres de clinique, règles, tarifs ;`,
 `les achats : commandes de stock gros, fournisseurs, prix d’achat ;`,
 `la facturation aux tiers payeurs, les imputations de l’AIB et toute collection fiscale ;`,
 `le plan annuel de travail, les régimes et plannings personnalisés du personnel ;`,
 `la passerelle SMS, ses numéros et ses textes, et les réponses de satisfaction.`)}
`;

  /* ---------------------------------------------------------------- Relais */
  ajouts['Le relais web'] = `
<h2>Les SMS passent par le relais</h2>
<p>Le relais tient la passerelle SMS. Le poste mère calcule les messages (rappels, vœux), les <b>dépose</b> au relais sous un identifiant opaque, et le relais les envoie par une tâche planifiée, puis <b>efface le texte et le numéro en clair</b>. Entre le dépôt et l’envoi, le relais détient le numéro et le texte : c’est la seule exception à son opacité, et elle ne concerne que les SMS aux patients. Seul le poste mère règle et déclenche cette passerelle ; un fileul n’y touche pas.</p>

<h2>La page publique de satisfaction</h2>
<p>Quand la collecte en ligne est activée, le relais sert une page publique sans cookie, par exemple <span class="cle">sighcnt.nassieratoo.com/s/&lt;jeton&gt;</span>. La page porte la devise de la clinique et le questionnaire seul. Les réponses sont chiffrées dans le navigateur ; le relais les garde sans pouvoir les lire jusqu’à ce que le poste mère les relève (chaque minute). Un lien révoqué ou expiré affiche « Ce lien n’est plus valable ».</p>
${info('Le panneau superadmin du relais (appareils, boîtes, codes, indicateurs, synchronisation, alertes, journal, comptes, paramètres, hébergement, sauvegarde, SMS, opacité, consultation, messagerie) n’est pas un écran d’agent. Il est décrit dans le Manuel administrateur.')}
`;

  return { ajouts, ecran, ch };
};
