import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show mobFonctions;
import 'package:sigh_sync/sigh_sync.dart';

import 'service_soignant.dart';
import 'service_suite.dart';

export 'service_soignant.dart';
export 'service_suite.dart';

/// Profils du mobile (spec §11). Le profil décide des écrans ET de ce que le serveur accepte : la réception de secours
/// ne couvre pas la caisse (refus nommé côté mère), le soignant ne crée pas de dossier hors tournée.
enum ProfilMobile { soignant, receptionSecours }

extension on ProfilMobile {
  String get cle => this == ProfilMobile.soignant ? 'soignant' : 'reception';
}

class EtatMobile {
  const EtatMobile({this.appaire = false, this.horsLigne = true, this.suspendu = false, this.enAttente = 0, this.aTraiter = 0, this.lotExpire});
  final bool appaire;
  final bool horsLigne;
  final bool suspendu;
  final int enAttente;
  final int aTraiter;

  /// Fin de validité du lot de tournée (ms epoch) : passé ce délai, les dossiers de la tournée s'effacent du téléphone.
  final int? lotExpire;
}

/// Ce que l'interface sait du moteur. Rien d'autre : en test c'est un faux, en production `MoteurMobileSync`.
abstract class MoteurMobile {
  ProfilMobile? get profil;
  ValueListenable<EtatMobile> get etat;
  /// Le profil soignant demande en plus l'agent (RG-12 : aucune action anonyme) et sa fonction (elle décide des commandes offertes).
  Future<void> appairer({required String code, required String cleClinique, required ProfilMobile profil, String agent = '', String fonction = ''});

  /// Le service du profil soignant (agenda, dossier, constantes, notes, prescription) ; `null` pour la réception de secours.
  ServiceSoignant? get soignant;

  /// Les opérations refusées par la mère : code, motif, geste (jamais rejouées telles quelles).
  Future<List<RefusAffiche>> aTraiter();

  /// Dossiers du lot de la tournée (profil soignant).
  Future<List<FichePatient>> tournee();

  /// Dossiers créés depuis ce téléphone (réception de secours) — y compris ceux pas encore partis.
  Future<List<FichePatient>> dossiersCrees();

  /// Écrit hors ligne : la saisie est visible AUSSITÔT et part à la première occasion.
  Future<String> creerPatient(Map<String, Object?> champs);
}

/// Un refus rendu par la mère, tel que l'écran « À traiter » l'affiche.
class RefusAffiche {
  const RefusAffiche({required this.operation, required this.code, required this.motif, required this.geste});
  final String operation, code, motif, geste;
}

/// La source du service soignant branchée sur le vrai moteur `Mobile` (même code que le banc d'essai à plusieurs processus).
class SourceSync implements SourceMobile {
  SourceSync(this._m);
  final Mobile _m;

  @override
  Future<List<LigneLot>> liste(String collection) async {
    final (_, c) = await _m.commande('GET /liste', const {}, {'collection': collection});
    return [
      for (final x in (c! as List))
        LigneLot('${(x as Map)['id']}', ((x['data'] ?? const {}) as Map).cast<String, Object?>(), archive: x['archive'] == true)
    ];
  }

  @override
  Future<String> creer(String collection, Map<String, Object?> champs) async {
    final (_, c) = await _m.commande('POST /ecrire', {'type': 'creer', 'collection': collection, 'champs': champs}, const {});
    return '${(c! as Map)['fiche']}';
  }

  @override
  Future<int?> lotExpire() async {
    final (_, c) = await _m.commande('GET /etat', const {}, const {});
    return ((c! as Map)['lot_expire'] as num?)?.toInt();
  }
}

/// Moteur réel : `packages/sync_dart` (même code que le banc d'essai à plusieurs processus).
class MoteurMobileSync implements MoteurMobile, ExtensionsMobile {
  MoteurMobileSync._(this._m) {
    _minuterie = Timer.periodic(const Duration(seconds: 2), (_) => actualiser());
    // Un téléphone déjà appairé retrouve son profil, son agent et sa fonction au redémarrage (ils vivent dans la base locale, pas en mémoire).
    if ((_m.base.meta('jeton') ?? '').isNotEmpty && _m.base.meta('profil') != null) {
      _profil = _m.base.meta('profil') == 'reception' ? ProfilMobile.receptionSecours : ProfilMobile.soignant;
      _bati();
      unawaited(_m.boucle());
    }
  }

