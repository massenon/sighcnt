/// LA LECTURE OCR DES SCANS, PRÉPARÉE (lot OCR-prep, portage de `prototype_html/assets/js/modules/fichiers-ocr.js`) : AUCUN moteur choisi, AUCUN moteur livré, AUCUNE qualité promise.
///
/// Décision de la Direction (PRD DOCS, Q7) : OCR local en phase 2, APRÈS un essai sur trois vrais scans de la clinique. Ce fichier est tout ce qui ne dépend pas du moteur : l'interface
/// qu'un moteur remplira, les six ÉTATS d'indexation, la file de traitement (règles pures), le marquage « lu par machine, à vérifier », le réglage. Par défaut AUCUN moteur n'est branché
/// et l'état le dit exactement : « aucun moteur d'OCR installé sur ce poste ». Jamais un échec muet, jamais « indexé » sans texte lu.
///
/// Rejoué sur `test/vecteurs/ocr.json`, tiré de la maquette réelle pilotée dans Chrome (`prototype_html/build/vecteurs-ocr.js`).
///
/// TROIS RÈGLES QUI NE SE DEVINENT PAS :
///  - la couche texte NATIVE d'un PDF prime TOUJOURS sur l'OCR : un fichier qui en porte une n'entre jamais dans la file, et le texte lu ne la remplace jamais ;
///  - une lecture ne se RÉÉCRIT jamais : une relance ou un autre moteur AJOUTE une version datée, l'ancienne reste lisible. L'identifiant d'une lecture est DÉTERMINISTE (empreinte du
///    fichier, moteur, version du moteur, langue, texte normalisé) : deux postes qui lisent le même scan avec le même moteur ne font qu'une version ;
///  - la file est UNE par empreinte : l'état de lecture d'un fichier est unique, deux dépôts du même scan ne font jamais deux files.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../droits/gestes_a_chaud.dart';
import '../format/diacritiques.dart';
import 'fichiers_donnees.dart' show docRolesZone2;
import 'fichiers_regles.dart' show FicheDoc, RefusFichier, docPeutVoir;
import 'sha256.dart';

// --- constantes ------------------------------------------------------------------------------------------------------------------------

/// La raison dite quand aucun moteur n'est installé : la même phrase partout (écran, journal, message sous « Aucun résultat »).
const String ocrRaisonSansMoteur = 'aucun moteur d’OCR installé sur ce poste';
const int ocrDelaiDefautMs = 120000;
const int ocrEssaisMax = 3;
const int ocrBrutMax = 20000;
const int ocrMotsMax = 4000;
const String ocrLangueDefaut = 'fra';

/// Les profils qui règlent la lecture des scans : l'administrateur et la Directrice Administrative.
const List<String> ocrRolesReglage = ['admin', 'da'];

/// Les paramètres de CLINIQUE de la lecture des scans (lot C, décision de la Direction du 13/11/2026 : « propre à chaque poste ET remonté à la mère pour une synchronisation uniforme »,
/// lecture retenue à confirmer, `DECISIONS-A-VALIDER.md` section Y) : posés à la mère, famille R (collection `parametres`, version datée), reçus des fileuls par le journal, JAMAIS vers un
/// téléphone. Chaque poste ne garde en propre que ce qu'il a d'INSTALLÉ (les moteurs disponibles). Les défauts sont SEMÉS (`definitions.dart`), jamais des constantes de l'écran.
/// Le geste réservé de la fiche RBAC (`packages/rbac/data/rbac.json`, clé `gestes`) qui donne la correction signée du texte lu.
const String ocrGesteCorriger = 'corriger_texte_ocr';

const String ocrCleActif = 'ocr.actif';
const String ocrCleMoteur = 'ocr.moteur';
const String ocrCleLangue = 'ocr.langue';
const String ocrCleDelai = 'ocr.delaiMs';

/// Le réglage de clinique est-il REÇU ? Vrai quand la fiche d'activation de la mère (même son semis) est arrivée : sinon la valeur lue serait le défaut, et le défaut peut différer de ce que
/// la mère a posé. Un réglage non reçu se DIT, il ne se lit jamais comme « désactivé » en silence.
const String ocrRaisonReglageNonRecu = 'le réglage de la lecture des scans n’est pas encore reçu de la poste mère';

/// Les codes de refus nommés (le même vocabulaire que la maquette).
class CodeOcr {
  static const moteurAbsent = 'MOTEUR_ABSENT';
  static const langueAbsente = 'LANGUE_ABSENTE';
  static const imageIllisible = 'IMAGE_ILLISIBLE';
  static const delaiDepasse = 'DELAI_DEPASSE';
  static const formatNonLu = 'FORMAT_NON_LU';
  static const rendu = 'RENDU_PAGES_ABSENT';
  static const aucunTexte = 'AUCUN_TEXTE';
  static const desactive = 'OCR_DESACTIVE';
  static const moteurEnEchec = 'MOTEUR_EN_ECHEC';
  static const essaisEpuises = 'ESSAIS_EPUISES';
  static const reglageReserve = 'REGLAGE_RESERVE';
  static const motifRequis = 'MOTIF_REQUIS';
  static const texteNatif = 'TEXTE_NATIF';
  static const droitRefuse = 'DROIT_REFUSE';
  static const registreAbsent = 'REGISTRE_ABSENT';
  static const sansPiece = 'SANS_PIECE';
  // Lot C : la correction signée du texte lu.
  static const correctionReservee = 'CORRECTION_RESERVEE';
  static const correctionTexteVide = 'CORRECTION_TEXTE_VIDE';
  static const correctionSansBase = 'CORRECTION_SANS_BASE';
  static const correctionIdentique = 'CORRECTION_IDENTIQUE';
}

