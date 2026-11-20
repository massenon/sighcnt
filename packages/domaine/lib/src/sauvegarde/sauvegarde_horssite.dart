// LA SAUVEGARDE HORS SITE (lot 5, ADR-0007) : les RÈGLES PURES, portées de `packages/sync/banc/sauvegarde-regles.js` (exécutable de référence ; vecteurs
// `test/vecteurs/sauvegarde_horssite.json` engendrés par `banc/vecteurs-sauvegarde.js`).
//
// Aucune clé, aucun réseau, aucun disque, aucune horloge : des fonctions de leurs arguments. Le chiffrement (nonce dérivé, AES-256-GCM, empreintes) est dans `packages/sync_dart`
// (le domaine n'a aucune dépendance) ; ici : le découpage, la taille chiffrée, le contrôle d'un réglage et d'un plan, la rotation, l'ordre de purge, le manifeste.
//
// Doctrine : un refus se NOMME (code, motif, geste) ; « non calculable » n'est pas zéro (un champ absent de l'état du relais ne devient jamais 0) ; rien ne se supprime
// sans nom (RG-14) : la rotation ARCHIVE, la purge est la seule suppression et n'a lieu que quand l'espace manque.

/// Le format du manifeste et du bloc (versionné : un logiciel plus ancien refuse un format qu'il ne connaît pas).
const int shFormat = 1;

/// Les deux types de copie, réglés indépendamment : le magasin (instantané de la base de la mère) et les fichiers numérisés.
const List<String> shTypes = ['magasin', 'fichiers'];

/// Le surcoût du chiffrement par bloc : nonce (12) et étiquette d'authentification (16).
const int shSurcoutBloc = 28;

/// Bornes d'un réglage (valeurs d'attente, à valider par la Direction : section AA des décisions). Un réglage hors bornes est REFUSÉ, jamais rogné en silence.
const int shTailleBlocMin = 64 * 1024;
const int shTailleBlocMax = 4 * 1024 * 1024;
const int shCopiesMin = 2;
const int shCopiesMax = 60;
const int shFrequenceMin = 15;
const int shFrequenceMax = 1440;
const int shHeureMin = 0;
const int shHeureMax = 23;
const int shBlocsControlesMin = 0;
const int shBlocsControlesMax = 200;

/// Les défauts SEMÉS (la règle de paramétrage : enregistrés en base, jamais lus d'ici à l'exécution : voir `definitionsParametres`).
const int shTailleBlocDefaut = 1024 * 1024;
const int shCopiesMagasinDefaut = 7;
const int shCopiesFichiersDefaut = 14;
const int shFrequenceDefaut = 60;
const int shHeureControleDefaut = 2;
const int shBlocsControlesDefaut = 10;

/// Les rôles qui règlent la copie hors site : l'administrateur et la Directrice Administrative (comme la destination de la sauvegarde locale des fichiers).
const List<String> shRolesReglage = ['admin', 'da'];
bool shPeutRegler(String role) => shRolesReglage.contains(role);

const String shCleActif = 'horssite.actif';
const String shCleDestinationMagasin = 'horssite.destinationMagasin';
const String shCleDestinationFichiers = 'horssite.destinationFichiers';
const String shCleDossierMagasin = 'horssite.dossierMagasin';
const String shCleDossierFichiers = 'horssite.dossierFichiers';
const String shCleFrequence = 'horssite.frequenceFichiersMin';
const String shCleHeureControle = 'horssite.heureControle';
const String shCleCopiesMagasin = 'horssite.copiesMagasin';
const String shCleCopiesFichiers = 'horssite.copiesFichiers';
const String shCleTailleBloc = 'horssite.tailleBloc';
const String shCleBlocsControles = 'horssite.blocsControles';

/// Un refus NOMMÉ : le code (stable, testable), le motif (lisible au guichet) et le geste de correction.
class RefusSauvegarde {
  const RefusSauvegarde(this.code, this.motif, this.geste, [this.plus = const {}]);
  final String code;
  final String motif;
  final String geste;
  final Map<String, Object?> plus;
  Map<String, Object?> toJson() => {'ok': false, 'code': code, 'motif': motif, 'geste': geste, ...plus};
  @override
  String toString() => '$code : $motif';
}

String shOctets(int n) => n >= 1024 * 1024 * 1024
    ? '${(n / 1024 / 1024 / 1024).toStringAsFixed(1)} Gio'
    : n >= 1024 * 1024
        ? '${(n / 1024 / 1024).toStringAsFixed(1)} Mio'
        : n >= 1024
            ? '${(n / 1024).toStringAsFixed(0)} Kio'
            : '$n o';

/// Une plage d'un contenu : début et longueur.
class PlageBloc {
  const PlageBloc(this.debut, this.longueur);
  final int debut;
  final int longueur;
  Map<String, Object?> toJson() => {'debut': debut, 'longueur': longueur};
}

