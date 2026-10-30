import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_sync/sigh_sync.dart';

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

class FichePatient {
  const FichePatient({required this.id, required this.champs});
  final String id;
  final Map<String, Object?> champs;
  String get code => '${champs['code'] ?? 'en attente de numéro'}';
  String get nom => '${champs['nom'] ?? ''} ${champs['prenom'] ?? ''}'.trim();
}

/// Ce que l'interface sait du moteur. Rien d'autre : en test c'est un faux, en production `MoteurMobileSync`.
abstract class MoteurMobile {
  ProfilMobile? get profil;
  ValueListenable<EtatMobile> get etat;
  Future<void> appairer({required String code, required String cleClinique, required ProfilMobile profil});

  /// Dossiers du lot de la tournée (profil soignant).
  Future<List<FichePatient>> tournee();

  /// Dossiers créés depuis ce téléphone (réception de secours) — y compris ceux pas encore partis.
  Future<List<FichePatient>> dossiersCrees();

  /// Écrit hors ligne : la saisie est visible AUSSITÔT et part à la première occasion.
  Future<String> creerPatient(Map<String, Object?> champs);
  Future<void> enregistrerConstantes(String patientId, Map<String, Object?> constantes);
}

/// Moteur réel : `packages/sync_dart` (même code que le banc d'essai à plusieurs processus).
class MoteurMobileSync implements MoteurMobile {
  MoteurMobileSync._(this._m) {
    _minuterie = Timer.periodic(const Duration(seconds: 2), (_) => actualiser());
  }

  final Mobile _m;
  Timer? _minuterie;
  final ValueNotifier<EtatMobile> _etat = ValueNotifier(const EtatMobile());
  ProfilMobile? _profil;

  static MoteurMobileSync creer({required String dbChemin, required String relais}) =>
      MoteurMobileSync._(Mobile(ConfigMobile(port: 0, relais: relais, dbChemin: dbChemin)));

  @override
  ProfilMobile? get profil => _profil;

  @override
  ValueListenable<EtatMobile> get etat => _etat;

  @override
  Future<void> appairer({required String code, required String cleClinique, required ProfilMobile profil}) async {
    final (statut, corps) = await _m.commande('POST /appairer', {'code': code, 'cle': cleClinique, 'profil': profil.cle}, const {});
    if (statut >= 400) {
      final c = corps is Map ? corps : const {};
      throw StateError('${c['code'] ?? 'appairage_refuse'}');
    }
    _profil = profil;
    unawaited(_m.boucle());
    await actualiser();
  }

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
  Future<void> enregistrerConstantes(String patientId, Map<String, Object?> constantes) async {
    await _m.commande('POST /ecrire', {'type': 'creer', 'collection': 'constantes', 'champs': {...constantes, 'patientId': patientId}}, const {});
    await actualiser();
  }

  void arreter() => _minuterie?.cancel();
}