/// Les gestes de correction de chaque refus.
const Map<String, String> ocrGestes = {
  'MOTEUR_ABSENT': 'Installer un moteur d’OCR sur ce poste, puis le choisir au réglage de la lecture des scans.',
  'LANGUE_ABSENTE': 'Choisir une langue que le moteur sait lire, ou installer ses données de langue.',
  'IMAGE_ILLISIBLE': 'Numériser de nouveau le scan, à plus forte résolution.',
  'DELAI_DEPASSE': 'Relancer la lecture ; si elle se répète, numériser en résolution plus basse.',
  'FORMAT_NON_LU': 'Déposer le scan en image (PNG, JPEG) ou brancher un moteur qui lit ce format.',
  'RENDU_PAGES_ABSENT': 'Brancher un rendeur de pages PDF, ou déposer le scan en image.',
  'AUCUN_TEXTE': 'Vérifier le scan ; la page est vierge ou trop pâle pour être lue.',
  'OCR_DESACTIVE': 'Activer la lecture des scans au réglage (administrateur ou Directrice Administrative).',
  'MOTEUR_EN_ECHEC': 'Relancer la lecture ; si elle se répète, le moteur est à vérifier.',
  'ESSAIS_EPUISES': 'Relancer la lecture à la main une fois la cause levée.',
  'REGLAGE_RESERVE': 'Demander le réglage à l’administrateur ou à la Directrice Administrative.',
  'MOTIF_REQUIS': 'Saisir le motif du réglage.',
  'TEXTE_NATIF': 'Ce fichier porte déjà une couche texte : elle prime, rien à lire.',
  'DROIT_REFUSE': 'Demander ce droit à l’administrateur (« Rôles & permissions »).',
  'CORRECTION_RESERVEE': 'Demander le droit « Corriger le texte lu par machine » à l’administrateur (« Rôles & permissions »), ou faire corriger la pièce par un agent habilité.',
  'CORRECTION_TEXTE_VIDE': 'Saisir le texte corrigé : une correction ne peut pas être vide.',
  'CORRECTION_SANS_BASE': 'Corriger à partir d’une lecture de ce scan : aucune lecture n’existe encore (lancer la lecture, ou saisir la pièce à la main hors de ce texte).',
  'CORRECTION_IDENTIQUE': 'Modifier le texte avant d’enregistrer : il est identique à celui de la version dont la correction part.',
};

/// Un refus nommé de la lecture : code, motif, geste (le contrat commun de tous les refus de fichier).
RefusFichier ocrRefus(String code, String motif, [String? geste]) => RefusFichier(code, motif, geste ?? ocrGestes[code] ?? '');

// --- l'interface d'un moteur --------------------------------------------------------------------------------------------------------------

/// Un mot lu, avec la confiance du moteur quand il la donne (0 à 1).
class MotOcr {
  const MotOcr(this.mot, [this.confiance]);
  final String mot;
  final double? confiance;
}

/// Ce qu'on donne à un moteur : les octets d'une IMAGE (ou d'une page rendue), son format, la langue demandée, le rang de la page.
class EntreeOcr {
  const EntreeOcr({required this.octets, required this.format, required this.langue, this.mime = '', this.page = 1});
  final Uint8List octets;
  final String format;
  final String langue;
  final String mime;
  final int page;
}

/// Ce qu'un moteur rend : le texte, les mots avec leur confiance si le moteur la donne, la langue, et QUI a lu (moteur et version : une lecture sans cela ne se compare pas).
class ResultatOcr {
  const ResultatOcr({required this.texte, this.mots = const [], required this.langue, required this.moteur, required this.version, this.pages = 1, this.dureeMs = 0});
  final String texte;
  final List<MotOcr> mots;
  final String langue;
  final String moteur;
  final String version;
  final int pages;
  final int dureeMs;

  /// La confiance moyenne des mots qui en portent une, arrondie au millième ; `null` quand le moteur n'en donne pas.
  double? get confiance {
    final c = [for (final m in mots) if (m.confiance != null) m.confiance!];
    if (c.isEmpty) return null;
    return (c.reduce((a, b) => a + b) / c.length * 1000).round() / 1000;
  }
}

/// Le refus d'un moteur : un code, un motif, un geste. Jamais une exception muette.
class ErreurOcr implements Exception {
  ErreurOcr(this.refus);
  final RefusFichier refus;
  @override
  String toString() => refus.toString();
}

/// L'interface qu'un moteur remplira. AUCUN moteur n'est fourni par le projet : le poste n'en branche aucun par défaut.
abstract class MoteurOcr {
  String get id;
  String get version;
  String get libelle;

  /// Les langues que le moteur sait lire (code du moteur, « fra » pour le français).
  List<String> get langues;

  /// Les formats d'IMAGE que le moteur lit : `png`, `jpeg`, `webp`.
  List<String> get formats;

  /// Lit une image. Lève [ErreurOcr] avec un refus nommé (image illisible, langue absente...), jamais autre chose.
  Future<ResultatOcr> lire(EntreeOcr entree);
}

/// Le rendu des pages d'un PDF sans couche texte en images : un autre composant, lui aussi absent par défaut. Sans lui, un PDF scanné est refusé en le nommant.
abstract class RendeurPages {
  Future<List<EntreeOcr>> rendre(Uint8List octets, {required String langue});
}

/// Le moteur FACTICE de test : il ne lit rien, il rend le texte qu'on lui a donné pour l'empreinte du fichier (ou un texte par défaut). Les trois défauts qu'un vrai moteur peut avoir
/// se simulent : [sansAccents] (les accents français disparaissent), [perdreUnMotSur] (un mot sur N est perdu), [bruit] (une lettre sur N est remplacée). Il sert aux tests et au banc de mesure.
class MoteurOcrFactice implements MoteurOcr {
  MoteurOcrFactice({
    this.id = 'factice',
    this.version = '0.1',
    this.libelle = 'Moteur factice de test',
    this.langues = const ['fra'],
    this.formats = const ['png', 'jpeg', 'webp'],
    this.textes = const {},
    this.texteParDefaut = '',
    this.sansAccents = false,
    this.perdreUnMotSur = 0,
    this.bruit = 0,
    this.confiance = 0.9,
    this.latence = Duration.zero,
    this.refus,
    this.attente,
  });

