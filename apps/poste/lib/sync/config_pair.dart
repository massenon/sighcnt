import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// La configuration du MODE PAIR d'un poste (ADR-0006), lue dans `pair.json` du dossier de données : adresse du relais, clé unique de la clinique (256 bits en
/// hexadécimal), nom du poste et, au premier lancement seulement, le code d'appairage délivré par le relais. Absent ou `actif` faux : le poste ne change pas
/// de comportement. L'écran de saisie de ces valeurs n'existe pas encore : le fichier est la seule porte, et le dit.
class ConfigPairPoste {
  const ConfigPairPoste({required this.relais, required this.cleHex, this.nom = 'poste', this.code});
  final String relais, cleHex, nom;
  final String? code;

  /// Rend `null` si le mode pair n'est pas actif. Un fichier illisible ou une clé qui n'a pas 64 caractères hexadécimaux lève `FormatException` nommée : un mode
  /// pair à moitié configuré ne doit pas démarrer en silence.
  static ConfigPairPoste? lire(String dossier) {
    final f = File('$dossier/pair.json');
    if (!f.existsSync()) return null;
    final Object? j;
    try {
      j = jsonDecode(f.readAsStringSync());
    } catch (e) {
      throw FormatException('pair.json illisible : $e');
    }
    if (j is! Map || j['actif'] != true) return null;
    final relais = '${j['relais'] ?? ''}', cle = '${j['cle'] ?? ''}';
    if (relais.isEmpty) throw const FormatException('pair.json : « relais » manque');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cle)) throw const FormatException('pair.json : « cle » doit faire 64 caractères hexadécimaux (256 bits)');
    final code = j['code'] == null || '${j['code']}'.isEmpty ? null : '${j['code']}';
    return ConfigPairPoste(relais: relais, cleHex: cle, nom: '${j['nom'] ?? 'poste'}', code: code);
  }

  /// Le contenu BRUT de `pair.json` (vide si absent ou illisible), pour l'écran de réglage : il lit aussi un mode désactivé, ce que [lire] ne rend pas.
  static Map<String, Object?> lireBrut(String dossier) {
    final f = File('$dossier/pair.json');
    if (!f.existsSync()) return {};
    try {
      final j = jsonDecode(f.readAsStringSync());
      return j is Map ? j.cast<String, Object?>() : {};
    } catch (_) {
      return {};
    }
  }

  /// Une clé de clinique neuve : 256 bits tirés du générateur sécurisé du système, en 64 caractères hexadécimaux.
  static String genererCle([Random? alea]) {
    final r = alea ?? Random.secure();
    return [for (var i = 0; i < 32; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  /// Écrit `pair.json` en CONSERVANT ce que l'appelant ne change pas (la clé en particulier : un réglage de l'adresse ne la perd pas). [code] vide : le code
  /// d'appairage est retiré (il est à usage unique, jamais gardé). Refus nommé (`FormatException`) si le mode est activé sans relais ou sans clé valide :
  /// un fichier qui ferait échouer le démarrage ne s'écrit pas.
  static void ecrire(String dossier,
      {bool? actif, String? relais, String? nom, String? cleHex, String? code, bool? recuperation, String? courriel, String? cleLe}) {
    final j = lireBrut(dossier);
    if (actif != null) j['actif'] = actif;
    if (relais != null) j['relais'] = relais;
    if (nom != null) j['nom'] = nom;
    if (cleHex != null) j['cle'] = cleHex;
    if (code != null) {
      if (code.isEmpty) {
        j.remove('code');
      } else {
        j['code'] = code;
      }
    }
    if (recuperation != null) j['recuperation'] = recuperation;
    if (courriel != null) j['courriel'] = courriel;
    if (cleLe != null) j['cle_le'] = cleLe;
    if (j['actif'] == true) {
      if ('${j['relais'] ?? ''}'.isEmpty) throw const FormatException('Le mode pair ne peut pas être activé sans adresse de relais.');
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch('${j['cle'] ?? ''}')) throw const FormatException('Le mode pair ne peut pas être activé sans clé de clinique valide.');
    }
    Directory(dossier).createSync(recursive: true);
    File('$dossier/pair.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(j));
  }
}
