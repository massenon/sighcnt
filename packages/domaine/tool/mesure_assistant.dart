/// MESURE de la compréhension de l'assistant (lot AST-0). Un outil de mesure, jamais livré au poste : aucun réseau, aucun modèle, aucune dépendance nouvelle.
///
///   dart run tool/mesure_assistant.dart                       rapport complet (Markdown et JSON) dans ./rapport-assistant
///   dart run tool/mesure_assistant.dart --sortie <dossier>    où écrire le rapport
///   dart run tool/mesure_assistant.dart --tableau             écrit le bloc engendré du tableau de couverture sur la sortie standard
///   dart run tool/mesure_assistant.dart --droits <fichier>    (re)engendre les vecteurs de droits depuis rbac.json
library;

import 'dart:convert';
import 'dart:io';

import 'src/assistant_comprehension.dart';
import 'src/assistant_mesure.dart';

Map<String, Object?> _json(String chemin) => (jsonDecode(File(chemin).readAsStringSync()) as Map).cast<String, Object?>();

void main(List<String> args) {
  String? valeur(String nom) {
    final i = args.indexWhere((a) => a == '--$nom');
    if (i >= 0 && i + 1 < args.length) return args[i + 1];
    final p = args.where((a) => a.startsWith('--$nom=')).firstOrNull;
    return p?.substring(nom.length + 3);
  }

  final catChemin = valeur('catalogue') ?? 'test/vecteurs/assistant_catalogue.json';
  final qChemin = valeur('questions') ?? 'test/vecteurs/assistant_questions.json';
  final rbacChemin = valeur('rbac') ?? '../rbac/data/rbac.json';
  final catJson = _json(catChemin);
  final cat = CatalogueAssistant(catJson);
  final rbac = _json(rbacChemin);
  final questions = [for (final q in (_json(qChemin)['questions'] as List)) (q as Map).cast<String, Object?>()];

  if (args.contains('--tableau')) {
    stdout.write(tableauCouverture(catJson, rbac, cat));
    return;
  }
  if (valeur('droits') != null) {
    File(valeur('droits')!).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(vecteursDroits(rbac, catJson, cat)));
    stdout.writeln('Vecteurs de droits écrits : ${valeur('droits')}');
    return;
  }

  final moteur = ReconnaisseurAssistant(cat);
  final m = mesurer(questions, moteur);
  final temps = mesurerTemps(questions, moteur, repetitions: int.tryParse(valeur('repetitions') ?? '') ?? 50);
  final matrice = matriceDroits(rbac, catJson, cat);
  final rapport = rapportMarkdown(m, temps, cat, catJson, rbac, matrice, questions);
  final sortie = Directory(valeur('sortie') ?? 'rapport-assistant')..createSync(recursive: true);
  File('${sortie.path}/rapport-assistant.md').writeAsStringSync(rapport);
  File('${sortie.path}/rapport-assistant.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'global': m.global, 'reglage': m.reglage, 'controle': m.controle, 'inventees': m.inventees,
    'tempsMoyenUs': temps.moyenneUs, 'tempsPireUs': temps.pireUs,
    'echecs': [for (final e in m.echecs) {'n': e.$1['n'], 'question': e.$1['question'], 'raison': e.$2.raison}],
    'reconnaissances': [for (var i = 0; i < questions.length; i++) {'n': questions[i]['n'], ...m.reconnaissances[i].toJson()}],
  }));
  stdout.writeln(rapport);
}

/// Les vecteurs de droits : une ligne par intention et par profil type, tirés de rbac.json.
Map<String, Object?> vecteursDroits(Map<String, Object?> rbac, Map<String, Object?> catJson, CatalogueAssistant cat) => {
      '_doc': 'ENGENDRÉ par `dart run tool/mesure_assistant.dart --droits` depuis packages/rbac/data/rbac.json et assistant_catalogue.json : ne pas éditer. Pour chaque intention, les écrans de lecture (un parmi) et, par profil type, le droit de lecture. Une intention sans écran est ouverte à tout profil (le geste « utiliser l\'assistant » est à créer).',
      'profils': catJson['profils'],
      'matrice': matriceDroits(rbac, catJson, cat),
    };

