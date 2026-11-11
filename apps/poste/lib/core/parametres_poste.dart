import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'config_poste.dart';
import 'etat_installation.dart';

/// Réglages PERSISTANTS du poste : c'est ici, et non à la compilation, que se décide qu'un poste est la mère.
/// Le secret de la mère et la clé de clinique NE SONT PAS conservés dans ce fichier (ils vont au coffre du système,
/// tâche de packaging) : seul ce qui n'est pas un secret l'est.
class ParametresPoste {
  const ParametresPoste(
      {required this.uuidPoste,
      this.mode = ModePoste.fileul,
      this.nomPoste = 'Poste',
      this.relais = '',
      this.activeDepuis,
      this.installation = EtatInstallation.vide,
      this.adresseMere = '',
      this.rejoint = false,
      this.posteSecours = false});
  final String uuidPoste;
  final ModePoste mode;
  final String nomPoste;
  final String relais;
  final DateTime? activeDepuis;

  /// Où en est l'assistant de première installation (donnée locale de CE poste, jamais synchronisée).
  final EtatInstallation installation;

  /// Poste FILEUL rattaché à une clinique : l'adresse de la mère (`http://hôte:port`) et le fait d'avoir rejoint. Vide / faux : le poste n'a rejoint personne.
  final String adresseMere;
  final bool rejoint;

  /// Ce poste est-il un POSTE DE SECOURS (poste partagé où un agent sans téléphone ouvre sa propre session) ? Donnée locale de CE poste, jamais synchronisée : le
  /// verrou de la session y suit le délai de secours (5 minutes par défaut, à valider) au lieu du délai ordinaire (lot ORG2, P3).
  final bool posteSecours;

  ParametresPoste avec(
          {ModePoste? mode,
          String? nomPoste,
          String? relais,
          DateTime? activeDepuis,
          EtatInstallation? installation,
          String? adresseMere,
          bool? rejoint,
          bool? posteSecours,
          bool effacerActivation = false}) =>
      ParametresPoste(
        uuidPoste: uuidPoste,
        mode: mode ?? this.mode,
        nomPoste: nomPoste ?? this.nomPoste,
        relais: relais ?? this.relais,
        activeDepuis:
            effacerActivation ? null : (activeDepuis ?? this.activeDepuis),
        installation: installation ?? this.installation,
        adresseMere: adresseMere ?? this.adresseMere,
        rejoint: rejoint ?? this.rejoint,
        posteSecours: posteSecours ?? this.posteSecours,
      );

  Map<String, Object?> toJson() => {
        'uuid_poste': uuidPoste,
        'mode': mode.name,
        'nom_poste': nomPoste,
        'relais': relais,
        'active_depuis': activeDepuis?.toIso8601String(),
        'installation': installation.toJson(),
        'adresse_mere': adresseMere,
        'rejoint': rejoint,
        'poste_secours': posteSecours,
      };

  factory ParametresPoste.depuisJson(Map<String, Object?> j) => ParametresPoste(
        uuidPoste: '${j['uuid_poste']}',
        mode: j['mode'] == 'mere' ? ModePoste.mere : ModePoste.fileul,
        nomPoste: '${j['nom_poste'] ?? 'Poste'}',
        relais: '${j['relais'] ?? ''}',
        activeDepuis: j['active_depuis'] == null
            ? null
            : DateTime.tryParse('${j['active_depuis']}'),
        installation: EtatInstallation.depuisJson(j['installation']),
        adresseMere: '${j['adresse_mere'] ?? ''}',
        rejoint: j['rejoint'] == true,
        posteSecours: j['poste_secours'] == true,
      );
}

abstract class StockageParametres {
  /// `null` = premier démarrage.
  Future<ParametresPoste?> lire();
  Future<void> ecrire(ParametresPoste p);
}

class StockageMemoire implements StockageParametres {
  StockageMemoire([this._p]);
  ParametresPoste? _p;
  @override
  Future<ParametresPoste?> lire() async => _p;
  @override
  Future<void> ecrire(ParametresPoste p) async => _p = p;
}

/// Fichier JSON écrit de façon ATOMIQUE (fichier temporaire puis renommage) : une coupure de courant pendant l'écriture
/// ne doit jamais laisser un poste sans réglages, ni à moitié mère.
class StockageFichier implements StockageParametres {
  StockageFichier(this.chemin, {List<int>? cle}) : _cle = cle;
  final String chemin;

  /// La clé du poste : les réglages portent des SECRETS (clé de la clinique, secret de la mère). Avec elle, le fichier est chiffré (AES-256-GCM, en-tête `SGHP`) ;
  /// un fichier en clair d'un poste d'avant est lu puis réécrit chiffré aussitôt. Sans elle : JSON en clair (développement).
  final List<int>? _cle;
  static final _aes = AesGcm.with256bits();
  static const _entete = 'SGHP';

  Future<void> _poser(ParametresPoste p) async {
    final tmp = File('$chemin.tmp');
    await tmp.parent.create(recursive: true);
    final texte = const JsonEncoder.withIndent(' ').convert(p.toJson());
    if (_cle == null) {
      await tmp.writeAsString(texte, flush: true);
    } else {
      final boite = await _aes.encrypt(utf8.encode(texte), secretKey: SecretKey(_cle!), aad: utf8.encode(_entete));
      await tmp.writeAsBytes([...utf8.encode(_entete), ...boite.concatenation()], flush: true);
    }
    await tmp.rename(chemin);
  }

  @override
  Future<ParametresPoste?> lire() async {
    final f = File(chemin);
    if (!await f.exists()) return null;
    try {
      final brut = await f.readAsBytes();
      final chiffre = brut.length > 4 && utf8.decode(brut.sublist(0, 4), allowMalformed: true) == _entete;
      final String texte;
      if (chiffre) {
        if (_cle == null) return null;
        texte = utf8.decode(await _aes.decrypt(SecretBox.fromConcatenation(brut.sublist(4), nonceLength: 12, macLength: 16), secretKey: SecretKey(_cle!), aad: utf8.encode(_entete)));
      } else {
        texte = utf8.decode(brut);
      }
      final p = ParametresPoste.depuisJson((jsonDecode(texte) as Map).cast<String, Object?>());
      // Un fichier en clair d'avant le chiffrement est réécrit chiffré tout de suite : la migration ne laisse pas de copie lisible.
      if (!chiffre && _cle != null) await _poser(p);
      return p;
    } catch (_) {
      // Fichier illisible : on ne devine pas. Le poste redémarre en fileul, jamais en mère par défaut.
      return null;
    }
  }

  @override
  Future<void> ecrire(ParametresPoste p) => _poser(p);
}