/// Le découpage : des plages de [tailleBloc] octets, la dernière plus courte. Un contenu vide n'a AUCUN bloc.
List<PlageBloc> shDecouper(int longueur, int tailleBloc) {
  if (longueur < 0) throw ArgumentError('longueur invalide');
  if (tailleBloc < 1) throw ArgumentError('taille de bloc invalide');
  return [for (var d = 0; d < longueur; d += tailleBloc) PlageBloc(d, longueur - d < tailleBloc ? longueur - d : tailleBloc)];
}

/// La taille d'un contenu une fois chiffré bloc par bloc.
int shTailleChiffree(int longueur, int tailleBloc) => longueur + shDecouper(longueur, tailleBloc).length * shSurcoutBloc;

bool _dans(Object? v, int a, int b) => v is int && v >= a && v <= b;

/// Le contrôle d'un RÉGLAGE d'un type. [r] : `actif`, `destination` (aucune, relais, dossier), `dossier`, `tailleBloc`, `copies`, `frequenceMinutes`, `heureControle`, `blocsControles`.
/// Activer sans destination, ou une destination « dossier » sans chemin, est REFUSÉ en le nommant.
RefusSauvegarde? shVerifierReglage(Map<String, Object?> r) {
  final dest = r['destination'];
  if (!const ['aucune', 'relais', 'dossier'].contains(dest)) {
    return RefusSauvegarde('DESTINATION_INCONNUE', 'la destination « $dest » n\'existe pas', 'Choisir : aucune, relais ou dossier distant.');
  }
  if (r['actif'] == true && dest == 'aucune') {
    return const RefusSauvegarde('DESTINATION_ABSENTE', 'la copie hors site ne peut pas être activée sans destination', 'Choisir le relais ou un dossier distant, puis activer.');
  }
  final dossier = r['dossier'];
  if (dest == 'dossier' && !(dossier is String && dossier.trim().isNotEmpty)) {
    return const RefusSauvegarde('DOSSIER_ABSENT', 'la destination « dossier distant » n\'a aucun chemin', 'Saisir le chemin complet du dossier monté.');
  }
  if (r['tailleBloc'] != null && !_dans(r['tailleBloc'], shTailleBlocMin, shTailleBlocMax)) {
    return RefusSauvegarde('TAILLE_BLOC_HORS_BORNES', 'la taille d\'un bloc doit être de ${shOctets(shTailleBlocMin)} à ${shOctets(shTailleBlocMax)}', 'Choisir une taille dans ces bornes (1 Mio par défaut).');
  }
  if (r['copies'] != null && !_dans(r['copies'], shCopiesMin, shCopiesMax)) {
    return RefusSauvegarde('ROTATION_HORS_BORNES', 'le nombre de copies gardées doit être de $shCopiesMin à $shCopiesMax', 'Choisir un nombre dans ces bornes : le plancher protège la reprise, le plafond protège l\'espace.');
  }
  if (r['frequenceMinutes'] != null && !_dans(r['frequenceMinutes'], shFrequenceMin, shFrequenceMax)) {
    return const RefusSauvegarde('FREQUENCE_HORS_BORNES', 'la fréquence doit être de 15 à 1440 minutes', 'Choisir une fréquence dans ces bornes (60 minutes par défaut).');
  }
  if (r['heureControle'] != null && !_dans(r['heureControle'], shHeureMin, shHeureMax)) {
    return const RefusSauvegarde('HEURE_HORS_BORNES', 'l\'heure du contrôle nocturne est un entier de 0 à 23', 'Choisir une heure de nuit (2 par défaut).');
  }
  if (r['blocsControles'] != null && !_dans(r['blocsControles'], shBlocsControlesMin, shBlocsControlesMax)) {
    return const RefusSauvegarde('BLOCS_CONTROLES_HORS_BORNES', 'le nombre de blocs contrôlés chaque nuit est un entier de 0 à 200', 'Choisir un nombre dans ces bornes (10 par défaut).');
  }
  return null;
}

