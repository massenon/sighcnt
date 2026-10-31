import '../format/format_fr.dart';
import '../format/js.dart';
import '../format/recherche.dart';

/// ENQUÊTES & SATISFACTION (M13) — règles portées de `prototype_html/assets/js/modules/m13-administration.js` (phase 10, vague 54) et rejouées sur les
/// vecteurs de la maquette (`test/vecteurs/qualite.json`, engendrés par `prototype_html/build/vecteurs-qualite.js`).
///
/// Le principe KoboCollect, hors ligne : le QUESTIONNAIRE est une donnée, le formulaire de saisie NAÎT du modèle (`qualChampsDepuisModele`, UN seul
/// générateur pour les deux habillages — saisie au guichet et page publique). Symboles préfixés `qual` / `Qual`.
typedef QualFiche = Map<String, Object?>;

/// Les trois types de question d'un modèle (`TYPES_QUESTION`).
const qualTypesQuestion = [
  ('note', 'Note de 1 à 5'),
  ('choix', 'Choix dans une liste'),
  ('texte', 'Réponse libre'),
];

/// Canaux de recueil au guichet (`CANAUX_ENQUETE`).
const qualCanaux = ['Au guichet', 'À la sortie', 'Par téléphone'];

/// Canal des réponses venues d'un LIEN PARTAGÉ : posé par la page publique, jamais sélectionnable à la main.
const qualCanalPublic = 'Lien public';

/// Alphabet des jetons : ni `l` ni `1`, ni `o` ni `0` (on les lit à voix haute, on les recopie).
const qualAlphabetJeton = 'abcdefghijkmnopqrstuvwxyz23456789';

/// Un champ de formulaire engendré depuis une question (`champsDepuisModele`).
class QualChamp {
  const QualChamp(this.nom, this.libelle, this.type,
      {this.requis = false, this.pleine = false, this.options = const [], this.lignes = 3});
  final String nom;
  final String libelle;

  /// `select` ou `textarea`.
  final String type;
  final bool requis;

  /// Pleine largeur (page publique : un patient répond sur un téléphone, une seule colonne se lit mieux).
  final bool pleine;
  final List<String> options;
  final int lignes;
}

List<QualFiche> _fiches(Object? v) =>
    [for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()];

/// `champsDepuisModele(enq, opts)` : LE générateur. `pleineLargeur` ne touche que la mise en page — questions, types et contraintes sont identiques des
/// deux côtés.
List<QualChamp> qualChampsDepuisModele(Object? questions, {bool pleineLargeur = false}) => [
      for (final q in _fiches(questions))
        if (q['type'] == 'note')
          QualChamp('${q['code']}', '${q['libelle']} (1 à 5)', 'select',
              requis: true, pleine: pleineLargeur, options: const ['1', '2', '3', '4', '5'])
        else if (q['type'] == 'choix')
          QualChamp('${q['code']}', '${q['libelle']}', 'select',
              requis: true,
              pleine: pleineLargeur,
              options: [for (final o in (q['options'] as List? ?? const [])) '$o'])
        else
          QualChamp('${q['code']}', '${q['libelle']}', 'textarea', pleine: pleineLargeur, lignes: 2),
    ];

/// `enregistrerReponse` : une note saisie dans une liste (texte) s'écrit comme un nombre.
Map<String, Object?> qualNormaliserReponses(Object? questions, Map<String, Object?> valeurs) {
  final v = {...valeurs};
  for (final q in _fiches(questions)) {
    final code = '${q['code']}';
    if (q['type'] == 'note' && v[code] != null) v[code] = nombreOuZero(v[code]);
  }
  return v;
}

/// Une réponse prête à insérer (`enregistrerReponse`), quel que soit le canal. `jetonId` trace le LIEN (pour compter par lien et révoquer) : il
/// n'identifie pas le répondant.
QualFiche qualReponse(QualFiche enquete, Map<String, Object?> valeurs,
        {required DateTime aujourdhui, String? canal, required String saisiPar, Object? jetonId}) =>
    {
      'enqueteId': enquete['id'],
      'date': iso(aujourdhui),
      'canal': canal ?? qualCanaux.first,
      'reponses': qualNormaliserReponses(enquete['questions'], valeurs),
      'saisiPar': saisiPar,
      'jetonId': jetonId,
    };

bool _vrai(Object? v) => v != null && v != '' && v != false && v != 0;

