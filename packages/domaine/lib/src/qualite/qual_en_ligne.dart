/// SATISFACTION EN LIGNE (lot SAT, ADR-0009) : versions datées du questionnaire, points de collecte, charge publiée au relais, JUGEMENT d'une réponse ouverte par la mère
/// (15 refus nommés) et ANALYSE. Règles portées de `prototype_html/assets/js/modules/m13-administration.js` (bloc « LOT SAT ») et rejouées sur les vecteurs tirés de
/// l'écran réel (`build/vecteurs-sat.js` → `test/vecteurs/satisfaction_en_ligne.json`). Aucune donnée de santé, aucun nom : un questionnaire de satisfaction n'en demande pas.
library;

import '../fichiers/sha256.dart';
import '../format/format_fr.dart';
import '../format/js.dart';
import 'dart:convert';

import '../parametres/parametres.dart' show DefinitionParametre, TypeParametre;
import 'qual_enquetes.dart';

/// Le réglage de clinique qui ouvre la collecte en ligne (défaut SEMÉ : désactivée, comme la sauvegarde hors site : une surface publique ne s'ouvre pas sans geste).
const String qualCleEnLigne = 'satisfaction.enLigne';

/// Les points de collecte (paramètre de clinique, défaut semé : les sept points de la décision S2 du PRD). Format `code=Libellé`, séparés par `;`.
const String qualClePointsCollecte = 'satisfaction.pointsCollecte';

const List<({String code, String libelle})> qualPointsCollecteDefaut = [
  (code: 'accueil', libelle: 'Accueil'),
  (code: 'consultation', libelle: 'Consultation'),
  (code: 'laboratoire', libelle: 'Laboratoire'),
  (code: 'pharmacie', libelle: 'Pharmacie'),
  (code: 'maternite', libelle: 'Maternité'),
  (code: 'hospitalisation', libelle: 'Hospitalisation'),
  (code: 'sortie', libelle: 'Sortie'),
];

/// Le paramètre en texte (`code=Libellé;code=Libellé`) → les points ; un texte illisible ou vide retombe sur les sept points semés.
List<({String code, String libelle})> qualPointsDepuisParametre(Object? valeur) {
  final out = <({String code, String libelle})>[];
  for (final part in '${valeur ?? ''}'.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final code = part.substring(0, i).trim(), lib = part.substring(i + 1).trim();
    if (RegExp(r'^[a-z0-9_]{2,24}$').hasMatch(code) && lib.isNotEmpty && !out.any((p) => p.code == code)) out.add((code: code, libelle: lib));
  }
  return out.isEmpty ? qualPointsCollecteDefaut : out;
}

String qualPointsVersParametre(Iterable<({String code, String libelle})> points) => points.map((p) => '${p.code}=${p.libelle}').join(';');

/// Les réponses et les liens de la collecte en ligne ne vont JAMAIS vers un téléphone (RG-13) : un téléphone perdu n'emporte ni réponse, ni commentaire, ni lien de collecte.
const Set<String> qualCollectionsJamaisMobile = {'reponsesEnquetes', 'jetonsEnquete'};

/// Le code du refus d'un lot de tournée qui nomme l'une d'elles.
const String qualCodeInterditAuMobile = 'satisfaction_interdite_au_mobile';

/// Les limites de la collecte en ligne (ADR-0009) : mêmes valeurs que le relais.
const int qualLiensMax = 200;
const int qualTexteMax = 1000;

/// L'enveloppe d'une réponse ouverte est lue par [qualJugerReponseEnLigne] : 15 refus nommés, jamais une réponse écrite à demi.
const List<String> qualRefusEnLigne = [
  'format_inconnu',
  'identifiant_invalide',
  'champ_identite',
  'lien_inconnu',
  'lien_revoque',
  'lien_expire',
  'enquete_introuvable',
  'version_incoherente',
  'point_inconnu',
  'question_inconnue',
  'reponse_obligatoire_manquante',
  'note_hors_bornes',
  'choix_hors_liste',
  'texte_trop_long',
  'reponses_vides',
];

class QualRefus {
  const QualRefus(this.code, this.motif, this.geste);
  final String code, motif, geste;
  @override
  String toString() => '$code : $motif';
}

