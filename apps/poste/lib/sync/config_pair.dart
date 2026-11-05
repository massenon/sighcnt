import 'dart:convert';
import 'dart:io';

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
}
