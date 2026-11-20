// LA MISE À JOUR DU LOGICIEL SANS PERTE DE DONNÉES (lot MAJ, PRD-MISE-A-JOUR) : les RÈGLES PURES.
//
// Aucun disque, aucune clé, aucun réseau, aucune horloge : des fonctions de leurs arguments (le poste et la mère les branchent). Le chiffrement, l'écriture
// atomique et la copie sont dans `apps/poste/lib/donnees/maj_poste.dart` et `packages/sync_dart`.
//
// Doctrine : un refus se NOMME (code, motif, geste) ; « non calculable » n'est pas zéro ; rien ne se supprime (RG-14) : une migration qui retire un champ le
// CONSERVE archivé ; une migration migrée deux fois donne le même résultat ; un état mixte n'existe pas (le poste migre dans un dossier neuf, puis bascule).
import 'dart:convert';

import '../fichiers/sha256.dart';

typedef CollectionsMaj = Map<String, List<Map<String, Object?>>>;

/// Le format des données que CE logiciel écrit. 0 = aucun repère (un poste d'avant le lot MAJ) ; 1 = jeu marqué ; 2 = champs nuls retirés (RG-14 : archivés).
const int formatDonneesCourant = 2;
const int formatSansVersion = 0;

/// Le geste réservé de la fiche RBAC qui couvre toute la chaîne (préparer, migrer, importer, annuler). Défaut semé : administrateur et Directrice Administrative (proposition à valider, BG).
const String majGeste = 'lancer_mise_a_jour';

/// La collection technique, en ajout seul, où une migration range ce qu'elle retire d'une fiche (jamais de suppression physique).
const String collectionArchiveMigrations = 'archiveMigrations';

/// Les codes de refus nommés du parcours.
class CodeMaj {
  CodeMaj._();
  static const sansSauvegarde = 'MAJ_SANS_SAUVEGARDE';
  static const donneesPlusRecentes = 'DONNEES_PLUS_RECENTES';
  static const ecartDeVersion = 'MAJ_ECART_DE_VERSION';
  static const geste = 'MAJ_GESTE_RESERVE';
  static const importSansCle = 'IMPORT_SANS_CLE';
  static const importAutreClinique = 'IMPORT_AUTRE_CLINIQUE';
  static const importSansCopie = 'IMPORT_SANS_COPIE_PREALABLE';
  static const importAltere = 'IMPORT_ALTERE';
  static const comptesDifferents = 'MAJ_COMPTES_DIFFERENTS';
  static const retourSansCopie = 'RETOUR_SANS_COPIE_VERIFIEE';

  /// Le code de protocole renvoyé à un fileul dont le format est refusé (spec §14).
  static const protocole426 = 'schema_incompatible';
}

class RefusMaj {
  const RefusMaj(this.code, this.motif, this.geste);
  final String code, motif, geste;
  Map<String, Object?> versJson() => {'code': code, 'motif': motif, 'geste': geste};
  @override
  String toString() => '$code : $motif ($geste)';
}

// --- réglages de clinique (en base, datés, défaut semé : jamais une constante du code) -----------------------------------------------------------------

/// Les VALEURS D'ATTENTE posées par défaut (propositions à valider par la Direction, section BG). Le poste les lit en base (famille `clinique`) ; ce ne sont que les défauts semés.
class ReglagesMaj {
  const ReglagesMaj({this.ageMaxCopieHeures = 24, this.ecartVersionTolere = 1, this.retourArriereMinutes = 30});
  final int ageMaxCopieHeures, ecartVersionTolere, retourArriereMinutes;
  static const ReglagesMaj defaut = ReglagesMaj();
}

// --- empreintes et comptes --------------------------------------------------------------------------------------------------------------------------

