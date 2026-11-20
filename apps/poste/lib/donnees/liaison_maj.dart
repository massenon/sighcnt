import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;

import 'maj_poste.dart';

/// Ce que l'écran « Mettre à jour le logiciel » ne peut pas savoir seul : le service du poste, son rôle dans la clinique et les gestes du système. Posé par `main.dart` ;
/// remplacé par les tests (aucune boîte de dialogue, aucune sortie de processus). `service` vaut `null` sur un poste sans chiffrement (développement).
class LiaisonMaj {
  LiaisonMaj._();

  static ServiceMiseAJour? service;

  /// Joue une opération du service (par défaut : telle quelle). Les tests d'écran la font tourner hors de leur horloge simulée.
  static Future<T> Function<T>(Future<T> Function() f) executer = <T>(f) => f();

  /// Ce poste est-il un fileul RATTACHÉ à une mère ? (un fileul non rattaché importe comme une mère de lui-même)
  static bool Function() fileulRattache = () => false;

  /// Le dernier tour réussi de ce fileul avec sa mère (avertissement `IMPORT_PLUS_ANCIEN_QUE_SYNC`).
  static DateTime? Function() derniereSynchro = () => null;

  /// Après un import sur un fileul rattaché : repart du début du journal de la mère (idempotent, la file d'envoi n'est jamais touchée).
  static void Function() rejouerJournal = () {};

  /// Écrit sur le disque tout ce que le magasin en mémoire n'a pas encore écrit (avant une copie, un export ou un remplacement : la copie doit contenir la dernière saisie).
  static Future<void> Function() figerMagasin = () async {};

  /// Ferme le poste après une opération qui a remplacé son magasin : le magasin en mémoire n'est jamais réécrit par-dessus la base remplacée.
  static Future<void> Function() redemarrer = () async => exit(0);

  /// Les boîtes de dialogue du système : choisir un export à importer, choisir où écrire l'export.
  static Future<String?> Function() choisirExport = () async {
    final f = await FilePicker.pickFile(dialogTitle: 'Export à importer (.sighexp)', type: FileType.any);
    return f?.path;
  };
  static Future<String?> Function(String nom) choisirDestination = (nom) async {
    final lieu = await fs.getSaveLocation(suggestedName: nom, acceptedTypeGroups: [const fs.XTypeGroup(label: 'Export SIGH-CNT', extensions: ['sighexp'])]);
    return lieu?.path;
  };

  static void reinitialiser() {
    service = null;
    executer = <T>(f) => f();
    fileulRattache = () => false;
    derniereSynchro = () => null;
    rejouerJournal = () {};
    figerMagasin = () async {};
    redemarrer = () async => exit(0);
  }
}