/// Le contrôle du PLAN d'une copie AVANT tout dépôt : [etat] est ce que la destination dit d'elle-même (`limites`, `utilise`, `liberable`). Un champ absent n'est PAS compté comme zéro :
/// la limite ne s'applique pas (jamais un refus fabriqué avec un zéro, jamais un feu vert fabriqué non plus : la destination la fera respecter à son tour).
RefusSauvegarde? shVerifierPlan({required int octetsCopie, Map<String, Object?>? etat}) {
  final e = etat ?? const <String, Object?>{};
  final l = (e['limites'] is Map) ? (e['limites'] as Map).cast<String, Object?>() : const <String, Object?>{};
  final max = l['tailleMaxCopie'];
  if (max is int && octetsCopie > max) {
    return RefusSauvegarde('SAUVEGARDE_TROP_GROSSE', 'la copie pèse ${shOctets(octetsCopie)} chiffrée, le maximum accepté par la destination est ${shOctets(max)}',
        'Relever la limite par copie du relais (panneau), ou choisir un dossier distant pour ce type de copie.', {'octetsCopie': octetsCopie, 'limite': max});
  }
  final quota = l['quotaOctets'];
  final utilise = e['utilise'];
  if (quota is int && utilise is int) {
    final liberable = e['liberable'];
    final libre = quota - utilise + (liberable is int ? liberable : 0);
    if (octetsCopie > libre) {
      final reste = libre < 0 ? 0 : libre;
      return RefusSauvegarde('ESPACE_RELAIS_INSUFFISANT', 'la copie demande ${shOctets(octetsCopie)}, il reste ${shOctets(reste)} sur le relais (anciennes copies libérables comprises)',
          'Relever le quota du relais, réduire le nombre de copies gardées, ou choisir un dossier distant.', {'octetsCopie': octetsCopie, 'libre': reste});
    }
  }
  return null;
}

/// Une copie vue par la destination : identifiant, type, état (ouverte, complete, archivee, purgee, abandonnee), date (ms).
class CopieVue {
  const CopieVue(this.id, this.type, this.etat, this.date);
  final String id;
  final String type;
  final String etat;
  final int date;
  factory CopieVue.depuisJson(Map<String, Object?> j) => CopieVue('${j['id']}', '${j['type']}', '${j['etat']}', (j['date'] as num).toInt());
}

int _plusRecente(CopieVue a, CopieVue b) {
  final d = b.date.compareTo(a.date);
  return d != 0 ? d : b.id.compareTo(a.id);
}

/// Le résultat de la rotation : les copies qui restent courantes, celles à ARCHIVER, ou un refus nommé.
class ResultatRotation {
  const ResultatRotation.ok(this.gardees, this.archiver) : refus = null;
  const ResultatRotation.refus(RefusSauvegarde this.refus)
      : gardees = const [],
        archiver = const [];
  final List<String> gardees;
  final List<String> archiver;
  final RefusSauvegarde? refus;
  bool get ok => refus == null;
}

/// La ROTATION d'un type : parmi les copies COMPLÈTES (la plus récente d'abord : date, puis identifiant), les [garder] premières restent courantes, les suivantes sont à ARCHIVER (jamais
/// supprimées). [garder] hors des bornes [plancher] à [plafond] : refus. Une copie qui n'est pas complète n'entre jamais dans le compte.
ResultatRotation shRotation(List<CopieVue> copies, Object? garder, int plancher, int plafond) {
  if (garder is! int || garder < plancher || garder > plafond) {
    return ResultatRotation.refus(RefusSauvegarde('ROTATION_HORS_BORNES', 'garder $garder copie(s) est hors des bornes du relais ($plancher à $plafond)', 'Choisir un nombre de copies dans les bornes du relais.', {'plancher': plancher, 'plafond': plafond}));
  }
  final completes = copies.where((c) => c.etat == 'complete').toList()..sort(_plusRecente);
  return ResultatRotation.ok([for (final c in completes.take(garder)) c.id], [for (final c in completes.skip(garder)) c.id]);
}

/// L'ORDRE DE PURGE quand l'espace manque : parmi les copies ARCHIVÉES ou ABANDONNÉES, la plus ancienne d'abord. Une copie courante, en cours, ou l'une des [plancher] plus récentes copies
/// restaurables (complètes ou archivées) de son type n'est JAMAIS candidate (double garde : le plancher tient même si le réglage était mal posé).
List<String> shOrdrePurge(List<CopieVue> copies, int plancher) {
  final protegees = <String>{};
  for (final t in shTypes) {
    final restaurables = copies.where((c) => c.type == t && (c.etat == 'complete' || c.etat == 'archivee')).toList()..sort(_plusRecente);
    protegees.addAll(restaurables.take(plancher).map((c) => c.id));
  }
  final candidates = copies.where((c) => (c.etat == 'archivee' || c.etat == 'abandonnee') && !protegees.contains(c.id)).toList()
    ..sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.id.compareTo(b.id);
    });
  return [for (final c in candidates) c.id];
}

