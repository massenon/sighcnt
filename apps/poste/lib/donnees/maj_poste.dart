import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import 'persistance.dart';

/// LA MISE À JOUR SANS PERTE AU POSTE (lot MAJ, PRD-MISE-A-JOUR) : « Préparer la mise à jour », migration contrôlée, essai à blanc, retour arrière, export portable, import.
/// Même service sur la MÈRE et sur un FILEUL (la mère reste l'autorité de la synchronisation ; un fileul qui importe se resynchronise ensuite par le journal).
///
/// Les règles sont au domaine (`packages/domaine/lib/src/maj/maj.dart`) ; ici : le disque et le chiffrement. L'INSTALLATEUR ne touche pas au dossier de données.
/// Les copies vivent à côté, dans `<dossier>-maj/`, jamais dans le dossier d'installation. Rien n'est supprimé (RG-14) : ce qui est remplacé est MIS DE CÔTÉ.
class RefusMajException implements Exception {
  RefusMajException(this.refus);
  final RefusMaj refus;
  String get code => refus.code;
  @override
  String toString() => '$refus';
}

class RapportMaj {
  RapportMaj({required this.comptes, this.notes = const [], this.etapes = const [], this.avertissements = const [], this.saisies = const [], this.copie});
  final RapportComptes comptes;
  final List<String> notes, etapes, avertissements;
  final List<SaisiePosterieure> saisies;
  final String? copie;
}

