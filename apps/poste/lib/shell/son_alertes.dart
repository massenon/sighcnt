import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../modules/cfg/cfb_notifications.dart' show CfbAudio;
import 'centre_notifications.dart';

/// LA SONORISATION DES ALERTES (`SIGH.notifications`, canal sonore de la maquette). Le son est un CANAL : ce service ne décide d'aucune alerte, il écoute le
/// centre de notifications et sonne quand une alerte NOUVELLE et non acquittée apparaît.
///
/// Les règles viennent des réglages de « Notifications » (`notificationsSon`) :
///  - `son` faux ou profil silencieux : rien ne sonne (cloche, badge et messages continuent) ;
///  - profil « critique » : seules les alertes graves sonnent, deux fois ; les autres profils sonnent pour toutes, en son renforcé si une alerte est grave ;
///  - la MÊME alerte ne resonne pas avant la temporisation choisie (une alerte persistante, un stock sous son seuil, ne doit pas sonner à chaque passage) ;
///  - entendre n'est pas traiter : une alerte acquittée ne sonne pas ;
///  - une panne audio ne bloque jamais rien.
class SonAlertes {
  SonAlertes(this.centre, {DateTime Function()? horloge, Future<bool> Function({bool fort})? jouer, bool Function()? disponible})
      : _horloge = horloge ?? DateTime.now,
        _jouer = jouer,
        _disponible = disponible;
  final CentreNotifications centre;
  final DateTime Function() _horloge;
  final Future<bool> Function({bool fort})? _jouer;
  final bool Function()? _disponible;
  final Map<String, DateTime> _dernierSon = {};
  bool _actif = false;

  /// Nombre de fois où le service a sonné (lu par les tests et par le diagnostic).
  int sonneries = 0;

  void demarrer() {
    if (_actif) return;
    _actif = true;
    centre.addListener(_surChangement);
    _surChangement();
  }

  void arreter() {
    if (!_actif) return;
    _actif = false;
    centre.removeListener(_surChangement);
  }

  Map<String, Object?> _params() {
    final f = centre.magasin.collection('reglages').actives.where((x) => x['id'] == 'notificationsSon').firstOrNull;
    final v = f?['valeur'];
    return cfbParamsNotif(v is Map ? v.cast<String, Object?>() : null);
  }

  void _surChangement() {
    if (!_actif) return;
    if (!(_disponible ?? CfbAudio.disponible)()) return;
    final p = _params();
    if (p['son'] != true) return;
    final profil = cfbProfilAudio(p['profil']);
    if (profil.$1 == 'silencieux') return;
    final tempo = Duration(minutes: (p['temporisation'] is num ? (p['temporisation'] as num).toInt() : 30));
    final maintenant = _horloge();
    // Les alertes détaillées (non regroupées) : on sonne pour chacune d'elles, pas pour une ligne de regroupement qui masquerait les nouvelles.
    final nouvelles = <AlerteNotif>[];
    for (final a in centre.collecter(detaille: true)) {
      if (a.acquittee || a.source == 'audio') continue;
      if (profil.$1 == 'critique' && a.priorite != 'critique') continue;
      final vu = _dernierSon[a.cle];
      if (vu != null && maintenant.difference(vu) < tempo) continue;
      nouvelles.add(a);
    }
    if (nouvelles.isEmpty) return;
    for (final a in nouvelles) {
      _dernierSon[a.cle] = maintenant;
    }
    final fort = nouvelles.any((a) => a.priorite == 'critique');
    sonneries++;
    _sonner(fort: fort, repetitions: profil.$4 + 1);
  }

  Future<void> _sonner({required bool fort, required int repetitions}) async {
    final jouer = _jouer ?? CfbAudio.jouer;
    try {
      for (var i = 0; i < repetitions; i++) {
        await jouer(fort: fort);
        if (i + 1 < repetitions) await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
    } catch (_) {
      // Une panne audio ne bloque jamais rien : le visuel demeure.
    }
  }
}
