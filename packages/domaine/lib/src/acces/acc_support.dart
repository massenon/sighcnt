/// Aide, contact éditeur et plan du site (SUP / AUTH) — règles de `prototype_html/assets/js/modules/support.js` et de l'écran `plan-du-site`, rejouées
/// sur les vecteurs de la maquette (`vecteurs-acces.js`). Le contenu documentaire (résumés de module, questions fréquentes, coordonnées) est EXTRAIT du
/// code de la maquette, mot pour mot : ce sont des textes qu'un agent lit, pas des données qu'on invente.
library;

import '../navigation/manifeste.dart';

/// Coordonnées de l'éditeur (`EDITEUR` de la maquette).
const Map<String, Object> accEditeur = {
  'auteur': 'Dr MASSENON Rhodes',
  'emails': ['rarhodes06@gmail.com', 'contact@massenonrhodes.com'],
  'telephone': '+229 01 51 33 50 40',
  'horaires': 'Lundi au vendredi, 8h – 17h (GMT)',
  'version': 'Prototype v1.0 — août 2026',
};

/// Ce que fait chaque module, en une phrase (`RESUMES`).
const Map<String, String> accResumesModules = {
  'DASH': 'Un tableau de bord par profil : indicateurs, alertes et accès rapides propres au poste de travail.',
  'PIL': 'La lecture transversale de l’activité : synthèse de la Direction, statistiques et tableau croisé dynamique.',
  'M1': 'Dossier patient unique : identité, antécédents, allergies, documents numérisés et historique complet.',
  'M2': 'Agenda, rendez-vous, consultations, ordonnances et soins à domicile, en remplacement des registres papier.',
  'M3': 'Admissions, plan des lits, feuilles de température et de soins, sorties avec les signatures exigées.',
  'M4': 'Suivi de grossesse, accouchements, registres officiels des naissances et des décès.',
  'M5': 'Demandes d’analyses, saisie des résultats, réactifs et banque de sang, du prélèvement au compte rendu.',
  'M6': 'Pharmacie et magasin : produits, lots, péremptions FEFO, mouvements, inventaires et dispensation.',
  'M7': 'Expression des besoins, commandes validées par la Direction, livraisons, réceptions et factures fournisseurs.',
  'M8': 'Facturation, encaissements, reliquats et état de caisse journalier.',
  'M9': 'Compagnies partenaires, cartes d’assurés, prises en charge, factures mensuelles et créances.',
  'MECEF': 'Facture normalisée : structure fiscale, transmission, avoirs et journal des transactions certifiées.',
  'M12': 'Comptabilité SYSCOHADA : plan comptable, journaux, écritures équilibrées, balance et états financiers.',
  'M10': 'Personnel, contrats, planning des gardes, présences, congés, évaluations et primes.',
  'M11': 'Calcul de la paie, bulletins, cotisations CNSS / ITS / VPS et validation par la Direction.',
  'M13': 'Courriers, réunions, plan annuel de travail, notes de service et interventions de l’ambulance.',
  'GED': 'Bibliothèque documentaire, circuit de validation et archivage avec durée de conservation.',
  'RAP': 'Bibliothèque des états officiels, générateur de rapports et historique des éditions.',
  'M14': 'Utilisateurs, rôles et permissions, sessions actives, journal d’audit et sauvegardes.',
  'CFG': 'Organigramme, papier à en-tête, référentiel tarifaire, règles métier et paramètres fiscaux.',
};

/// Résumé d'un module ; « Module du système. » quand la maquette n'en a pas.
String accResumeModule(String code) => accResumesModules[code] ?? 'Module du système.';

/// Une question fréquente. `r` porte les balises de la maquette (`<code>`, `<strong>`, `<em>`), que l'écran rend en texte enrichi.
class AccQuestion {
  const AccQuestion(this.q, this.r);
  final String q;
  final String r;
}