String rapportMarkdown(ResultatMesure m, ({double moyenneUs, int pireUs, String pireQuestion}) temps, CatalogueAssistant cat, Map<String, Object?> catJson, Map<String, Object?> rbac,
    List<Map<String, Object?>> matrice, List<Map<String, Object?>> questions) {
  final b = StringBuffer();
  final ids = cat.intentions.keys.toList()..sort();
  b.writeln('# Mesure de la reconnaissance de l\'assistant (lot AST-0)');
  b.writeln();
  b.writeln('Date de référence de la reconnaissance : ${cat.aujourdhui}. Questions : ${questions.length} (proposées par la Direction, NON collectées sur le terrain). Aucun modèle, aucun réseau.');
  b.writeln();
  b.writeln('## Taux de bonne intention');
  b.writeln();
  b.writeln('| Jeu | Questions | Réussies | Taux |');
  b.writeln('|---|---|---|---|');
  for (final (nom, f) in <(String, bool Function(Map<String, Object?>))>[
    ('Global', (q) => true),
    ('Réglage (n impair)', (q) => jeuDe(q['n'] as int) == 'reglage'),
    ('Contrôle (n pair)', (q) => jeuDe(q['n'] as int) == 'controle'),
    ('Lecture (75)', (q) => q['limite'] != true),
    ('Cas limites (25)', (q) => q['limite'] == true),
  ]) {
    b.writeln('| $nom | ${m.compte(f)} | ${m.compte(f, seulementOk: true)} | ${pct(m.taux(f))} |');
  }
  b.writeln();
  b.writeln('Réponses inventées (valeur de réponse produite, paramètre non lu dans la question, intention hors catalogue) : **${m.inventees}**.');
  b.writeln();
  b.writeln('## Par intention');
  b.writeln();
  b.writeln('| Intention | Réussies | Questions | Taux |');
  b.writeln('|---|---|---|---|');
  final pi = m.parIntention(ids);
  for (final id in ids) {
    final (ok, tot) = pi[id]!;
    b.writeln('| $id ${cat.intentions[id]!['libelle']} | $ok | $tot | ${tot == 0 ? 'sans question' : pct(ok / tot)} |');
  }
  b.writeln();
  b.writeln('## Échecs (${m.echecs.length})');
  b.writeln();
  if (m.echecs.isEmpty) {
    b.writeln('Aucun.');
  } else {
    b.writeln('| N° | Jeu | Question | Raison |');
    b.writeln('|---|---|---|---|');
    for (final (q, j) in m.echecs) {
      b.writeln('| ${q['n']} | ${jeuDe(q['n'] as int)} | ${q['question']} | ${j.raison} |');
    }
  }
  b.writeln();
  final avecParams = m.questions.where((q) => q['parametres'] != null).length;
  b.writeln('## Paramètres typés');
  b.writeln();
  b.writeln('Vecteurs qui déclarent des paramètres : $avecParams ; exacts : ${avecParams - m.echecsParametres.length}.');
  for (final (q, j) in m.echecsParametres) {
    b.writeln('- ${q['n']} « ${q['question']} » : ${j.raisonParams}');
  }
  b.writeln();
  b.writeln('## Temps de reconnaissance');
  b.writeln();
  b.writeln('Moyenne : ${temps.moyenneUs.toStringAsFixed(1)} µs par question ; pire cas : ${temps.pireUs} µs (« ${temps.pireQuestion} »). Machine du conteneur, machine virtuelle Dart (JIT), pas un vieux poste.');
  b.writeln();
  b.writeln('## Robustesse (la même question abîmée)');
  b.writeln();
  b.writeln('| Variante | Réaction inchangée | Questions | Taux |');
  b.writeln('|---|---|---|---|');
  for (final e in mesurerRobustesse(questions, ReconnaisseurAssistant(cat)).entries) {
    b.writeln('| ${e.key} | ${e.value.$1} | ${e.value.$2} | ${pct(e.value.$1 / e.value.$2)} |');
  }
  b.writeln();
  b.writeln('## Droits');
  b.writeln();
  final sans = profilsSansDroit(matrice);
  b.writeln('Intentions où au moins un profil type n\'a pas le droit : ${sans.values.where((l) => l.isNotEmpty).length} sur ${ids.length}.');
  b.writeln();
  final inco = incoherencesAnnexe(questions, rbac, catJson, cat);
  b.writeln('Questions dont le profil type de l\'annexe n\'a PAS le droit de lecture d\'après rbac.json (${inco.length}) :');
  for (final i in inco) {
    b.writeln('- ${i['n']} « ${i['question']} » (profil ${i['profil']}, rôle ${i['roles']}, ${i['intention']}, écrans ${i['ecrans']})');
  }
  b.writeln();
  b.writeln('Droits manquants :');
  for (final d in droitsManquants(rbac, cat)) {
    b.writeln('- ${d['code']} (${d['intentions']}) : ${d['libelle']}');
  }
  return b.toString();
}