  @override
  final String id;
  @override
  final String version;
  @override
  final String libelle;
  @override
  final List<String> langues;
  @override
  final List<String> formats;

  /// Le texte à rendre, par empreinte SHA-256 du fichier (hexadécimal).
  final Map<String, String> textes;
  final String texteParDefaut;
  final bool sansAccents;
  final int perdreUnMotSur;
  final int bruit;
  final double? confiance;
  final Duration latence;

  /// Un refus à lever à chaque lecture (jusqu'à ce qu'on le retire).
  RefusFichier? refus;

  /// Un futur que la lecture attend avant de rendre (tester la file : un scan tenu en cours).
  Future<void>? attente;

  /// Le nombre de lectures demandées, et le plus grand nombre de lectures EN MÊME TEMPS (la file n'en autorise qu'une).
  int appels = 0;
  int enCours = 0;
  int maxParallele = 0;
  final List<EntreeOcr> entrees = [];

  @override
  Future<ResultatOcr> lire(EntreeOcr entree) async {
    appels++;
    enCours++;
    if (enCours > maxParallele) maxParallele = enCours;
    entrees.add(entree);
    try {
      if (refus != null) throw ErreurOcr(refus!);
      if (attente != null) await attente;
      if (latence > Duration.zero) await Future<void>.delayed(latence);
      final sha = sha256Octets(entree.octets);
      var t = textes[sha] ?? texteParDefaut;
      if (sansAccents) t = sansDiacritiques(t).replaceAll('œ', 'oe').replaceAll('Œ', 'OE').replaceAll('æ', 'ae').replaceAll('Æ', 'AE');
      if (perdreUnMotSur > 0) {
        final mots = t.split(RegExp(r'\s+'));
        t = [for (var i = 0; i < mots.length; i++) if ((i + 1) % perdreUnMotSur != 0) mots[i]].join(' ');
      }
      if (bruit > 0) {
        final s = StringBuffer();
        var k = 0;
        for (final r in t.runes) {
          final c = String.fromCharCode(r);
          k++;
          s.write(k % bruit == 0 && RegExp(r'\p{L}', unicode: true).hasMatch(c) ? '#' : c);
        }
        t = s.toString();
      }
      final mots = [for (final m in t.split(RegExp(r'\s+'))) if (m.isNotEmpty) MotOcr(m, confiance)];
      return ResultatOcr(texte: t, mots: mots, langue: entree.langue, moteur: id, version: version);
    } finally {
      enCours--;
    }
  }
}

// --- le réglage ---------------------------------------------------------------------------------------------------------------------------

/// Le réglage de la lecture des scans, lu de la fiche en base : DÉSACTIVÉ par défaut (« à valider » par la Direction), moteur non choisi, français.
class ReglageOcr {
  const ReglageOcr({this.actif = false, this.moteur, this.langue = ocrLangueDefaut, this.delaiMs = ocrDelaiDefautMs, this.regleLe, this.reglePar, this.regle = false});
  final bool actif;
  final String? moteur;
  final String langue;
  final int delaiMs;
  final String? regleLe;
  final String? reglePar;

  /// Un réglage a-t-il jamais été posé ? (sinon : les défauts).
  final bool regle;

  Map<String, Object?> toJson() => {'actif': actif, 'moteur': moteur, 'langue': langue, 'delaiMs': delaiMs, 'regleLe': regleLe, 'reglePar': reglePar};
}

ReglageOcr ocrReglageLire(Map<String, Object?>? r) {
  if (r == null) return const ReglageOcr();
  final d = r['delaiMs'];
  return ReglageOcr(
    actif: r['actif'] == true,
    moteur: r['moteur'] == null ? null : '${r['moteur']}',
    langue: (r['langue'] == null || '${r['langue']}'.isEmpty) ? ocrLangueDefaut : '${r['langue']}',
    delaiMs: d is num && d > 0 ? d.toInt() : ocrDelaiDefautMs,
    regleLe: r['regleLe'] as String?,
    reglePar: r['reglePar'] as String?,
    regle: true,
  );
}

/// Lot CLO-3 : le réglage est le geste réservé [ocrGesteRegler] de la fiche RBAC ; [ocrRolesReglage] n'est que son défaut d'origine (manifeste `N.GESTES`).
const String ocrGesteRegler = 'regler_lecture_scans';
bool ocrPeutRegler(String role) => gesDroit(role, ocrGesteRegler, ocrRolesReglage);

/// Le réglage demandé : réservé à l'administrateur et à la DAF, motivé ; ACTIVER sans moteur installé (ou avec une langue qu'il ne lit pas) est REFUSÉ en le nommant.
/// [moteurs] : les moteurs installés sur ce poste, par identifiant. L'écriture et le journal sont à l'appelant.
({bool ok, RefusFichier? refus, ReglageOcr? reglage}) ocrDefinirReglage(
    {required String role,
    required bool actif,
    required String? moteur,
    required String langue,
    required String? motif,
    required Map<String, MoteurOcr> moteurs,
    required ReglageOcr avant,
    int? delaiMs,
    required String regleLe,
    required String reglePar}) {
  if (!ocrPeutRegler(role)) {
    return (ok: false, refus: ocrRefus(CodeOcr.reglageReserve, 'la lecture des scans (OCR) se règle par l’administrateur ou la Directrice Administrative'), reglage: null);
  }
  if ((motif ?? '').trim().isEmpty) return (ok: false, refus: ocrRefus(CodeOcr.motifRequis, 'un réglage de la lecture des scans se motive'), reglage: null);
  final lng = langue.isEmpty ? ocrLangueDefaut : langue;
  if (actif) {
    if (moteur == null || !moteurs.containsKey(moteur)) {
      return (
        ok: false,
        refus: ocrRefus(CodeOcr.moteurAbsent, moteur != null ? 'le moteur « $moteur » n’est pas installé sur ce poste' : '$ocrRaisonSansMoteur : il n’y a rien à activer'),
        reglage: null
      );
    }
    final m = moteurs[moteur]!;
    if (!m.langues.contains(lng)) {
      return (ok: false, refus: ocrRefus(CodeOcr.langueAbsente, 'le moteur « $moteur » ne lit pas la langue « $lng » (langues : ${m.langues.join(', ')})'), reglage: null);
    }
  }
  return (
    ok: true,
    refus: null,
    reglage: ReglageOcr(actif: actif, moteur: moteur, langue: lng, delaiMs: delaiMs != null && delaiMs > 0 ? delaiMs : avant.delaiMs, regleLe: regleLe, reglePar: reglePar, regle: true)
  );
}

