import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sigh_sync/sigh_sync.dart';

import '../core/config_poste.dart';
import '../core/parametres_poste.dart';

/// Refus nommé de l'activation : le message dit POURQUOI et ce qui reste possible. Jamais une exception muette.
class ActivationRefusee implements Exception {
  ActivationRefusee(this.code, this.motif);
  final String code;
  final String motif;
  @override
  String toString() => motif;
}

/// Ce que l'activation demande au RELAIS (apps/web : `POST /mere/activer`, `/mere/desactiver`).
abstract class RelaisMere {
  Future<void> activer({required String uuid, required String etiquette, required bool remplacer});
  Future<void> desactiver(String uuid);
}

class RelaisMereHttp implements RelaisMere {
  RelaisMereHttp({required this.base, required this.secretMere, http.Client? client}) : _http = client ?? http.Client();
  final Uri base;
  final String secretMere;
  final http.Client _http;

  Future<void> _post(String chemin, Map<String, Object?> corps) async {
    final http.Response r;
    try {
      r = await _http.post(base.resolve(chemin), headers: {'content-type': 'application/json', 'x-mere': secretMere}, body: jsonEncode(corps)).timeout(const Duration(seconds: 8));
    } catch (e) {
      throw ActivationRefusee('relais_injoignable', 'Le relais n’a pas répondu : l’activation exige de le joindre (une seule mère par clinique). $e');
    }
    if (r.statusCode == 200) return;
    final j = r.body.isEmpty ? const {} : (jsonDecode(r.body) as Map);
    if (r.statusCode == 403) throw ActivationRefusee('secret_invalide', 'Le secret de la mère est refusé par le relais.');
    throw ActivationRefusee('${j['code'] ?? 'http_${r.statusCode}'}', '${j['motif'] ?? 'Refus du relais (${r.statusCode}).'}');
  }

  @override
  Future<void> activer({required String uuid, required String etiquette, required bool remplacer}) => _post('/mere/activer', {'uuid': uuid, 'etiquette': etiquette, 'remplacer': remplacer});

  @override
  Future<void> desactiver(String uuid) => _post('/mere/desactiver', {'uuid': uuid});
}

/// Le service de la mère tel que l'application le pilote (HTTP de synchronisation, base, planificateur).
abstract class ServiceMere {
  bool get enMarche;
  Future<void> demarrer();
  Future<void> arreter();
}

/// Service réel : `packages/sync_dart` dans le processus de l'application.
class ServiceMereLocal implements ServiceMere {
  ServiceMereLocal(this.config);
  final ConfigMere config;
  Mere? _mere;

  @override
  bool get enMarche => _mere != null;

  @override
  Future<void> demarrer() async {
    if (_mere != null) return;
    final m = await Mere.creer(config);
    await m.demarrer();
    _mere = m;
  }

  @override
  Future<void> arreter() async {
    final m = _mere;
    _mere = null;
    await m?.arreter();
  }
}

/// Activation et désactivation du MODE MÈRE sur ce poste. Atomique : si le service ne démarre pas, la déclaration au
/// relais est retirée et le poste reste fileul — jamais « mère déclarée » sans service pour la servir.
class ActivationMere {
  ActivationMere({required this.stockage, required this.service, required this.relaisPour});
  final StockageParametres stockage;
  final ServiceMere service;

  /// Fabrique du client relais à partir de l'URL et du secret saisis (le secret n'est jamais conservé ici).
  final RelaisMere Function(String relais, String secretMere) relaisPour;

  Future<ParametresPoste> parametres() async {
    final p = await stockage.lire();
    if (p != null) return p;
    final neuf = ParametresPoste(uuidPoste: uuid7());
    await stockage.ecrire(neuf);
    return neuf;
  }

  Future<ParametresPoste> activer({required String relais, required String secretMere, required String cleClinique, String? nomPoste, bool remplacer = false}) async {
    final p = await parametres();
    if (p.mode == ModePoste.mere && service.enMarche) return p;
    if (relais.trim().isEmpty || Uri.tryParse(relais.trim())?.hasScheme != true) throw ActivationRefusee('relais_invalide', 'Adresse du relais invalide (ex. https://relais.exemple.bj).');
    if (secretMere.trim().isEmpty) throw ActivationRefusee('secret_requis', 'Le secret de la mère est obligatoire.');
    if (cleClinique.trim().length < 16) throw ActivationRefusee('cle_invalide', 'La clé de clinique est obligatoire (16 caractères au moins) : sans elle, rien de ce qui quitte le serveur ne pourrait être restauré.');
    final etiquette = (nomPoste == null || nomPoste.trim().isEmpty) ? p.nomPoste : nomPoste.trim();
    final r = relaisPour(relais.trim(), secretMere.trim());
    await r.activer(uuid: p.uuidPoste, etiquette: etiquette, remplacer: remplacer);
    try {
      await service.demarrer();
    } catch (e) {
      try {
        await r.desactiver(p.uuidPoste);
      } catch (_) {/* le relais est peut-être injoignable : la déclaration expirera avec le silence de la mère */}
      throw ActivationRefusee('service_non_demarre', 'Le service de synchronisation n’a pas pu démarrer : $e. Le poste reste fileul.');
    }
    final apres = p.avec(mode: ModePoste.mere, nomPoste: etiquette, relais: relais.trim(), activeDepuis: DateTime.now());
    await stockage.ecrire(apres);
    return apres;
  }

  /// Le poste redevient fileul QUOI QU'IL ARRIVE (service arrêté, réglage écrit) : on ne laisse jamais un poste « mère »
  /// sans service. Si le relais n'a pas pu libérer la place, un AVERTISSEMENT le dit — elle se libère d'elle-même quand la
  /// mère reste silencieuse (reprise explicite possible depuis un autre poste).
  Future<({ParametresPoste parametres, String? avertissement})> desactiver({required String secretMere}) async {
    final p = await parametres();
    if (p.mode != ModePoste.mere) return (parametres: p, avertissement: null);
    await service.arreter();
    String? avertissement;
    try {
      await relaisPour(p.relais, secretMere.trim()).desactiver(p.uuidPoste);
    } on ActivationRefusee catch (e) {
      avertissement = 'Service arrêté, mais la place de mère n’a pas été libérée au relais (${e.motif}).';
    }
    final apres = p.avec(mode: ModePoste.fileul, effacerActivation: true);
    await stockage.ecrire(apres);
    return (parametres: apres, avertissement: avertissement);
  }
}
