/// LES FICHIERS NUMÉRISÉS : règles pures (lot D5, portage du lot DOCS-1 de la maquette : `assets/js/modules/fichiers.js`, `D.DOCUMENTS` de `data.js`, `PR.peutVoirDocument`
/// de `parcours.js`, `api/fichiers.php`). Un scan de courrier (M13) ou de document du patient (M1) vit HORS du magasin, sous son empreinte SHA-256 ; la fiche ne
/// garde que ses métadonnées (champ `fichier`). Rejoué sur `test/vecteurs/fichiers.json`, tiré de la maquette réelle pilotée dans Chrome et de son serveur PHP.
///
/// Trois doctrines tenues ici, jamais recopiées dans un écran :
///  - le FORMAT se lit sur les OCTETS (PDF, JPEG, PNG, et WEBP au seul dossier patient), jamais sur l'extension ou le type que le fichier prétend avoir ;
///  - la TAILLE MAXIMALE est une valeur en base (`documentsBornes`), la constante du domaine n'est que le défaut « à valider » ;
///  - un refus est NOMMÉ : un code, un motif lisible, le geste de correction (jamais un message muet).
library;

import 'dart:typed_data';

import '../droits/gestes_a_chaud.dart';
import '../droits/matrice.dart' show Droit;
import '../format/diacritiques.dart';
import '../format/js.dart' show arrondiJs, toFixedJs;
import 'fichiers_donnees.dart';
import 'sha256.dart';

typedef FicheDoc = Map<String, Object?>;

/// Un refus nommé : code, motif, geste (le contrat commun de tous les refus de fichier).
class RefusFichier {
  const RefusFichier(this.code, this.motif, this.geste, [this.plus = const {}]);
  final String code;
  final String motif;
  final String geste;

  /// Informations en plus (par exemple les deux empreintes d'une divergence).
  final Map<String, Object?> plus;

  Map<String, Object?> toJson() => {'code': code, 'motif': motif, 'geste': geste, ...plus};

  @override
  String toString() => '$code : $motif $geste';
}

/// La famille d'un fichier : `courrier` (M13) ou `patient` (M1).
const List<String> fichierFamilles = ['courrier', 'patient'];

/// L'écran dont une famille suit les droits (`m13-courriers`, `m1-documents`) : lu de `rbac.json`, jamais réécrit.
String fichierEcranDeFamille(String famille) => famille == 'patient' ? 'm1-documents' : 'm13-courriers';

/// Le poids d'un fichier en toutes lettres (`fichiers.js` : `poids`).
String fichierPoids(num? o) {
  if (o == null) return 'non renseignée';
  if (o >= 1024 * 1024) return '${toFixedJs(o / 1024 / 1024, 1).replaceFirst('.', ',')} Mo';
  final ko = arrondiJs(o / 1024).toInt();
  return '${ko < 1 ? 1 : ko} Ko';
}

// --- format -----------------------------------------------------------------------------------------------------------------------------------

/// Le format ADMIS d'un nom de fichier et d'un type MIME DÉCLARÉS, pour une famille ; `null` s'il n'est pas admis (`DOC.formatDe`).
FormatFichier? fichierFormatDeclare(String nom, String mime, String famille) {
  final m = RegExp(r'\.([a-z0-9]+)$').firstMatch(nom.toLowerCase());
  final ext = m?.group(1) ?? '';
  final type = mime.toLowerCase();
  for (final f in fichierFormats) {
    if (!f.familles.contains(famille)) continue;
    if (f.ext.contains(ext) || (ext.isEmpty && f.mime == type)) return f;
  }
  return null;
}