const List<AccQuestion> accFaq = [
  AccQuestion('Comment est attribué le numéro de dossier d’un patient ?',
      'Automatiquement, au format <code>CNT/[n° d’ordre]/[année]</code> — par exemple <code>CNT/530/25</code>. Le champ est verrouillé à la saisie : il ne peut être ni choisi ni modifié après création (règle RG-01). C’est cette unicité qui permet de retrouver un dossier partout dans l’application.'),
  AccQuestion('Pourquoi le prix de vente d’un médicament est-il égal à son prix d’achat ?',
      'C’est la règle RG-02 arrêtée par la clinique : les médicaments sont facturés au prix d’achat, sans marge. Toute exception doit être validée par la Direction et reste tracée. Le référentiel tarifaire signale immédiatement une ligne dont le prix de vente s’écarterait du prix d’achat.'),
  AccQuestion('Un patient présente une carte d’assurance expirée : que fait le système ?',
      'La prise en charge n’est pas appliquée et la facturation devient intégrale au patient (règle RG-09). L’écran de facturation affiche un bandeau rouge rappelant la date d’expiration ; il suffit de mettre à jour la validité dans le dossier du patient pour rétablir la couverture.'),
  AccQuestion('Pourquoi une sortie de stock est-elle refusée ?',
      'Parce que la quantité demandée dépasse le stock disponible : le stock ne peut jamais devenir négatif (règle RG-03). Vérifier l’état réel du rayon, puis régulariser par un inventaire ou une réception.'),
  AccQuestion('Comment obtenir un document en PDF ?',
      'Chaque état dispose d’un bouton <strong>Imprimer</strong> qui ouvre l’aperçu au papier à en-tête de la clinique, puis la boîte d’impression du navigateur. Y choisir la destination <strong>« Enregistrer au format PDF »</strong>. Le catalogue complet se trouve dans <em>Rapports & Impression → Bibliothèque des états</em>.'),
  AccQuestion('J’ai supprimé un enregistrement par erreur : est-il perdu ?',
      'Non. La suppression physique n’existe pas (règle RG-14) : l’enregistrement est <strong>archivé</strong>. Il reste consultable dans l’onglet « Archivés » de son écran et peut être restauré. Juste après l’opération, le message de confirmation propose d’ailleurs « Annuler ».'),
  AccQuestion('Pourquoi certains écrans ne proposent-ils pas de modification ?',
      'Parce qu’ils affichent un <strong>état calculé</strong> ou une <strong>preuve</strong> : grand livre, balance, état de caisse, alertes de stock, journal d’audit, journal MECeF. Les modifier reviendrait à falsifier un résultat. Chacun de ces écrans indique où corriger la donnée d’origine.'),
  AccQuestion('Qui a accès à quoi ?',
      'Le périmètre dépend du profil de connexion (règle RG-13) : le médical est réservé aux soignants habilités, le financier et les ressources humaines aux profils comptables et RH. Le menu lui-même est filtré : un écran interdit n’apparaît pas. Toute action reste journalisée avec son auteur (RG-12).'),
  AccQuestion('Mes saisies disparaissent après un rechargement de la page.',
      'C’est le comportement du prototype ouvert par double-clic : le navigateur refuse alors l’accès au stockage local et les données ne vivent qu’en mémoire. Servir le dossier (<code>npx serve .</code>) pour les conserver. La version définitive s’appuiera sur une base PostgreSQL installée sur le serveur.'),
];

