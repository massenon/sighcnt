/// LA SAUVEGARDE ET LA RESTAURATION DES FICHIERS NUMÉRISÉS D'UN POSTE (lot D5, étape 7, miroir de SAUV-F de la maquette).
///
/// Le dossier des fichiers (`<aa>/<sha256>.<ext>`) n'est PAS dans le magasin : la sauvegarde du magasin ne le couvre donc pas. Cette sauvegarde est À PART :
///  - INCRÉMENTALE : un fichier que la destination tient déjà (même empreinte, même taille) n'est pas recopié ; les fichiers étant adressés par empreinte (immuables), recopier
///    n'apporterait rien ;
///  - JAMAIS TOURNANTE : rien ne se supprime à la destination, jamais (conservation illimitée, RG-14) ; les anciennes copies et les manifestes datés restent ;
///  - VÉRIFIÉE : l'empreinte est RECALCULÉE sur les octets réellement lus à la source, un fichier altéré n'est jamais propagé (il est nommé), et la copie est RELUE à la destination
///    (déchiffrée, empreinte recalculée) avant d'être comptée ; l'écriture est atomique (`.tmp` puis renommage) ;
///  - CHIFFRÉE comme la source : la destination reçoit des fichiers scellés par la même clé (AES-256-GCM, l'empreinte liée au chiffré) ; sans clé (développement), en clair, et le dit ;
///  - BORNÉE en temps : une passe lancée par la minuterie du poste ne fige pas l'interface ; au moins un fichier par passe, le reste à la passe suivante (aucun curseur à tenir : la
///    destination dit ce qui est déjà copié) ;
///  - un MANIFESTE daté `manifestes/fichiers-AAAA-MM-JJ.json` (empreintes, formats, tailles : jamais un nom de patient ni un contenu) dit ce que la destination porte.
///
/// La destination n'est JAMAIS créée par le poste : elle doit exister, être un dossier absolu, être inscriptible (par une écriture réelle) et ne pas recouvrir le dossier des fichiers.
/// La restauration est une SIMULATION par défaut ; elle ne pose jamais une copie altérée, ne remplace jamais un fichier intact, met de côté (`_alteres/`) un fichier altéré avant de
/// le remplacer.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'stockage_fichiers.dart';

/// Le sous-dossier de la destination qui reçoit la copie (l'arbre `<aa>/<sha256>.<ext>`, les manifestes).
const String dossierSauvegardeFichiers = 'fichiers-numerises';

String _canonique(String chemin) {
  try {
    return Directory(chemin).resolveSymbolicLinksSync();
  } catch (_) {
    return Directory(chemin).absolute.path;
  }
}

String _avecSeparateur(String p) => p.endsWith(Platform.pathSeparator) ? p : '$p${Platform.pathSeparator}';

/// `true` : [a] est [b] ou se trouve dessous (chemins déjà canoniques).
bool cheminSousOuEgal(String a, String b) => a == b || _avecSeparateur(a).startsWith(_avecSeparateur(b));