String _hex(List<int> b) => [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();

class ServiceMiseAJour {
  ServiceMiseAJour({
    required this.dossier,
    required List<int> cle,
    DateTime Function()? horloge,
    this.reglages = ReglagesMaj.defaut,
    this.dossierFichiers,
    this.apresEcritureCollection,
  })  : _cle = cle,
        _horloge = horloge ?? DateTime.now;

  final String dossier;
  final List<int> _cle;
  final DateTime Function() _horloge;
  final ReglagesMaj reglages;

  /// Le dossier des fichiers numérisés (joint à l'export portable, jamais écrasé à l'import). `null` : le poste n'en tient pas.
  final String? dossierFichiers;

  /// Crochet d'essai (coupure simulée) : appelé après l'écriture de la collection numéro `n` d'une migration ou d'un import.
  final void Function(int n)? apresEcritureCollection;

  static final _aes = AesGcm.with256bits();
  String get dossierMaj => '$dossier-maj';
  PersistanceFichiers get _p => PersistanceFichiers(dossier, cle: _cle);
  String get empreinteCle => sha256Octets(_cle);
  File get _marqueur => File('$dossierMaj/en-cours.json');
  File get _journal => File('$dossierMaj/journal.jsonl');

  // --- journal (RG-12) -----------------------------------------------------------------------------------------------------------------------------
  Future<void> _journaliser(String action, Map<String, Object?> detail) async {
    await Directory(dossierMaj).create(recursive: true);
    await _journal.writeAsString('${jsonEncode({'quand': _horloge().toIso8601String(), 'action': action, ...detail})}\n', mode: FileMode.append, flush: true);
  }

  Future<List<Map<String, Object?>>> journal() async =>
      !await _journal.exists() ? [] : [for (final l in await _journal.readAsLines()) if (l.trim().isNotEmpty) (jsonDecode(l) as Map).cast<String, Object?>()];

  // --- version du format ------------------------------------------------------------------------------------------------------------------------------
  /// La version du format écrite dans la fiche `_meta` du magasin. 0 : aucun repère (poste d'avant), ou dossier neuf (alors rien à migrer, voir [estNeuf]).
  Future<int> formatDonnees() async => ((await _p.lireMeta())['formatDonnees'] as num?)?.toInt() ?? formatSansVersion;

  Future<bool> estNeuf() async => (await _p.lireTout()).isEmpty;

  /// À l'ouverture : un dossier neuf reçoit le format courant (rien à migrer) ; sinon le plan est calculé. Un format plus récent est REFUSÉ (jamais lu à moitié).
  Future<PlanMigration> plan() async {
    final p = _p;
    if ((await p.lireTout()).isEmpty && (await formatDonnees()) == 0) return const PlanMigration([], formatDonneesCourant, formatDonneesCourant, null);
    return planifierMigration(await formatDonnees());
  }

  Future<void> marquerNeuf() async {
    if (await estNeuf() && await formatDonnees() == 0) await _p.ecrireMeta({...await _p.lireMeta(), 'formatDonnees': formatDonneesCourant});
  }

  // --- copies vérifiées ------------------------------------------------------------------------------------------------------------------------------------
  Future<List<int>> _signer(Map<String, Object?> m) async => (await Hmac.sha256().calculateMac(utf8.encode(jsonCanonique(m)), secretKey: SecretKey(_cle))).bytes;

  Future<void> _copierCollections(String source, String cible) async {
    final s = Directory(source);
    await Directory(cible).create(recursive: true);
    if (!await s.exists()) return; // dossier neuf : rien à copier
    await for (final e in s.list()) {
      if (e is! File) continue;
      final n = e.uri.pathSegments.last;
      if (n.endsWith('.sigh') || n.endsWith('.json')) await e.copy('$cible/$n');
    }
  }

  Future<CollectionsMaj> _lire(String dir) async => {for (final e in (await PersistanceFichiers(dir, cle: _cle).lireTout()).entries) e.key: e.value};

  String _horodatage() => _horloge().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

  /// « Préparer la mise à jour » : copie chiffrée des collections, RESTAURATION VÉRIFIÉE dans un dossier neuf, comptes et empreintes consignés, manifeste signé, journal RG-12.
  /// Rend le dossier de la copie. Un écart entre l'original et la restauration refuse (`MAJ_COMPTES_DIFFERENTS`) et la copie n'est PAS déclarée vérifiée.
  Future<String> preparer() async {
    final id = 'copie-${_horodatage()}';
    final dest = '$dossierMaj/copies/$id';
    final p = _p;
    final vivant = await p.lireTout();
    if (p.problemes.isNotEmpty) throw RefusMajException(RefusMaj(CodeMaj.comptesDifferents, 'Une collection est illisible : ${p.problemes.first}', 'Réparer ou restaurer avant toute mise à jour'));
    final avant = releverCollections(vivant);
    await _copierCollections(dossier, '$dest/donnees');
    // restauration vérifiée : dans un dossier NEUF, jamais sur place
    final essai = '$dossierMaj/verif/$id';
    await _copierCollections('$dest/donnees', essai);
    final restaure = await _lire(essai);
    final rap = comparerReleves(avant, releverCollections(restaure));
    await Directory(essai).delete(recursive: true); // la restauration d'essai est un jetable, jamais une donnée de la clinique
    if (!rap.ok) {
      await _journaliser('preparer_refuse', {'copie': id, 'rapport': rap.phrase});
      throw RefusMajException(RefusMaj(CodeMaj.comptesDifferents, 'La restauration de la copie ne redonne pas les mêmes données : ${rap.phrase}', 'Relancer ; si l’écart persiste, ne pas mettre à jour et appeler l’assistance'));
    }
    final manifeste = <String, Object?>{
      'copie': id,
      'faiteLe': _horloge().toUtc().toIso8601String(),
      'formatDonnees': await formatDonnees(),
      'empreinteCle': empreinteCle,
      'collections': {for (final e in avant.entries) e.key: e.value.versJson()},
    };
    await File('$dest/manifeste.json').writeAsString(jsonEncode({...manifeste, 'signature': _hex(await _signer(manifeste))}), flush: true);
    await _p.ecrireMeta({...await _p.lireMeta(), 'derniereCopieVerifiee': manifeste['faiteLe'], 'derniereCopie': id});
    await _journaliser('preparer', {'copie': id, 'formatDonnees': manifeste['formatDonnees'], 'rapport': rap.phrase, 'collections': manifeste['collections']});
    return dest;
  }

  Future<Map<String, Object?>?> _manifesteValide(String dir) async {
    try {
      final j = (jsonDecode(await File('$dir/manifeste.json').readAsString()) as Map).cast<String, Object?>();
      final sig = j.remove('signature');
      if (sig != _hex(await _signer(j)) || j['empreinteCle'] != empreinteCle) return null;
      return j;
    } catch (_) {
      return null;
    }
  }

  /// La dernière copie dont le manifeste est signé par CETTE clé ET dont le contenu se relit aux comptes du manifeste (rien n'est cru sur parole : la méta ne suffit pas).
  Future<({String dir, DateTime faiteLe, Map<String, Object?> manifeste})?> derniereCopieVerifiee() async {
    final d = Directory('$dossierMaj/copies');
    if (!await d.exists()) return null;
    final noms = [for (final e in await d.list().toList()) if (e is Directory) e.uri.pathSegments.where((x) => x.isNotEmpty).last]..sort();
    for (final n in noms.reversed) {
      final dir = '${d.path}/$n';
      final m = await _manifesteValide(dir);
      if (m == null) continue;
      final relu = releverCollections(await _lire('$dir/donnees'));
      final attendu = {for (final e in (m['collections'] as Map).entries) '${e.key}': ReleveCollection(((e.value as Map)['compte'] as num).toInt(), '${(e.value as Map)['empreinte']}')};
      if (!comparerReleves(attendu, relu).ok) continue;
      return (dir: dir, faiteLe: DateTime.parse('${m['faiteLe']}'), manifeste: m);
    }
    return null;
  }

  // --- reprise après coupure -------------------------------------------------------------------------------------------------------------------------------
  /// À appeler AVANT toute ouverture du magasin : si une migration ou un import a été interrompu, les collections reviennent à la copie d'AVANT (jamais un état mixte).
  /// Rend vrai si une reprise a eu lieu.
  Future<bool> reprendreSiInterrompu() async {
    if (!await _marqueur.exists()) return false;
    final m = (jsonDecode(await _marqueur.readAsString()) as Map).cast<String, Object?>();
    final avant = '${m['avant']}';
    final cote = '$dossierMaj/interrompus/${_horodatage()}';
    await Directory(cote).create(recursive: true);
    // l'état mixte est MIS DE CÔTÉ (jamais supprimé), puis les collections d'avant reviennent
    final d = Directory(dossier);
    await for (final e in d.list()) {
      if (e is! File) continue;
      final n = e.uri.pathSegments.last;
      if (n.endsWith('.sigh') || n.endsWith('.json')) await e.rename('$cote/$n');
    }
    await _copierCollections(avant, dossier);
    await _marqueur.rename('$cote/en-cours.json');
    await _journaliser('reprise_apres_coupure', {'operation': m['operation'], 'retour_a': avant});
    return true;
  }

  Future<String> _avantOperation(String operation) async {
    final avant = '$dossierMaj/avant-$operation-${_horodatage()}';
    await _copierCollections(dossier, avant);
    await Directory(dossierMaj).create(recursive: true);
    await _marqueur.writeAsString(jsonEncode({'operation': operation, 'avant': avant, 'debut': _horloge().toIso8601String()}), flush: true);
    return avant;
  }

  Future<void> _terminer() async {
    if (await _marqueur.exists()) await _marqueur.rename('$dossierMaj/termine-${_horodatage()}.json');
  }

  Future<void> _ecrireTout(CollectionsMaj c, int format, {required List<String> aMettreDeCote}) async {
    final p = _p;
    var n = 0;
    for (final e in c.entries) {
      await p.ecrire(e.key, e.value);
      apresEcritureCollection?.call(++n);
    }
    for (final nom in aMettreDeCote) {
      for (final ext in ['sigh', 'json']) {
        final f = File('$dossier/$nom.$ext');
        if (await f.exists()) {
          await Directory('$dossierMaj/remplacees').create(recursive: true);
          await f.rename('$dossierMaj/remplacees/$nom.$ext.${_horodatage()}');
        }
      }
    }
    await p.ecrireMeta({...await p.lireMeta(), 'formatDonnees': format});
  }

  // --- migration -----------------------------------------------------------------------------------------------------------------------------------------------
  /// ESSAI À BLANC : dit ce qui changerait, n'écrit RIEN (ni données, ni journal, ni marqueur).
  Future<RapportMaj> essaiABlanc() async {
    final plan = await this.plan();
    if (plan.refus != null) throw RefusMajException(plan.refus!);
    final c = await _lire(dossier);
    final avant = releverCollections(c);
    final r = executerMigrations(c, plan);
    return RapportMaj(comptes: comparerReleves(avant, releverCollections(r.collections), modifieesParMigration: r.modifiees), notes: r.notes, etapes: r.etapes);
  }

  /// Lance la migration. Refus nommés : geste, `DONNEES_PLUS_RECENTES`, `MAJ_SANS_SAUVEGARDE` (copie vérifiée de moins de [ReglagesMaj.ageMaxCopieHeures] h, relue sur disque).
  /// Le poste ne passe en service qu'après le contrôle des comptes et des empreintes ; un écart remet les données d'AVANT.
  Future<RapportMaj> migrer({required bool geste}) async {
    final plan = await this.plan();
    if (plan.refus != null) throw RefusMajException(plan.refus!);
    final copie = await derniereCopieVerifiee();
    final refus = jugerLancement(geste: geste, copieVerifieeLe: copie?.faiteLe, maintenant: _horloge().toUtc(), reglages: reglages);
    if (refus != null) {
      await _journaliser('migrer_refuse', {'code': refus.code, 'motif': refus.motif});
      throw RefusMajException(refus);
    }
    if (plan.aRien) return RapportMaj(comptes: const RapportComptes([]), notes: const ['Les données sont déjà au format courant.'], copie: copie!.dir);
    final c = await _lire(dossier);
    final avant = releverCollections(c);
    final r = executerMigrations(c, plan);
    final avantDir = await _avantOperation('migration');
    try {
      await _ecrireTout(r.collections, r.formatApres, aMettreDeCote: const []);
      final apres = releverCollections(await _lire(dossier));
      final rap = comparerReleves(avant, apres, modifieesParMigration: r.modifiees);
      final attendu = releverCollections(r.collections);
      final fidele = comparerReleves(attendu, apres).ok;
      if (!rap.ok || !fidele) throw RefusMajException(RefusMaj(CodeMaj.comptesDifferents, 'Le contrôle d’après migration refuse : ${rap.ok ? 'les données relues diffèrent de celles écrites' : rap.phrase}', 'Les données d’avant ont été remises ; ne pas mettre en service, appeler l’assistance'));
      await _terminer();
      await _journaliser('migrer', {'de': plan.de, 'vers': plan.vers, 'etapes': r.etapes, 'rapport': rap.phrase, 'copie': copie!.dir});
      return RapportMaj(comptes: rap, notes: r.notes, etapes: r.etapes, copie: copie.dir);
    } on Exception catch (e) {
      // une COUPURE (process tué, Error) ne passe pas ici : le marqueur reste et `reprendreSiInterrompu` agit au démarrage suivant
      await reprendreSiInterrompu();
      await _journaliser('migrer_annulee', {'cause': '$e', 'retour_a': avantDir});
      rethrow;
    }
  }

  // --- retour arrière -------------------------------------------------------------------------------------------------------------------------------------------
  /// Ce que ferait « Annuler la mise à jour » : la dernière copie vérifiée et la liste des saisies POSTÉRIEURES (à montrer avant). Ne change rien.
  Future<({RefusMaj? refus, List<SaisiePosterieure> saisies, DateTime? copieDu})> proposerRetourArriere({required bool geste}) async {
    final copie = await derniereCopieVerifiee();
    final j = jugerRetourArriere(geste: geste, copieVerifiee: copie != null, copie: copie == null ? null : await _lire('${copie.dir}/donnees'), actuel: await _lire(dossier));
    return (refus: j.refus, saisies: j.saisies, copieDu: copie?.faiteLe);
  }

  /// Restaure la dernière copie vérifiée. L'état ACTUEL est d'abord rangé à part (`avant-retour-…`) : les saisies postérieures ne sont jamais écrasées en silence, elles
  /// restent lisibles et sont listées au rapport.
  Future<RapportMaj> retourArriere({required bool geste}) async {
    final prop = await proposerRetourArriere(geste: geste);
    if (prop.refus != null) throw RefusMajException(prop.refus!);
    final copie = (await derniereCopieVerifiee())!;
    final avantDir = await _avantOperation('retour');
    try {
      final c = await _lire('${copie.dir}/donnees');
      final actuel = await _lire(dossier);
      await _ecrireTout(c, (copie.manifeste['formatDonnees'] as num).toInt(), aMettreDeCote: [for (final k in actuel.keys) if (!c.containsKey(k)) k]);
      final rap = comparerReleves(releverCollections(c), releverCollections(await _lire(dossier)));
      if (!rap.ok) throw RefusMajException(RefusMaj(CodeMaj.comptesDifferents, 'Le contrôle d’après retour arrière refuse : ${rap.phrase}', 'Les données d’avant le retour ont été remises'));
      await _terminer();
      await _journaliser('retour_arriere', {'copie': copie.dir, 'saisies_posterieures': prop.saisies.length, 'gardees_dans': avantDir, 'rapport': rap.phrase});
      return RapportMaj(comptes: rap, saisies: prop.saisies, copie: avantDir, notes: ['Les saisies postérieures à la copie sont gardées dans $avantDir (rien n’est écrasé en silence).']);
    } on Exception {
      // une COUPURE (process tué, Error) ne passe pas ici : le marqueur reste et `reprendreSiInterrompu` agit au démarrage suivant
      await reprendreSiInterrompu();
      rethrow;
    }
  }

  // --- export portable -------------------------------------------------------------------------------------------------------------------------------------------
  static const _entete = 'SGX1';

  /// EXPORT COMPLET PORTABLE : UN fichier chiffré (AES-256-GCM, clé de clinique) : base, fichiers numérisés, manifeste signé, version du format. Illisible sans la clé.
  /// L'en-tête n'en dit que l'empreinte de la clé (non réversible) pour refuser une autre clinique AVANT de déchiffrer. La clé n'est JAMAIS dans le fichier.
  Future<String> exporter(String destination) async {
    final c = await _lire(dossier);
    final fichiers = <String, String>{};
    if (dossierFichiers != null && await Directory(dossierFichiers!).exists()) {
      final racine = Directory(dossierFichiers!).absolute.path;
      await for (final e in Directory(racine).list(recursive: true)) {
        if (e is File) fichiers[e.path.substring(racine.length + 1).replaceAll('\\', '/')] = base64.encode(await e.readAsBytes());
      }
    }
    final releve = releverCollections(c);
    final manifeste = <String, Object?>{
      'exporteLe': _horloge().toUtc().toIso8601String(),
      'formatDonnees': await formatDonnees(),
      'empreinteCle': empreinteCle,
      'collections': {for (final e in releve.entries) e.key: e.value.versJson()},
      'fichiers': fichiers.length,
    };
    final contenu = utf8.encode(jsonEncode({'manifeste': manifeste, 'signature': _hex(await _signer(manifeste)), 'collections': c, 'fichiers': fichiers}));
    final boite = await _aes.encrypt(contenu, secretKey: SecretKey(_cle), aad: utf8.encode(_entete));
    final f = File(destination);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes([...utf8.encode(_entete), ...sha256Bytes(_cle), ...boite.concatenation()], flush: true);
    await tmp.rename(f.path);
    await _journaliser('exporter', {'fichier': f.path, 'formatDonnees': manifeste['formatDonnees'], 'collections': manifeste['collections'], 'fichiers': fichiers.length});
    return f.path;
  }

  static List<int> sha256Bytes(List<int> b) => [for (var i = 0; i < 64; i += 2) int.parse(sha256Octets(b).substring(i, i + 2), radix: 16)];

  /// Lit un export SANS rien écrire : en-tête, clé, déchiffrement, signature du manifeste. Refus nommés (`IMPORT_AUTRE_CLINIQUE`, `IMPORT_ALTERE`).
  Future<({Map<String, Object?> manifeste, CollectionsMaj collections, Map<String, String> fichiers, bool signatureValide, String? empreinteCleExport})> _ouvrirExport(String source) async {
    final brut = await File(source).readAsBytes();
    if (brut.length < 4 + 32 + 12 + 16 || utf8.decode(brut.sublist(0, 4), allowMalformed: true) != _entete) {
      throw RefusMajException(const RefusMaj(CodeMaj.importAltere, 'Ce fichier n’est pas un export SIGH.', 'Choisir un fichier d’export fait par « Exporter toute la base »'));
    }
    final empreinteExport = _hex(brut.sublist(4, 36));
    if (empreinteExport != empreinteCle) {
      throw RefusMajException(const RefusMaj(CodeMaj.importAutreClinique, 'L’export vient d’une autre clinique (la clé de chiffrement diffère).', 'Utiliser l’export de CETTE clinique, ou restaurer la bonne clé'));
    }
    final List<int> clair;
    try {
      clair = await _aes.decrypt(SecretBox.fromConcatenation(brut.sublist(36), nonceLength: 12, macLength: 16), secretKey: SecretKey(_cle), aad: utf8.encode(_entete));
    } catch (_) {
      throw RefusMajException(const RefusMaj(CodeMaj.importAltere, 'L’export est altéré ou tronqué : il ne se déchiffre pas.', 'Refaire l’export depuis le poste d’origine'));
    }
    final j = (jsonDecode(utf8.decode(clair)) as Map).cast<String, Object?>();
    final m = (j['manifeste'] as Map).cast<String, Object?>();
    return (
      manifeste: m,
      collections: {for (final e in (j['collections'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()]},
      fichiers: {for (final e in (j['fichiers'] as Map).entries) '${e.key}': '${e.value}'},
      signatureValide: j['signature'] == _hex(await _signer(m)),
      empreinteCleExport: '${m['empreinteCle']}',
    );
  }

  /// IMPORT d'un export portable, sur la mère ET sur un fileul (mêmes contrôles). Refus : geste, clé, autre clinique, altéré, plus récent, pas de copie préalable vérifiée.
  /// Le magasin local est REMPLACÉ (l'ancien est rangé dans `avant-import-…`), les fichiers numérisés absents sont ajoutés (jamais écrasés), le format est migré, les comptes sont
  /// contrôlés. Sur un fileul rattaché, les saisies locales absentes de la base importée (ou différentes) sont LISTÉES ; l'appelant relance ensuite la synchronisation par le journal
  /// (`MoteurFileul.rejouerDepuisLeDebut`) sans jamais écrire une fiche à la place de la mère. [essaiABlanc] : dit tout, n'écrit rien.
  Future<RapportMaj> importer(String source, {required bool geste, bool fileulRattache = false, DateTime? derniereSynchro, bool essaiABlanc = false}) async {
    final copie = await derniereCopieVerifiee();
    final copieOk = copie != null && _horloge().toUtc().difference(copie.faiteLe) <= Duration(hours: reglages.ageMaxCopieHeures);
    if (!geste) throw RefusMajException(jugerImport(geste: false, cleLocalePresente: true, empreinteCleExport: empreinteCle, empreinteCleLocale: empreinteCle, signatureValide: true, formatExport: 0, copieLocaleVerifiee: copieOk).refus!);
    final ex = await _ouvrirExport(source);
    final format = (ex.manifeste['formatDonnees'] as num?)?.toInt() ?? formatSansVersion;
    final exporteLe = DateTime.tryParse('${ex.manifeste['exporteLe']}');
    final j = jugerImport(
        geste: geste,
        cleLocalePresente: true,
        empreinteCleExport: ex.empreinteCleExport,
        empreinteCleLocale: empreinteCle,
        signatureValide: ex.signatureValide,
        formatExport: format,
        copieLocaleVerifiee: copieOk || essaiABlanc,
        fileulRattache: fileulRattache,
        exporteLe: exporteLe,
        derniereSynchro: derniereSynchro);
    if (!j.accepte) {
      await _journaliser('importer_refuse', {'code': j.refus!.code, 'motif': j.refus!.motif});
      throw RefusMajException(j.refus!);
    }
    final plan = planifierMigration(format);
    final migre = executerMigrations(ex.collections, plan);
    final local = await _lire(dossier);
    final saisies = fileulRattache ? saisiesPosterieures(migre.collections, local) : <SaisiePosterieure>[];
    final attendu = releverCollections(migre.collections);
    if (essaiABlanc) {
      return RapportMaj(comptes: comparerReleves(releverCollections(local), attendu, modifieesParMigration: {...migre.modifiees, ...attendu.keys}), notes: ['Essai à blanc : rien n’a été écrit.', ...migre.notes], avertissements: j.avertissements, saisies: saisies, etapes: migre.etapes);
    }
    final avantDir = await _avantOperation('import');
    try {
      await _ecrireTout(migre.collections, migre.formatApres, aMettreDeCote: [for (final k in local.keys) if (!migre.collections.containsKey(k)) k]);
      final relu = releverCollections(await _lire(dossier));
      final rap = comparerReleves(attendu, relu);
      if (!rap.ok) throw RefusMajException(RefusMaj(CodeMaj.comptesDifferents, 'Le contrôle d’après import refuse : ${rap.phrase}', 'Le magasin d’avant l’import a été remis'));
      var ajoutes = 0;
      if (dossierFichiers != null) {
        for (final e in ex.fichiers.entries) {
          if (e.key.contains('..')) continue;
          final f = File('$dossierFichiers/${e.key}');
          if (await f.exists()) continue; // un fichier numérisé n'est jamais écrasé
          await f.parent.create(recursive: true);
          await f.writeAsBytes(base64.decode(e.value), flush: true);
          ajoutes++;
        }
      }
      await _terminer();
      await _journaliser('importer', {'fichier': source, 'formatExport': format, 'rapport': rap.phrase, 'saisies_locales_non_presentes': saisies.length, 'fichiers_ajoutes': ajoutes, 'gardee_dans': avantDir, 'avertissements': j.avertissements});
      return RapportMaj(comptes: comparerReleves(releverCollections(local), relu, modifieesParMigration: {...migre.modifiees, ...relu.keys}), notes: [...migre.notes, '$ajoutes fichier(s) numérisé(s) ajouté(s), aucun écrasé.', 'Le magasin d’avant l’import est gardé dans $avantDir.'], avertissements: j.avertissements, saisies: saisies, etapes: migre.etapes, copie: avantDir);
    } on Exception {
      // une COUPURE (process tué, Error) ne passe pas ici : le marqueur reste et `reprendreSiInterrompu` agit au démarrage suivant
      await reprendreSiInterrompu();
      rethrow;
    }
  }
}