List<QualFiche> _l(Object? v) => [for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()];

// --------------------------------------------------------------------------------------------------------------------------------------------
// Versions datées du questionnaire
// --------------------------------------------------------------------------------------------------------------------------------------------

/// `versionsDe` : les versions d'une enquête ; sans `versions`, V1 = `questions`, en vigueur depuis la création.
List<QualFiche> qualVersionsDe(QualFiche enquete) {
  final vs = _l(enquete['versions']);
  if (vs.isNotEmpty) return vs;
  return [
    {'version': 'V1', 'effetLe': '${enquete['creeLe'] ?? '2000-01-01'}', 'questions': enquete['questions'] ?? const []}
  ];
}

/// `versionALaDate` : la dernière version dont l'effet est atteint à [date] (`AAAA-MM-JJ`) ; à défaut, la première.
QualFiche qualVersionALaDate(QualFiche enquete, String date) {
  final vs = [...qualVersionsDe(enquete)]..sort((a, b) => '${a['effetLe']}'.compareTo('${b['effetLe']}'));
  var choisie = vs.first;
  for (final v in vs) {
    if ('${v['effetLe']}'.compareTo(date) <= 0) choisie = v;
  }
  return choisie;
}

/// `ajouterVersion` : modifier le questionnaire AJOUTE une version (jamais une réécriture). `versions == null` et `refus == null` : rien ne change.
({List<QualFiche>? versions, QualRefus? refus}) qualAjouterVersion(QualFiche enquete, List<QualFiche> questions, String date) {
  final vs = qualVersionsDe(enquete);
  final derniere = qualVersionALaDate(enquete, '9999-12-31');
  if (jsonEncode(derniere['questions']) == jsonEncode(questions)) return (versions: null, refus: null);
  if (date.compareTo('${derniere['effetLe']}') < 0) {
    return (versions: null, refus: QualRefus('VERSION_ANTERIEURE', 'Une version prend effet après la dernière (${derniere['version']} du ${derniere['effetLe']}).', 'Choisir une date d’effet plus récente.'));
  }
  return (versions: [...vs, {'version': 'V${vs.length + 1}', 'effetLe': date, 'questions': questions}], refus: null);
}

// --------------------------------------------------------------------------------------------------------------------------------------------
// Analyse
// --------------------------------------------------------------------------------------------------------------------------------------------

class QualAnalyse {
  const QualAnalyse(
      {required this.reponses,
      required this.notes,
      required this.satisfaction,
      required this.recommandation,
      required this.parQuestion,
      required this.parMois,
      required this.parPoint});
  final int reponses, notes;

  /// Notes 4 ou 5 sur le total des notes valides ; `null` : NON CALCULABLE (jamais zéro).
  final double? satisfaction, recommandation;

  /// Le taux de réponse demande les passages comptés à l'accueil : non calculable tant qu'ils ne le sont pas.
  double? get tauxReponse => null;
  final List<({String code, String libelle, int n, double? moyenne, double? satisfaction})> parQuestion;
  final List<({String mois, int n, double? satisfaction})> parMois;
  final List<({String point, String libelle, int n, double? satisfaction})> parPoint;
}

double _a1(double x) => arrondiJs(x * 10) / 10;

List<({String q, double n})> _notesValides(Iterable<QualFiche> reps, Iterable<QualFiche> questions) {
  final out = <({String q, double n})>[];
  for (final r in reps) {
    for (final q in questions) {
      if (q['type'] != 'note') continue;
      final v = (r['reponses'] as Map?)?[q['code']];
      final n = v == null || '$v'.trim().isEmpty ? null : (v is num ? v.toDouble() : double.tryParse('$v'.trim()));
      if (n != null && n.isFinite && n >= 1 && n <= 5) out.add((q: '${q['code']}', n: n));
    }
  }
  return out;
}

double? _taux(List<({String q, double n})> notes) => notes.isEmpty ? null : _a1(notes.where((x) => x.n >= 4).length / notes.length * 100);