// --- texte lu : mots, identifiant, version ----------------------------------------------------------------------------------------------

/// Les mots d'un texte lu : normalisés (sans accent, minuscules), distincts, de deux lettres au moins, dans l'ordre de première apparition.
List<String> ocrMotsNormalises(String texte) {
  final vus = <String>{};
  final out = <String>[];
  for (final m in texte.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))) {
    final n = sansDiacritiques(m).toLowerCase();
    if (n.length >= 2 && vus.add(n)) out.add(n);
  }
  return out;
}

/// L'identifiant d'une lecture : DÉTERMINISTE, donc idempotent d'un poste à l'autre (`OCR-<empreinte 16>-<hash 12>`).
String ocrIdLecture(String sha, String moteur, String version, String langue, String motsNorm) =>
    'OCR-${sha.substring(0, 16)}-${sha256Octets(utf8.encode('$moteur|$version|$langue|$motsNorm')).substring(0, 12)}';

/// L'identifiant d'une fiche du registre `fichiers` : une fiche par empreinte (même règle que `fichierIdRegistre`).
String ocrIdRegistre(String sha) => 'FIC-${sha.substring(0, 16)}';

/// La fiche d'une LECTURE (une version) : immuable, datée, signée. [texte] est le texte brut rendu par le moteur.
FicheDoc ocrNouvelleLecture({
  required String sha,
  required String texte,
  required String moteur,
  required String moteurVersion,
  required String langue,
  required String ocrLe,
  required String ocrPar,
  required String declencheur,
  required int pages,
  required int dureeMs,
  double? confiance,
}) {
  final norm = ocrMotsNormalises(texte);
  return {
    'id': ocrIdLecture(sha, moteur, moteurVersion, langue, norm.join(' ')),
    'sha256': sha,
    'texteBrut': texte.length > ocrBrutMax ? texte.substring(0, ocrBrutMax) : texte,
    'brutTronque': texte.length > ocrBrutMax,
    'texte': norm.take(ocrMotsMax).join(' '),
    'motsTronques': norm.length > ocrMotsMax,
    'nbMots': norm.length,
    'confiance': confiance,
    'texteSource': 'ocr',
    'moteur': moteur,
    'moteurVersion': moteurVersion,
    'langue': langue,
    'ocrLe': ocrLe,
    'ocrPar': ocrPar,
    'declencheur': declencheur,
    'pages': pages,
    'dureeMs': dureeMs,
  };
}

int _cmp(FicheDoc a, FicheDoc b) {
  final d = '${a['ocrLe']}'.compareTo('${b['ocrLe']}');
  return d != 0 ? d : '${a['id']}'.compareTo('${b['id']}');
}

/// Les versions lues d'une empreinte, de la plus ancienne à la plus récente (date de lecture, puis identifiant : un ordre que tous les postes retrouvent).
List<FicheDoc> ocrVersionsOrdonnees(Iterable<FicheDoc> versions) => [...versions]..sort(_cmp);

/// Une version est-elle une CORRECTION signée (et non une lecture machine) ?
bool ocrEstCorrection(FicheDoc v) => v['texteSource'] == 'correction';

/// Les corrections signées que NULLE autre ne remplace (les « têtes »), de la plus ancienne à la plus récente (lot C). Une correction en remplace d'autres par `remplace` (liste d'identifiants).
List<FicheDoc> ocrTetes(Iterable<FicheDoc> versions) {
  final tri = ocrVersionsOrdonnees(versions);
  final remplacees = <String>{
    for (final x in tri)
      for (final id in (x['remplace'] as List? ?? const [])) '$id'
  };
  return [
    for (final x in tri)
      if (ocrEstCorrection(x) && !remplacees.contains('${x['id']}')) x
  ];
}

/// Les corrections CONCURRENTES d'une empreinte (deux têtes ou plus : deux postes ont corrigé la même version), ou une liste vide. Rien n'est perdu : chacune reste une version.
List<FicheDoc> ocrConflit(Iterable<FicheDoc> versions) {
  final t = ocrTetes(versions);
  return t.length > 1 ? t : const [];
}

/// La version COURANTE (lot C) : la correction signée la plus récente non remplacée ; SANS correction, la lecture machine la plus récente qui porte du texte, ou `null`. Une lecture
/// machine, même plus récente, ne prend JAMAIS la place d'une correction signée : l'agent décide en signant une nouvelle correction.
FicheDoc? ocrVersionCourante(Iterable<FicheDoc> versions) {
  final t = ocrTetes(versions);
  if (t.isNotEmpty) return t.last;
  final v = ocrVersionsOrdonnees(versions).where((x) => !ocrEstCorrection(x) && ((x['nbMots'] as num?) ?? 0) > 0).toList();
  return v.isEmpty ? null : v.last;
}

// --- la correction signée du texte lu (lot C) -----------------------------------------------------------------------------------------------

/// Le texte comparé à un autre : les blancs répétés et ceux des bords ne comptent pas.
String ocrBlancs(String t) => t.replaceAll(RegExp(r'\s+'), ' ').trim();

/// L'identifiant d'une correction : DÉTERMINISTE (empreinte, version dont elle part, texte sans blancs superflus). Le même texte sur la même version est la MÊME version, d'un poste à l'autre.
String ocrIdCorrection(String sha, String corrigeDe, String texte) => 'OCC-${sha.substring(0, 16)}-${sha256Octets(utf8.encode('$corrigeDe|${ocrBlancs(texte)}')).substring(0, 12)}';