/// JSON canonique : clés triées, aucun espace. Même fiche, même texte, quel que soit l'ordre d'écriture des clés.
String jsonCanonique(Object? v) {
  if (v is Map) {
    final cles = v.keys.map((k) => '$k').toList()..sort();
    return '{${[for (final k in cles) '${jsonEncode(k)}:${jsonCanonique(v[k])}'].join(',')}}';
  }
  if (v is List) return '[${[for (final x in v) jsonCanonique(x)].join(',')}]';
  return jsonEncode(v);
}

String identiteFiche(Map<String, Object?> f) => '${f['id'] ?? f['code'] ?? sha256Octets(utf8.encode(jsonCanonique(f)))}';

String empreinteFiche(Map<String, Object?> f) => sha256Octets(utf8.encode(jsonCanonique(f)));

class ReleveCollection {
  const ReleveCollection(this.compte, this.empreinte);
  final int compte;
  final String empreinte;
  Map<String, Object?> versJson() => {'compte': compte, 'empreinte': empreinte};
}

/// Les comptes et l'empreinte de chaque collection. L'empreinte d'une collection ne dépend ni de l'ordre des fiches ni de l'ordre des clés.
Map<String, ReleveCollection> releverCollections(CollectionsMaj c) {
  final out = <String, ReleveCollection>{};
  for (final e in c.entries) {
    final h = [for (final f in e.value) '${identiteFiche(f)}:${empreinteFiche(f)}']..sort();
    out[e.key] = ReleveCollection(e.value.length, sha256Octets(utf8.encode(h.join('\n'))));
  }
  return out;
}