/// Les balises d'une réponse retirées : ce que l'agent LIT (et ce que les vecteurs de la maquette mesurent par `textContent`).
String accTexteSansBalises(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&');

/// Une ligne de la rubrique « Modules du logiciel » et de la liste des modules de l'anomalie : le module d'une rangée du manifeste.
class AccModuleManifeste {
  const AccModuleManifeste(this.domaine, this.code, this.label, this.icone, this.ecrans);
  final String domaine;
  final String code;
  final String label;
  final String? icone;
  final List<EcranNav> ecrans;
}

/// Les rangées du manifeste dans l'ordre des domaines (`N.NAV`), chacune avec ses écrans. Ni les hubs ni les pages d'accès n'y figurent : ce sont les
/// écrans fonctionnels que la maquette compte.
List<AccModuleManifeste> accModules(Manifeste m) {
  final out = <AccModuleManifeste>[];
  for (final d in m.domaines) {
    for (final r in m.rangees.where((r) => r.domaine == d.nom)) {
      out.add(AccModuleManifeste(d.nom, r.code, r.label, r.icone, [
        for (final id in r.ecrans)
          if (m.ecran(id) != null) m.ecran(id)!
      ]));
    }
  }
  return out;
}

/// Les quatre chiffres de l'aide : modules, écrans, règles de gestion (14, fixe), profils.
({int modules, int ecrans, int regles, int profils}) accChiffresAide(Manifeste m, int profils) {
  final mods = accModules(m);
  return (modules: mods.length, ecrans: mods.fold(0, (n, x) => n + x.ecrans.length), regles: 14, profils: profils);
}

/// Les options de l'anomalie « Module concerné » : « CODE — libellé » de chaque rangée, puis « Autre / je ne sais pas ». Un code peut revenir (M2 sur
/// trois rangées) : la maquette ne dédoublonne pas, le poste non plus.
List<({String code, String libelle})> accOptionsModules(Manifeste m) => [
      for (final x in accModules(m)) (code: x.code, libelle: '${x.code} — ${x.label}'),
      (code: 'AUTRE', libelle: 'AUTRE — Autre / je ne sais pas'),
    ];

// ----------------------------------------------------------------------------------------------------------------------------------------------
// Contact éditeur
// ----------------------------------------------------------------------------------------------------------------------------------------------

/// Les contrôles de la maquette — le refus se nomme.
String? accControlerMessage(String objet, String message) =>
    objet.trim().isEmpty || message.trim().isEmpty ? 'Renseigner l’objet et le message.' : null;
String? accControlerAnomalie(String? module, String description) =>
    module == null || module.isEmpty || description.trim().isEmpty ? 'Indiquer le module et décrire le problème.' : null;

/// La référence suivante d'une demande : `SUP-AAAA-NNNN`. La maquette compte avec un compteur de PAGE (`C.nextRef`) qui repart de 1 à chaque
/// chargement et écrit « 2026 » en dur ; le poste prend le plus grand numéro DÉJÀ ÉCRIT + 1, de l'année courante (écart consigné).
String accReferenceSupport(int annee, Iterable<Object?> existantes) {
  final prefixe = 'SUP-$annee-';
  var max = 0;
  for (final r in existantes) {
    final s = '$r';
    if (!s.startsWith(prefixe)) continue;
    final n = int.tryParse(s.substring(prefixe.length));
    if (n != null && n > max) max = n;
  }
  return '$prefixe${(max + 1).toString().padLeft(4, '0')}';
}

/// La demande « message » : les champs que la maquette écrit (hors référence, date, auteur et état, posés par l'appelant).
Map<String, Object?> accDemandeMessage(String objet, String message) => {
      'type': 'message',
      'objet': objet,
      'description': message,
      'module': null,
      'etapes': null,
      'capture': null,
    };

/// La demande « anomalie ».
Map<String, Object?> accDemandeAnomalie(String module, String description, String? etapes, String? capture) => {
      'type': 'anomalie',
      'objet': 'Anomalie — $module',
      'module': module,
      'description': description,
      'etapes': etapes,
      'capture': capture,
    };

String accToastDemande(String type) => type == 'anomalie' ? 'Anomalie signalée à l’éditeur.' : 'Message envoyé à l’éditeur.';
String accDetailDemande(String reference) => 'Référence $reference — réponse sous 48 h ouvrées.';

// ----------------------------------------------------------------------------------------------------------------------------------------------
// Plan du site
// ----------------------------------------------------------------------------------------------------------------------------------------------

class AccPlanModule {
  const AccPlanModule(this.label, this.code, this.icone, this.ecrans);
  final String label;
  final String code;
  final String? icone;
  final List<EcranNav> ecrans;
}

class AccPlanSection {
  const AccPlanSection(this.domaine, this.icone, this.modules);
  final String domaine;
  final String? icone;
  final List<AccPlanModule> modules;
}

class AccPlan {
  const AccPlan(this.sections, this.systeme, this.totalEcrans);
  final List<AccPlanSection> sections;

  /// « Accès et pages système » : les pages hors navigation.
  final List<EcranNav> systeme;
  final int totalEcrans;
  String get pied => '$totalEcrans écrans métier recensés au manifeste, plus ${systeme.length} pages d’accès et système.';
}

/// L'inventaire COMPLET des écrans — non filtré par les droits, comme la maquette. Les « pages d'accès et système » sont les entrées hors ruban du
/// manifeste (`N.STANDALONE`), dans l'ordre où le manifeste les déclare.
AccPlan accPlanDuSite(Manifeste m, List<EcranNav> systeme) {
  final mods = accModules(m);
  final sections = [
    for (final d in m.domaines)
      if (mods.any((x) => x.domaine == d.nom))
        AccPlanSection(d.nom, d.icone, [for (final x in mods.where((x) => x.domaine == d.nom)) AccPlanModule(x.label, x.code, x.icone, x.ecrans)]),
  ];
  return AccPlan(sections, systeme, mods.fold(0, (n, x) => n + x.ecrans.length));
}

/// Les pages hors navigation (`N.STANDALONE`) : les écrans autonomes du manifeste, plus les deux écrans d'aide (module SUP, hors ruban, atteints par le
/// menu profil). Dans l'ordre du manifeste.
List<EcranNav> accEcransSysteme(Manifeste m) =>
    [for (final e in m.tousLesEcrans) if (e.standalone || e.module == 'SUP') e];

/// Les écrans servis SANS COQUE par le poste : sans barre, sans ruban, sans page standard. Les écrans d'accès, les pages d'erreur, le plan du site et la
/// page publique d'enquête. Les autres écrans « autonomes » du manifeste (pages de saisie, pages-renvoi) gardent la coque : elles sont atteintes depuis
/// un registre, avec les droits de ce registre.
const Set<String> accEcransPleinEcran = {
  'index',
  'auth-forgot',
  'auth-reset',
  'auth-2fa',
  'auth-lock',
  'error-404',
  'error-403',
  'plan-du-site',
  'enquete-publique',
};

/// Les pages PUBLIQUES : elles ne reçoivent ni session, ni navigation, ni manifeste. Une page d'enquête qui afficherait la coquille de l'application serait
/// une porte — on la tend à des inconnus.
const Set<String> accEcransPublics = {'enquete-publique'};
