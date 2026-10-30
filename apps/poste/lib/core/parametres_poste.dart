import 'dart:convert';
import 'dart:io';

import 'config_poste.dart';

/// Réglages PERSISTANTS du poste : c'est ici, et non à la compilation, que se décide qu'un poste est la mère.
/// Le secret de la mère et la clé de clinique NE SONT PAS conservés dans ce fichier (ils vont au coffre du système,
/// tâche de packaging) : seul ce qui n'est pas un secret l'est.
class ParametresPoste {
  const ParametresPoste({required this.uuidPoste, this.mode = ModePoste.fileul, this.nomPoste = 'Poste', this.relais = '', this.activeDepuis});
  final String uuidPoste;
  final ModePoste mode;
  final String nomPoste;
  final String relais;
  final DateTime? activeDepuis;

  ParametresPoste avec({ModePoste? mode, String? nomPoste, String? relais, DateTime? activeDepuis, bool effacerActivation = false}) => ParametresPoste(
        uuidPoste: uuidPoste,
        mode: mode ?? this.mode,
        nomPoste: nomPoste ?? this.nomPoste,
        relais: relais ?? this.relais,
        activeDepuis: effacerActivation ? null : (activeDepuis ?? this.activeDepuis),
      );

  Map<String, Object?> toJson() => {'uuid_poste': uuidPoste, 'mode': mode.name, 'nom_poste': nomPoste, 'relais': relais, 'active_depuis': activeDepuis?.toIso8601String()};

  factory ParametresPoste.depuisJson(Map<String, Object?> j) => ParametresPoste(
        uuidPoste: '${j['uuid_poste']}',
        mode: j['mode'] == 'mere' ? ModePoste.mere : ModePoste.fileul,
        nomPoste: '${j['nom_poste'] ?? 'Poste'}',
        relais: '${j['relais'] ?? ''}',
        activeDepuis: j['active_depuis'] == null ? null : DateTime.tryParse('${j['active_depuis']}'),
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
  StockageFichier(this.chemin);
  final String chemin;

  @override
  Future<ParametresPoste?> lire() async {
    final f = File(chemin);
    if (!await f.exists()) return null;
    try {
      return ParametresPoste.depuisJson((jsonDecode(await f.readAsString()) as Map).cast<String, Object?>());
    } catch (_) {
      // Fichier illisible : on ne devine pas. Le poste redémarre en fileul, jamais en mère par défaut.
      return null;
    }
  }

  @override
  Future<void> ecrire(ParametresPoste p) async {
    final tmp = File('$chemin.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(p.toJson()), flush: true);
    await tmp.rename(chemin);
  }
}