  final Mobile _m;
  ServiceSoignant? _soignant;
  Timer? _minuterie;
  final ValueNotifier<EtatMobile> _etat = ValueNotifier(const EtatMobile());
  ProfilMobile? _profil;

  static MoteurMobileSync creer({required String dbChemin, required String relais}) =>
      MoteurMobileSync._(Mobile(ConfigMobile(port: 0, relais: relais, dbChemin: dbChemin)));

  @override
  ProfilMobile? get profil => _profil;

  @override
  ServiceSoignant? get soignant => _soignant;

  void _bati() {
    final fonction = _m.base.meta('fonction') ?? '';
    _soignant = _profil == ProfilMobile.soignant && fonction.isNotEmpty
        ? ServiceSoignant(SourceSync(_m), session: SessionSoignant(agent: _m.base.meta('agent') ?? '', fonction: fonction))
        : null;
  }

  @override
  ValueListenable<EtatMobile> get etat => _etat;

  @override
  Future<void> appairer({required String code, required String cleClinique, required ProfilMobile profil, String agent = '', String fonction = ''}) async {
    if (profil == ProfilMobile.soignant && (agent.trim().isEmpty || !mobFonctions.contains(fonction))) {
      throw StateError('agent_et_fonction_requis');
    }
    final (statut, corps) = await _m.commande('POST /appairer', {'code': code, 'cle': cleClinique, 'profil': profil.cle}, const {});
    if (statut >= 400) {
      final c = corps is Map ? corps : const {};
      throw StateError('${c['code'] ?? 'appairage_refuse'}');
    }
    _profil = profil;
    _m.base.poserMeta('agent', agent.trim());
    _m.base.poserMeta('fonction', profil == ProfilMobile.soignant ? fonction : '');
    _bati();
    unawaited(_m.boucle());
    await actualiser();
  }

  @override
  Future<void> actualiser() async {
    try {
      final (_, c) = await _m.commande('GET /etat', const {}, const {});
      final j = (c! as Map).cast<String, Object?>();
      _etat.value = EtatMobile(
        appaire: _profil != null,
        horsLigne: j['hors_ligne'] == true,
        suspendu: j['suspendu'] == true,
        enAttente: ((j['en_attente'] ?? 0) as num).toInt(),
        aTraiter: ((j['a_traiter'] ?? const []) as List).length,
        lotExpire: (j['lot_expire'] as num?)?.toInt(),
      );
    } catch (_) {
      _etat.value = const EtatMobile(appaire: true, horsLigne: true);
    }
  }

  Future<List<FichePatient>> _liste() async {
    final (_, c) = await _m.commande('GET /liste', const {}, {'collection': 'patients'});
    return [for (final x in (c! as List)) FichePatient(id: '${(x as Map)['id']}', champs: ((x['data'] ?? const {}) as Map).cast<String, Object?>())];
  }

  @override
  Future<List<FichePatient>> tournee() => _liste();

  @override
  Future<List<FichePatient>> dossiersCrees() => _liste();

  @override
  Future<String> creerPatient(Map<String, Object?> champs) async {
    final (_, c) = await _m.commande('POST /ecrire', {'type': 'creer', 'collection': 'patients', 'champs': champs}, const {});
    await actualiser();
    return '${(c! as Map)['fiche']}';
  }

  @override
  Future<List<RefusAffiche>> aTraiter() async {
    final (_, c) = await _m.commande('GET /etat', const {}, const {});
    final j = (c! as Map).cast<String, Object?>();
    return [
      for (final r in ((j['a_traiter'] ?? const []) as List))
        RefusAffiche(
            operation: '${(r as Map)['id']}', code: '${r['code'] ?? ''}', motif: '${r['motif'] ?? ''}', geste: '${r['geste'] ?? ''}')
    ];
  }

  // --- ExtensionsMobile (suite du mobile : lot, réglages, orientation) ---------------------------------------------------------------------

  @override
  SourceMobile get source => SourceSync(_m);

  @override
  String get agent => _m.base.meta('agent') ?? '';

  @override
  Future<String?> appareil() async {
    try {
      final (_, c) = await _m.commande('GET /etat', const {}, const {});
      final u = (c! as Map)['uuid'];
      return u == null ? null : '$u';
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> reinitialiserAppairage() async {
    _m.base.poserMeta('jeton', '');
    _m.base.poserMeta('profil', '');
    _profil = null;
    _soignant = null;
    _etat.value = const EtatMobile();
  }

  void arreter() => _minuterie?.cancel();
}
