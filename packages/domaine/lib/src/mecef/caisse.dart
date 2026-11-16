/// MECeF, lot MECEF-M (16/11/2026) : l'ÉTAT DE LA CAISSE, l'IMPRIMANTE DE CAISSE datée, et les deux gestes réservés qui règlent le mode et l'imprimante.
///
/// Port de `etatCaisse`, `imprimanteALaDate` et `definirImprimante` de la maquette (`prototype_html/assets/js/parcours.js`), rejoué sur les vecteurs
/// `mecef_m.json` tirés de la maquette pilotée (`prototype_html/build/vecteurs-mecef-m.js`).
///
/// Décisions de la Direction (09/11/2026 et suite) : AUCUN numéro simulé ; le mode (boîtier ou e-MECeF) est un réglage de clinique, défaut « boîtier », réglé par
/// le geste réservé [mecefGesteMode] ; l'imprimante de caisse (Xprinter XP-Q800, thermique 80 mm, liaison semée « à vérifier à l'arrière de l'appareil ») est un
/// réglage DATÉ, jamais une constante lue par un écran, réglé par le geste réservé [mecefGesteImprimante]. Aucun nom de rôle ici : le droit se lit de la fiche RBAC.
/// Un refus se nomme (code, motif, geste) ; « non calculable » n'est jamais zéro.
library;

import 'dart:convert';

import 'montants.dart' show RefusMecef;
import 'mode.dart' show mecefModes;

/// Le geste réservé qui règle le mode de facturation normalisée (clé de `rbac.json`, section `gestes`).
const String mecefGesteMode = 'regler_mode_mecef';

/// Le geste réservé qui règle l'imprimante de caisse.
const String mecefGesteImprimante = 'regler_imprimante_caisse';

/// Une liaison de l'imprimante : identifiant STOCKÉ, libellé, et si elle se choisit (la liaison semée « à vérifier » ne se choisit pas : on la constate, puis on règle USB ou Ethernet).
class LiaisonImprimante {
  const LiaisonImprimante(this.id, this.libelle, {required this.choisissable});
  final String id;
  final String libelle;
  final bool choisissable;
}

const List<LiaisonImprimante> liaisonsImprimante = [
  LiaisonImprimante('usb', 'USB', choisissable: true),
  LiaisonImprimante('ethernet', 'Ethernet (réseau)', choisissable: true),
  LiaisonImprimante('a_verifier', 'À vérifier à l’arrière de l’appareil', choisissable: false),
];

String libelleLiaisonImprimante(String id) => liaisonsImprimante.where((l) => l.id == id).map((l) => l.libelle).firstOrNull ?? id;

/// Une version datée du réglage de l'imprimante (jamais réécrite : on en pose une autre).
class VersionImprimante {
  const VersionImprimante({required this.dateEffet, required this.modele, required this.liaison, required this.nom, this.type = 'thermique', this.largeurMm = 80, this.motif});
  final String dateEffet; // AAAA-MM-JJ
  final String modele;
  final String type;
  final int largeurMm;
  final String liaison;
  final String nom;
  final String? motif;

  factory VersionImprimante.depuisJson(Map<String, Object?> j) => VersionImprimante(
        dateEffet: '${j['dateEffet']}'.substring(0, 10),
        modele: '${j['modele'] ?? imprimanteSemee.modele}',
        type: '${j['type'] ?? imprimanteSemee.type}',
        largeurMm: (j['largeurMm'] as num?)?.toInt() ?? imprimanteSemee.largeurMm,
        liaison: '${j['liaison'] ?? imprimanteSemee.liaison}',
        nom: '${j['nom'] ?? imprimanteSemee.nom}',
        motif: j['motif'] as String?,
      );

  Map<String, Object?> toJson() => {'dateEffet': dateEffet, 'modele': modele, 'type': type, 'largeurMm': largeurMm, 'liaison': liaison, 'nom': nom, 'motif': motif};
}

