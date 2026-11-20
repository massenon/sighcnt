/// LE BANC DE MESURE DE L'OCR (lot OCR-prep) : étant donné un dossier de scans et leur transcription de référence (un `.txt` de même nom à côté), mesure par moteur le taux de mots
/// corrects, le taux de caractères corrects, le temps par page, les mots perdus et les ACCENTS FRANÇAIS perdus.
///
/// AUCUN moteur n'est choisi ni fourni ici. Trois sortes de moteurs se branchent :
///  - les moteurs FACTICES (`factice-parfait`, `factice-sans-accents`, `factice-perd-mots`, `factice-bruit`) : ils rendent la transcription elle-même, déformée d'une façon connue ; ils
///    servent à PROUVER que la mesure est juste (un moteur parfait donne 100 %, un moteur qui supprime les accents le montre), jamais à juger un moteur ;
///  - un moteur par COMMANDE (`--commande "<ligne de commande>"`) : le jour où un moteur est installé sur le poste, sa ligne de commande se donne ici avec `{image}` et `{langue}` ; la sortie
///    standard est le texte lu. Aucune ligne de commande n'est fournie par défaut : le banc ne présume d'aucun moteur.
///  - tout moteur écrit en Dart qui implémente [MoteurOcr] (interface du domaine), passé à [mesurerDossier].
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';

/// Un scan à mesurer : le fichier et sa transcription de référence.
class ScanReference {
  ScanReference(this.fichier, this.octets, this.reference);
  final String fichier;
  final Uint8List octets;
  final String reference;
}

/// Ce que le dossier contient : les scans qui ont leur transcription, ceux qui n'en ont pas (nommés), les PDF (non mesurés, nommés).
class ContenuDossier {
  ContenuDossier(this.scans, this.sansTranscription, this.pdf);
  final List<ScanReference> scans;
  final List<String> sansTranscription;
  final List<String> pdf;
}

const _extensions = {'png', 'jpg', 'jpeg', 'webp'};

/// Lit le dossier : chaque image `x.png`, `x.jpg`, `x.jpeg` ou `x.webp` a sa transcription `x.txt`. Un PDF est nommé et NON mesuré : lire ses pages exige un rendeur de pages qu'aucun poste
/// n'a encore (il se mesure sur ses pages rendues en images).
ContenuDossier lireDossier(String dossier) {
  final d = Directory(dossier);
  if (!d.existsSync()) throw ArgumentError('le dossier « $dossier » n’existe pas');
  final scans = <ScanReference>[];
  final sans = <String>[];
  final pdf = <String>[];
  final fichiers = d.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final f in fichiers) {
    final nom = f.uri.pathSegments.last;
    final i = nom.lastIndexOf('.');
    if (i < 0) continue;
    final ext = nom.substring(i + 1).toLowerCase();
    final base = nom.substring(0, i);
    if (ext == 'pdf') {
      pdf.add(nom);
      continue;
    }
    if (!_extensions.contains(ext)) continue;
    final t = File('${f.parent.path}${Platform.pathSeparator}$base.txt');
    if (!t.existsSync()) {
      sans.add(nom);
      continue;
    }
    scans.add(ScanReference(nom, f.readAsBytesSync(), t.readAsStringSync()));
  }
  return ContenuDossier(scans, sans, pdf);
}

/// Un moteur factice qui rend la transcription (la référence du scan) déformée d'une façon connue. Il sait quel scan on lui donne par l'empreinte de ses octets.
MoteurOcrFactice moteurFactice(String nom, List<ScanReference> scans) {
  final textes = {for (final s in scans) sha256Octets(s.octets): s.reference};
  switch (nom) {
    case 'factice-parfait':
      return MoteurOcrFactice(id: nom, textes: textes);
    case 'factice-sans-accents':
      return MoteurOcrFactice(id: nom, textes: textes, sansAccents: true);
    case 'factice-perd-mots':
      return MoteurOcrFactice(id: nom, textes: textes, perdreUnMotSur: 5);
    case 'factice-bruit':
      return MoteurOcrFactice(id: nom, textes: textes, bruit: 25);
  }
  throw ArgumentError('moteur factice inconnu : $nom (factice-parfait, factice-sans-accents, factice-perd-mots, factice-bruit)');
}

