import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import 'transcription_mobile.dart' show PieceSync;

/// LA CONFIGURATION DE LA CLINIQUE VOYAGE DE LA MÈRE AUX POSTES FILEULS (PRD-POSTE-premiere-installation, EF-INST-06 et 07, PLAN étape 9).
///
/// Ce que la mère diffuse : les collections ESSENTIELLES (paramétrage, référentiels, droits, modules, catalogues : `cfbEssentielles`, la même liste que le
/// vidage des jeux de test conserve) plus les COMPTES (`utilisateurs`, `identifiants`). Ce qu'elle ne diffuse pas : l'activité (patients, factures…), qui
/// reste locale en attendant le pont entre le magasin et le journal d'opérations (plan de synchronisation, S2 à S4).
///
/// Le canal est celui qui existe : la mère écrit chaque fiche au journal (`POST /admin/referentiel` de son propre service), le fileul la reçoit par la
/// synchronisation (`GET /liste`) et l'applique à son magasin. Aucun canal nouveau.
Set<String> collectionsConfiguration() => {...cfbEssentielles, 'utilisateurs'}.difference({'rolesBase', 'modulesManifeste', 'reglages', 'audit'});

/// Les collections qu'un fileul continue d'ÉCRIRE lui-même : un agent s'y connecte, change son mot de passe, voit son compteur d'échecs monter. Elles ne sont
/// pas protégées par la garde « réglé sur la mère ».
const Set<String> collectionsLocalesDuFileul = {'utilisateurs'};

String _empreinte(Fiche f) => jsonEncode(f);

/// Côté MÈRE : publie les fiches de configuration qui ont changé. Un geste sur une collection de configuration réarme une minuterie (1 s) ; la publication
/// n'envoie que les fiches dont le contenu a changé depuis la dernière réussie. Un échec n'est pas perdu : la fiche reste « à publier » et repart au tour suivant.
class PublicateurConfiguration {
  PublicateurConfiguration(this.magasin, this.publier, {this.delai = const Duration(seconds: 1), Set<String>? collections})
      : collections = collections ?? collectionsConfiguration();
  final Magasin magasin;
  final Future<void> Function(String collection, String fiche, Map<String, Object?> champs) publier;
  final Duration delai;
  final Set<String> collections;
  final Map<String, String> _publie = {};
  final Map<String, VoidCallback> _ecouteurs = {};
  Timer? _minuterie;
  bool _enCours = false;

  /// Le dernier échec de publication (`null` : tout va bien).
  final ValueNotifier<String?> erreur = ValueNotifier<String?>(null);

  void demarrer() {
    for (final n in collections) {
      if (_ecouteurs.containsKey(n)) continue;
      void ecoute() => _armer();
      _ecouteurs[n] = ecoute;
      magasin.collection(n).addListener(ecoute);
    }
    _armer();
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
    _ecouteurs.forEach((n, e) => magasin.collection(n).removeListener(e));
    _ecouteurs.clear();
  }

  void _armer() {
    _minuterie ??= Timer(delai, () {
      _minuterie = null;
      unawaited(pousser());
    });
  }

  /// Publie maintenant ce qui a changé. Rend le nombre de fiches publiées.
  Future<int> pousser() async {
    if (_enCours) return 0;
    _enCours = true;
    var n = 0;
    try {
      for (final nom in collections) {
        for (final f in magasin.collection(nom).toutes) {
          final id = '${f['id'] ?? ''}';
          if (id.isEmpty) continue;
          final cle = '$nom/$id';
          // RG-13 : la rémunération et les références sociales des agents (`cfbChampsDeTestConserves`) restent sur la mère, elles ne partent pas aux postes.
          final champs = <String, Object?>{...f}..removeWhere((k, _) => (cfbChampsDeTestConserves[nom] ?? const []).contains(k));
          final e = _empreinte(champs);
          if (_publie[cle] == e) continue;
          try {
            await publier(nom, id, champs);
            _publie[cle] = e;
            n++;
          } catch (err) {
            erreur.value = 'Publication de « $nom » impossible : $err';
            _armer();
            return n;
          }
        }
      }
      erreur.value = null;
    } finally {
      _enCours = false;
    }
    return n;
  }
}