/// Le contrôle d'une destination AVANT toute copie : `null` si elle convient, sinon le refus nommé. La destination n'est jamais créée.
Future<RefusFichier?> verifierDestinationSauvegarde(String destination, String dossierFichiers) async {
  final d = destination.trim();
  if (d.isEmpty) return const RefusFichier('DESTINATION_ABSENTE', 'aucune destination n’est réglée pour la sauvegarde des fichiers', 'Régler un dossier de destination (de préférence sur un autre disque).');
  if (!Directory(d).isAbsolute) {
    return RefusFichier('DESTINATION_RELATIVE', '« $d » n’est pas un chemin absolu : il dépendrait du dossier de lancement du logiciel', 'Saisir le chemin complet du dossier (par exemple D:\\sauvegardes ou /mnt/sauvegardes).');
  }
  final type = FileSystemEntity.typeSync(d);
  if (type == FileSystemEntityType.notFound) {
    return RefusFichier('DESTINATION_INEXISTANTE', '« $d » n’existe pas (le poste ne crée jamais la destination : un disque externe absent se créerait sur le disque des données)', 'Brancher le disque ou créer le dossier, puis recommencer.');
  }
  if (type != FileSystemEntityType.directory) {
    return RefusFichier('DESTINATION_PAS_UN_DOSSIER', '« $d » n’est pas un dossier', 'Choisir un dossier.');
  }
  final sonde = File('$d${Platform.pathSeparator}.sigh-ecriture-${Random().nextInt(1 << 30).toRadixString(16)}.tmp');
  try {
    await sonde.writeAsString('essai', flush: true);
    await sonde.delete();
  } catch (e) {
    try {
      if (sonde.existsSync()) sonde.deleteSync();
    } catch (_) {}
    return RefusFichier('DESTINATION_NON_INSCRIPTIBLE', 'le poste n’a pas pu écrire dans « $d » ($e)', 'Vérifier les droits d’écriture et la place libre de ce dossier.');
  }
  final cd = _canonique(d);
  final cs = _canonique(dossierFichiers);
  if (cheminSousOuEgal(cd, cs) || cheminSousOuEgal(cs, cd)) {
    return const RefusFichier('DESTINATION_RECOUVRE_LES_FICHIERS', 'la destination recouvre le dossier des fichiers numérisés : la copie serait la source elle-même', 'Choisir un dossier distinct, hors du dossier des fichiers.');
  }
  return null;
}

class RapportSauvegardeFichiers {
  RapportSauvegardeFichiers(
      {required this.copies, required this.dejaCopies, required this.restants, required this.alteres, required this.erreurs, required this.manifeste, required this.duree, required this.octetsCopies, required this.chiffre});

  /// Fichiers copiés à cette passe (relus et vérifiés à la destination).
  final int copies;

  /// Fichiers que la destination tenait déjà (non recopiés).
  final int dejaCopies;

  /// Fichiers qui attendent la passe suivante (borne de temps).
  final int restants;

  /// Fichiers ALTÉRÉS à la source : jamais copiés, nommés par leur empreinte.
  final List<String> alteres;

  /// Erreurs de copie (une ligne par fichier : empreinte et motif).
  final List<String> erreurs;
  final String? manifeste;
  final Duration duree;
  final int octetsCopies;

  /// La copie est chiffrée au repos (la source et la destination portent la même clé).
  final bool chiffre;

  bool get complet => restants == 0 && alteres.isEmpty && erreurs.isEmpty;
}

