import 'dart:async';

import 'package:flutter/foundation.dart';

import 'etat_sync.dart';

/// Ce que le moteur de synchronisation sait dire de lui à un instant donné (reflet de `Fileul` / `GET /etat`).
/// L'interface ne dépend pas du moteur : en production c'est `sigh_sync`, dans les tests un faux.
class InstantaneSync {
  const InstantaneSync({this.horsLigne = false, this.suspendu = false, this.enAttente = 0, this.aTraiter = 0, this.tentatives = 0, this.derniereErreur});
  final bool horsLigne;
  final bool suspendu;
  final int enAttente;
  final int aTraiter;
  final int tentatives;
  final String? derniereErreur;

  factory InstantaneSync.depuisEtat(Map<String, Object?> j) => InstantaneSync(
        horsLigne: j['hors_ligne'] == true,
        suspendu: j['suspendu'] == true,
        enAttente: ((j['en_attente'] ?? 0) as num).toInt(),
        aTraiter: ((j['a_traiter'] ?? const []) as List).length,
        tentatives: ((j['tentatives'] ?? 0) as num).toInt(),
        derniereErreur: j['derniere_erreur'] as String?,
      );
}

typedef LireInstantane = Future<InstantaneSync> Function();

/// Règle de lecture, dans l'ordre : suspendu > hors ligne > en retard (des opérations attendent) > synchronisé.
/// Une panne du moteur lui-même se lit « hors ligne » : jamais un voyant resté vert faute de réponse.
EtatSync lireEtat(InstantaneSync i, {DateTime? depuis}) {
  if (i.suspendu) return EtatSync(niveau: NiveauSync.suspendu, enAttente: i.enAttente, aTraiter: i.aTraiter, depuis: depuis);
  if (i.horsLigne) return EtatSync(niveau: NiveauSync.horsLigne, enAttente: i.enAttente, aTraiter: i.aTraiter, depuis: depuis);
  if (i.enAttente > 0) return EtatSync(niveau: NiveauSync.enCours, enAttente: i.enAttente, aTraiter: i.aTraiter, depuis: depuis);
  return EtatSync(niveau: NiveauSync.synchronise, aTraiter: i.aTraiter);
}

/// Source d'état alimentée par l'interrogation périodique du moteur. `depuis` ne change que lorsque le NIVEAU change :
/// « hors ligne depuis 12 min » doit compter à partir du début de la coupure, pas du dernier sondage.
class SourceSyncPeriodique extends ValueNotifier<EtatSync> {
  SourceSyncPeriodique({required this.lire, this.intervalle = const Duration(seconds: 2), DateTime Function()? maintenant})
      : _maintenant = maintenant ?? DateTime.now,
        super(const EtatSync(niveau: NiveauSync.horsLigne)) {
    _minuterie = Timer.periodic(intervalle, (_) => actualiser());
    actualiser();
  }

  final LireInstantane lire;
  final Duration intervalle;
  final DateTime Function() _maintenant;
  Timer? _minuterie;
  bool _fini = false;

  Future<void> actualiser() async {
    InstantaneSync i;
    try {
      i = await lire();
    } catch (_) {
      i = const InstantaneSync(horsLigne: true);
    }
    if (_fini) return;
    var e = lireEtat(i);
    final depuis = e.niveau == value.niveau && value.depuis != null ? value.depuis : (e.niveau == NiveauSync.synchronise ? null : _maintenant());
    e = EtatSync(niveau: e.niveau, enAttente: e.enAttente, aTraiter: e.aTraiter, depuis: depuis);
    value = e;
  }

  @override
  void dispose() {
    _fini = true;
    _minuterie?.cancel();
    super.dispose();
  }
}