/// Le refus de DROIT d'une correction, ou `null`. Il faut ÉCRIRE sur l'écran de la pièce ([peutDeposer]), LIRE la zone du scan ([zoneLue] : toujours vrai hors dossier patient) ET détenir le
/// geste réservé ([gesteAccorde], `corriger_texte_ocr` de la fiche RBAC). Le motif dit laquelle des trois conditions manque.
RefusFichier? ocrRefusDroitCorrection({required bool peutDeposer, required bool zoneLue, required bool gesteAccorde}) {
  if (!peutDeposer) {
    return ocrRefus(CodeOcr.correctionReservee, 'votre profil n’écrit pas sur l’écran de cette pièce (ou la pièce est d’une zone qu’il ne lit pas) : il ne peut pas corriger son texte');
  }
  if (!zoneLue) return ocrRefus(CodeOcr.correctionReservee, 'cette pièce médicale est d’une zone que votre profil ne lit pas (RG-13)');
  if (!gesteAccorde) return ocrRefus(CodeOcr.correctionReservee, 'le droit « Corriger le texte lu par machine » n’est pas accordé à votre rôle');
  return null;
}

/// La commande « Corriger le texte lu » est-elle OFFERTE ? ABSENTE sinon, jamais grisée : droit, pas de couche texte native, une lecture à corriger.
bool ocrCorrectionPossible(
    {required bool peutDeposer, required bool zoneLue, required bool gesteAccorde, required EtatIndexation etat, required Iterable<FicheDoc> versions}) =>
    ocrRefusDroitCorrection(peutDeposer: peutDeposer, zoneLue: zoneLue, gesteAccorde: gesteAccorde) == null &&
    etat != EtatIndexation.indexe &&
    versions.any((x) => ((x['nbMots'] as num?) ?? 0) > 0 || ocrEstCorrection(x));

/// La correction demandée : le refus nommé, ou la FICHE de la version à ajouter. [versions] : les lectures de l'empreinte ; [corrigeDe] : la version dont le texte sert de départ (par défaut la
/// courante) ; [par] et [le] : le signataire et le moment (RG-12 : aucune action anonyme). [deja] : la même version existe, rien à écrire (rejeu, second poste). La fiche REMPLACE les corrections
/// courantes qu'elle a sous les yeux (`remplace`) : c'est ce qui départage un conflit.
({RefusFichier? refus, FicheDoc? fiche, bool deja, bool conflit}) ocrCorriger({
  required String sha,
  required String texte,
  required bool natif,
  required Iterable<FicheDoc> versions,
  String? corrigeDe,
  required String par,
  required String le,
  required bool peutDeposer,
  required bool zoneLue,
  required bool gesteAccorde,
}) {
  ({RefusFichier? refus, FicheDoc? fiche, bool deja, bool conflit}) non(RefusFichier r) => (refus: r, fiche: null, deja: false, conflit: false);
  final d = ocrRefusDroitCorrection(peutDeposer: peutDeposer, zoneLue: zoneLue, gesteAccorde: gesteAccorde);
  if (d != null) return non(d);
  if (natif) return non(ocrRefus(CodeOcr.texteNatif, 'ce fichier porte déjà une couche texte : elle prime, il n’y a rien à corriger'));
  if (texte.trim().isEmpty) return non(ocrRefus(CodeOcr.correctionTexteVide, 'le texte corrigé est vide'));
  final vs = ocrVersionsOrdonnees(versions);
  final FicheDoc? base = corrigeDe != null ? vs.where((x) => x['id'] == corrigeDe).firstOrNull : ocrVersionCourante(vs);
  if (base == null) {
    return non(ocrRefus(CodeOcr.correctionSansBase, corrigeDe != null ? 'la version « $corrigeDe » n’est pas une lecture de ce scan' : 'ce scan n’a aucune lecture à corriger'));
  }
  if (ocrBlancs(texte) == ocrBlancs('${base['texteBrut'] ?? ''}')) {
    return non(ocrRefus(CodeOcr.correctionIdentique, 'le texte est identique à celui de la version dont la correction part'));
  }
  final id = ocrIdCorrection(sha, '${base['id']}', texte);
  if (vs.any((x) => x['id'] == id)) return (refus: null, fiche: null, deja: true, conflit: ocrConflit(vs).length > 1);
  final norm = ocrMotsNormalises(texte);
  final remplace = [for (final t in ocrTetes(vs)) '${t['id']}'];
  return (
    refus: null,
    deja: false,
    conflit: false,
    fiche: {
      'id': id,
      'sha256': sha,
      'texteBrut': texte.length > ocrBrutMax ? texte.substring(0, ocrBrutMax) : texte,
      'brutTronque': texte.length > ocrBrutMax,
      'texte': norm.take(ocrMotsMax).join(' '),
      'motsTronques': norm.length > ocrMotsMax,
      'nbMots': norm.length,
      'texteSource': 'correction',
      'corrigeDe': '${base['id']}',
      'remplace': remplace,
      'corrigePar': par,
      'corrigeLe': le,
      'ocrLe': le,
    }
  );
}

/// La garde d'ÉCRITURE d'une correction : sans signataire, sans date, sans la version dont elle part ou sans texte, elle n'entre pas (RG-12). `null` : recevable.
String? ocrMotifCorrectionNonSignee(FicheDoc f) {
  if (f['texteSource'] != 'correction') return null;
  final vide = (Object? v) => v == null || '$v'.trim().isEmpty;
  if (vide(f['corrigePar']) || vide(f['corrigeLe']) || vide(f['corrigeDe']) || vide(f['texteBrut'])) {
    return 'Une correction du texte lu se signe : signataire, date, version dont elle part et texte sont requis.';
  }
  return null;
}

