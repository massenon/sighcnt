/// M10 (C) — badges du personnel, événements et participations, assurance du personnel, planning rotatif sécurité & entretien.
/// Symboles préfixés `rhc` / `Rhc`. Source : `prototype_html/assets/js/modules/m10-rh.js` (vague 54, vagues 20-21), `parcours.js` (fabrique des badges) ;
/// vecteurs : `test/vecteurs/rhc.json` (engendrés par `prototype_html/build/vecteurs-rh-c.js`, écrans montés dans Chrome à l'horloge du 30/10/2026 10 h).
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart' show trierPar;
import '../referentiels/periodes.dart' show ajouterJours;
import '../referentiels/regles.dart' show joursEntre;
import 'rhb_regles.dart';

typedef FicheRhc = Map<String, Object?>;

/// `String(x)` du JavaScript : une valeur absente s'écrit « undefined » (la maquette concatène sans garde, on le reprend pour la parité).
String _js(Object? v) => v == null ? 'undefined' : '$v';

bool _vrai(Object? v) => v != null && v != false && v != 0 && v != '';

// ---------------------------------------------------------------------------------------------------------------------
// BADGES (vague 54) — le badge est une PIÈCE IMPRIMÉE de M10 ; il se RETIRE, il ne se supprime pas.
// ---------------------------------------------------------------------------------------------------------------------

class RhcEtatBadge {
  const RhcEtatBadge(this.id, this.label, this.ton, this.actif);
  final String id, label, ton;
  final bool actif;
}

const rhcEtatsBadge = <RhcEtatBadge>[
  RhcEtatBadge('a_editer', 'À éditer', 'warning', true),
  RhcEtatBadge('edite', 'Édité', 'info', true),
  RhcEtatBadge('remis', 'Remis à l’agent', 'success', true),
  RhcEtatBadge('perdu', 'Perdu / volé', 'danger', false),
  RhcEtatBadge('retire', 'Retiré', 'neutral', false),
];

/// `etatBadge(id)` : un état inconnu se lit « actif », sous son identifiant.
RhcEtatBadge rhcEtatBadge(Object? id) {
  for (final e in rhcEtatsBadge) {
    if (e.id == id) return e;
  }
  return RhcEtatBadge('$id', '$id', 'neutral', true);
}

const rhcMotifsRetrait = ['Perte', 'Vol', 'Détérioration', 'Départ de l’agent', 'Réédition — remplacement', 'Erreur de saisie'];

/// Le retrait « perte » ou « vol » classe le badge « perdu / volé » ; tout autre motif, « retiré ».
String rhcEtatDeRetrait(Object? motif) => RegExp('perte|vol', caseSensitive: false).hasMatch('$motif') ? 'perdu' : 'retire';

/// Durée de validité d'attente, en mois — LA DIRECTION N'A PAS ARRÊTÉ (aucun document de cadrage ne la fixe).
const rhcDureeValiditeMois = 24;

/// Les QUATRE décisions qui appartiennent à la Direction : valeur d'attente explicitement marquée, jamais présentée comme arrêtée.
class RhcDecisionBadge {
  const RhcDecisionBadge(this.libelle, this.valeur, this.unite, this.motif);
  final String libelle, valeur, motif;
  final String? unite;
  String get valeurAffichee => valeur + (unite != null ? ' $unite' : '');
}