/// `jetonOuvert(j, date)` : un jeton archivé, révoqué ou échu ne s'ouvre pas ; sans date d'expiration il reste ouvert.
bool qualJetonOuvert(QualFiche? j, {required String aLaDate}) {
  if (j == null || j['statut'] == 'archive') return false;
  if (_vrai(j['revoqueLe'])) return false;
  final e = j['expireLe'];
  return !_vrai(e) || '$e'.compareTo(aLaDate) >= 0;
}

/// `etatJeton(j)` : libellé et ton du badge.
({String libelle, String ton}) qualEtatJeton(QualFiche? j, {required String aLaDate}) {
  if (j == null) return (libelle: 'inconnu', ton: 'neutral');
  String fr(Object? d) {
    final x = DateTime.tryParse('$d');
    return x == null ? '' : dateFR(x);
  }

  if (_vrai(j['revoqueLe'])) return (libelle: 'Révoqué le ${fr(j['revoqueLe'])}', ton: 'danger');
  if (!qualJetonOuvert(j, aLaDate: aLaDate)) return (libelle: 'Expiré le ${fr(j['expireLe'])}', ton: 'warning');
  return (libelle: 'Ouvert', ton: 'success');
}

/// `jetonEnquete()` : 24 caractères tirés au hasard — l'adresse porte un JETON, JAMAIS l'identifiant de l'enquête (sans cela on énumère les enquêtes en
/// changeant un numéro). [alea] rend un entier dans `[0, n)`.
String qualGenererJeton(int Function(int n) alea) =>
    [for (var i = 0; i < 24; i++) qualAlphabetJeton[alea(qualAlphabetJeton.length)]].join();

/// La fiche d'un lien de partage (`ouvrirPartage`). `anonyme` : le choix « oui » / « non » du formulaire. Daté (`creeLe`, `expireLe`) et révocable.
QualFiche qualNouveauJeton(
        {required QualFiche enquete,
        required String jeton,
        required String anonyme,
        required String usage,
        required String expireLe,
        String? note,
        required DateTime aujourdhui,
        required String ouvertPar}) =>
    {
      'jeton': jeton,
      'enqueteId': enquete['id'],
      'enqueteTitre': enquete['titre'],
      'anonyme': anonyme == 'oui',
      'usage': usage,
      'creeLe': iso(aujourdhui),
      'expireLe': expireLe,
      'revoqueLe': null,
      'note': (note == null || note.isEmpty) ? null : note,
      'ouvertPar': ouvertPar,
    };

/// Le jeton correspondant au code de l'adresse, ou `null`. Un jeton archivé n'est pas écarté ici : c'est `qualJetonOuvert` qui le refuse.
QualFiche? qualJetonParCode(Iterable<QualFiche> jetons, String? code) {
  if (code == null || code.isEmpty) return null;
  for (final j in jetons) {
    if (j['jeton'] == code) return j;
  }
  return null;
}

/// Ce que la page publique montre pour un code : le modèle seulement si le jeton est ouvert ET l'enquête existe. Sinon `null` — UNE SEULE réponse pour
/// « jeton inconnu », « expiré » et « révoqué » : les distinguer renseignerait sur ce qui existe.
({QualFiche jeton, QualFiche enquete})? qualPagePublique(
    {required Iterable<QualFiche> jetons,
    required Iterable<QualFiche> enquetes,
    required String? code,
    required String aLaDate}) {
  final j = qualJetonParCode(jetons, code);
  if (j == null || !qualJetonOuvert(j, aLaDate: aLaDate)) return null;
  for (final e in enquetes) {
    if (e['id'] == j['enqueteId']) return (jeton: j, enquete: e);
  }
  return null;
}

/// Mention d'anonymat de la page publique (portée par le lien).
String qualMentionAnonymat(bool anonyme) => anonyme
    ? 'Questionnaire ANONYME : votre réponse n’est reliée ni à votre nom, ni à votre dossier. Aucune question ne porte sur votre santé.'
    : 'Questionnaire NOMINATIF : votre nom sera enregistré avec votre réponse. Aucune question ne porte sur votre santé.';

/// Qui a répondu, tel qu'il s'écrit au magasin : ANONYME VEUT DIRE ANONYME — ni nom, ni lien vers un dossier.
String qualSaisiPar({required bool anonyme, String? nom}) =>
    anonyme ? 'Réponse anonyme — lien partagé' : ((nom == null || nom.isEmpty) ? 'Répondant non nommé' : nom);