/// Le texte (mots normalisés) que la recherche lit pour un fichier : LA COUCHE TEXTE NATIVE PRIME TOUJOURS ; sinon la version OCR courante, SEULEMENT si le profil lit la zone du
/// document (le texte d'un scan de zone 2 est de zone 2). [natifIndexe] : le fichier porte une couche texte ; [natifTexte] : ses mots normalisés.
String ocrTexteRecherche(
    {required bool natifIndexe, required String natifTexte, required Iterable<FicheDoc> versions, required String famille, required String? type, required String role}) {
  if (natifIndexe) return natifTexte;
  if (famille == 'patient' && !docPeutVoir(type, role).autorise) return '';
  final c = ocrVersionCourante(versions);
  return c == null ? '' : '${c['texte'] ?? ''}';
}

// --- états d'indexation ---------------------------------------------------------------------------------------------------------------------

/// Les six états d'indexation d'un fichier, jamais confondus.
enum EtatIndexation {
  indexe('indexe'),
  ocrCorrige('ocr_corrige'),
  ocrEnAttente('ocr_en_attente'),
  ocrEnCours('ocr_en_cours'),
  ocrIndexe('ocr_indexe'),
  ocrEchec('ocr_echec'),
  nonIndexe('non_indexe');

  const EtatIndexation(this.code);
  final String code;
}

/// Ce que le poste dit de l'indexation d'un fichier : l'état, le petit mot de la ligne, la phrase de la carte, la raison, la SOURCE du texte (`couche_texte`, `ocr` ou rien), si le
/// texte est MARQUÉ « à vérifier », et si un texte est disponible pour la recherche.
class EtatIndexationOcr {
  const EtatIndexationOcr(this.etat, this.court, this.libelle, this.raison, this.source, this.marque, this.disponible, {this.conflit = false});
  final EtatIndexation etat;
  final String court;
  final String libelle;
  final String? raison;
  final String? source;
  final bool marque;
  final bool disponible;

  /// Deux corrections signées concurrentes de la même version (lot C) : à départager par une nouvelle correction.
  final bool conflit;
  String get code => etat.code;
}

/// L'état d'indexation. [versions] : les lectures de l'empreinte ; [file] : l'état de lecture en cours (`etat` : `en_attente`, `en_cours`, `echec`, avec `raison`) ou `null`.
EtatIndexationOcr ocrEtatIndexation(
    {required bool natif,
    required Iterable<FicheDoc> versions,
    FicheDoc? file,
    required bool moteurInstalle,
    required bool actif,
    required bool moteurActif,
    bool reglageRecu = true}) {
  final cur = ocrVersionCourante(versions);
  final signe = cur != null && ocrEstCorrection(cur);
  final conflit = ocrTetes(versions).length > 1;
  if (natif) {
    return const EtatIndexationOcr(EtatIndexation.indexe, 'texte indexé', 'Texte indexé (couche texte du fichier)', null, 'couche_texte', false, true);
  }
  final source = cur != null ? (signe ? 'correction' : 'ocr') : null;
  final dispo = cur != null;
  final marque = dispo && !signe;
  final precedente = signe ? ' (la correction signée reste le texte courant)' : ' (la version précédente reste lisible)';
  final etatFile = file?['etat'];
  if (etatFile == 'en_cours') {
    return EtatIndexationOcr(EtatIndexation.ocrEnCours, 'lecture OCR en cours', 'Lecture OCR en cours${cur != null ? precedente : ''}', null, source, marque, dispo, conflit: conflit);
  }
  if (etatFile == 'en_attente') {
    return EtatIndexationOcr(EtatIndexation.ocrEnAttente, 'lecture OCR en attente', 'Lecture OCR en attente${cur != null ? precedente : ''}', null, source, marque, dispo, conflit: conflit);
  }
  if (etatFile == 'echec') {
    final r = file?['raison'] as String?;
    return EtatIndexationOcr(EtatIndexation.ocrEchec, 'lecture OCR en échec', 'Lecture OCR en échec : ${r ?? 'cause non renseignée'}${signe ? ' (la correction signée reste le texte courant)' : ''}', r, source, marque, dispo, conflit: conflit);
  }
  if (signe) {
    final qui = '${cur['corrigePar'] ?? 'auteur inconnu'}';
    return EtatIndexationOcr(EtatIndexation.ocrCorrige, 'texte corrigé et signé par $qui',
        'Texte corrigé et signé par $qui${conflit ? ' (deux corrections concurrentes à départager)' : ''}', null, 'correction', false, true,
        conflit: conflit);
  }
  if (cur != null) {
    return const EtatIndexationOcr(EtatIndexation.ocrIndexe, 'texte lu par machine, à vérifier', 'Texte lu par machine, à vérifier', null, 'ocr', true, true);
  }
  final raison = !moteurInstalle
      ? ocrRaisonSansMoteur
      : (!reglageRecu ? ocrRaisonReglageNonRecu : !actif ? 'la lecture OCR est désactivée au réglage' : (!moteurActif ? 'le moteur choisi au réglage n’est pas installé sur ce poste' : 'lecture OCR non encore demandée'));
  return EtatIndexationOcr(EtatIndexation.nonIndexe, 'texte non indexé', 'Texte non indexé : $raison', raison, null, false, false);
}

/// Le texte de la phrase sous « Aucun résultat » : ce que la recherche ne lit pas, avec le BON nombre. `null` quand tout est lisible.
String? ocrIndiceVide(Iterable<EtatIndexationOcr> etats) {
  final liste = etats.toList();
  final sans = liste.where((e) => !e.disponible).toList();
  final out = <String>[];
  String pieces(int n, [String s = 's']) => 'pièce${n > 1 ? s : ''}';
  if (sans.isNotEmpty) {
    final n = sans.length;
    out.add('$n ${n > 1 ? 'pièces numérisées n’ont' : 'pièce numérisée n’a'} pas de texte indexé (image sans couche texte) : la recherche par le contenu ne les lit pas, seules leurs données de fiche sont cherchées.');
    final nonLu = liste.where((e) => e.etat == EtatIndexation.nonIndexe).toList();
    final attente = liste.where((e) => e.etat == EtatIndexation.ocrEnAttente || e.etat == EtatIndexation.ocrEnCours).length;
    final echec = liste.where((e) => e.etat == EtatIndexation.ocrEchec).length;
    if (nonLu.isNotEmpty) out.add('${nonLu.length} ${pieces(nonLu.length)} sans texte lu : ${nonLu.first.raison}.');
    if (attente > 0) out.add('$attente ${pieces(attente)} en attente de lecture OCR.');
    if (echec > 0) out.add('$echec ${pieces(echec)} dont la lecture OCR a échoué.');
  }
  final lus = liste.where((e) => e.etat == EtatIndexation.ocrIndexe).length;
  if (lus > 0) out.add('$lus ${pieces(lus)} ne se cherche${lus > 1 ? 'nt' : ''} que par un texte lu par machine, à vérifier.');
  return out.isEmpty ? null : out.join(' ');
}