/// Un moteur par COMMANDE : le jour où un moteur est installé, sa ligne de commande se donne avec `{image}` (le chemin du scan) et `{langue}` ; la sortie standard est le texte lu. Un
/// moteur absent du poste ou un code de sortie non nul est un refus NOMMÉ, jamais un texte vide présenté comme une lecture.
class MoteurOcrCommande implements MoteurOcr {
  MoteurOcrCommande(this.commande, {this.id = 'commande', this.version = '', this.langueMoteur = 'fra'});
  final String commande;
  @override
  final String id;
  @override
  final String version;
  final String langueMoteur;
  @override
  String get libelle => 'Moteur par commande';
  @override
  List<String> get langues => [langueMoteur];
  @override
  List<String> get formats => const ['png', 'jpeg', 'webp'];

  @override
  Future<ResultatOcr> lire(EntreeOcr entree) async {
    final ext = {'jpeg': 'jpg'}[entree.format] ?? entree.format;
    final tmp = Directory.systemTemp.createTempSync('sigh-ocr-mesure-');
    try {
      final image = File('${tmp.path}${Platform.pathSeparator}scan.$ext')..writeAsBytesSync(entree.octets);
      final ligne = commande.replaceAll('{image}', image.path).replaceAll('{langue}', entree.langue);
      final mots = _decouper(ligne);
      if (mots.isEmpty) throw ErreurOcr(ocrRefus(CodeOcr.moteurAbsent, 'la commande est vide'));
      ProcessResult r;
      try {
        r = await Process.run(mots.first, mots.sublist(1));
      } on ProcessException catch (e) {
        throw ErreurOcr(ocrRefus(CodeOcr.moteurAbsent, 'la commande « ${mots.first} » ne s’exécute pas sur ce poste (${e.message})'));
      }
      if (r.exitCode != 0) {
        throw ErreurOcr(ocrRefus(CodeOcr.moteurEnEchec, 'la commande s’est terminée avec le code ${r.exitCode} : ${'${r.stderr}'.trim().split('\n').first}'));
      }
      return ResultatOcr(texte: '${r.stdout}', langue: entree.langue, moteur: id, version: version);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  /// Découpe une ligne de commande en mots, en respectant les guillemets doubles.
  static List<String> _decouper(String ligne) {
    final out = <String>[];
    final b = StringBuffer();
    var guillemets = false;
    for (final r in ligne.runes) {
      final c = String.fromCharCode(r);
      if (c == '"') {
        guillemets = !guillemets;
      } else if (c == ' ' && !guillemets) {
        if (b.isNotEmpty) out.add(b.toString());
        b.clear();
      } else {
        b.write(c);
      }
    }
    if (b.isNotEmpty) out.add(b.toString());
    return out;
  }
}

/// Mesure UN moteur sur tous les scans du dossier. Un moteur qui refuse un scan est compté (zéro mot correct), jamais exclu.
Future<SyntheseMoteur> mesurerMoteur(MoteurOcr moteur, List<ScanReference> scans, {String langue = 'fra', int delaiMs = 120000}) async {
  final out = <MesureScan>[];
  for (final s in scans) {
    final format = fichierFormatDesOctets(s.octets);
    if (format == null || format == 'pdf') {
      out.add(MesureScan(fichier: s.fichier, pages: 1, dureeMs: 0, refusCode: CodeOcr.formatNonLu, refusMotif: 'le contenu n’est pas une image lisible (png, jpeg, webp)'));
      continue;
    }
    final t = Stopwatch()..start();
    final lu = await ocrLireFichier(moteur: moteur, octets: s.octets, formatId: format, mime: null, langue: langue, delaiMs: delaiMs);
    t.stop();
    if (!lu.ok) {
      out.add(MesureScan(fichier: s.fichier, pages: 1, dureeMs: t.elapsedMilliseconds, refusCode: lu.refus!.code, refusMotif: lu.refus!.motif));
    } else {
      out.add(MesureScan(fichier: s.fichier, pages: lu.pages, dureeMs: t.elapsedMilliseconds, mesure: ocrMesurer(s.reference, lu.texte)));
    }
  }
  return SyntheseMoteur(moteur.id, moteur.version, out);
}

/// Mesure plusieurs moteurs et écrit le rapport (Markdown et JSON) dans [sortie]. Rend les synthèses et le chemin du rapport.
Future<({List<SyntheseMoteur> syntheses, String rapport, String json})> mesurerDossier(
    {required String dossier,
    required List<MoteurOcr> Function(List<ScanReference>) moteurs,
    required String sortie,
    String langue = 'fra',
    int delaiMs = 120000,
    bool synthetique = false,
    bool avecExemples = false,
    DateTime? maintenant}) async {
  final contenu = lireDossier(dossier);
  if (contenu.scans.isEmpty) {
    throw StateError('aucun scan avec sa transcription dans « $dossier » : déposer des images (png, jpg, webp) et, à côté, un fichier .txt de même nom portant la transcription de référence');
  }
  final syntheses = <SyntheseMoteur>[];
  for (final m in moteurs(contenu.scans)) {
    syntheses.add(await mesurerMoteur(m, contenu.scans, langue: langue, delaiMs: delaiMs));
  }
  final t = maintenant ?? DateTime.now();
  final date = '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  var md = ocrRapportMarkdown(
      syntheses: syntheses,
      date: date,
      dossier: dossier,
      machine: '${Platform.operatingSystem}, ${Platform.numberOfProcessors} processeurs',
      nbSansTranscription: contenu.sansTranscription.length,
      synthetique: synthetique,
      avecExemples: avecExemples);
  if (contenu.sansTranscription.isNotEmpty) md += '\n## Scans sans transcription (ignorés)\n\n${[for (final n in contenu.sansTranscription) '- $n'].join('\n')}\n';
  if (contenu.pdf.isNotEmpty) {
    md += '\n## PDF non mesurés\n\nLire les pages d\'un PDF exige un rendeur de pages qu\'aucun poste n\'a encore ; ces fichiers se mesurent sur leurs pages rendues en images :\n\n${[for (final n in contenu.pdf) '- $n'].join('\n')}\n';
  }
  Directory(sortie).createSync(recursive: true);
  final base = '$sortie${Platform.pathSeparator}rapport-ocr-$date';
  File('$base.md').writeAsStringSync(md);
  final json = '$base.json';
  File(json).writeAsStringSync(_jsonEnLignes({
    'date': date,
    'dossier': dossier,
    'synthetique': synthetique,
    'sansTranscription': contenu.sansTranscription,
    'pdf': contenu.pdf,
    'moteurs': [for (final s in syntheses) s.toJson()]
  }));
  return (syntheses: syntheses, rapport: '$base.md', json: json);
}

String _jsonEnLignes(Object? v, [String indent = '']) {
  if (v is Map) {
    if (v.isEmpty) return '{}';
    final i2 = '$indent  ';
    return '{\n${[for (final e in v.entries) '$i2"${e.key}": ${_jsonEnLignes(e.value, i2)}'].join(',\n')}\n$indent}';
  }
  if (v is List) {
    if (v.isEmpty) return '[]';
    final i2 = '$indent  ';
    return '[\n${[for (final e in v) '$i2${_jsonEnLignes(e, i2)}'].join(',\n')}\n$indent]';
  }
  if (v is String) return '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
  if (v is double) return v.isFinite ? '$v' : 'null';
  return '$v';
}