/// Le format lu sur les PREMIERS OCTETS : `pdf`, `jpeg`, `png`, `webp`, ou `null`. Jamais ce que le nom ou le type prétendent.
String? fichierFormatDesOctets(List<int> o) {
  bool debut(List<int> sig, [int off = 0]) {
    if (o.length < off + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (o[off + i] != sig[i]) return false;
    }
    return true;
  }

  if (debut(const [0x25, 0x50, 0x44, 0x46, 0x2d])) return 'pdf';
  if (debut(const [0xff, 0xd8, 0xff])) return 'jpeg';
  if (debut(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'png';
  if (debut(const [0x52, 0x49, 0x46, 0x46]) && debut(const [0x57, 0x45, 0x42, 0x50], 8)) return 'webp';
  return null;
}

FormatFichier? fichierFormatParId(String id) {
  for (final f in fichierFormats) {
    if (f.id == id) return f;
  }
  return null;
}

String _libellesAdmis(String famille) => [for (final f in fichierFormats) if (f.familles.contains(famille)) f.libelle].join(', ');

String _gesteFormat(String famille) => 'Enregistrer la numérisation en PDF, JPEG ou PNG${famille == 'patient' ? ' (WEBP admis au dossier patient)' : ''}.';

/// Le contrôle SANS réseau d'un fichier DÉCLARÉ (nom, type, taille) : format par l'extension ou le type, fichier non vide, taille maximale. Rend le format ou le refus.
({FormatFichier? format, RefusFichier? refus}) fichierControler({required String nom, required String mime, required int taille, required String famille, required int tailleMax}) {
  final fmt = fichierFormatDeclare(nom, mime, famille);
  if (fmt == null) {
    return (format: null, refus: RefusFichier('FORMAT_REFUSE', 'le format de « $nom » n’est pas admis (${_libellesAdmis(famille)})', _gesteFormat(famille)));
  }
  if (taille == 0) {
    return (format: null, refus: RefusFichier('FICHIER_VIDE', '« $nom » ne contient aucun octet', 'Choisir un fichier numérisé non vide.'));
  }
  if (taille > tailleMax) {
    return (
      format: null,
      refus: RefusFichier('TAILLE_DEPASSEE', 'le fichier pèse ${fichierPoids(taille)}, le maximum réglé est ${fichierPoids(tailleMax)}',
          'Numériser en résolution plus basse, ou demander à l’administrateur de relever la taille maximale.')
    );
  }
  return (format: fmt, refus: null);
}

/// Le contrôle COMPLET d'un dépôt, côté poste : la déclaration, PUIS le contenu (les octets doivent être du format que le nom annonce : « l'extension ne suffit pas »).
/// Rend le format réel et l'empreinte, ou le refus nommé. L'empreinte est calculée ICI sur les octets : jamais lue d'une promesse.
({FormatFichier? format, String? sha256, RefusFichier? refus}) fichierVerifierOctets(
    {required String nom, required String mime, required Uint8List octets, required String famille, required int tailleMax}) {
  final c = fichierControler(nom: nom, mime: mime, taille: octets.length, famille: famille, tailleMax: tailleMax);
  if (c.refus != null) return (format: null, sha256: null, refus: c.refus);
  final reel = fichierFormatDesOctets(octets);
  if (reel == null || reel != c.format!.id) {
    return (
      format: null,
      sha256: null,
      refus: RefusFichier('FORMAT_REFUSE', 'le contenu de « $nom » n’est pas un ${c.format!.libelle} (l’extension ne suffit pas)', 'Enregistrer de nouveau la numérisation dans ce format.')
    );
  }
  return (format: fichierFormatParId(reel), sha256: sha256Octets(octets), refus: null);
}

/// Le contrôle du SERVEUR (la mère) à la réception d'un fichier complet : le contenu est de l'un des formats admis de la famille, jamais lu sur un nom. Même texte que
/// `api/fichiers.php` (FORMAT_REFUSE, 415).
({FormatFichier? format, RefusFichier? refus}) fichierControlerContenu(List<int> octets, String famille) {
  final id = fichierFormatDesOctets(octets);
  final fmt = id == null ? null : fichierFormatParId(id);
  if (fmt == null || !fmt.familles.contains(famille)) {
    return (
      format: null,
      refus: RefusFichier('FORMAT_REFUSE', 'le contenu du fichier n’est pas un format admis (${_libellesAdmis(famille).toUpperCase()})', _gesteFormat(famille))
    );
  }
  return (format: fmt, refus: null);
}

/// Ce que le poste décide AVANT d'envoyer quoi que ce soit : le refus nommé, ou le format réel, l'empreinte et le doublon éventuel. [fiches] : les fiches de la collection de la
/// famille ; [ficheCourante] : la fiche qui reçoit la pièce ; [portee] : « la même » fiche pour le doublon (le même dossier patient). Un doublon sur la MÊME fiche ou le même dossier
/// REFUSE (`DOUBLON_MEME_FICHE`) ; un doublon sur une AUTRE fiche avertit seulement (`autre`) : l'écran demande confirmation.
({RefusFichier? refus, FormatFichier? format, String? sha256, FicheDoc? autre}) fichierPreparerDepot(
    {required String nom,
    required String mime,
    required Uint8List octets,
    required String famille,
    required int tailleMax,
    required Iterable<FicheDoc> fiches,
    FicheDoc? ficheCourante,
    bool Function(FicheDoc)? portee}) {
  final v = fichierVerifierOctets(nom: nom, mime: mime, octets: octets, famille: famille, tailleMax: tailleMax);
  if (v.refus != null) return (refus: v.refus, format: null, sha256: null, autre: null);
  final d = fichierDoublon(fiches, v.sha256!, ficheCourante: ficheCourante, portee: portee);
  if (d != null && d.memeFiche != null) {
    return (refus: fichierRefusDoublon(d.memeFiche!, parPortee: portee != null), format: null, sha256: v.sha256, autre: null);
  }
  return (refus: null, format: v.format, sha256: v.sha256, autre: d?.autre);
}

// --- taille maximale (réglage en base) ---------------------------------------------------------------------------------------------------

/// La taille maximale d'UN fichier, en octets : la valeur réglée (`documentsBornes.tailleMax`) si elle est valide, sinon le défaut ; toujours bornée par le plafond.
int fichierTailleMax(Map<String, Object?>? reglage) {
  final v = reglage == null ? null : reglage['tailleMax'];
  final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  if (n != null && n > 0 && n.isFinite) {
    final e = n.floor();
    return e < fichierTaillePlafond ? e : fichierTaillePlafond;
  }
  return fichierTailleDefaut;
}

bool fichierTailleMaxReglee(Map<String, Object?>? reglage) {
  final v = reglage == null ? null : reglage['tailleMax'];
  final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  return n != null && n > 0;
}

/// Les profils qui règlent la taille maximale : l'administrateur et la Directrice Administrative.
const List<String> fichierRolesReglage = ['admin', 'da'];

/// Lot CLO-3 : le réglage est le geste réservé [fichierGesteRegler] de la fiche RBAC ; [fichierRolesReglage] n'est que son défaut d'origine (manifeste `N.GESTES`).
const String fichierGesteRegler = 'regler_fichiers';
bool fichierPeutRegler(String role) => gesDroit(role, fichierGesteRegler, fichierRolesReglage);

/// Règle la taille maximale (en octets). Réservé à l'administrateur et à la DAF, motivé, borné. Rend la nouvelle valeur ou le refus nommé ; l'écriture et le journal
/// sont à l'appelant (le magasin).
({bool ok, RefusFichier? refus, int? avant, int? tailleMax}) fichierDefinirTailleMax(
    {required String role, required Object? octets, required String? motif, required Map<String, Object?>? reglage}) {
  if (!fichierPeutRegler(role)) {
    return (
      ok: false,
      refus: const RefusFichier('REGLAGE_RESERVE', 'la taille maximale des fichiers se règle par l’administrateur ou la Directrice Administrative', 'Demander le réglage à l’un d’eux.'),
      avant: null,
      tailleMax: null
    );
  }
  final n = octets is num ? octets.toDouble() : (octets == null || octets == '' ? null : double.tryParse('$octets'));
  if (octets == '' || octets == null || n == null || !n.isFinite || n != n.floorToDouble() || n < fichierTaillePlancher || n > fichierTaillePlafond) {
    return (
      ok: false,
      refus: RefusFichier('TAILLE_INVALIDE', 'la taille maximale est un nombre entier d’octets, de ${fichierPoids(fichierTaillePlancher)} à ${fichierPoids(fichierTaillePlafond)}',
          'Saisir une taille en mégaoctets dans cette plage.'),
      avant: null,
      tailleMax: null
    );
  }
  if ((motif ?? '').trim().isEmpty) {
    return (ok: false, refus: const RefusFichier('MOTIF_REQUIS', 'un réglage de taille se motive', 'Saisir le motif du réglage.'), avant: null, tailleMax: null);
  }
  return (ok: true, refus: null, avant: fichierTailleMax(reglage), tailleMax: n.toInt());
}

// --- zones et droits ------------------------------------------------------------------------------------------------------------------

/// La zone d'un type de document du patient : 1 = administratif (identité, couverture), 2 = médical (RG-13). Un type INCONNU se range à la zone la plus stricte.
int docZoneDe(String? type) {
  for (final t in docTypesPatient) {
    if (t.libelle == type) return t.zone;
  }
  return 2;
}

/// `PR.peutVoirDocument` : le profil lit-il (ou dépose-t-il) un document de ce TYPE ? Rend la décision, la zone et le motif.
({bool autorise, int zone, String motif}) docPeutVoir(String? type, String role) {
  final zone = docZoneDe(type);
  if (zone < 2) return (autorise: true, zone: zone, motif: 'Pièce administrative (zone 1) : lisible de tout profil qui ouvre l’écran');
  if (docRolesZone2.contains(role)) return (autorise: true, zone: zone, motif: 'Profil clinique : les pièces médicales (zone 2) lui sont ouvertes');
  return (autorise: false, zone: zone, motif: 'Pièce médicale (zone 2) : seuls les profils cliniques la lisent (RG-13)');
}

/// Le droit d'un profil sur une famille de fichiers, pour un geste (`voir`, `editer`, `annuler`) : le droit de l'ÉCRAN de la famille ([droitEcran], lu de la matrice
/// `rbac.json`), plus la ZONE du type au dossier patient. Rend `null` si permis, sinon le refus nommé (mêmes codes et mêmes textes que `api/fichiers.php`).
RefusFichier? fichierRefusDroit({required String role, required String famille, required String geste, required String? type, required Droit droitEcran}) {
  final permis = geste == 'editer' ? droitEcran.editer : (geste == 'annuler' ? droitEcran.annuler : droitEcran.voir);
  if (!permis) {
    final ecran = fichierEcranDeFamille(famille);
    return RefusFichier('DROIT_REFUSE', 'le profil « $role » n’a pas le droit de ${geste == 'voir' ? 'lire' : 'déposer'} sur l’écran « $ecran »',
        'Demander ce droit à l’administrateur (« Rôles & permissions »).');
  }
  if (famille == 'patient') {
    final zone = docZoneDe(type);
    if (zone >= 2 && !docRolesZone2.contains(role)) {
      return RefusFichier('ZONE_REFUSEE', 'le profil « $role » ne lit ni ne dépose les pièces médicales du dossier patient (RG-13)',
          'Seuls les profils cliniques traitent ce type de pièce ; l’accueil dépose la pièce d’identité et la carte d’assurance.');
    }
  }
  return null;
}

// --- noms --------------------------------------------------------------------------------------------------------------------------------

/// Une chaîne sans accent ni espace, pour un nom de fichier : lettres minuscules, chiffres et tirets (`DOC.slug`).
String docSlug(Object? t) {
  var s = sansDiacritiques('${t ?? ''}').toLowerCase();
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return s;
}

/// Le NOM DE TÉLÉCHARGEMENT d'une pièce (EF-DOC-4), recalculé, jamais saisi : la RÉFÉRENCE de la fiche ne change jamais. Courrier : `AAAA-MM-JJ_ARR_NNNN.ext` ; patient :
/// `AAAA-MM-JJ_CODE_type_NNN.ext`.
String docNomNormalise(String famille, FicheDoc? fiche, String ext) {
  final dateBrute = '${fiche?['date'] ?? ''}';
  final date = dateBrute.isEmpty ? '0000-00-00' : (dateBrute.length > 10 ? dateBrute.substring(0, 10) : dateBrute);
  final e = (ext.isEmpty ? 'pdf' : ext).toLowerCase().replaceFirst(RegExp(r'^\.'), '');
  if (famille == 'courrier') {
    final m = RegExp(r'^(ARR|DEP)-\d{4}-(\d+)$').firstMatch('${fiche?['reference'] ?? ''}');
    final sens = m != null ? m.group(1)! : (fiche?['sens'] == 'depart' ? 'DEP' : 'ARR');
    return '${date}_${sens}_${m != null ? m.group(2)! : '0000'}.$e';
  }
  final n = RegExp(r'(\d+)$').firstMatch('${fiche?['reference'] ?? ''}');
  var rang = n != null ? '${int.parse(n.group(1)!)}' : '0';
  while (rang.length < 3) {
    rang = '0$rang';
  }
  final brut = fiche?['code'];
  final code = ((brut == null || '$brut'.isEmpty) ? 'SANS-DOSSIER' : '$brut').replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  final type = docSlug(fiche?['type']);
  return '${date}_${code}_${type.isEmpty ? 'document' : type}_$rang.$e';
}

/// L'empreinte abrégée (huit caractères) imprimée sur la fiche.
String docAbrege(Object? sha) {
  final s = '${sha ?? ''}';
  return s.length > 8 ? s.substring(0, 8) : s;
}

/// L'extension de stockage d'un type MIME (`extDe`).
String fichierExtDeMime(String? mime) =>
    const {'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp'}[mime] ?? 'bin';

// --- la fiche : fichier, fichiers retirés, numérisé dérivé ---------------------------------------------------------------------------

/// Le fichier de la fiche (le champ `fichier` quand il porte une empreinte), ou `null`. Un ancien `fichier` TEXTE (nom saisi du jeu d'avant) n'est pas un fichier.
Map<String, Object?>? fichierDe(FicheDoc? f) {
  final x = f?['fichier'];
  if (x is Map && x['sha256'] != null && '${x['sha256']}'.isNotEmpty) return x.cast<String, Object?>();
  return null;
}

/// `numerise` d'un courrier est DÉRIVÉ : vrai quand un fichier est rattaché, jamais saisi (la case est retirée).
bool courrierNumerise(FicheDoc? f) => fichierDe(f) != null;

/// L'objet `fichier` de la fiche, construit d'un dépôt réussi. [depot] : `sha256`, `ext`, `mime`, `taille`, `pages`, `texteIndexe`.
Map<String, Object?> fichierConstruire(
    {required String famille, required FicheDoc fiche, required Map<String, Object?> depot, required String nomOrigine, required String deposePar, required String deposeLe}) {
  return {
    'sha256': depot['sha256'],
    'nom': nomOrigine,
    'nomNormalise': docNomNormalise(famille, fiche, '${depot['ext']}'),
    'mime': depot['mime'],
    'taille': depot['taille'],
    'pages': depot['pages'],
    'texteIndexe': depot['texteIndexe'] == true,
    'deposePar': deposePar,
    'deposeLe': deposeLe,
  };
}

/// Le nom de téléchargement qui SUIT la fiche quand sa date ou sa référence change : l'objet `fichier` recalculé (la référence, elle, ne change jamais).
Map<String, Object?> fichierRecalculerNom(String famille, FicheDoc fichePrevue, Map<String, Object?> fichier) {
  final ext = '${fichier['nomNormalise'] ?? ''}'.split('.').last;
  return {...fichier, 'nomNormalise': docNomNormalise(famille, fichePrevue, ext)};
}

/// Le retrait d'une pièce (RG-14) : le patch à appliquer à la fiche (`fichier` à vide, l'historique `fichiersRetires` allongé de la pièce) ; le fichier reste au disque.
/// `null` si la fiche ne porte aucun fichier. L'ANNULATION remet `fichier` ET l'historique d'avant (une clé ajoutée par le patch ne se retire pas d'elle-même).
({Map<String, Object?> patch, Map<String, Object?> annulation})? fichierRetirer(
    {required FicheDoc fiche, required String motif, required String retirePar, required String retireLe}) {
  final x = fichierDe(fiche);
  if (x == null) return null;
  final ancien = [for (final e in (fiche['fichiersRetires'] as List? ?? const [])) e];
  final m = motif.length > 200 ? motif.substring(0, 200) : motif;
  return (
    patch: {
      'fichier': null,
      'fichiersRetires': [
        ...ancien,
        {...x, 'retireLe': retireLe, 'retirePar': retirePar, 'motif': m}
      ],
    },
    annulation: {'fichier': x, 'fichiersRetires': ancien},
  );
}

// --- doublon par dossier --------------------------------------------------------------------------------------------------------------

/// Le doublon d'un fichier (même empreinte) : `memeFiche` (la même fiche, ou la même PORTÉE : le même dossier patient) refuse le dépôt ; `autre` avertit (le fichier est déjà
/// la pièce d'une autre fiche). [portee] dit si une autre fiche est « la même » (le même dossier patient).
({FicheDoc? memeFiche, FicheDoc? autre})? fichierDoublon(Iterable<FicheDoc> fiches, String sha, {FicheDoc? ficheCourante, bool Function(FicheDoc)? portee}) {
  final memes = [
    for (final f in fiches)
      if (f['statut'] != 'archive' && fichierDe(f)?['sha256'] == sha) f
  ];
  for (final f in memes) {
    final meme = (ficheCourante != null && f['id'] == ficheCourante['id']) || (portee != null && portee(f));
    if (meme) return (memeFiche: f, autre: null);
  }
  return memes.isNotEmpty ? (memeFiche: null, autre: memes.first) : null;
}

/// La désignation d'une pièce dans un message de doublon : `GED-00003 (nom-normalisé.pdf)`.
String fichierNomPiece(FicheDoc f) {
  final x = fichierDe(f);
  return '${f['reference'] ?? f['id']} (${x != null ? (x['nomNormalise'] ?? x['nom']) : 'sans fichier'})';
}

/// Le refus d'un doublon sur la MÊME fiche ou le même dossier.
RefusFichier fichierRefusDoublon(FicheDoc existante, {required bool parPortee}) => RefusFichier(
    'DOUBLON_MEME_FICHE', 'ce fichier est déjà rattaché à ${parPortee ? 'ce dossier' : 'cette fiche'} : pièce ${fichierNomPiece(existante)}', 'Ouvrir la pièce existante plutôt que de la déposer deux fois.');

// --- registre par empreinte et recherche dans le texte ------------------------------------------------------------------------------

/// L'identifiant d'une fiche du registre `fichiers` : une fiche par empreinte (ajout seul), jamais deux.
String fichierIdRegistre(String sha) => 'FIC-${sha.substring(0, 16)}';

/// Les mots d'un texte indexé, normalisés (sans accent, minuscules), distincts, longueur 2 au moins, séparés par une espace.
String fichierNormaliserMots(Iterable<String> mots) {
  final vus = <String>{};
  final out = <String>[];
  for (final m in mots) {
    final n = sansDiacritiques(m).toLowerCase();
    if (n.length >= 2 && vus.add(n)) out.add(n);
  }
  return out.join(' ');
}

/// La fiche du registre `fichiers` pour un dépôt (SANS compteur de références : il se DÉDUIT des fiches, un compteur synchronisé serait compté deux fois).
Map<String, Object?> fichierEntreeRegistre({required Map<String, Object?> depot, required String premiereDate}) => {
      'id': fichierIdRegistre('${depot['sha256']}'),
      'sha256': depot['sha256'],
      'taille': depot['taille'],
      'mime': depot['mime'],
      'pages': depot['pages'],
      'premiereDate': premiereDate,
      'texteIndexe': depot['texteIndexe'] == true,
      'texte': depot['texteIndexe'] == true ? fichierNormaliserMots([for (final m in (depot['mots'] as List? ?? const [])) '$m']) : '',
      'motsTronques': depot['motsTronques'] == true,
    };

/// Le nombre de références d'une empreinte, DÉDUIT des fiches qui la portent (archivées exclues) : jamais stocké ni synchronisé.
int fichierNbReferences(Iterable<FicheDoc> fiches, String sha) => fiches.where((f) => f['statut'] != 'archive' && fichierDe(f)?['sha256'] == sha).length;

/// Le texte que la recherche lit en plus des colonnes d'un courrier ou d'un document : observations, date lisible, nom du fichier, nom normalisé, TEXTE extrait.
String fichierTexteRecherche(FicheDoc fiche, {required String dateFr, required String texteIndexe, String? observations}) {
  final x = fichierDe(fiche);
  return [observations ?? '', dateFr, x != null ? '${x['nom'] ?? ''}' : '', x != null ? '${x['nomNormalise'] ?? ''}' : '', x != null ? texteIndexe : ''].join(' ');
}

/// La recherche de la maquette : `C.matches(texte, terme)`, sans accent ni casse.
bool fichierCorrespond(String texte, String terme) => sansDiacritiques(texte).toLowerCase().contains(sansDiacritiques(terme).toLowerCase());

/// Ce que la recherche ne lit PAS, dit sous « Aucun résultat » : jamais un vide qui se lit « il n'y a rien dans ce courrier ». `null` quand tout est indexé.
String? fichierIndiceNonIndexe(int nbNonIndexes) => nbNonIndexes == 0
    ? null
    : '$nbNonIndexes pièce${nbNonIndexes > 1 ? 's numérisées n’ont' : ' numérisée n’a'} pas de texte indexé (image sans couche texte) : la recherche par le contenu ne les lit pas, seules leurs données de fiche sont cherchées.';

// --- l'état d'un fichier AU POSTE ----------------------------------------------------------------------------------------------------

/// Ce que le poste dit d'un fichier rattaché à une fiche (EF-SYNC-17 : « non disponible hors ligne », jamais un écran vide).
enum EtatFichierPoste { sansFichier, present, enCoursDeTransfert, nonDisponibleHorsLigne, altere, zoneRefusee }

/// L'état d'un fichier. [referenceParFiche] : la fiche porte un `fichier` ; [copieLocale] : `true` présent et intact, `false` présent mais altéré, `null` absent ;
/// [mereJoignable] : le poste joint sa mère (ou est la mère) : le binaire absent est alors « en cours de transfert » (le poste vient le chercher) ; la mère coupée, il est « non
/// disponible hors ligne », que le transfert ait commencé ou non (il reprendra au retour de la mère) ; [zoneAutorisee] : le profil lit la zone du document.
EtatFichierPoste fichierEtatPoste({required bool referenceParFiche, required bool? copieLocale, required bool mereJoignable, required bool zoneAutorisee}) {
  if (!referenceParFiche) return EtatFichierPoste.sansFichier;
  if (!zoneAutorisee) return EtatFichierPoste.zoneRefusee;
  if (copieLocale == true) return EtatFichierPoste.present;
  if (copieLocale == false) return EtatFichierPoste.altere;
  return mereJoignable ? EtatFichierPoste.enCoursDeTransfert : EtatFichierPoste.nonDisponibleHorsLigne;
}

/// Le libellé de l'état, avec le geste (jamais un écran vide ni une erreur).
String fichierLibelleEtatPoste(EtatFichierPoste e, {String? sha}) {
  switch (e) {
    case EtatFichierPoste.sansFichier:
      return 'Aucune pièce numérisée rattachée à cette fiche.';
    case EtatFichierPoste.present:
      return 'Fichier présent sur ce poste.';
    case EtatFichierPoste.enCoursDeTransfert:
      return 'Fichier en cours de transfert vers ce poste : il s’ouvrira dès son arrivée (empreinte ${docAbrege(sha)}).';
    case EtatFichierPoste.nonDisponibleHorsLigne:
      return 'Fichier non disponible hors ligne : il arrivera quand ce poste joindra de nouveau la mère (empreinte ${docAbrege(sha)}).';
    case EtatFichierPoste.altere:
      return 'Le fichier rangé sur ce poste n’a plus son empreinte (${docAbrege(sha)}) : il n’est pas servi. Il sera redemandé à la mère.';
    case EtatFichierPoste.zoneRefusee:
      return 'Pièce non affichée à votre profil : les pièces médicales du dossier ne se lisent que par les profils cliniques (RG-13).';
  }
}