String _jour(Object? d) {
  final s = '${d ?? ''}';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

/// `analyseSatisfaction(enq, reponses, filtres)` : filtres `du`, `au` (jours inclus), `point`, `version`, `canal` ; tout est recalculé des réponses.
QualAnalyse qualAnalyse(QualFiche enquete, Iterable<QualFiche> reponses,
    {String du = '', String au = '', String point = '', String version = '', String canal = '', List<({String code, String libelle})> points = qualPointsCollecteDefaut}) {
  final reps = [
    for (final r in reponses)
      if (r['enqueteId'] == enquete['id'] &&
          (du.isEmpty || _jour(r['date']).compareTo(du) >= 0) &&
          (au.isEmpty || _jour(r['date']).compareTo(au) <= 0) &&
          (point.isEmpty || r['point'] == point) &&
          (version.isEmpty || '${r['version'] ?? 'V1'}' == version) &&
          (canal.isEmpty || r['canal'] == canal))
        r
  ];
  final toutes = <String, QualFiche>{};
  for (final v in qualVersionsDe(enquete)) {
    for (final q in _l(v['questions'])) {
      toutes.putIfAbsent('${q['code']}', () => q);
    }
  }
  final qs = toutes.values.toList();
  final notes = _notesValides(reps, qs);
  final parQuestion = [
    for (final q in qs)
      if (q['type'] == 'note')
        () {
          final ns = notes.where((x) => x.q == '${q['code']}').toList();
          return (
            code: '${q['code']}',
            libelle: '${q['libelle']}',
            n: ns.length,
            moyenne: ns.isEmpty ? null : _a1(ns.fold<double>(0, (a, x) => a + x.n) / ns.length),
            satisfaction: _taux(ns)
          );
        }()
  ];
  double? reco;
  QualFiche? qReco;
  for (final q in qs) {
    if (q['code'] == 'Q_RECO' || RegExp('recommand', caseSensitive: false).hasMatch('${q['libelle']}')) {
      qReco = q;
      break;
    }
  }
  if (qReco != null) {
    final rep = [for (final r in reps) if ('${(r['reponses'] as Map?)?[qReco['code']] ?? ''}'.trim().isNotEmpty) r];
    if (rep.isNotEmpty) {
      final oui = RegExp(r'^(oui|plutôt oui)', caseSensitive: false);
      reco = _a1(rep.where((r) => oui.hasMatch('${(r['reponses'] as Map)[qReco!['code']]}')).length / rep.length * 100);
    }
  }
  final parMoisM = <String, List<QualFiche>>{}, parPointM = <String, List<QualFiche>>{};
  for (final r in reps) {
    final d = '${r['date'] ?? ''}';
    (parMoisM[d.length >= 7 ? d.substring(0, 7) : d] ??= []).add(r);
    (parPointM['${r['point'] ?? ''}'] ??= []).add(r);
  }
  final ordre = [for (final p in points) p.code];
  final cles = parPointM.keys.toList()
    ..sort((a, b) {
      final ia = ordre.indexOf(a) < 0 ? 99 : ordre.indexOf(a), ib = ordre.indexOf(b) < 0 ? 99 : ordre.indexOf(b);
      return ia != ib ? ia - ib : a.compareTo(b);
    });
  return QualAnalyse(
    reponses: reps.length,
    notes: notes.length,
    satisfaction: _taux(notes),
    recommandation: reco,
    parQuestion: parQuestion,
    parMois: [for (final m in (parMoisM.keys.toList()..sort())) (mois: m, n: parMoisM[m]!.length, satisfaction: _taux(_notesValides(parMoisM[m]!, qs)))],
    parPoint: [
      for (final p in cles)
        (
          point: p,
          libelle: p.isEmpty ? 'Sans point' : points.where((x) => x.code == p).map((x) => x.libelle).followedBy([p]).first,
          n: parPointM[p]!.length,
          satisfaction: _taux(_notesValides(parPointM[p]!, qs))
        )
    ],
  );
}

/// « Non calculable » n'est pas zéro.
String qualPctOuNC(double? v) => v == null ? 'Non calculable' : pourcent(v);

// --------------------------------------------------------------------------------------------------------------------------------------------
// Publication au relais
// --------------------------------------------------------------------------------------------------------------------------------------------

/// L'empreinte d'un jeton (SHA-256 hexadécimal) : la SEULE forme sous laquelle le relais le connaît.
String qualEmpreinteJeton(String jeton) => sha256Octets(utf8.encode(jeton));

/// La charge publiée avec un lien : ce que la page publique affiche (aucune donnée de santé, aucun nom).
Map<String, Object?> qualCharge(QualFiche enquete, QualFiche jeton, {required String aLaDate, List<({String code, String libelle})> points = qualPointsCollecteDefaut}) {
  final v = qualVersionALaDate(enquete, aLaDate);
  final code = '${jeton['point'] ?? ''}';
  final libelle = points.where((p) => p.code == code).map((p) => p.libelle).followedBy([code]).first;
  return {
    'enquete': enquete['id'],
    'version': v['version'],
    'point': {'code': code, 'libelle': libelle},
    'titre': enquete['titre'],
    'intro': 'Merci de donner votre avis : cela prend moins d’une minute.',
    'questions': [
      for (final q in _l(v['questions']))
        {
          'code': q['code'],
          'type': q['type'],
          'libelle': q['libelle'],
          if (q['type'] == 'choix') 'options': [for (final o in (q['options'] as List? ?? const [])) '$o'],
          'obligatoire': q['type'] != 'texte',
        }
    ],
  };
}

int _finDeJourMs(String jour) => DateTime.parse('${jour}T23:59:59Z').millisecondsSinceEpoch;

/// Les liens ouverts « En ligne » à publier : au plus [qualLiensMax] (les plus récents d'abord) ; `ignores` compte ceux qui dépassent (alerte nommée, jamais silence).
({List<Map<String, Object?>> liens, int ignores}) qualLiensAPublier(
    {required Iterable<QualFiche> jetons, required Iterable<QualFiche> enquetes, required String aLaDate, List<({String code, String libelle})> points = qualPointsCollecteDefaut}) {
  final ouverts = [
    for (final j in jetons)
      if (j['enLigne'] == true && qualJetonOuvert(j, aLaDate: aLaDate)) j
  ]..sort((a, b) => '${b['creeLe']}'.compareTo('${a['creeLe']}'));
  final liens = <Map<String, Object?>>[];
  for (final j in ouverts) {
    if (liens.length >= qualLiensMax) break;
    final e = enquetes.where((x) => x['id'] == j['enqueteId'] && x['statut'] != 'archive').firstOrNull;
    if (e == null || '${j['jeton'] ?? ''}'.isEmpty) continue;
    liens.add({
      'empreinte': qualEmpreinteJeton('${j['jeton']}'),
      'charge': qualCharge(e, j, aLaDate: aLaDate, points: points),
      'expire': '${j['expireLe'] ?? ''}'.isEmpty ? null : _finDeJourMs(_jour(j['expireLe'])),
      'revoque': null,
    });
  }
  return (liens: liens, ignores: ouverts.length - liens.length);
}

// --------------------------------------------------------------------------------------------------------------------------------------------
// Jugement d'une réponse ouverte par la mère
// --------------------------------------------------------------------------------------------------------------------------------------------

final RegExp _cleIdentite = RegExp(r'(^|_)(nom|prenom|prénom|telephone|téléphone|tel|email|mail|courriel|dossier|patient|adresse|naissance|cnt|numero|numéro|identite|identité)', caseSensitive: false);

const _champsAdmis = {'id', 'enquete', 'version', 'point', 'langue', 'reponses'};

QualRefus _r(String code, String motif, String geste) => QualRefus(code, motif, geste);

/// Juge le clair d'une enveloppe ouverte. [idRelais] et [empreinteLien] sont ceux que le RELAIS a vus (la déclaration du navigateur n'attribue rien : n'importe qui peut chiffrer pour la
/// clé publique) ; [recuMs] est la date de réception au relais. Retourne la fiche `reponsesEnquetes` (identité `REPW-<id>`) ou un refus nommé.
({QualFiche? reponse, QualRefus? refus}) qualJugerReponseEnLigne({
  required Object? clair,
  required String idRelais,
  required String empreinteLien,
  required int recuMs,
  required Iterable<QualFiche> jetons,
  required Iterable<QualFiche> enquetes,
  List<({String code, String libelle})> points = qualPointsCollecteDefaut,
}) {
  ({QualFiche? reponse, QualRefus? refus}) non(QualRefus r) => (reponse: null, refus: r);
  if (clair is! Map || clair['reponses'] is! Map) return non(_r('format_inconnu', 'Le contenu n’a pas la forme d’une réponse de satisfaction.', 'Ignorer l’enveloppe : elle ne vient pas de la page publique.'));
  final c = clair.cast<String, Object?>();
  final rep = (c['reponses'] as Map).cast<String, Object?>();
  if (c.keys.any((k) => !_champsAdmis.contains(k) && !_cleIdentite.hasMatch(k))) {
    return non(_r('format_inconnu', 'Un champ inconnu accompagne la réponse.', 'Ignorer l’enveloppe.'));
  }
  if (c['id'] is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(c['id'] as String) || c['id'] != idRelais) {
    return non(_r('identifiant_invalide', 'L’identifiant de la réponse n’est pas celui du dépôt.', 'Ignorer l’enveloppe.'));
  }
  if (c.keys.any((k) => !_champsAdmis.contains(k)) || rep.keys.any(_cleIdentite.hasMatch)) {
    return non(_r('champ_identite', 'Un champ d’identité (nom, téléphone, dossier…) accompagne la réponse : une réponse de satisfaction est anonyme.', 'Refuser la réponse et ne rien conserver de ce champ.'));
  }
  final recuJour = iso(DateTime.fromMillisecondsSinceEpoch(recuMs, isUtc: true));
  QualFiche? jeton;
  for (final j in jetons) {
    if ('${j['jeton'] ?? ''}'.isNotEmpty && qualEmpreinteJeton('${j['jeton']}') == empreinteLien) jeton = j;
  }
  if (jeton == null) return non(_r('lien_inconnu', 'Le lien par lequel la réponse est venue n’existe pas.', 'Ignorer l’enveloppe.'));
  final revoque = '${jeton['revoqueLe'] ?? ''}';
  if (revoque.isNotEmpty && recuJour.compareTo(_jour(revoque)) > 0) return non(_r('lien_revoque', 'Le lien était révoqué à la réception.', 'Ignorer l’enveloppe.'));
  final expire = '${jeton['expireLe'] ?? ''}';
  if (expire.isNotEmpty && recuJour.compareTo(_jour(expire)) > 0) return non(_r('lien_expire', 'Le lien était expiré à la réception.', 'Ignorer l’enveloppe.'));
  QualFiche? enquete;
  for (final e in enquetes) {
    if (e['id'] == jeton['enqueteId'] && e['statut'] != 'archive') enquete = e;
  }
  if (enquete == null || (c['enquete'] != null && c['enquete'] != enquete['id'])) {
    return non(_r('enquete_introuvable', 'L’enquête du lien n’existe plus ou ne correspond pas.', 'Ignorer l’enveloppe.'));
  }
  QualFiche? version;
  for (final v in qualVersionsDe(enquete)) {
    if ('${v['version']}' == '${c['version']}' && '${v['effetLe']}'.compareTo(recuJour) <= 0) version = v;
  }
  if (version == null) return non(_r('version_incoherente', 'La version « ${c['version']} » du questionnaire n’existe pas ou n’avait pas pris effet.', 'Ignorer l’enveloppe.'));
  final pointLien = '${jeton['point'] ?? ''}';
  if (pointLien.isNotEmpty && (!points.any((p) => p.code == pointLien) || '${c['point'] ?? ''}' != pointLien)) {
    return non(_r('point_inconnu', 'Le point de collecte de la réponse n’est pas celui du lien.', 'Ignorer l’enveloppe.'));
  }
  if (rep.isEmpty) return non(_r('reponses_vides', 'Aucune réponse n’accompagne l’enveloppe.', 'Ignorer l’enveloppe.'));
  final questions = {for (final q in _l(version['questions'])) '${q['code']}': q};
  final propres = <String, Object?>{};
  for (final e in rep.entries) {
    final q = questions[e.key];
    if (q == null) return non(_r('question_inconnue', 'La question « ${e.key} » n’est pas dans la version ${version['version']}.', 'Ignorer l’enveloppe.'));
    final v = e.value;
    final vide = v == null || '$v'.trim().isEmpty;
    if (vide) continue;
    switch ('${q['type']}') {
      case 'note':
      case 'nps':
        final borne = q['type'] == 'note' ? (1, 5) : (0, 10);
        if (v is! num || v != v.truncate() || v < borne.$1 || v > borne.$2) {
          return non(_r('note_hors_bornes', 'La note de « ${q['libelle']} » doit être un entier de ${borne.$1} à ${borne.$2}.', 'Ignorer l’enveloppe.'));
        }
        propres[e.key] = v.toInt();
      case 'choix':
        final opts = [for (final o in (q['options'] as List? ?? const [])) '$o'];
        if (v is! String || !opts.contains(v)) return non(_r('choix_hors_liste', 'Le choix de « ${q['libelle']} » n’est pas dans la liste.', 'Ignorer l’enveloppe.'));
        propres[e.key] = v;
      default:
        if (v is! String || v.trim().length > qualTexteMax) return non(_r('texte_trop_long', 'Le commentaire dépasse $qualTexteMax caractères.', 'Ignorer l’enveloppe.'));
        propres[e.key] = v.trim();
    }
  }
  for (final q in questions.values) {
    if (q['type'] != 'texte' && q['obligatoire'] != false && !propres.containsKey('${q['code']}')) {
      return non(_r('reponse_obligatoire_manquante', 'La réponse à « ${q['libelle']} » manque.', 'Ignorer l’enveloppe.'));
    }
  }
  if (propres.isEmpty) return non(_r('reponses_vides', 'Aucune réponse n’accompagne l’enveloppe.', 'Ignorer l’enveloppe.'));
  return (
    reponse: {
      'id': 'REPW-${c['id']}',
      'statut': 'actif',
      'enqueteId': enquete['id'],
      'date': recuJour,
      'canal': qualCanalPublic,
      'version': version['version'],
      'point': pointLien.isEmpty ? null : pointLien,
      'langue': 'fr',
      'reponses': propres,
      'saisiPar': qualSaisiPar(anonyme: true),
      'jetonId': jeton['id'],
      'enLigne': true,
    },
    refus: null
  );
}


// --------------------------------------------------------------------------------------------------------------------------------------------
// Les paramètres de clinique de la satisfaction (famille `satisfaction`, jamais vers un téléphone, défauts SEMÉS, versionnés par date)
// --------------------------------------------------------------------------------------------------------------------------------------------

const List<DefinitionParametre> qualDefinitionsEnLigne = [
  DefinitionParametre(
    cle: qualCleEnLigne,
    famille: 'satisfaction',
    type: TypeParametre.choix,
    choix: ['non', 'oui'],
    libellesChoix: {'non': 'Désactivée : aucun lien n’est publié', 'oui': 'Activée : la mère publie les liens et relève les réponses'},
    defaut: 'non',
    libelle: 'Satisfaction en ligne (formulaire public)',
    aide: 'Ouvre la collecte par adresse personnalisée ou code QR (relais, ADR-0009). Désactivée par défaut : une surface publique ne s’ouvre pas sans geste. La mère publie alors la clé publique et les liens anonymes, relève les enveloppes chiffrées et les ouvre.',
    source: 'Proposition à valider (lot SAT, DECISIONS-A-VALIDER section AV) : la Direction a validé le principe (section AQ points 14 et 16)',
    branche: true,
    appliquePar: 'Lot SAT (satisfaction en ligne)',
  ),
  DefinitionParametre(
    cle: qualClePointsCollecte,
    famille: 'satisfaction',
    type: TypeParametre.texte,
    defaut: 'accueil=Accueil;consultation=Consultation;laboratoire=Laboratoire;pharmacie=Pharmacie;maternite=Maternité;hospitalisation=Hospitalisation;sortie=Sortie',
    libelle: 'Points de collecte de la satisfaction',
    aide: 'Un lien et une affiche par point : l’analyse compare les services. Format « code=Libellé » séparés par des points-virgules (code : minuscules, chiffres, tiret bas). Les sept points sont ceux de la décision S2 du PRD de la satisfaction (07/11/2026).',
    source: 'Décision S2 de la Direction du 07/11/2026 (PRD-SATISFACTION)',
    branche: true,
    appliquePar: 'Lot SAT (satisfaction en ligne)',
  ),
];