String _jour(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Copie incrémentale vérifiée des fichiers de [source] vers [destination]. Lève [ErreurFichier] (refus nommé) si la destination ne convient pas.
Future<RapportSauvegardeFichiers> sauvegarderFichiers(StockageFichiers source,
    {required String destination, List<int>? cle, Duration borne = const Duration(seconds: 15), DateTime Function()? horloge}) async {
  final refus = await verifierDestinationSauvegarde(destination, source.dossier);
  if (refus != null) throw ErreurFichier(refus);
  final maintenant = horloge ?? DateTime.now;
  final chrono = Stopwatch()..start();
  final dest = StockageFichiers('${destination.trim()}/$dossierSauvegardeFichiers', cle: cle);
  final shas = await source.empreintes().toList()
    ..sort();
  var copies = 0, dejaCopies = 0, octets = 0;
  var restants = 0;
  final alteres = <String>[], erreurs = <String>[];
  final entrees = <Map<String, Object?>>[];
  for (var i = 0; i < shas.length; i++) {
    final sha = shas[i];
    try {
      final chemin = await source.cheminDe(sha);
      if (chemin == null) continue;
      final ext = chemin.split('.').last;
      final meta = await source.meta(sha);
      // Déjà à la destination (même taille que la source) : rien à recopier. La copie est relue et vérifiée À SA CRÉATION ; le contrôle complet est `controlerSauvegardeFichiers`.
      final cheminDest = dest.cheminPour(sha, ext);
      if (File(cheminDest).existsSync() && File(cheminDest).lengthSync() == File(chemin).lengthSync()) {
        dejaCopies++;
        entrees.add({'sha256': sha, 'ext': ext, 'mime': meta?.mime, 'taille': meta?.taille});
        continue;
      }
      // La borne de temps ne se lit qu'AVANT une copie (constater qu'un fichier est déjà copié ne coûte rien) ; au moins une copie par passe.
      if (chrono.elapsed > borne && (copies + alteres.length + erreurs.length) > 0) {
        restants = shas.length - i;
        break;
      }
      // L'empreinte est RECALCULÉE sur les octets lus : un fichier altéré à la source n'est JAMAIS propagé.
      final Uint8List clair;
      try {
        clair = await source.lire(sha);
      } on ErreurFichier catch (e) {
        if (e.refus.code == 'FICHIER_ALTERE') {
          alteres.add(sha);
          continue;
        }
        rethrow;
      }
      final usage = meta?.usages.isNotEmpty == true ? meta!.usages.first : const <String, Object?>{};
      await dest.ranger(clair, famille: '${usage['famille'] ?? 'courrier'}', zone: (usage['zone'] as num?)?.toInt() ?? 0, deposePar: meta?.deposePar);
      for (final u in (meta?.usages ?? const <Map<String, Object?>>[]).skip(1)) {
        await dest.ajouterUsage(sha, famille: '${u['famille']}', zone: (u['zone'] as num?)?.toInt() ?? 0);
      }
      // La copie est RELUE (déchiffrée, empreinte recalculée) avant d'être comptée.
      if (await dest.etat(sha) != EtatLocalFichier.present) {
        erreurs.add('${docAbrege(sha)} : la copie relue à la destination n’a pas son empreinte');
        continue;
      }
      copies++;
      octets += clair.length;
      entrees.add({'sha256': sha, 'ext': ext, 'mime': meta?.mime, 'taille': meta?.taille});
    } on ErreurFichier catch (e) {
      erreurs.add('${docAbrege(sha)} : ${e.refus.code}, ${e.refus.motif}');
    } catch (e) {
      erreurs.add('${docAbrege(sha)} : $e');
    }
  }
  String? manifeste;
  if (entrees.isNotEmpty || shas.isEmpty) {
    final dir = Directory('${destination.trim()}/$dossierSauvegardeFichiers/manifestes');
    await dir.create(recursive: true);
    final f = File('${dir.path}/fichiers-${_jour(maintenant())}.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
        jsonEncode({
          'date': maintenant().toIso8601String(),
          'chiffre': dest.chiffre,
          'fichiers': entrees,
          'alteres': alteres,
          'restants': restants,
        }),
        flush: true);
    await tmp.rename(f.path);
    manifeste = f.path;
  }
  return RapportSauvegardeFichiers(
      copies: copies, dejaCopies: dejaCopies, restants: restants, alteres: alteres, erreurs: erreurs, manifeste: manifeste, duree: chrono.elapsed, octetsCopies: octets, chiffre: dest.chiffre);
}

class RapportControleSauvegarde {
  RapportControleSauvegarde({required this.intacts, required this.manquants, required this.alteres});
  final int intacts;

  /// Fichiers de la source que la destination n'a pas.
  final List<String> manquants;

  /// Copies de la destination dont l'empreinte ne tient plus.
  final List<String> alteres;
  bool get sain => manquants.isEmpty && alteres.isEmpty;
}

/// Relit TOUTE la destination (déchiffrement, empreinte recalculée) et la confronte à la source : manquants, copies altérées.
Future<RapportControleSauvegarde> controlerSauvegardeFichiers(StockageFichiers source, {required String destination, List<int>? cle}) async {
  final dest = StockageFichiers('${destination.trim()}/$dossierSauvegardeFichiers', cle: cle);
  var intacts = 0;
  final manquants = <String>[], alteres = <String>[];
  await for (final sha in source.empreintes()) {
    switch (await dest.etat(sha)) {
      case EtatLocalFichier.present:
        intacts++;
      case EtatLocalFichier.absent:
        manquants.add(sha);
      case EtatLocalFichier.altere:
        alteres.add(sha);
    }
  }
  return RapportControleSauvegarde(intacts: intacts, manquants: manquants, alteres: alteres);
}

class RapportRestaurationFichiers {
  RapportRestaurationFichiers(
      {required this.simulation,
      required this.aRestaurer,
      required this.restaures,
      required this.dejaIntacts,
      required this.misDeCote,
      required this.copiesAlterees,
      required this.erreurs});
  final bool simulation;

  /// Fichiers que la destination porte et que ce poste n'a pas (ou a altérés).
  final int aRestaurer;
  final int restaures;
  final int dejaIntacts;

  /// Fichiers ALTÉRÉS du poste, mis de côté dans `_alteres/` avant d'être remplacés.
  final int misDeCote;

  /// Copies de la sauvegarde elles-mêmes altérées : JAMAIS posées, nommées.
  final List<String> copiesAlterees;
  final List<String> erreurs;

  /// Tout ce qui devait l'être l'est (code de sortie 0 de la maquette) : aucune copie altérée, aucune erreur.
  bool get sain => copiesAlterees.isEmpty && erreurs.isEmpty;
}

/// Restaure les fichiers de la sauvegarde [source] vers [cible]. [simulation] (défaut) : ne touche à rien et dit ce qui serait fait. Un fichier intact du poste n'est JAMAIS écrasé.
Future<RapportRestaurationFichiers> restaurerFichiers(StockageFichiers cible,
    {required String source, List<int>? cle, bool simulation = true, DateTime Function()? horloge}) async {
  final racine = '${source.trim()}/$dossierSauvegardeFichiers';
  if (!Directory(racine).existsSync()) {
    throw ErreurFichier(RefusFichier('SAUVEGARDE_INTROUVABLE', 'aucune sauvegarde de fichiers sous « $racine »', 'Choisir la destination où la sauvegarde a été faite.'));
  }
  final sauv = StockageFichiers(racine, cle: cle);
  var aRestaurer = 0, restaures = 0, intacts = 0, misDeCote = 0;
  final alterees = <String>[], erreurs = <String>[];
  final maintenant = horloge ?? DateTime.now;
  await for (final sha in sauv.empreintes()) {
    final etat = await cible.etat(sha);
    if (etat == EtatLocalFichier.present) {
      intacts++;
      continue;
    }
    final Uint8List clair;
    try {
      clair = await sauv.lire(sha);
    } on ErreurFichier catch (e) {
      // La copie de la sauvegarde est altérée : elle n'est JAMAIS posée.
      if (e.refus.code == 'FICHIER_ALTERE') {
        alterees.add(sha);
      } else {
        erreurs.add('${docAbrege(sha)} : ${e.refus.code}');
      }
      continue;
    }
    aRestaurer++;
    if (simulation) continue;
    try {
      if (etat == EtatLocalFichier.altere) {
        final chemin = await cible.cheminDe(sha);
        if (chemin != null) {
          final garde = Directory('${cible.dossier}/_alteres');
          await garde.create(recursive: true);
          await File(chemin).rename('${garde.path}/${chemin.split('/').last}.${maintenant().millisecondsSinceEpoch}');
          misDeCote++;
        }
      }
      final meta = await sauv.meta(sha);
      final usages = meta?.usages ?? const <Map<String, Object?>>[];
      final u0 = usages.isNotEmpty ? usages.first : const <String, Object?>{};
      await cible.ranger(clair, famille: '${u0['famille'] ?? 'courrier'}', zone: (u0['zone'] as num?)?.toInt() ?? 0, deposePar: meta?.deposePar);
      for (final u in usages.skip(1)) {
        await cible.ajouterUsage(sha, famille: '${u['famille']}', zone: (u['zone'] as num?)?.toInt() ?? 0);
      }
      if (await cible.etat(sha) == EtatLocalFichier.present) {
        restaures++;
      } else {
        erreurs.add('${docAbrege(sha)} : le fichier restauré n’a pas son empreinte');
      }
    } on ErreurFichier catch (e) {
      erreurs.add('${docAbrege(sha)} : ${e.refus.code}, ${e.refus.motif}');
    }
  }
  return RapportRestaurationFichiers(
      simulation: simulation, aRestaurer: aRestaurer, restaures: restaures, dejaIntacts: intacts, misDeCote: misDeCote, copiesAlterees: alterees, erreurs: erreurs);
}