const rhcDecisionsBadge = <RhcDecisionBadge>[
  RhcDecisionBadge(
      'Durée de validité d’un badge',
      '24',
      'mois',
      'Valeur d’attente — aucun document de cadrage ne fixe de durée. Deux ans est l’usage courant ; la Direction peut retenir la durée du contrat, ou une validité sans terme pour les titulaires.'),
  RhcDecisionBadge('Format du numéro de série', 'BDG-NNNNN-AAAA', null,
      'Proposé par analogie avec les pièces certifiantes, dont la série repart à 1 chaque année comme le registre papier. À confirmer : la clinique tient peut-être déjà une numérotation de badges qu’il faudrait reprendre.'),
  RhcDecisionBadge('Mentions portées au verso', 'Restitution, perte, propriété de la clinique', null,
      'Rédigées faute de texte remis. Elles engagent la clinique vis-à-vis du porteur : c’est à la Direction de les arrêter.'),
  RhcDecisionBadge('Le badge sert-il de support de POINTAGE ?', 'Non — décision non prise', null,
      'S’il pointe, il se relie au registre des présences (M10) et la conception change : lecteur à l’entrée, horodatage, traitement des oublis de badge. Tant que ce n’est pas tranché, le badge IDENTIFIE seulement.'),
];

/// Date « AAAA-MM-JJ » (ou instant) → jour local ; `null` si illisible.
DateTime? _jour(Object? d) {
  if (d is DateTime) return d;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${d ?? ''}');
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

/// `expirationDepuis(dateEmission)` : la date d'expiration déduite de la durée d'attente — jamais saisie deux fois. `setMonth` du JavaScript :
/// un jour qui n'existe pas dans le mois d'arrivée déborde sur le suivant (29 février → 1ᵉʳ mars).
String rhcExpirationDepuis(Object? dateEmission) {
  final d = _jour(dateEmission) ?? DateTime.now();
  return iso(DateTime(d.year, d.month + rhcDureeValiditeMois, d.day));
}

/// `expire(b, aLaDate)` : échue STRICTEMENT avant la date ; un badge qui expire aujourd'hui est encore valide.
bool rhcExpire(FicheRhc b, DateTime aLaDate) {
  final e = b['expireLe'];
  return _vrai(e) && '$e'.compareTo(iso(aLaDate)) < 0;
}

class RhcVerdict {
  const RhcVerdict(this.code, this.label, this.ton, this.message);
  final String code, label, ton, message;
}

/// `verdictBadge(b, aLaDate)` — le badge présenté au contrôle : VALIDE, EXPIRÉ, RETIRÉ ou INCONNU (plus « non remis »). « Inconnu » n'est pas
/// « retiré » : le premier signale un badge qui ne vient pas d'ici, le second un badge que la clinique a repris. Le retrait PRIME sur l'expiration.
RhcVerdict rhcVerdictBadge(FicheRhc? b, DateTime aLaDate) {
  if (b == null) {
    return const RhcVerdict('inconnu', 'BADGE INCONNU', 'danger',
        'Aucun badge ne porte ce numéro. Ce n’est pas un badge de la clinique, ou il a été émis avant la mise en service du registre.');
  }
  final etat = rhcEtatBadge(b['etat']);
  if (!etat.actif) {
    final motif = _vrai(b['motifRetrait']) ? ' — ${b['motifRetrait']}' : '';
    final le = _vrai(b['retireLe']) ? ', le ${_dateFR(b['retireLe'])}' : '';
    return RhcVerdict('retire', 'BADGE RETIRÉ', 'danger', 'Badge ${etat.label.toLowerCase()}$motif$le. Il ne vaut plus identification.');
  }
  if (rhcExpire(b, aLaDate)) {
    return RhcVerdict('expire', 'BADGE EXPIRÉ', 'warning',
        'Validité échue le ${_dateFR(b['expireLe'])}. L’agent est connu du registre : le badge est à rééditer, ce n’est pas un refus d’identité.');
  }
  if (b['etat'] == 'a_editer') {
    return const RhcVerdict('non_remis', 'BADGE NON REMIS', 'warning',
        'Le badge est enregistré mais n’a pas encore été édité ni remis à l’agent : une carte qui circule alors qu’elle n’a pas été remise doit être signalée à la RH.');
  }
  return RhcVerdict('valide', 'BADGE VALIDE', 'success', 'Valable jusqu’au ${_vrai(b['expireLe']) ? _dateFR(b['expireLe']) : '—'}.');
}

String _dateFR(Object? d) {
  final j = _jour(d);
  return j == null ? '$d' : dateFR(j);
}

/// `PR.numeroBadge(date)` — UNE fabrique, comme le code d'analyse : série ANNUELLE `BDG-NNNNN-AAAA`, le rang suivant le plus grand déjà écrit POUR CETTE
/// ANNÉE, archivés compris (un badge retiré garde son numéro). [badges] : TOUTES les fiches de la collection.
String rhcNumeroBadge(Iterable<FicheRhc> badges, Object? date, DateTime maintenant) {
  final annee = (_jour(date) ?? maintenant).year.toString();
  var max = 0;
  for (final b in badges) {
    final m = RegExp(r'^BDG-(\d{5})-(\d{4})$').firstMatch('${b['numero'] ?? ''}');
    if (m != null && m.group(2) == annee) {
      final n = int.parse(m.group(1)!);
      if (n > max) max = n;
    }
  }
  return 'BDG-${(max + 1).toString().padLeft(5, '0')}-$annee';
}

/// `PR.badgeQR(badge)` — LA décision la plus importante du module : le QR ne porte que le MATRICULE et le NUMÉRO DE SÉRIE. Ni nom, ni fonction, ni
/// téléphone, ni URL : un badge se photographie dans un couloir, le logiciel est hors ligne, et la vérification doit passer par le LOGICIEL.
String rhcBadgeQR(FicheRhc badge) => 'CNT-BDG|MAT:${_vrai(badge['matricule']) ? badge['matricule'] : ''}|SER:${_vrai(badge['numero']) ? badge['numero'] : ''}';

/// `PR.lireBadgeQR(texte)` — la charge utile complète (badge scanné) ou le seul numéro (saisi à la main : refuser la saisie rendrait le contrôle impossible
/// le jour où le QR est abîmé). Texte vide → `null`.
({String? matricule, String numero, String source})? rhcLireBadgeQR(Object? texte) {
  final t = '${texte ?? ''}'.trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^CNT-BDG\|MAT:([^|]*)\|SER:(.+)$').firstMatch(t);
  if (m != null) return (matricule: m.group(1)!.isEmpty ? null : m.group(1), numero: m.group(2)!.trim(), source: 'qr');
  return (matricule: null, numero: t, source: 'saisie');
}

/// Le badge porté par ce numéro (comparaison sans casse), archivés compris : la fiche d'un badge perdu est celle qu'on ressort.
FicheRhc? rhcBadgeDuNumero(Iterable<FicheRhc> badges, String numero) {
  final n = numero.toUpperCase();
  for (final b in badges) {
    if ('${b['numero'] ?? ''}'.toUpperCase() == n) return b;
  }
  return null;
}

/// Le badge EN COURS d'un agent (un seul badge valide par agent : deux cartes valides pour la même personne, c'est une carte qui circule sans titulaire).
FicheRhc? rhcBadgeEnCours(Iterable<FicheRhc> badgesActifs, Object? personnelId) {
  for (final b in badgesActifs) {
    if (b['personnelId'] == personnelId && rhcEtatBadge(b['etat']).actif) return b;
  }
  return null;
}

/// Les agents SANS badge en cours (effectif rapproché du registre), dans l'ordre de la collection du personnel.
List<FicheRhc> rhcAgentsSansBadge(List<FicheRhc> personnel, List<FicheRhc> badgesEnCours) =>
    [for (final a in personnel) if (!badgesEnCours.any((b) => b['personnelId'] == a['id'])) a];

/// Les badges dont la validité échoit dans les 60 jours (`C.daysBetween(AUJ, expireLe) <= 60`, l'expiré compris).
List<FicheRhc> rhcBadgesExpirant(List<FicheRhc> enCours, DateTime auj) => [
      for (final b in enCours)
        if (_vrai(b['expireLe']) && joursEntre(auj, _utc(b['expireLe'])) <= 60) b
    ];

DateTime _utc(Object? d) {
  final j = _jour(d) ?? DateTime.now();
  return DateTime.utc(j.year, j.month, j.day);
}

/// Le gabarit tel que l'impression l'attend (`modeleNormalise`) : zones en objet, mentions en lignes. UN seul point de conversion.
class RhcModele {
  const RhcModele(this.id, this.libelle, this.orientation, this.zones, this.mentionsVerso);
  final String? id, libelle;
  final String orientation;
  final Map<String, bool> zones;
  final List<String> mentionsVerso;
  bool get portrait => orientation == 'portrait';
}

const rhcZonesBadge = ['photo', 'nom', 'fonction', 'service', 'qr'];

/// `modeleParDefaut()` : le modèle marqué « par défaut », à défaut le premier.
FicheRhc? rhcModeleParDefaut(List<FicheRhc> actifs) {
  for (final m in actifs) {
    if (_vrai(m['defaut'])) return m;
  }
  return actifs.isEmpty ? null : actifs.first;
}

RhcModele rhcModeleNormalise(FicheRhc? m, List<FicheRhc> actifs) {
  final mod = m ?? rhcModeleParDefaut(actifs);
  final zonesBrutes = mod?['zones'];
  final z = <String, bool>{
    for (final k in rhcZonesBadge) k: zonesBrutes == null || (zonesBrutes is List && zonesBrutes.contains(k)),
  };
  return RhcModele(
    mod?['id'] as String?,
    mod?['libelle'] as String?,
    _vrai(mod?['orientation']) ? '${mod!['orientation']}' : 'paysage',
    z,
    [for (final l in '${mod?['mentionsVerso'] ?? ''}'.split('\n')) if (l.trim().isNotEmpty) l.trim()],
  );
}

// ---------------------------------------------------------------------------------------------------------------------
// ÉVÉNEMENTS DU PERSONNEL ET PARTICIPATIONS (vague 21) — ces sommes TRANSITENT : ni recette ni charge.
// ---------------------------------------------------------------------------------------------------------------------

const rhcMontantStandard = 1000;
const rhcSourceEvenements = 'Usage de la clinique — participation du personnel aux événements';

class RhcNatureEvenement {
  const RhcNatureEvenement(this.id, this.label, this.ton);
  final String id, label, ton;
}

const rhcNaturesEvenement = <RhcNatureEvenement>[
  RhcNatureEvenement('mariage', 'Mariage', 'success'),
  RhcNatureEvenement('naissance', 'Naissance', 'info'),
  RhcNatureEvenement('deces', 'Décès', 'neutral'),
  RhcNatureEvenement('bapteme', 'Baptême', 'info'),
  RhcNatureEvenement('retraite', 'Départ à la retraite', 'warning'),
  RhcNatureEvenement('maladie', 'Soutien maladie', 'danger'),
  RhcNatureEvenement('autre', 'Autre événement', 'navy'),
];

String rhcNatureEvenement(Object? id) {
  for (final n in rhcNaturesEvenement) {
    if (n.id == id) return n.label;
  }
  return '$id';
}

class RhcModeReglement {
  const RhcModeReglement(this.id, this.label, this.hint);
  final String id, label, hint;
}

const rhcModesReglement = <RhcModeReglement>[
  RhcModeReglement('salaire', 'Imputation sur salaire', 'Retenue portée au bulletin du mois choisi'),
  RhcModeReglement('comptant', 'Paiement au comptant', 'Versement à la caisse, avec reçu'),
];

/// Libellé court d'un mode (états imprimés, graphiques).
String rhcModeCourt(Object? mode) => mode == 'salaire' ? 'Sur salaire' : 'Comptant';

/// `engendrerParticipations(evenement)` — UNE participation par agent actif, HORS BÉNÉFICIAIRE : c'est ce geste unique qui fait tenir le module. Par défaut
/// TOUT le personnel cotise ; une sélection restreint la liste — mais une sélection VIDE retombe sur tout le personnel (repli du moteur). Appelée à la
/// création de l'événement et seulement là : régénérer écraserait les règlements déjà encaissés. [agents] : le personnel actif, dans l'ordre de la collection.
List<FicheRhc> rhcParticipationsAEngendrer(FicheRhc evenement, List<FicheRhc> agents) {
  var vises = [for (final e in agents) if (e['id'] != evenement['beneficiaireId']) e];
  final choisis = evenement['participants'];
  if (evenement['portee'] == 'selection' && choisis is List && choisis.isNotEmpty) {
    vises = [for (final e in vises) if (choisis.contains(e['id'])) e];
  }
  return [
    for (final e in vises)
      {
        'evenementId': evenement['id'],
        'evenementLibelle': evenement['libelle'],
        'nature': evenement['nature'],
        'dateEvenement': evenement['date'],
        'employeId': e['id'],
        'agent': e['nomComplet'],
        'matricule': e['matricule'],
        'fonction': e['fonction'],
        'service': e['service'],
        'montant': evenement['montantParAgent'],
        'mode': evenement['modeParDefaut'] ?? 'salaire',
        'periodeRetenue': evenement['periodePaiement'],
        'statutPaiement': 'du',
      }
  ];
}

/// `Number(v) || standard` : un montant vide OU NUL retombe sur le montant standard (zéro n'est pas un montant de participation).
int rhcMontantParAgent(Object? saisi, [Object? repli]) {
  final n = nombreOuZero(saisi);
  if (n != 0) return n.round();
  final r = repli == null ? rhcMontantStandard : nombreOuZero(repli);
  return r == 0 ? 0 : r.round();
}

class RhcBilan {
  const RhcBilan(this.attendus, this.attendu, this.regles, this.collecte, this.salaire, this.comptant);
  final int attendus, regles, salaire, comptant;
  final num attendu, collecte;
  num get reste => attendu - collecte;
  int get taux => attendu != 0 ? arrondiJs(collecte / attendu * 100).toInt() : 0;
}

num _somme(Iterable<FicheRhc> l, String cle) => l.fold<num>(0, (a, x) => a + nombreOuZero(x[cle]));
num rhcSomme(Iterable<FicheRhc> l, String cle) => _somme(l, cle);

/// `bilanEvenement(evenement)` à partir des participations ACTIVES de l'événement : réglée = `statutPaiement === 'paye'`.
RhcBilan rhcBilanEvenement(List<FicheRhc> parts) {
  final regles = [for (final x in parts) if (x['statutPaiement'] == 'paye') x];
  return RhcBilan(parts.length, _somme(parts, 'montant'), regles.length, _somme(regles, 'montant'), parts.where((x) => x['mode'] == 'salaire').length,
      parts.where((x) => x['mode'] == 'comptant').length);
}

/// Les participations qui suivent une modification d'événement : SEULES les non réglées changent (ce qui a été encaissé l'a été au montant annoncé sur le
/// reçu). Rend les correctifs à appliquer, par identifiant.
Map<Object?, FicheRhc> rhcCorrectifsParticipations(List<FicheRhc> parts, FicheRhc evenement) => {
      for (final x in parts)
        if (x['statutPaiement'] != 'paye')
          x['id']: {'montant': evenement['montantParAgent'], 'periodeRetenue': evenement['periodePaiement'], 'evenementLibelle': evenement['libelle'], 'nature': evenement['nature']}
    };

// ---------------------------------------------------------------------------------------------------------------------
// ASSURANCE DU PERSONNEL (vague 20) — prise en charge à 100 %, ni recette ni créance ; AUCUNE saisie.
// ---------------------------------------------------------------------------------------------------------------------

const rhcPeriodesAssurance = <(String, String)>[
  ('', 'Depuis toujours'),
  ('30', '30 derniers jours'),
  ('90', 'Trois derniers mois'),
  ('180', 'Six derniers mois'),
  ('365', 'Douze derniers mois'),
];

String rhcLibellePeriodeAssurance(String valeur) => rhcPeriodesAssurance.firstWhere((p) => p.$1 == valeur).$2;

/// `borneMin()` : la plus ancienne date retenue (ISO), ou `null` depuis toujours.
String? rhcBorneMin(String valeur, DateTime auj) {
  final j = nombreOuZero(valeur).toInt();
  return j != 0 ? iso(ajouterJours(auj, -j)) : null;
}

/// `prestations()` — consultations reçues, analyses prescrites et hospitalisations des agents ayant un dossier patient. Lues dans les collections d'ORIGINE,
/// jamais recopiées : une copie divergerait du dossier au premier changement. [prixAnalyse] : `D.ANALYSES` (code ou libellé → prix), pour les demandes sans
/// montant propre. Plus récent d'abord (`C.sortBy(date).reverse()`).
List<FicheRhc> rhcPrestations({
  required List<FicheRhc> patients,
  required List<FicheRhc> consultations,
  required List<FicheRhc> analyses,
  required List<FicheRhc> admissions,
  String? min,
  String fonction = '',
  num? Function(Object? analyse) prixAnalyse = _aucunPrix,
  String Function(Object? analyse)? libelleAnalyse,
}) {
  final agents = [for (final p in patients) if (_vrai(p['personnelId'])) p];
  final parPatient = {for (final p in agents) p['id']: p};
  final out = <FicheRhc>[];
  FicheRhc base(FicheRhc pat, String id, String d, String nature, String detail, Object? praticien, num valeur) => {
        'id': id,
        'date': d,
        'agent': '${_js(pat['nom'])} ${_js(pat['prenom'])}',
        'patientId': pat['id'],
        'code': pat['code'],
        'matricule': pat['matricule'],
        'fonction': pat['fonctionAgent'],
        'fonctionLabel': rhbFonctionLabel(pat['fonctionAgent']),
        'nature': nature,
        'detail': detail,
        'praticien': praticien,
        'valeur': valeur,
      };
  String jour10(Object? v) {
    final s = '${v ?? ''}';
    return s.length > 10 ? s.substring(0, 10) : s;
  }

  for (final c in consultations) {
    final pat = parPatient[c['patientId']];
    if (pat == null) continue;
    final d = jour10(c['date']);
    if (min != null && d.compareTo(min) < 0) continue;
    out.add(base(pat, '${c['id']}', d, 'Consultation', '${_js(c['type'])} — ${_vrai(c['motif']) ? c['motif'] : ''}', c['medecin'], nombreOuZero(c['tarif'])));
  }
  for (final a in analyses) {
    final pat = parPatient[a['patientId']];
    if (pat == null) continue;
    final d = jour10(_vrai(a['date']) ? a['date'] : (_vrai(a['dateDemande']) ? a['dateDemande'] : a['dateHeure']));
    if (d.isEmpty || (min != null && d.compareTo(min) < 0)) continue;
    final nom = _vrai(a['analyse']) ? '${a['analyse']}' : (libelleAnalyse?.call(a['analyse']) ?? 'Analyse');
    final propre = nombreOuZero(a['montant']) != 0 ? nombreOuZero(a['montant']) : nombreOuZero(a['prix']);
    final valeur = propre != 0 ? propre : nombreOuZero(prixAnalyse(a['analyse']));
    out.add(base(pat, '${a['id']}', d, 'Analyse', nom, _vrai(a['prescripteur']) ? a['prescripteur'] : (_vrai(a['demandeur']) ? a['demandeur'] : '—'), valeur));
  }
  for (final h in admissions) {
    final pat = parPatient[h['patientId']];
    if (pat == null) continue;
    final d = jour10(h['dateEntree']);
    if (d.isEmpty || (min != null && d.compareTo(min) < 0)) continue;
    out.add(base(pat, '${h['id']}', d, 'Hospitalisation', '${_vrai(h['service']) ? h['service'] : ''} — lit ${_vrai(h['lit']) ? h['lit'] : '—'}',
        _vrai(h['medecin']) ? h['medecin'] : '—', nombreOuZero(h['montant'])));
  }
  final filtrees = fonction.isEmpty ? out : [for (final x in out) if (x['fonction'] == fonction) x];
  return trierPar(filtrees, (x) => x['date']).reversed.toList();
}

num? _aucunPrix(Object? _) => null;

/// Les agents les plus pris en charge (valeur décroissante, ex æquo dans l'ordre d'apparition), dix au plus.
List<(String, num)> rhcDixPremiersAgents(List<FicheRhc> rows) {
  final parAgent = <String, num>{};
  for (final r in rows) {
    parAgent['${r['agent']}'] = (parAgent['${r['agent']}'] ?? 0) + nombreOuZero(r['valeur']);
  }
  final noms = trierPar(parAgent.keys.toList(), (k) => parAgent[k], descendant: true);
  return [for (final k in noms.take(10)) (k, parAgent[k]!)];
}

// ---------------------------------------------------------------------------------------------------------------------
// SÉCURITÉ & ENTRETIEN — planning rotatif
// ---------------------------------------------------------------------------------------------------------------------

/// Les vacations proposées à l'affectation sont celles de la FONCTION : un agent de sécurité ne se voit pas proposer « entretien général », et
/// réciproquement — c'est ce qui distingue les deux rotations. Dans l'ordre du référentiel des types de planning.
List<RhbTypePlanning> rhcTypesRotation(Object? fonction) {
  final ids = fonction == 'securite' ? const ['garde', 'soiree', 'repos24'] : const ['permanence', 'entretien_general', 'incineration', 'repos24'];
  return [for (final t in rhbTypesPlanning) if (ids.contains(t.id)) t];
}

/// `« G — Garde 24h (08:00 → 08:00) »`.
String rhcLibelleRotation(RhbTypePlanning t) => '${t.court} — ${t.label}${t.debut != null ? ' (${t.debut} → ${t.fin})' : ''}';

/// Le repos de 24 h qui suit une garde reste opposable ici comme au planning général : une garde la VEILLE interdit la suivante. Rend le jour (ISO) de la
/// garde en cause, ou `null`. (La rotation ne connaît que `garde` : ni `garde_hospi` ni le repos de 48 h, qui sont ceux du planning général.)
String? rhcIncompatibiliteRotation(List<FicheRhc> planningActif, {required Object? employeId, required DateTime jour, required String type}) {
  if (type != 'garde') return null;
  final veille = iso(ajouterJours(jour, -1));
  return planningActif.any((x) => x['employeId'] == employeId && x['date'] == veille && x['type'] == 'garde') ? veille : null;
}

/// Les agents de sécurité et d'entretien, dans l'ordre de la collection du personnel.
List<FicheRhc> rhcAgentsRotation(List<FicheRhc> personnelActif) => [for (final e in personnelActif) if (e['fonction'] == 'securite' || e['fonction'] == 'entretien') e];

/// Vacations TRAVAILLÉES de sécurité / entretien : les repos sont exclus (ils figurent à la rotation mais ne sont pas des postes tenus).
List<FicheRhc> rhcVacationsRotation(List<FicheRhc> planningActif) =>
    [for (final v in planningActif) if ((v['fonction'] == 'securite' || v['fonction'] == 'entretien') && !'${v['type']}'.startsWith('repos')) v];

/// `C.groupBy` : clés dans l'ordre d'apparition.
Map<String, List<FicheRhc>> rhcGrouper(Iterable<FicheRhc> rows, String Function(FicheRhc) cle) {
  final out = <String, List<FicheRhc>>{};
  for (final r in rows) {
    (out[cle(r)] ??= []).add(r);
  }
  return out;
}