/// Le réglage tel qu'il se LIT à une date : la version en vigueur, ou le défaut SEMÉ (`source` = `defaut`).
class ImprimanteALaDate {
  const ImprimanteALaDate({required this.source, required this.dateEffet, required this.modele, required this.type, required this.largeurMm, required this.liaison, required this.nom});
  final String source; // 'defaut' | 'version'
  final String? dateEffet;
  final String modele;
  final String type;
  final int largeurMm;
  final String liaison;
  final String nom;
  String get liaisonLibelle => libelleLiaisonImprimante(liaison);
}

/// Le défaut SEMÉ : la Xprinter XP-Q800, thermique, rouleau 80 mm ; liaison à vérifier (la liaison réelle n'est pas connue : rien n'est supposé).
const ImprimanteALaDate imprimanteSemee = ImprimanteALaDate(
    source: 'defaut', dateEffet: null, modele: 'Xprinter XP-Q800', type: 'thermique', largeurMm: 80, liaison: 'a_verifier', nom: 'Imprimante de caisse');

/// La version en vigueur à [date] (AAAA-MM-JJ) : la dernière dont la date d'effet est atteinte, sinon le défaut semé.
ImprimanteALaDate imprimanteALaDate(Iterable<VersionImprimante> versions, String date) {
  final d = date.substring(0, 10);
  final vig = versions.where((v) => v.dateEffet.compareTo(d) <= 0).toList()..sort((a, b) => a.dateEffet.compareTo(b.dateEffet));
  if (vig.isEmpty) return imprimanteSemee;
  final v = vig.last;
  return ImprimanteALaDate(source: 'version', dateEffet: v.dateEffet, modele: v.modele, type: v.type, largeurMm: v.largeurMm, liaison: v.liaison, nom: v.nom);
}

/// Le contrôle d'un réglage, DANS L'ORDRE où la maquette le rend : réservé, fileul en lecture seule, motif obligatoire, date passée, nom requis, liaison inconnue.
/// `null` : recevable. [aDroit] = le geste réservé de la fiche RBAC pour le rôle courant ; [libelleRole] et [rolesQuiLeDetiennent] ne servent qu'à DIRE le refus.
RefusMecef? imprimanteControler({
  required bool aDroit,
  required bool fileul,
  required String? motif,
  required String dateEffet,
  required String aujourdhui,
  required String? nom,
  required String? liaison,
  String libelleRole = 'ce rôle',
  String rolesQuiLeDetiennent = 'aucun rôle ne le détient',
}) {
  if (!aDroit) {
    return RefusMecef(
        'IMPRIMANTE_RESERVE',
        'Régler l’imprimante de caisse est un droit réservé de la fiche du rôle : « $libelleRole » ne l’a pas.',
        'Demander le réglage à un rôle qui détient le droit « Régler l’imprimante de caisse » ($rolesQuiLeDetiennent).');
  }
  if (fileul) {
    return const RefusMecef('FILEUL_LECTURE_SEULE', 'Cette configuration est tenue par la mère ; modifiez-la sur le poste mère.',
        'Ouvrir le même écran sur le poste mère : la modification arrivera ici par la synchronisation.');
  }
  if ((motif ?? '').trim().length < 3) {
    return const RefusMecef('IMPRIMANTE_MOTIF_OBLIGATOIRE', 'Un motif est obligatoire pour régler l’imprimante de caisse.', 'Saisir le motif du réglage.');
  }
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateEffet)) {
    return const RefusMecef('IMPRIMANTE_DATE_ILLISIBLE', 'Date d’effet illisible : attendu AAAA-MM-JJ.', 'Choisir la date d’effet.');
  }
  if (dateEffet.compareTo(aujourdhui) < 0) {
    return RefusMecef('IMPRIMANTE_DATE_PASSEE',
        'La date d’effet ${_dateFr(dateEffet)} est passée : un réglage ne s’insère pas dans le passé (des tickets sont déjà imprimés).', 'Choisir aujourd’hui ou une date à venir.');
  }
  if ((nom ?? '').trim().isEmpty) {
    return const RefusMecef('IMPRIMANTE_NOM_REQUIS', 'Le nom de l’imprimante est obligatoire.', 'Saisir le nom sous lequel le poste connaît l’imprimante.');
  }
  final choix = liaisonsImprimante.where((l) => l.choisissable).toList();
  if (!choix.any((l) => l.id == liaison)) {
    return RefusMecef(
        'IMPRIMANTE_LIAISON_INCONNUE',
        'La liaison « ${liaison ?? ''} » n’est pas l’une des liaisons proposées (${choix.map((l) => l.libelle).join(', ')}).',
        'Choisir USB ou Ethernet, après avoir vérifié à l’arrière de l’appareil.');
  }
  return null;
}