/// Le MANIFESTE (clair, avant chiffrement) : format, type, éléments (référence, taille, empreinte du clair, blocs). Sans date ni auteur : l'identité d'une copie est celle de son CONTENU
/// (rejouer le même état est la même copie). Les éléments sont triés par référence. Chaque élément de [elements] : `ref`, `taille`, `sha256`, `meta` (facultatif), `blocs` (`id`, `taille`, `clair`).
Map<String, Object?> shManifeste({required String type, required List<Map<String, Object?>> elements, required int tailleBloc}) {
  final els = [
    for (final e in elements)
      {
        'ref': e['ref'],
        'taille': e['taille'],
        'sha256': e['sha256'],
        if (e['meta'] != null) 'meta': e['meta'],
        'blocs': [for (final b in (e['blocs'] as List)) {'id': (b as Map)['id'], 'taille': b['taille'], 'clair': b['clair']}],
      }
  ]..sort((a, b) => '${a['ref']}'.compareTo('${b['ref']}'));
  return {'format': shFormat, 'type': type, 'tailleBloc': tailleBloc, 'total': els.fold<int>(0, (s, e) => s + (e['taille'] as int)), 'elements': els};
}

final RegExp _sha = RegExp(r'^[0-9a-f]{64}$');

/// Un manifeste lu : forme, cohérence (la somme des blocs en clair égale la taille de l'élément, le total égale la somme). Rend un refus nommé ou `null`.
RefusSauvegarde? shVerifierManifeste(Object? m) {
  if (m is! Map || m['format'] != shFormat) {
    return const RefusSauvegarde('MANIFESTE_ILLISIBLE', 'le manifeste n\'a pas le format attendu', 'Utiliser un logiciel de la même version que celui qui a fait la copie.');
  }
  if (!shTypes.contains(m['type']) || m['elements'] is! List) {
    return const RefusSauvegarde('MANIFESTE_ILLISIBLE', 'le manifeste est incomplet', 'Choisir une autre copie.');
  }
  var total = 0;
  for (final e in (m['elements'] as List)) {
    if (e is! Map || e['ref'] is! String || e['taille'] is! int || e['blocs'] is! List || !_sha.hasMatch('${e['sha256'] ?? ''}')) {
      return const RefusSauvegarde('MANIFESTE_ILLISIBLE', 'un élément du manifeste est incomplet', 'Choisir une autre copie.');
    }
    final somme = (e['blocs'] as List).fold<int>(0, (s, b) => s + ((b as Map)['clair'] as int));
    if (somme != e['taille']) {
      return RefusSauvegarde('MANIFESTE_INCOHERENT', 'un élément annonce ${e['taille']} octets et ses blocs en portent $somme', 'Choisir une autre copie : celle-ci est incohérente.');
    }
    total += e['taille'] as int;
  }
  if (total != m['total']) {
    return RefusSauvegarde('MANIFESTE_INCOHERENT', 'le manifeste annonce ${m['total']} octets et ses éléments en portent $total', 'Choisir une autre copie : celle-ci est incohérente.');
  }
  return null;
}

/// Le réglage de la clinique (lu de la base : `parametres`, famille `horssite`) pour un type.
class ReglageType {
  const ReglageType({required this.destination, required this.dossier, required this.copies});
  final String destination;
  final String dossier;
  final int copies;
  bool get actifPossible => destination != 'aucune';
}

class ReglageHorsSite {
  const ReglageHorsSite({
    this.actif = false,
    this.magasin = const ReglageType(destination: 'relais', dossier: '', copies: shCopiesMagasinDefaut),
    this.fichiers = const ReglageType(destination: 'aucune', dossier: '', copies: shCopiesFichiersDefaut),
    this.frequenceMinutes = shFrequenceDefaut,
    this.heureControle = shHeureControleDefaut,
    this.tailleBloc = shTailleBlocDefaut,
    this.blocsControles = shBlocsControlesDefaut,
  });
  final bool actif;
  final ReglageType magasin;
  final ReglageType fichiers;
  final int frequenceMinutes;
  final int heureControle;
  final int tailleBloc;
  final int blocsControles;

  ReglageType de(String type) => type == 'magasin' ? magasin : fichiers;
}

/// Le contrôle du réglage de la clinique : chaque type contrôlé comme dans [shVerifierReglage] (les bornes s'appliquent à tous, la destination « aucune » d'un type est permise tant que
/// l'autre type en a une) ; activer sans AUCUNE destination est refusé.
RefusSauvegarde? shVerifierReglageClinique(ReglageHorsSite r) {
  if (r.actif && !r.magasin.actifPossible && !r.fichiers.actifPossible) {
    return const RefusSauvegarde('DESTINATION_ABSENTE', 'la copie hors site ne peut pas être activée sans destination', 'Choisir le relais ou un dossier distant pour au moins un type de copie, puis activer.');
  }
  for (final t in shTypes) {
    final x = r.de(t);
    final refus = shVerifierReglage({
      'actif': r.actif && x.actifPossible,
      'destination': x.destination,
      'dossier': x.dossier,
      'tailleBloc': r.tailleBloc,
      'copies': x.copies,
      'frequenceMinutes': r.frequenceMinutes,
      'heureControle': r.heureControle,
      'blocsControles': r.blocsControles,
    });
    if (refus != null) return refus;
  }
  return null;
}