/// Au-dessus des résultats : « N résultat(s) trouvé(s) dans un texte lu par machine ». `null` quand aucun.
String? ocrNoteRecherche(int n) =>
    n <= 0 ? null : '$n résultat${n > 1 ? 's' : ''} trouvé${n > 1 ? 's' : ''} dans un texte lu par machine (OCR) : la reconnaissance peut se tromper, à vérifier sur la pièce.';

// --- la file ---------------------------------------------------------------------------------------------------------------------------------

/// Une lecture est-elle POSSIBLE maintenant : activée au réglage, moteur choisi ET installé ?
bool ocrPret({required bool actif, required bool moteurActif}) => actif && moteurActif;

/// La demande d'une lecture. [registre] : la fiche du registre de l'empreinte ; [relance] : demandée par un agent. Rend le refus nommé, ou ce qu'il faut écrire sur le registre :
/// `etat` (la nouvelle file) ; [deja] dit qu'il n'y a rien à faire (déjà en file, déjà lu, déjà en échec : la file est UNE par empreinte).
({RefusFichier? refus, FicheDoc? etat, bool deja, bool lu}) ocrDemander(
    {required FicheDoc? registre,
    required Iterable<FicheDoc> versions,
    required bool moteurInstalle,
    required bool actif,
    required bool moteurActif,
    required bool relance,
    required String? famille,
    required String? type,
    required String maintenant,
    required String par}) {
  if (registre == null) {
    return (refus: ocrRefus(CodeOcr.registreAbsent, 'ce fichier n’est pas au registre des empreintes', 'Déposer le scan depuis sa fiche.'), etat: null, deja: false, lu: false);
  }
  if (registre['texteIndexe'] == true) return (refus: ocrRefus(CodeOcr.texteNatif, 'ce fichier porte déjà une couche texte'), etat: null, deja: false, lu: false);
  if (!ocrPret(actif: actif, moteurActif: moteurActif)) {
    return (
      refus: ocrRefus(!moteurInstalle ? CodeOcr.moteurAbsent : CodeOcr.desactive, !moteurInstalle ? ocrRaisonSansMoteur : 'la lecture OCR est désactivée au réglage'),
      etat: null,
      deja: false,
      lu: false
    );
  }
  final f = registre['ocr'] is Map ? (registre['ocr'] as Map).cast<String, Object?>() : null;
  if (f != null && (f['etat'] == 'en_attente' || f['etat'] == 'en_cours')) return (refus: null, etat: null, deja: true, lu: false);
  if (!relance && ocrVersionCourante(versions) != null) return (refus: null, etat: null, deja: true, lu: true);
  if (!relance && f != null && f['etat'] == 'echec') return (refus: null, etat: null, deja: true, lu: false);
  return (
    refus: null,
    etat: {
      'etat': 'en_attente',
      'demandeLe': maintenant,
      'demandePar': par,
      'declencheur': relance ? 'relance' : 'automatique',
      'famille': famille ?? f?['famille'],
      'type': type ?? f?['type'],
      'essais': 0,
    },
    deja: false,
    lu: false
  );
}

/// La commande « Relancer la lecture » est-elle OFFERTE ? Le droit d'écrire sur l'écran de la pièce (la zone est déjà portée par ce droit), une lecture possible, pas de couche
/// texte, rien déjà en file. ABSENTE sinon, jamais grisée.
bool ocrRelancePossible({required bool peutDeposer, required bool pret, required EtatIndexation etat}) =>
    peutDeposer && pret && etat != EtatIndexation.indexe && etat != EtatIndexation.ocrEnAttente && etat != EtatIndexation.ocrEnCours;

/// La relance REFUSÉE par le moteur lui-même (masquer un bouton ne protège rien) : le refus nommé, ou `null` si elle peut partir.
RefusFichier? ocrRefusRelance({required bool peutDeposer, required bool moteurInstalle, required bool actif, required bool moteurActif, required bool sansPiece}) {
  if (!peutDeposer) return ocrRefus(CodeOcr.droitRefuse, 'votre profil ne peut pas relancer la lecture de cette pièce');
  if (sansPiece) return ocrRefus(CodeOcr.sansPiece, 'cette fiche ne porte aucun fichier', 'Déposer d’abord le scan.');
  if (!ocrPret(actif: actif, moteurActif: moteurActif)) {
    return ocrRefus(!moteurInstalle ? CodeOcr.moteurAbsent : CodeOcr.desactive, !moteurInstalle ? ocrRaisonSansMoteur : 'la lecture OCR est désactivée au réglage');
  }
  return null;
}

/// Le prochain fichier à lire : le plus ancien « en attente » que ce profil n'a pas écarté. Un fichier à la fois.
FicheDoc? ocrChoisirSuivant(Iterable<FicheDoc> registres, {Set<String> ecartes = const {}}) {
  FicheDoc? best;
  for (final f in registres) {
    final o = f['ocr'];
    if (o is! Map || o['etat'] != 'en_attente' || ecartes.contains('${f['sha256']}')) continue;
    if (best == null) {
      best = f;
      continue;
    }
    // Le plus ancien d'abord ; à la même seconde, l'empreinte départage : tous les postes choisissent dans le même ordre.
    final bo = best['ocr'] as Map;
    final c = '${o['demandeLe']}'.compareTo('${bo['demandeLe']}');
    if (c < 0 || (c == 0 && '${f['sha256']}'.compareTo('${best['sha256']}') < 0)) best = f;
  }
  return best;
}