/// « 18 204 » : le séparateur de milliers est l'espace insécable fine du français (affichage seulement).
String nombreFr(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

class LigneComparaison {
  const LigneComparaison(this.collection, this.avant, this.apres, this.statut);
  final String collection;
  final int? avant, apres;

  /// `identique` | `modifiee_par_migration` | `COMPTE_DIFFERENT` | `EMPREINTE_DIFFERENTE` | `ABSENTE_APRES` | `AJOUTEE_PAR_MIGRATION`
  final String statut;
  bool get anomalie => statut == 'COMPTE_DIFFERENT' || statut == 'EMPREINTE_DIFFERENTE' || statut == 'ABSENTE_APRES';
}

class RapportComptes {
  const RapportComptes(this.lignes);
  final List<LigneComparaison> lignes;
  bool get ok => lignes.every((l) => !l.anomalie);
  List<LigneComparaison> get differences => [for (final l in lignes) if (l.anomalie) l];
  int get totalAvant => lignes.fold(0, (s, l) => s + (l.avant ?? 0));
  int get totalApres => lignes.where((l) => l.avant != null).fold(0, (s, l) => s + (l.apres ?? 0));

  /// Le rapport lisible : « 18 204 fiches avant, 18 204 après », puis chaque différence NOMMÉE.
  String get phrase => '${nombreFr(totalAvant)} fiches avant, ${nombreFr(totalApres)} après'
      '${ok ? '' : ' : ${differences.length} différence(s) : ${[for (final l in differences) '${l.collection} (${l.statut}, ${l.avant ?? 'non calculable'} avant, ${l.apres ?? 'non calculable'} après)'].join(' ; ')}'}';
}

/// Compare le relevé d'AVANT (copie vérifiée) et celui d'APRÈS la migration. Les comptes doivent être IDENTIQUES ; l'empreinte ne peut changer que pour les collections que la
/// migration déclare avoir modifiées ([modifieesParMigration]) ; une collection absente après est une anomalie ; une collection ajoutée par la migration est nommée, jamais anomalie.
RapportComptes comparerReleves(Map<String, ReleveCollection> avant, Map<String, ReleveCollection> apres, {Set<String> modifieesParMigration = const {}}) {
  final l = <LigneComparaison>[];
  for (final e in avant.entries) {
    final a = apres[e.key];
    if (a == null) {
      l.add(LigneComparaison(e.key, e.value.compte, null, 'ABSENTE_APRES'));
    } else if (a.compte != e.value.compte) {
      l.add(LigneComparaison(e.key, e.value.compte, a.compte, 'COMPTE_DIFFERENT'));
    } else if (a.empreinte != e.value.empreinte) {
      l.add(LigneComparaison(e.key, e.value.compte, a.compte, modifieesParMigration.contains(e.key) ? 'modifiee_par_migration' : 'EMPREINTE_DIFFERENTE'));
    } else {
      l.add(LigneComparaison(e.key, e.value.compte, a.compte, 'identique'));
    }
  }
  for (final e in apres.entries) {
    if (!avant.containsKey(e.key)) l.add(LigneComparaison(e.key, null, e.value.compte, 'AJOUTEE_PAR_MIGRATION'));
  }
  return RapportComptes(l);
}

// --- la chaîne de migrations ------------------------------------------------------------------------------------------------------------------------

class ResultatEtape {
  const ResultatEtape(this.collections, {this.modifiees = const {}, this.notes = const []});
  final CollectionsMaj collections;
  final Set<String> modifiees;
  final List<String> notes;
}

class MigrationDonnees {
  const MigrationDonnees({required this.id, required this.de, required this.vers, required this.description, required this.appliquer});
  final String id, description;
  final int de, vers;
  final ResultatEtape Function(CollectionsMaj) appliquer;
}

CollectionsMaj _copie(CollectionsMaj c) => {
      for (final e in c.entries) e.key: [for (final f in e.value) (jsonDecode(jsonEncode(f)) as Map).cast<String, Object?>()]
    };

/// 0 → 1 : le jeu reçoit un repère de version. Aucune donnée ne change.
ResultatEtape _m001(CollectionsMaj c) => ResultatEtape(_copie(c), notes: const ['Le jeu de données reçoit son repère de version (aucune fiche modifiée).']);

/// 1 → 2 : « les champs nuls ne s'écrivent plus » (CLAUDE.md) : un champ à `null` est retiré de la fiche, et son NOM est conservé en ajout seul dans
/// `archiveMigrations` (RG-14 : rien ne se perd sans trace). Idempotente : une fiche sans champ nul n'est pas touchée, une archive existante n'est jamais dupliquée.
ResultatEtape _m002(CollectionsMaj c) {
  final out = _copie(c);
  final archives = out[collectionArchiveMigrations] ?? <Map<String, Object?>>[];
  final connues = {for (final a in archives) '${a['id']}'};
  final modifiees = <String>{};
  var retires = 0;
  for (final e in out.entries.toList()) {
    if (e.key == collectionArchiveMigrations) continue;
    for (final f in e.value) {
      final nuls = [for (final k in f.keys) if (f[k] == null) k]..sort();
      if (nuls.isEmpty) continue;
      for (final k in nuls) {
        f.remove(k);
      }
      retires += nuls.length;
      modifiees.add(e.key);
      final id = 'MIG-M002-${e.key}-${identiteFiche(f)}';
      if (!connues.contains(id)) {
        archives.add({'id': id, 'migration': 'M002', 'collection': e.key, 'fiche': identiteFiche(f), 'champsNulsRetires': nuls});
        connues.add(id);
      }
    }
  }
  if (archives.isNotEmpty) out[collectionArchiveMigrations] = archives;
  return ResultatEtape(out, modifiees: modifiees, notes: ['$retires champ(s) nul(s) retiré(s) dans ${modifiees.length} collection(s), noms conservés dans $collectionArchiveMigrations.']);
}

final List<MigrationDonnees> migrationsDonnees = [
  MigrationDonnees(id: 'M001', de: 0, vers: 1, description: 'Repère de version du jeu de données', appliquer: _m001),
  MigrationDonnees(id: 'M002', de: 1, vers: 2, description: 'Champs nuls retirés des fiches, noms archivés (RG-14)', appliquer: _m002),
];

class PlanMigration {
  const PlanMigration(this.etapes, this.de, this.vers, this.refus);
  final List<MigrationDonnees> etapes;
  final int de, vers;
  final RefusMaj? refus;
  bool get aRien => refus == null && etapes.isEmpty;
}

/// Le plan : les étapes ordonnées de [formatDonnees] à [formatLogiciel]. Des données plus RÉCENTES que le logiciel sont refusées (`DONNEES_PLUS_RECENTES`) : jamais lues à moitié.
PlanMigration planifierMigration(int formatDonnees, {int formatLogiciel = formatDonneesCourant, List<MigrationDonnees>? chaine}) {
  final ch = chaine ?? migrationsDonnees;
  if (formatDonnees > formatLogiciel) {
    return PlanMigration(const [], formatDonnees, formatLogiciel,
        RefusMaj(CodeMaj.donneesPlusRecentes, 'Les données sont au format $formatDonnees, ce logiciel ne connaît que le format $formatLogiciel.', 'Installer la version du logiciel qui a écrit ces données (ou une plus récente), jamais ouvrir ces données avec une version plus ancienne'));
  }
  final etapes = <MigrationDonnees>[];
  var v = formatDonnees;
  while (v < formatLogiciel) {
    final m = ch.where((x) => x.de == v).toList();
    if (m.isEmpty) {
      return PlanMigration(etapes, formatDonnees, formatLogiciel,
          RefusMaj(CodeMaj.ecartDeVersion, 'Aucune migration ne part du format $v : la chaîne est incomplète.', 'Installer d’abord la version intermédiaire du logiciel'));
    }
    etapes.add(m.first);
    v = m.first.vers;
  }
  return PlanMigration(etapes, formatDonnees, formatLogiciel, null);
}

class ResultatMigration {
  const ResultatMigration(this.collections, this.formatApres, this.modifiees, this.notes, this.etapes);
  final CollectionsMaj collections;
  final int formatApres;
  final Set<String> modifiees;
  final List<String> notes;
  final List<String> etapes;
}

/// Exécute le plan sur une COPIE des collections (l'entrée n'est jamais modifiée) : c'est aussi l'essai à blanc (rien n'est écrit, `modifiees` et `notes` disent ce qui changerait).
ResultatMigration executerMigrations(CollectionsMaj collections, PlanMigration plan) {
  if (plan.refus != null) throw StateError('${plan.refus}');
  var c = _copie(collections);
  final modifiees = <String>{};
  final notes = <String>[];
  for (final m in plan.etapes) {
    final r = m.appliquer(c);
    c = r.collections;
    modifiees.addAll(r.modifiees);
    notes.addAll(['${m.id} : ${m.description}', ...r.notes]);
  }
  return ResultatMigration(c, plan.vers, modifiees, notes, [for (final m in plan.etapes) m.id]);
}

// --- les gardes du parcours -------------------------------------------------------------------------------------------------------------------------

/// Peut-on LANCER la migration ? Le geste est réservé (la commande est ABSENTE sans lui, le moteur refuse aussi) ; une copie VÉRIFIÉE de moins de [ReglagesMaj.ageMaxCopieHeures] est exigée.
RefusMaj? jugerLancement({required bool geste, required DateTime? copieVerifieeLe, required DateTime maintenant, ReglagesMaj reglages = ReglagesMaj.defaut}) {
  if (!geste) return const RefusMaj(CodeMaj.geste, 'Lancer une mise à jour est un geste réservé de la fiche de droits.', 'Demander à un profil habilité (fiche RBAC, geste « lancer_mise_a_jour »)');
  if (copieVerifieeLe == null) {
    return const RefusMaj(CodeMaj.sansSauvegarde, 'Aucune copie vérifiée de ce poste : la migration ne se lance jamais sans filet.', 'Utiliser « Préparer la mise à jour » (sauvegarde chiffrée puis restauration vérifiée dans un dossier neuf)');
  }
  final age = maintenant.difference(copieVerifieeLe);
  if (age.isNegative) return const RefusMaj(CodeMaj.sansSauvegarde, 'La date de la copie vérifiée est dans le futur : elle n’est pas crue.', 'Refaire « Préparer la mise à jour »');
  if (age > Duration(hours: reglages.ageMaxCopieHeures)) {
    return RefusMaj(CodeMaj.sansSauvegarde, 'La dernière copie vérifiée date de ${age.inHours} h (maximum ${reglages.ageMaxCopieHeures} h).', 'Refaire « Préparer la mise à jour » juste avant la mise à jour');
  }
  return null;
}

/// L'écart de version de format entre la mère et un fileul. Tolérance = réglage de clinique (défaut : une version). Hors tolérance : `426 schema_incompatible`, le fileul n'envoie rien et GARDE sa file.
RefusMaj? jugerEcartVersion({required int formatMere, required int? formatFileul, ReglagesMaj reglages = ReglagesMaj.defaut}) {
  if (formatFileul == null) {
    return const RefusMaj(CodeMaj.ecartDeVersion, 'Le fileul ne dit pas son format de données : non calculable, il n’est pas cru compatible.', 'Mettre à jour le poste fileul vers la version de la mère');
  }
  final ecart = (formatMere - formatFileul).abs();
  if (ecart <= reglages.ecartVersionTolere) return null;
  final plusAncien = formatFileul < formatMere;
  return RefusMaj(CodeMaj.ecartDeVersion,
      'Le fileul est au format $formatFileul, la mère au format $formatMere (écart $ecart, tolérance ${reglages.ecartVersionTolere}).',
      plusAncien ? 'Mettre à jour ce poste vers la version de la mère : ses saisies hors ligne sont gardées' : 'Mettre à jour la mère d’abord (la mère se met à jour avant les fileuls)');
}

class JugementImport {
  const JugementImport(this.refus, this.avertissements);
  final RefusMaj? refus;
  final List<String> avertissements;
  bool get accepte => refus == null;
}

/// Peut-on IMPORTER cette base (export portable ou sauvegarde) ? Même contrôle sur la mère et sur un fileul. Aucun import sans la clé de la clinique, jamais d'une autre clinique,
/// jamais de données plus récentes que le logiciel, jamais sans copie préalable vérifiée du magasin local. Sur un fileul rattaché : avertissement NON bloquant si l'export est plus
/// ancien que la dernière synchronisation (les saisies postérieures sont listées, jamais écrasées en silence).
JugementImport jugerImport({
  required bool geste,
  required bool cleLocalePresente,
  required String? empreinteCleExport,
  required String? empreinteCleLocale,
  required bool signatureValide,
  required int formatExport,
  required bool copieLocaleVerifiee,
  bool fileulRattache = false,
  DateTime? exporteLe,
  DateTime? derniereSynchro,
  int formatLogiciel = formatDonneesCourant,
}) {
  JugementImport refus(String c, String m, String g) => JugementImport(RefusMaj(c, m, g), const []);
  if (!geste) return refus(CodeMaj.geste, 'Importer une base est un geste réservé de la fiche de droits.', 'Demander à un profil habilité (fiche RBAC, geste « lancer_mise_a_jour »)');
  if (!cleLocalePresente || empreinteCleLocale == null) {
    return refus(CodeMaj.importSansCle, 'Ce poste n’a pas la clé de la clinique : sans elle aucune copie n’est lisible, c’est voulu.', 'Restaurer la clé de clinique (écran « Restaurer la clé ») puis recommencer');
  }
  if (!signatureValide) return refus(CodeMaj.importAltere, 'Le manifeste de l’export ne se vérifie pas : fichier altéré ou tronqué.', 'Refaire l’export depuis le poste d’origine');
  if (empreinteCleExport != empreinteCleLocale) {
    return refus(CodeMaj.importAutreClinique, 'L’export vient d’une autre clinique (la clé de chiffrement diffère).', 'Utiliser l’export de CETTE clinique, ou restaurer la bonne clé');
  }
  if (formatExport > formatLogiciel) {
    return refus(CodeMaj.donneesPlusRecentes, 'L’export est au format $formatExport, ce logiciel ne connaît que le format $formatLogiciel.', 'Installer la version du logiciel qui a écrit cet export (ou plus récente)');
  }
  if (!copieLocaleVerifiee) {
    return refus(CodeMaj.importSansCopie, 'Aucune copie vérifiée du magasin actuel de ce poste : l’import le remplace.', 'Utiliser « Préparer la mise à jour » puis recommencer');
  }
  final av = <String>[];
  if (fileulRattache && exporteLe != null && derniereSynchro != null && exporteLe.isBefore(derniereSynchro)) {
    av.add('IMPORT_PLUS_ANCIEN_QUE_SYNC : cette base date d’avant la dernière synchronisation de ce poste. Elle se remettra à jour depuis la mère ; les saisies de ce poste postérieures à l’export sont listées et la copie d’avant l’import les garde, rien n’est écrasé en silence.');
  }
  return JugementImport(null, av);
}

class SaisiePosterieure {
  const SaisiePosterieure(this.collection, this.fiche, this.nature);
  final String collection, fiche;

  /// `creee` | `modifiee` | `absente_maintenant` (ne devrait jamais arriver : RG-14)
  final String nature;
  Map<String, Object?> versJson() => {'collection': collection, 'fiche': fiche, 'nature': nature};
}

/// Ce qui a été saisi APRÈS une copie : fiches créées, fiches modifiées, fiches disparues. Sert à l'écran « Annuler la mise à jour » (retour arrière) et à l'import sur un fileul :
/// la liste est montrée AVANT, et la copie d'avant les garde (jamais écrasées en silence).
List<SaisiePosterieure> saisiesPosterieures(CollectionsMaj copie, CollectionsMaj actuel) {
  final out = <SaisiePosterieure>[];
  for (final e in actuel.entries) {
    if (e.key == collectionArchiveMigrations) continue;
    final base = {for (final f in copie[e.key] ?? const <Map<String, Object?>>[]) identiteFiche(f): empreinteFiche(f)};
    for (final f in e.value) {
      final id = identiteFiche(f);
      if (!base.containsKey(id)) {
        out.add(SaisiePosterieure(e.key, id, 'creee'));
      } else if (base[id] != empreinteFiche(f)) {
        out.add(SaisiePosterieure(e.key, id, 'modifiee'));
      }
    }
  }
  for (final e in copie.entries) {
    if (e.key == collectionArchiveMigrations) continue;
    final ids = {for (final f in actuel[e.key] ?? const <Map<String, Object?>>[]) identiteFiche(f)};
    for (final f in e.value) {
      if (!ids.contains(identiteFiche(f))) out.add(SaisiePosterieure(e.key, identiteFiche(f), 'absente_maintenant'));
    }
  }
  return out;
}

/// Le retour arrière : permis seulement avec une copie VÉRIFIÉE (nommée) ; rend la liste des saisies postérieures à montrer AVANT de restaurer.
({RefusMaj? refus, List<SaisiePosterieure> saisies}) jugerRetourArriere({required bool geste, required bool copieVerifiee, required CollectionsMaj? copie, required CollectionsMaj actuel}) {
  if (!geste) return (refus: const RefusMaj(CodeMaj.geste, 'Annuler une mise à jour est un geste réservé de la fiche de droits.', 'Demander à un profil habilité (fiche RBAC, geste « lancer_mise_a_jour »)'), saisies: const []);
  if (!copieVerifiee || copie == null) {
    return (refus: const RefusMaj(CodeMaj.retourSansCopie, 'Aucune copie vérifiée à restaurer : un retour arrière ne se fait jamais sur une copie non vérifiée.', 'Utiliser la dernière sauvegarde chiffrée de la mère, vérifiée'), saisies: const []);
  }
  return (refus: null, saisies: saisiesPosterieures(copie, actuel));
}