// --------------------------------------------------------------------------------------------------------------------------------------------
// Satisfaction : tout est CALCULÉ depuis les réponses recueillies
// --------------------------------------------------------------------------------------------------------------------------------------------

/// Les notes valides d'une question : `Number(valeur)` fini et strictement positif (une réponse vide ou non numérique ne compte pas).
List<double> _notes(List<QualFiche> reps, String code) {
  final out = <double>[];
  for (final x in reps) {
    final v = (x['reponses'] as Map?)?[code];
    final d = v is num ? v.toDouble() : (v == null || '$v'.trim().isEmpty ? 0.0 : double.tryParse('$v'.trim()));
    if (d != null && d.isFinite && d > 0) out.add(d);
  }
  return out;
}

double? _moyenne(List<double> vals) =>
    vals.isEmpty ? null : arrondiJs(vals.reduce((a, b) => a + b) / vals.length * 10) / 10;

class QualSatisfaction {
  const QualSatisfaction(
      {required this.reponses,
      required this.notes,
      required this.globale,
      required this.recommandent,
      required this.avecCommentaire,
      required this.commentaires});
  final int reponses;

  /// (code, libellé, moyenne ou `null`) pour chaque question de type note.
  final List<({String code, String libelle, double? moyenne})> notes;
  final double? globale;
  final int recommandent;
  final int avecCommentaire;

  /// Les huit derniers commentaires libres, du plus récent au plus ancien.
  final List<({String date, String texte})> commentaires;

  /// `C.pct(reco / reponses * 100)` ou « — » sans réponse.
  String get recommandation => reponses == 0 ? '—' : pourcent(recommandent / reponses * 100);
  String get noteGlobale => globale == null ? '—' : '${_nb(globale!)} / 5';
}

String _nb(double d) => d == d.truncateToDouble() ? '${d.truncate()}' : '$d';

/// `adm-satisfaction` : moyennes par question, recommandation, commentaires — recalculés à chaque affichage.
QualSatisfaction qualSatisfaction(QualFiche enquete, Iterable<QualFiche> reponsesActives) {
  final reps = [for (final r in reponsesActives) if (r['enqueteId'] == enquete['id']) r];
  final questions = _fiches(enquete['questions']);
  final notes = [
    for (final q in questions)
      if (q['type'] == 'note')
        (code: '${q['code']}', libelle: '${q['libelle']}', moyenne: _moyenne(_notes(reps, '${q['code']}')))
  ];
  final moyennes = [for (final n in notes) if (n.moyenne != null) n.moyenne!];
  final globale = moyennes.isEmpty ? null : _moyenne(moyennes);
  QualFiche? qReco;
  for (final q in questions) {
    if (q['code'] == 'Q_RECO' || RegExp('recommand', caseSensitive: false).hasMatch('${q['libelle']}')) {
      qReco = q;
      break;
    }
  }
  final motReco = RegExp(r'^(oui|plutôt oui)', caseSensitive: false);
  final reco = qReco == null
      ? 0
      : reps.where((x) => motReco.hasMatch('${(x['reponses'] as Map?)?[qReco!['code']] ?? ''}')).length;
  String texte(QualFiche x, QualFiche q) {
    final v = (x['reponses'] as Map?)?[q['code']];
    return v == null ? '' : '$v'.trim();
  }

  final libres = [for (final q in questions) if (q['type'] == 'texte') q];
  final avec = reps.where((x) => libres.any((q) => texte(x, q).isNotEmpty)).length;
  final commentaires = <({String date, String texte})>[];
  for (final x in reps) {
    for (final q in questions) {
      final t = texte(x, q);
      if (q['type'] == 'texte' && t.isNotEmpty) commentaires.add((date: '${x['date']}', texte: t));
    }
  }
  final tries = trierPar(commentaires, (c) => c.date).reversed.take(8).toList();
  return QualSatisfaction(
      reponses: reps.length,
      notes: notes,
      globale: globale,
      recommandent: reco,
      avecCommentaire: avec,
      commentaires: tries);
}

/// Le modèle de satisfaction d'un poste : la référence `ENQ-SAT`, sinon le premier actif.
QualFiche? qualEnqueteSatisfaction(Iterable<QualFiche> actifs) {
  final l = actifs.toList();
  for (final e in l) {
    if (e['reference'] == 'ENQ-SAT') return e;
  }
  return l.isEmpty ? null : l.first;
}