String _dateFr(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';

/// Le paramètre du registre (famille `mecef`, versionné par date, défaut SEMÉ) qui porte le réglage de l'imprimante : une valeur JSON `{modele, type, largeurMm, liaison, nom}`.
/// Le réglage a son PROPRE écran (« Configuration fiscale », geste réservé) : la famille `mecef` ne se règle pas au panneau générique ([parFamillesReglageDedie]).
const String mecefCleImprimante = 'mecef.imprimante';

/// Le défaut semé du paramètre ([imprimanteSemee] en JSON ; une constante, car une définition du registre est constante : un test vérifie qu'il dit la même chose).
const String mecefImprimanteDefautJson = '{"modele":"Xprinter XP-Q800","type":"thermique","largeurMm":80,"liaison":"a_verifier","nom":"Imprimante de caisse"}';

/// La valeur JSON d'un réglage, pour le registre.
String imprimanteValeurJson({required String modele, required String type, required int largeurMm, required String liaison, required String nom}) =>
    jsonEncode({'modele': modele, 'type': type, 'largeurMm': largeurMm, 'liaison': liaison, 'nom': nom});

/// Une version du registre (valeur JSON + date d'effet + motif) lue comme [VersionImprimante] ; `null` si la valeur est illisible (une valeur illisible ne casse pas la caisse :
/// la lecture retombe sur la version précédente ou le défaut semé).
VersionImprimante? imprimanteVersionDepuisRegistre(String dateEffet, Object? valeur, {String? motif}) {
  try {
    final j = jsonDecode('$valeur');
    if (j is! Map) return null;
    return VersionImprimante.depuisJson({...j.cast<String, Object?>(), 'dateEffet': dateEffet, 'motif': motif});
  } on FormatException {
    return null;
  }
}

/// Le contrôle du changement de MODE, dans l'ordre de la maquette : mode inconnu, droit réservé, fileul en lecture seule. `null` : recevable.
RefusMecef? mecefModeControler({
  required Object? mode,
  required bool aDroit,
  required bool fileul,
  String libelleRole = 'ce rôle',
  String rolesQuiLeDetiennent = 'aucun rôle ne le détient',
}) {
  if (mode is! String || !mecefModes.contains(mode)) {
    return RefusMecef('MODE_INCONNU', 'Le mode « $mode » n’existe pas.', 'Choisir boîtier physique ou e-MECeF.');
  }
  if (!aDroit) {
    return RefusMecef(
        'MODE_RESERVE',
        'Régler le mode de facturation normalisée est un droit réservé de la fiche du rôle : « $libelleRole » ne l’a pas.',
        'Demander le changement à un rôle qui détient le droit « Régler le mode de facturation normalisée » ($rolesQuiLeDetiennent).');
  }
  if (fileul) {
    return const RefusMecef('FILEUL_LECTURE_SEULE', 'Cette configuration est tenue par la mère ; modifiez-la sur le poste mère.',
        'Ouvrir le même écran sur le poste mère : la modification arrivera ici par la synchronisation.');
  }
  return null;
}

/// Ce que l'état de la caisse lit d'une facture (les seuls champs qui comptent).
class PieceCaisse {
  const PieceCaisse({required this.numero, required this.proforma, required this.montantPaye, required this.statutPaiement, required this.statutMecef});
  final String numero;
  final bool proforma;
  final num? montantPaye;
  final String? statutPaiement;
  final String? statutMecef;

  factory PieceCaisse.depuisJson(Map<String, Object?> j) => PieceCaisse(
        numero: '${j['numero']}',
        proforma: j['proforma'] == true,
        montantPaye: j['montantPaye'] is num ? j['montantPaye'] as num : null,
        statutPaiement: j['statutPaiement'] as String?,
        statutMecef: j['statutMecef'] as String?,
      );
}

/// Ce que l'état de la caisse lit d'un avoir.
class AvoirCaisse {
  const AvoirCaisse({required this.reference, required this.montant, required this.statutMecef});
  final String? reference;
  final num? montant;
  final String? statutMecef;

  factory AvoirCaisse.depuisJson(Map<String, Object?> j) =>
      AvoirCaisse(reference: j['reference'] as String?, montant: j['montant'] is num ? j['montant'] as num : null, statutMecef: j['statutMecef'] as String?);
}

/// L'état de la caisse : [ventesMontant] et [avoirsMontant] valent `null` quand un montant ne se calcule pas (jamais zéro).
class EtatCaisse {
  const EtatCaisse({required this.ventes, required this.parEtat, required this.ventesIncalculables, required this.ventesMontant, required this.avoirs, required this.avoirsIncalculables, required this.avoirsMontant});
  final int ventes;
  final Map<String, int> parEtat;
  final int ventesIncalculables;
  final num? ventesMontant;
  final int avoirs;
  final int avoirsIncalculables;
  final num? avoirsMontant;
}

/// L'état canonique d'une pièce (`etatMecef` de la maquette) : les identifiants STOCKÉS ne se renomment pas.
String _etatCanonique(String? stocke) {
  switch (stocke) {
    case 'valide':
      return 'normalisee';
    case 'a_verifier':
      return 'a_verifier';
    case 'rejete':
      return 'refusee';
    case 'expiree':
      return 'expiree';
    default:
      return 'en_attente';
  }
}

/// Les ventes ENCAISSÉES (montant payé strictement positif ; à défaut de montant, le statut « soldée »), hors pro-forma, dont la facture n'est pas normalisée ; les avoirs
/// en attente de certification se comptent À PART. Un montant absent rend le total `null` : « Non calculable ».
EtatCaisse etatCaisse(Iterable<PieceCaisse> factures, Iterable<AvoirCaisse> avoirs) {
  final ventes = factures.where((f) {
    final encaissee = f.montantPaye != null ? f.montantPaye! > 0 : f.statutPaiement == 'soldee';
    return !f.proforma && encaissee && f.statutMecef != 'valide' && f.statutMecef != 'sans_objet';
  }).toList();
  final parEtat = <String, int>{};
  for (final f in ventes) {
    final e = _etatCanonique(f.statutMecef);
    parEtat[e] = (parEtat[e] ?? 0) + 1;
  }
  final inc = ventes.where((f) => f.montantPaye == null).length;
  final enAttente = avoirs.where((a) => a.statutMecef == 'en_attente').toList();
  final avInc = enAttente.where((a) => a.montant == null).length;
  return EtatCaisse(
    ventes: ventes.length,
    parEtat: parEtat,
    ventesIncalculables: inc,
    ventesMontant: ventes.isEmpty ? 0 : (inc > 0 ? null : ventes.fold<num>(0, (t, f) => t + f.montantPaye!)),
    avoirs: enAttente.length,
    avoirsIncalculables: avInc,
    avoirsMontant: enAttente.isEmpty ? 0 : (avInc > 0 ? null : enAttente.fold<num>(0, (t, a) => t + a.montant!)),
  );
}
