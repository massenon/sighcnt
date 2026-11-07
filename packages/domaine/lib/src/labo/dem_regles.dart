/// Demandes d'analyses (M5) — les règles de `m5-demandes`, `m5-prelevement`, `m5-demandes-maternite` et `m5-demandes-hospitalisation`, extraites de
/// `prototype_html/assets/js/modules/m5-laboratoire.js` et de `PR.codeAnalyse` (parcours.js), rejouées sur des vecteurs tirés des écrans RÉELS
/// pilotés dans Chrome (`prototype_html/build/vecteurs-demandes.js`). Tout est préfixé `dem` : le barrel du domaine ne tolère aucune collision.
library;

import '../format/format_fr.dart';
import '../referentiels/regles.dart';
import '../stock/delivrance.dart' show referenceSuivante;

typedef FicheDem = Map<String, Object?>;

/// Vérité JavaScript d'une valeur de fiche (`undefined`, `null`, `false`, `0` et `''` sont faux).
bool _vrai(Object? v) =>
    v != null && v != false && v != 0 && v != '' && !(v is double && v.isNaN);

/// `new Date(x)` côté JS : l'heure LOCALE du poste, `null` si illisible.
DateTime? _date(Object? v) {
  if (v is DateTime) return v.toLocal();
  final d = DateTime.tryParse('${v ?? ''}'.trim());
  return d?.toLocal();
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le code d'analyse unique NNNNN-AAAA et la référence LAB-NNNNN
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `PR.codeAnalyse(date)` — fabrique UNIQUE du code d'analyse (série annuelle `NNNNN-AAAA`, comme les pièces certifiantes) : le plus grand rang déjà
/// écrit POUR L'ANNÉE de la demande, plus un. [demandes] est le registre ENTIER (archivées comprises : un rang archivé reste attribué).
/// Une date absente ou illisible retombe sur l'année de [maintenant]. Un code qui n'a pas exactement la forme `\d{5}-\d{4}` est ignoré.
String demCodeAnalyse(Object? date, Iterable<FicheDem> demandes,
    {required DateTime maintenant}) {
  final d = _vrai(date) ? _date(date) : maintenant;
  final annee = '${(d ?? maintenant).year}';
  var max = 0;
  final re = RegExp(r'^(\d{5})-(\d{4})$');
  for (final x in demandes) {
    final m = re.firstMatch('${x['codeAnalyse'] ?? ''}');
    if (m != null && m.group(2) == annee) {
      final rang = int.parse(m.group(1)!);
      if (rang > max) max = rang;
    }
  }
  return '${(max + 1).toString().padLeft(5, '0')}-$annee';
}

/// `C.referenceSuivante('LAB-', 5, demandes)` — la référence de la demande suit le REGISTRE, jamais un compteur de page (écart E142 : `C.nextRef`
/// repartait à 1 à chaque chargement et émettait un `LAB-00001` déjà attribué).
String demReferenceSuivante(Iterable<FicheDem> demandes) =>
    referenceSuivante('LAB-', 5, demandes);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le circuit du prélèvement
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `reglee(r)` de `m5-prelevement` : une demande est réglée tant que rien ne la bloque. Le parcours pose `bloqueParPaiement` (l'encaissement le
/// lève) ; l'ancien test ne lisait que `bloquee`, champ qui n'existe nulle part, et tenait toute demande pour réglée (écart E140).
bool demReglee(FicheDem r) =>
    !_vrai(r['bloquee']) &&
    !_vrai(r['bloqueParPaiement']) &&
    r['statutPaiement'] != 'impaye';

/// Onglet « À prélever » : rien n'a été prélevé et le résultat n'est pas rendu. Les demandes impayées y figurent (visibles, non exécutables).
List<FicheDem> demAPrelever(Iterable<FicheDem> actives) => [
      for (final r in actives)
        if (!_vrai(r['preleveLe']) && !resultatRendu(r['etatAnalyse'] as String?)) r
    ];

/// Onglet « À transmettre » : prélevé, pas encore remis au laboratoire. Aucun filtre sur l'état de résultat (écart E148, porté tel quel).
List<FicheDem> demPreleves(Iterable<FicheDem> actives) => [
      for (final r in actives)
        if (_vrai(r['preleveLe']) && !_vrai(r['recuLaboLe'])) r
    ];

/// Onglet « Reçus au laboratoire » : reçu et résultat non rendu — on interroge le référentiel (`resultatRendu`), on ne compare pas de chaînes
/// (une analyse rectifiée est rendue et ne doit pas revenir dans la file de travail).
List<FicheDem> demRecus(Iterable<FicheDem> actives) => [
      for (final r in actives)
        if (_vrai(r['recuLaboLe']) && !resultatRendu(r['etatAnalyse'] as String?)) r
    ];

/// Les quatre indicateurs de `m5-prelevement`.
class DemKpisPrelevement {
  const DemKpisPrelevement(
      {required this.aPrelever,
      required this.attenteReglement,
      required this.aTransmettre,
      required this.recus});
  final int aPrelever;
  final int attenteReglement;
  final int aTransmettre;
  final int recus;
}

DemKpisPrelevement demKpisPrelevement(Iterable<FicheDem> actives) {
  final attente = demAPrelever(actives);
  final bloquees = attente.where((r) => !demReglee(r)).length;
  return DemKpisPrelevement(
      aPrelever: attente.length - bloquees,
      attenteReglement: bloquees,
      aTransmettre: demPreleves(actives).length,
      recus: demRecus(actives).length);
}

/// Le patch écrit par « Prélèvement effectué ». `preleveLe` est l'INSTANT du clic (l'heure saisie est gardée telle quelle à côté, écart E147) ;
/// `etatAnalyse` ne change jamais : la maquette compare à `'attente'`, un état qui n'existe pas (écart E141).
FicheDem demPatchPrelevement(FicheDem saisie,
    {required FicheDem demande, required DateTime maintenant}) {
  return {
    ...saisie,
    'preleveLe': _instant(maintenant),
    'etatAnalyse':
        demande['etatAnalyse'] == 'attente' ? 'preleve' : demande['etatAnalyse'],
  };
}

/// Le patch écrit par « Transmettre » : l'échantillon est remis au laboratoire avec son bon ; le laboratoire peut enfin saisir (et pas avant).
FicheDem demPatchTransmission(
        {required DateTime maintenant, required String utilisateur}) =>
    {
      'recuLaboLe': _instant(maintenant),
      'recuPar': utilisateur,
      'etatAnalyse': 'en_cours',
    };

/// `toISOString()` : UTC, millisecondes.
String _instant(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
        d.millisecondsSinceEpoch,
        isUtc: true)
    .toIso8601String();

/// Ce que fait « Prendre en charge » sur la file des prélèvements (m5-demandes) : les demandes de l'ordonnance encore `en_attente` passent
/// `en_cours` — sans passer par le prélèvement (écart E146) ; celles que la caisse a déjà débloquées (`attente_prelevement`) ne bougent pas, et la
/// tâche est pourtant close. Rend les identifiants à mettre à jour et le NOMBRE annoncé (toutes les demandes de l'ordonnance).
({List<Object?> aMettreAJour, int annonce}) demPriseEnCharge(
    Iterable<FicheDem> demandes, Object? ordonnanceId) {
  final siennes = [
    for (final d in demandes)
      if (d['ordonnanceId'] == ordonnanceId) d
  ];
  return (
    aMettreAJour: [
      for (final d in siennes)
        if (d['etatAnalyse'] == 'en_attente') d['id']
    ],
    annonce: siennes.length
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Vues par service demandeur
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Vue « Demandes — maternité » : le service se lit dans le secteur ET dans le libellé du service (écart E145 : le jeu écrit « Maternité » là où la
/// fiche du service écrit l'identifiant `maternite`).
bool demServiceMaternite(FicheDem r) =>
    RegExp('MATERN', caseSensitive: false).hasMatch('${r['secteurDemandeur'] ?? ''}') ||
    RegExp('MATERN', caseSensitive: false).hasMatch('${r['serviceDemandeur'] ?? ''}');

/// Vue « Demandes — hospitalisation » : patient hospitalisé ou mis en observation.
bool demServiceHospitalisation(FicheDem r) =>
    r['hospitalise'] == true ||
    RegExp('HOSPI|OBSERVATION', caseSensitive: false)
        .hasMatch('${r['secteurDemandeur'] ?? ''}');

class DemKpisService {
  const DemKpisService(
      {required this.demandes,
      required this.attenteReglement,
      required this.aPreleverTransmettre,
      required this.rendues});
  final int demandes;
  final int attenteReglement;
  final int aPreleverTransmettre;
  final int rendues;
}

/// Les quatre indicateurs d'une vue par service. « En attente de règlement » lit l'ÉTAT `en_attente`, pas le champ de blocage (porté tel quel).
DemKpisService demKpisService(List<FicheDem> lignes) => DemKpisService(
    demandes: lignes.length,
    attenteReglement: lignes.where((r) => r['etatAnalyse'] == 'en_attente').length,
    aPreleverTransmettre: lignes
        .where((r) => const ['attente_prelevement', 'preleve'].contains(r['etatAnalyse']))
        .length,
    rendues: lignes.where((r) => resultatRendu(r['etatAnalyse'] as String?)).length);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Création d'une demande (formulaire « Nouveau » de m5-demandes)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `beforeSave` : le refus qui NOMME ce qui manque — sans identité, le résultat ne peut être ni remis ni retrouvé.
String? demRefusSaisie(FicheDem saisie) {
  bool plein(String k) => '${saisie[k] ?? ''}'.trim().isNotEmpty;
  if (!_vrai(saisie['patientCode']) && !(plein('nom') && plein('prenom'))) {
    return 'Sélectionner un patient du répertoire, ou renseigner le nom ET les prénoms du patient adressé de l’extérieur.';
  }
  return null;
}

/// `PR.dossierExterne` (fabrique du dossier d'un patient adressé de l'extérieur), pour la saisie du laboratoire. Le code suit `C.codePatient`
/// (900 + effectif du répertoire, année de la demande). L'âge DÉCLARÉ est daté du jour de la déclaration. [prescripteur] est gardé tel quel comme
/// « prescripteur extérieur » (écart E144 : le prescripteur interne choisi y est recopié).
FicheDem demDossierExterne(FicheDem v,
    {required Object? date, required int effectifRepertoire, required DateTime maintenant}) {
  final d = _date(date) ?? maintenant;
  final declare = !_vrai(v['dateNaissance']) &&
      v['age'] != null &&
      '${v['age']}' != '';
  num? age() {
    final n = num.tryParse('${v['age']}');
    return n;
  }

  return {
    'code': codePatient(900 + effectifRepertoire, d.year),
    'nom': '${v['nom']}'.toUpperCase(),
    'prenom': v['prenom'],
    'sexe': _vrai(v['sexe']) ? v['sexe'] : 'M',
    'dateNaissance': _vrai(v['dateNaissance']) ? v['dateNaissance'] : null,
    'age': declare ? age() : null,
    'ageReferenceLe': declare ? iso(d) : null,
    'telephone': _vrai(v['telephone']) ? v['telephone'] : null,
    'adresse': _vrai(v['residence']) ? v['residence'] : null,
    'quartier': _vrai(v['residence']) ? v['residence'] : null,
    'dateCreation': iso(d),
    'externe': true,
    'origineDossier': _vrai(v['origineDossier'])
        ? v['origineDossier']
        : 'Patient externe — accueil',
    'prescripteurExterieur': _vrai(v['prescripteur']) ? v['prescripteur'] : null,
    'assure': false,
    'assureur': null,
    'tauxPriseEnCharge': 0,
  };
}

const _clesIdentite = [
  'nom',
  'prenom',
  'sexe',
  'dateNaissance',
  'naissanceConnue',
  'age',
  'telephone',
  'residence'
];

/// `transformerDemande(v)` : la fiche à enregistrer depuis la saisie du formulaire.
///  * le dossier choisi l'emporte ; sans dossier mais avec un nom, le dossier de l'externe est ouvert par [creerPatient] (qui l'écrit au répertoire
///    et rend la fiche, identifiant compris) ;
///  * les champs d'identité ne sont pas gardés sur la demande ;
///  * l'analyse (désignation, catégorie, échantillon, délai, tarif) est reprise du catalogue ;
///  * la référence suit le registre, le code d'analyse vient de [demCodeAnalyse] ; [existante] (modification) garde les deux.
FicheDem demPreparerDemande({
  required FicheDem saisie,
  required FicheDem? patient,
  required FicheDem? analyse,
  required Iterable<FicheDem> demandes,
  required FicheDem Function(FicheDem dossier) creerPatient,
  required int effectifRepertoire,
  required DateTime maintenant,
  FicheDem? existante,
}) {
  final v = {...saisie};
  var p = patient;
  if (p == null && '${v['nom'] ?? ''}'.trim().isNotEmpty) {
    p = creerPatient(demDossierExterne({
      ...v,
      'origineDossier': 'Patient externe — laboratoire',
    },
        date: _vrai(v['dateHeure']) ? v['dateHeure'] : _instant(maintenant),
        effectifRepertoire: effectifRepertoire,
        maintenant: maintenant));
    v['patientCode'] = p['code'];
    v['origineDemande'] = 'externe';
  }
  for (final k in _clesIdentite) {
    v.remove(k);
  }
  if (p != null) {
    v['patientId'] = p['id'];
    v['patient'] = '${p['nom']} ${p['prenom']}';
  }
  if (analyse != null) {
    v['analyse'] = analyse['designation'];
    v['categorie'] = analyse['categorie'];
    v['echantillon'] = analyse['echantillon'];
    v['delai'] = analyse['delai'];
    v['prix'] = analyse['prix'];
  }
  // À la MODIFICATION, la référence et le code déjà attribués sont conservés (le formulaire ne les porte pas : écart E149).
  if (!_vrai(v['reference'])) {
    v['reference'] = _vrai(existante?['reference'])
        ? existante!['reference']
        : demReferenceSuivante(demandes);
  }
  if (!_vrai(v['codeAnalyse'])) {
    v['codeAnalyse'] = _vrai(existante?['codeAnalyse'])
        ? existante!['codeAnalyse']
        : demCodeAnalyse(v['dateHeure'], demandes, maintenant: maintenant);
  }
  return v;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Libellés
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Origine de la demande, telle que le tableau l'écrit (texte exporté / recherché).
String demOrigineLibelle(FicheDem r) {
  switch (r['origine']) {
    case 'ordonnance':
      return 'Ordonnance';
    case 'service':
      return 'Fiche de service';
    case 'accueil-externe':
      return 'Accueil — externe';
    default:
      return 'Manuelle';
  }
}

/// Sections du bulletin (`L.SECTIONS`) : identifiant → libellé.
const demSections = {
  'hematologie': 'Hématologie',
  'serologie': 'Sérologie',
  'parasitologie': 'Parasitologie',
  'biochimie': 'Biochimie',
  'bacteriologie': 'Bactériologie',
  'hormonologie': 'Hormonologie',
};

String _norm(Object? x) => '${x ?? ''}'
    .toUpperCase()
    .replaceAll(RegExp('[ÉÈÊË]'), 'E')
    .replaceAll(RegExp('[ÀÂÄ]'), 'A')
    .replaceAll(RegExp('[ÎÏ]'), 'I')
    .replaceAll(RegExp('[ÔÖ]'), 'O')
    .replaceAll(RegExp('[ÛÜÙ]'), 'U')
    .replaceAll(RegExp('[^A-Z0-9]'), '');

/// `codeExamenDeStatique(r)` : l'examen du catalogue de laboratoire qui répond à la désignation de la demande (égalité ou préfixe, accents et
/// ponctuation neutralisés). Sert la colonne « Section » du bon d'analyse.
FicheDem? demExamenDe(FicheDem r, Iterable<FicheDem> examens) {
  final cible = _norm(r['analyse']);
  for (final e in examens) {
    final d = _norm(e['designation']);
    if (e['code'] == r['examenCode'] || d == cible || d.startsWith(cible)) {
      return e;
    }
  }
  return null;
}

/// `C.ageTexte(rec)` : « 45 ans », ou « 45 ans (âge déclaré) » quand aucune date de naissance ne l'établit ; « — » sans rien.
String demAgeTexte(FicheDem? rec, {required DateTime maintenant}) {
  if (rec == null) return '—';
  int? a;
  if (_vrai(rec['dateNaissance'])) {
    final n = _date(rec['dateNaissance']);
    if (n != null) {
      a = maintenant.year - n.year;
      if (maintenant.month < n.month ||
          (maintenant.month == n.month && maintenant.day < n.day)) a -= 1;
    }
  } else if (rec['age'] != null && '${rec['age']}' != '') {
    final n = int.tryParse('${rec['age']}'.trim());
    if (n != null && n >= 0) {
      a = n;
      final ref = _date(rec['ageReferenceLe']);
      if (ref != null) {
        final ecoule = (maintenant.difference(ref).inHours / 24 / 365.25).floor();
        a = n + (ecoule > 0 ? ecoule : 0);
      }
    }
  }
  if (a == null) return '—';
  final declare = !_vrai(rec['dateNaissance']) &&
      rec['age'] != null &&
      '${rec['age']}' != '';
  return '$a an${a > 1 ? 's' : ''}${declare ? ' (âge déclaré)' : ''}';
}