/// Côté FILEUL : applique à son magasin les fiches de configuration que la mère a diffusées, et REFUSE les écritures locales de configuration (« réglé sur la
/// mère »). Deux exceptions : les comptes sont insérés mais jamais écrasés (le fileul tient ses compteurs), et un haché n'est remplacé que par un haché PLUS
/// RÉCENT (`definiLe`), de sorte qu'un mot de passe changé sur le fileul ne revienne pas à l'ancien au tour suivant.
class ApplicateurConfiguration {
  ApplicateurConfiguration(this.magasin, this.liste, {Set<String>? collections}) : collections = collections ?? collectionsConfiguration();
  final Magasin magasin;
  final Future<List<PieceSync>> Function(String collection) liste;
  final Set<String> collections;
  Timer? _minuterie;
  bool _applique = false;
  bool _gardesPosees = false;

  /// Nombre de fiches reçues depuis le démarrage.
  final ValueNotifier<int> recues = ValueNotifier<int>(0);
  final ValueNotifier<String?> erreur = ValueNotifier<String?>(null);

  static const String motifGarde = 'Réglé sur la mère : cette configuration se modifie sur le poste principal, puis elle est reprise ici.';

  void _poserGardes() {
    if (_gardesPosees) return;
    _gardesPosees = true;
    for (final n in collections.difference(collectionsLocalesDuFileul)) {
      // `appliquerDistante` ne passe pas par les gardes : seule l'écriture de l'agent est refusée.
      magasin.collection(n).garder((op, f) => motifGarde);
    }
  }

  void demarrer({Duration intervalle = const Duration(seconds: 3)}) {
    _poserGardes();
    _minuterie?.cancel();
    _minuterie = Timer.periodic(intervalle, (_) => unawaited(tirer()));
    unawaited(tirer());
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
  }

  /// Un tour : lit chaque collection de configuration et applique ce qui a changé. Rend le nombre de fiches appliquées.
  Future<int> tirer() async {
    if (_applique) return 0;
    _applique = true;
    var n = 0;
    try {
      for (final nom in collections) {
        final col = magasin.collection(nom);
        for (final p in await liste(nom)) {
          final f = <String, Object?>{...p.data, 'id': p.data['id'] ?? p.id, if (p.archive) 'statut': 'archive'};
          final local = col.parId(f['id']);
          if (nom == 'utilisateurs' && local != null) continue;
          if (nom == 'identifiants' && local != null) {
            final distant = DateTime.tryParse('${f['definiLe'] ?? ''}');
            final ici = DateTime.tryParse('${local['definiLe'] ?? ''}');
            if (distant == null || (ici != null && !distant.isAfter(ici))) continue;
          }
          if (col.appliquerDistante(f)) n++;
        }
      }
      erreur.value = null;
    } catch (e) {
      erreur.value = 'Configuration de la mère illisible : $e';
    } finally {
      _applique = false;
    }
    recues.value += n;
    return n;
  }
}

/// La publication réelle : le service de la mère du MÊME processus, par son point d'entrée d'administration (`POST /admin/referentiel`).
Future<void> Function(String, String, Map<String, Object?>) publierVersMereLocale({required int port, required String admin, http.Client? client}) {
  final c = client ?? http.Client();
  return (collection, fiche, champs) async {
    final r = await c
        .post(Uri.parse('http://127.0.0.1:$port/admin/referentiel'),
            headers: {'content-type': 'application/json', 'x-admin': admin}, body: jsonEncode({'collection': collection, 'fiche': fiche, 'champs': champs}))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw StateError('la mère a répondu ${r.statusCode} : ${r.body}');
    // Un refus de la mère revient en 200 avec un statut : il est NOMMÉ, jamais avalé.
    final corps = jsonDecode(r.body);
    if (corps is Map && corps['statut'] == 'refusee') throw StateError('${corps['motif'] ?? corps['code']}');
  };
}