/// La REPRISE d'un traitement « en cours » depuis plus de deux délais (arrêt du poste) : remis en attente, ou en échec après trois essais. `null` : rien à faire.
FicheDoc? ocrReprendre(FicheDoc file, {required DateTime maintenant, required int delaiMs}) {
  if (file['etat'] != 'en_cours') return null;
  final debut = DateTime.tryParse('${file['debutLe'] ?? ''}');
  if (debut != null && debut.millisecondsSinceEpoch > maintenant.millisecondsSinceEpoch - delaiMs * 2) return null;
  final essais = ((file['essais'] as num?) ?? 0).toInt();
  if (essais >= ocrEssaisMax) {
    return {...file, 'etat': 'echec', 'code': CodeOcr.essaisEpuises, 'raison': 'la lecture a été interrompue $essais fois', 'geste': ocrGestes[CodeOcr.essaisEpuises], 'finLe': maintenant.toUtc().toIso8601String()};
  }
  return {...file, 'etat': 'en_attente'};
}

// --- lire un fichier avec un moteur --------------------------------------------------------------------------------------------------------

/// Le message d'une erreur que le moteur n'a pas su nommer : le texte seul, sans le nom du type d'erreur.
String _messageErreur(Object e) {
  if (e is StateError) return e.message;
  if (e is ArgumentError) return '${e.message}';
  if (e is FormatException) return e.message;
  return '$e'.replaceFirst(RegExp(r'^(Exception|Error): '), '');
}

/// Ce que rend la lecture d'un fichier : le texte, les pages, la durée, la confiance, ou le refus nommé.
class LectureFichier {
  const LectureFichier.ok({required this.texte, required this.pages, required this.dureeMs, this.confiance})
      : refus = null,
        mots = const [];
  const LectureFichier.refus(RefusFichier this.refus)
      : texte = '',
        pages = 0,
        dureeMs = 0,
        confiance = null,
        mots = const [];
  final String texte;
  final int pages;
  final int dureeMs;
  final double? confiance;
  final RefusFichier? refus;
  final List<MotOcr> mots;
  bool get ok => refus == null;
}

/// Lit les OCTETS d'un fichier avec [moteur] : image directement, PDF par le [rendeur] (absent : refus nommé). Borné en temps ([delaiMs]) ; un échec du moteur est NOMMÉ. Un texte vide
/// n'est pas une lecture : AUCUN_TEXTE. Ne choisit aucun moteur : celui qu'on lui donne.
Future<LectureFichier> ocrLireFichier(
    {required MoteurOcr? moteur, required Uint8List octets, required String formatId, required String? mime, required String langue, required int delaiMs, RendeurPages? rendeur}) async {
  if (moteur == null) return LectureFichier.refus(ocrRefus(CodeOcr.moteurAbsent, ocrRaisonSansMoteur));
  List<EntreeOcr> pages;
  if (formatId == 'pdf') {
    if (rendeur == null) {
      return LectureFichier.refus(ocrRefus(CodeOcr.rendu, 'ce scan est un PDF sans couche texte : aucun rendeur de pages n’est installé pour en tirer des images'));
    }
    try {
      pages = await rendeur.rendre(octets, langue: langue);
    } on ErreurOcr catch (e) {
      return LectureFichier.refus(e.refus);
    } catch (e) {
      return LectureFichier.refus(ocrRefus(CodeOcr.moteurEnEchec, _messageErreur(e)));
    }
  } else {
    if (!moteur.formats.contains(formatId)) {
      return LectureFichier.refus(ocrRefus(CodeOcr.formatNonLu, 'le moteur « ${moteur.id} » ne lit pas le format ${formatId.toUpperCase()}'));
    }
    if (!moteur.langues.contains(langue)) {
      return LectureFichier.refus(ocrRefus(CodeOcr.langueAbsente, 'le moteur « ${moteur.id} » ne lit pas la langue « $langue »'));
    }
    pages = [EntreeOcr(octets: octets, format: formatId, langue: langue, mime: mime ?? '', page: 1)];
  }
  final debut = DateTime.now();
  final textes = <String>[];
  final mots = <MotOcr>[];
  try {
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      final r = await moteur
          .lire(EntreeOcr(octets: p.octets, format: p.format, langue: langue, mime: p.mime, page: i + 1))
          .timeout(Duration(milliseconds: delaiMs), onTimeout: () => throw ErreurOcr(ocrRefus(CodeOcr.delaiDepasse, 'le moteur n’a pas répondu en ${delaiMs % 1000 == 0 ? '${delaiMs ~/ 1000}' : (delaiMs / 1000).toStringAsFixed(1).replaceFirst('.', ',')} s')));
      textes.add(r.texte);
      mots.addAll(r.mots);
    }
  } on ErreurOcr catch (e) {
    return LectureFichier.refus(e.refus);
  } catch (e) {
    return LectureFichier.refus(ocrRefus(CodeOcr.moteurEnEchec, _messageErreur(e)));
  }
  final texte = textes.join('\n');
  if (texte.trim().isEmpty) return LectureFichier.refus(ocrRefus(CodeOcr.aucunTexte, 'le moteur n’a lu aucun mot'));
  final confs = [for (final m in mots) if (m.confiance != null) m.confiance!];
  return LectureFichier.ok(
      texte: texte,
      pages: pages.length,
      dureeMs: DateTime.now().difference(debut).inMilliseconds,
      confiance: confs.isEmpty ? null : (confs.reduce((a, b) => a + b) / confs.length * 1000).round() / 1000);
}

/// Les profils qui lisent la zone 2 (rappel : un fichier de zone 2 ne se lit, ni ne se lit par machine, que sous un de ces rôles).
List<String> ocrRolesZone2() => docRolesZone2;
