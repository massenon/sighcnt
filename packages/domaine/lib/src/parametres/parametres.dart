// LES PARAMÈTRES VERSIONNÉS PAR DATE (lot L0, décision de la Direction du 09/11/2026), portés de `packages/sync/banc/parametres.js` (exécutable de référence ;
// vecteurs `test/vecteurs/parametres.json` engendrés par `banc/vecteurs-parametres.js`).
//
// Règle : tout ce qui est paramétrable se règle au poste, est ENREGISTRÉ EN BASE avec un DÉFAUT semé, et se VERSIONNE PAR DATE quand des pièces ont été émises
// sous l'ancienne valeur. Une VERSION est une fiche immuable de la collection `parametres` (famille R : la mère seule écrit) ; une correction ajoute une version,
// elle ne réécrit jamais une fiche. Résolution à la date D : parmi les versions dont la date d'effet est <= D (`null` = depuis toujours), celle qui porte la plus
// grande (date d'effet, version) ; sinon le défaut. Une valeur déjà utilisée par une pièce ne se réécrit jamais : `parametre_deja_utilise`.
//
// Doctrine : un refus se NOMME (code, motif, geste). Fonctions PURES : l'appelant (magasin du poste, mère) écrit, journalise (RG-12) et notifie.
// Aucune date « du jour » ici : la date est toujours fournie (date de la pièce, date d'effet saisie), jamais lue sur l'horloge.

/// La collection des versions de paramètres (famille R) et celle de leurs usages par les pièces (famille B, ajout seul).
const String parCollectionParametres = 'parametres';
const String parCollectionUsages = 'usagesParametres';

/// Familles que RG-13 ferme au téléphone (financier, RH, fiscal, sécurité, secrets). Seconde barrière : un paramètre ne va à un mobile que si sa définition le
/// DÉCLARE (`mobile`), que sa famille n'est pas ici et qu'il n'est pas `sensible`. Liste prudentielle, à valider par la Direction (aucun document ne la fixe).
const List<String> parFamillesJamaisMobile = ['paie', 'rh', 'fiscal', 'bareme_aib', 'comptabilite', 'mecef', 'securite', 'relais', 'courriel', 'sms'];

enum TypeParametre {
  booleen,
  texte,
  choix,
  entier,
  nombre;

  static TypeParametre? depuis(Object? v) {
    for (final t in TypeParametre.values) {
      if (t.name == v) return t;
    }
    return null;
  }
}

/// Un refus NOMMÉ : le code (stable, testable), le motif (lisible au guichet) et le geste de correction.
class RefusParametre {
  const RefusParametre(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
  Map<String, Object?> toJson() => {'ok': false, 'code': code, 'motif': motif, 'geste': geste};
  @override
  String toString() => '$code : $motif';
}

/// Ce que déclare un paramètre : sa clé, sa famille, son type, son défaut SEMÉ. C'est une donnée du registre, jamais une constante d'un écran.
class DefinitionParametre {
  const DefinitionParametre({
    required this.cle,
    required this.famille,
    required this.type,
    required this.defaut,
    this.libelle = '',
    this.aide = '',
    this.choix,
    this.libellesChoix = const {},
    this.sensible = false,
    this.mobile = false,
    this.source,
    this.branche = true,
    this.appliquePar,
  });
  final String cle;
  final String famille;
  final TypeParametre type;
  final Object? defaut;
  final String libelle;
  final String aide;
  final List<String>? choix;

  /// Le libellé affiché de chaque choix (l'identifiant du choix est ce qui voyage et se compare ; le libellé ne sert qu'à l'écran).
  final Map<String, String> libellesChoix;
  final bool sensible;

  /// Ce paramètre peut-il aller sur un téléphone ? Faux par défaut ; voir [Parametres.autoriseMobile].
  final bool mobile;

  /// D'où vient la valeur par défaut (document ou décision). `null` : à dire à l'écran comme « proposition à valider ».
  final String? source;

  /// Faux : le réglage s'enregistre mais l'écran qu'il commande ne le lit pas encore (lot à venir). L'écran des paramètres le dit.
  final bool branche;
  final String? appliquePar;

  factory DefinitionParametre.fromJson(Map<String, Object?> j) => DefinitionParametre(
        cle: '${j['cle']}',
        famille: '${j['famille']}',
        type: TypeParametre.depuis(j['type']) ?? TypeParametre.texte,
        defaut: j['defaut'],
        libelle: '${j['libelle'] ?? ''}',
        choix: (j['choix'] as List?)?.map((x) => '$x').toList(),
        sensible: j['sensible'] == true,
        mobile: j['mobile'] == true,
        source: j['source'] as String?,
      );
}

/// Une VERSION d'un paramètre (une fiche de la collection `parametres`).
class Parametre {
  const Parametre({
    required this.cle,
    required this.famille,
    required this.type,
    required this.valeur,
    required this.defaut,
    required this.dateEffet,
    required this.version,
    required this.auteur,
    this.creeLe,
    this.motif,
    this.choix,
    this.sensible = false,
    this.mobile = false,
    this.source,
  });
  final String cle;
  final String famille;
  final TypeParametre type;
  final Object? valeur;
  final Object? defaut;

  /// AAAA-MM-JJ, ou `null` pour la version 0 semée (« depuis toujours »).
  final String? dateEffet;
  final int version;
  final String auteur;
  final String? creeLe;
  final String? motif;
  final List<String>? choix;
  final bool sensible;
  final bool mobile;
  final String? source;

  /// L'identifiant de la fiche : `cle@dateEffet@version` (`defaut` pour la version 0).
  String get id => Parametres.idVersion(cle, dateEffet, version);

  factory Parametre.fromJson(Map<String, Object?> j) => Parametre(
        cle: '${j['cle']}',
        famille: '${j['famille']}',
        type: TypeParametre.depuis(j['type']) ?? TypeParametre.texte,
        valeur: j['valeur'],
        defaut: j['defaut'],
        dateEffet: j['dateEffet'] as String?,
        version: (j['version'] as num?)?.toInt() ?? -1,
        auteur: '${j['auteur'] ?? ''}',
        creeLe: j['creeLe'] as String?,
        motif: j['motif'] as String?,
        choix: (j['choix'] as List?)?.map((x) => '$x').toList(),
        sensible: j['sensible'] == true,
        mobile: j['mobile'] == true,
        source: j['source'] as String?,
      );

  Map<String, Object?> toJson() => {
        'cle': cle,
        'famille': famille,
        'type': type.name,
        if (choix != null) 'choix': choix,
        'valeur': valeur,
        'defaut': defaut,
        'dateEffet': dateEffet,
        'version': version,
        'auteur': auteur,
        'creeLe': creeLe,
        'motif': motif,
        'sensible': sensible,
        'mobile': mobile,
        'source': source,
      };
}

/// La valeur en vigueur à une date, avec d'où elle vient (`version` ou `defaut`).
class ResolutionParametre {
  const ResolutionParametre(this.valeur, this.origine, this.version, this.dateEffet);
  final Object? valeur;
  final String origine;
  final int version;
  final String? dateEffet;
  Map<String, Object?> toJson() => {'ok': true, 'valeur': valeur, 'origine': origine, 'version': version, 'dateEffet': dateEffet};
}

/// Un résultat : soit [valeur], soit [refus] (jamais les deux).
class ResultatParametre<T> {
  const ResultatParametre.ok(T this.valeur) : refus = null;
  const ResultatParametre.refuse(RefusParametre this.refus) : valeur = null;
  final T? valeur;
  final RefusParametre? refus;
  bool get ok => refus == null;
}

class Parametres {
  const Parametres._();

  static final RegExp _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static RefusParametre _r(String code, String motif, String geste) => RefusParametre(code, motif, geste);

  static bool dateValide(Object? s) {
    if (s is! String || !_iso.hasMatch(s)) return false;
    final d = DateTime.tryParse('${s}T00:00:00Z');
    return d != null && d.toIso8601String().substring(0, 10) == s;
  }

  static bool valeurValide(TypeParametre type, Object? v, List<String>? choix) {
    switch (type) {
      case TypeParametre.booleen:
        return v is bool;
      case TypeParametre.texte:
        return v is String;
      case TypeParametre.choix:
        return choix != null && v is String && choix.contains(v);
      case TypeParametre.entier:
        return v is int || (v is double && v.isFinite && v == v.truncateToDouble());
      case TypeParametre.nombre:
        return v is num && v.isFinite;
    }
  }

  /// Un paramètre part-il vers un téléphone ? Seule la LISTE BLANCHE répond oui : déclaré `mobile`, non sensible, famille non réservée (RG-13).
  static bool autoriseMobile(Map<String, Object?>? champs) =>
      champs != null && champs['mobile'] == true && champs['sensible'] != true && !parFamillesJamaisMobile.contains(champs['famille']);

  static String idVersion(String cle, String? dateEffet, int version) => '$cle@${dateEffet ?? 'defaut'}@$version';

  static String _cleTri(Parametre v) => v.dateEffet ?? '';
  static Parametre _plusRecente(Parametre a, Parametre b) {
    final ca = _cleTri(a), cb = _cleTri(b);
    if (ca != cb) return ca.compareTo(cb) > 0 ? a : b;
    return a.version >= b.version ? a : b;
  }

  /// La valeur en vigueur à [date] (AAAA-MM-JJ). [definition] porte le défaut quand aucune version n'existe encore.
  static ResultatParametre<ResolutionParametre> resoudre(String cle, List<Parametre> versions, String date, {DefinitionParametre? definition}) {
    if (!dateValide(date)) {
      return ResultatParametre.refuse(_r('date_invalide', 'Date « $date » illisible : attendu AAAA-MM-JJ.', 'Fournir la date de la pièce au format AAAA-MM-JJ'));
    }
    final vs = versions.where((v) => v.cle == cle && (v.dateEffet == null || v.dateEffet!.compareTo(date) <= 0)).toList();
    if (vs.isNotEmpty) {
      final v = vs.reduce(_plusRecente);
      return ResultatParametre.ok(ResolutionParametre(v.valeur, 'version', v.version, v.dateEffet));
    }
    if (definition != null && definition.cle == cle) return ResultatParametre.ok(ResolutionParametre(definition.defaut, 'defaut', 0, null));
    final autres = versions.where((v) => v.cle == cle).toList();
    if (autres.isNotEmpty) {
      final premieres = autres.map((v) => v.dateEffet).whereType<String>().toList()..sort();
      return ResultatParametre.refuse(_r('aucune_version_en_vigueur', '« $cle » n\'avait aucune valeur en vigueur au $date (première version au ${premieres.isEmpty ? 'null' : premieres.first}).',
          'Déclarer un défaut ou choisir une date postérieure'));
    }
    return ResultatParametre.refuse(_r('parametre_inconnu', 'Paramètre « $cle » inconnu : ni définition ni version.', 'Déclarer le paramètre dans le registre des paramètres'));
  }

  /// La date de la dernière pièce qui a utilisé [cle] (`null` : aucune).
  static String? dernierUsage(List<Map<String, Object?>> usages, String cle) {
    final l = usages.where((u) => u['cle'] == cle && dateValide(u['date'])).map((u) => u['date'] as String).toList()..sort();
    return l.isEmpty ? null : l.last;
  }

  /// Contrôle d'une version, à l'ÉMISSION (poste) comme à la RÉCEPTION (mère) : même fonction, mêmes refus. Travaille sur la fiche TELLE QU'ELLE VOYAGE (carte de
  /// champs) : la mère ne reconstruit rien, elle contrôle ce qu'elle a reçu. Rend `null` si la version est recevable, sinon le refus nommé.
  static RefusParametre? validerChamps(Map<String, Object?> c, List<Map<String, Object?>> existantes, List<Map<String, Object?>> usages) {
    for (final k in const ['cle', 'famille', 'type', 'auteur']) {
      final v = c[k];
      if (v is! String || v.trim().isEmpty) {
        return _r(k == 'auteur' ? 'auteur_manquant' : 'champ_manquant', 'Le champ « $k » est obligatoire${k == 'auteur' ? ' (RG-12 : aucune action anonyme)' : ''}.', 'Renseigner le champ');
      }
    }
    final type = TypeParametre.depuis(c['type']);
    if (type == null) return _r('type_inconnu', 'Type « ${c['type']} » inconnu.', 'Choisir : ${TypeParametre.values.map((t) => t.name).join(', ')}');
    final choix = (c['choix'] as List?)?.map((x) => '$x').toList();
    final cle = c['cle'] as String;
    if (!valeurValide(type, c['valeur'], choix)) {
      return _r('valeur_invalide', 'La valeur de « $cle » n\'est pas de type ${type.name}${type == TypeParametre.choix ? ' (${(choix ?? const []).join(' / ')})' : ''}.', 'Saisir une valeur du bon type');
    }
    if (c.containsKey('defaut') && !valeurValide(type, c['defaut'], choix)) {
      return _r('defaut_invalide', 'Le défaut de « $cle » n\'est pas de type ${type.name}.', 'Corriger la définition du paramètre');
    }
    final vers = c['version'];
    final version = vers is int ? vers : (vers is double && vers.isFinite && vers == vers.truncateToDouble() ? vers.toInt() : null);
    if (version == null || version < 0) return _r('version_invalide', 'Le numéro de version est un entier positif ou nul.', 'Laisser le poste numéroter');
    final dateEffet = c['dateEffet'];
    if (c.containsKey('dateEffet') && dateEffet == null) {
      if (version != 0) {
        return _r('date_effet_manquante', 'Une nouvelle version porte une date d\'effet : seule la version 0 (le défaut semé) en est dépourvue.', 'Fixer une date d\'effet');
      }
    } else {
      if (!dateValide(dateEffet)) return _r('date_invalide', 'Date d\'effet « $dateEffet » illisible : attendu AAAA-MM-JJ.', 'Saisir la date d\'effet');
      if (version == 0) return _r('version_invalide', 'La version 0 est réservée au défaut semé.', 'Laisser le poste numéroter');
      final u = dernierUsage(usages, cle);
      if (u != null && (dateEffet as String).compareTo(u) <= 0) {
        return _r('parametre_deja_utilise', 'La valeur de « $cle » a déjà servi à une pièce du $u : une version effective au $dateEffet la réécrirait.', 'Fixer une date d\'effet postérieure au $u');
      }
      // Une seule fiche par (clé, version). L'ORDRE d'arrivée ne compte pas : le poste publie du plus récent au plus ancien (le magasin insère en tête), la mère doit
      // accepter v2 puis v1. Seul un NUMÉRO DÉJÀ PRIS par une autre fiche est refusé (deux postes qui auraient numéroté de leur côté).
      if (existantes.any((v) => v['cle'] == cle && ((v['version'] as num?)?.toInt() ?? -1) == version)) {
        return _r('version_deja_prise', 'La version $version de « $cle » existe déjà.', 'Rafraîchir le poste puis recommencer');
      }
    }
    if (c['mobile'] == true && (c['sensible'] == true || parFamillesJamaisMobile.contains(c['famille']))) {
      return _r('mobile_interdit', '« $cle » ne peut pas aller sur un téléphone : ${c['sensible'] == true ? 'paramètre sensible' : 'famille « ${c['famille']} » réservée'} (RG-13).', 'Retirer l\'envoi au téléphone de la définition');
    }
    return null;
  }

  /// [validerChamps] pour une version déjà construite.
  static RefusParametre? validerFiche(Parametre c, List<Parametre> existantes, List<Map<String, Object?>> usages) =>
      validerChamps(c.toJson(), [for (final e in existantes) e.toJson()], usages);

  /// Le geste de l'administrateur : proposer une nouvelle valeur datée. Rend la version à écrire (et journaliser) ou un refus nommé.
  static ResultatParametre<Parametre> proposer({
    required DefinitionParametre? definition,
    required List<Parametre> versions,
    required List<Map<String, Object?>> usages,
    required Object? valeur,
    required String? dateEffet,
    required String auteur,
    String? creeLe,
    String? motif,
  }) {
    if (definition == null) {
      return ResultatParametre.refuse(_r('parametre_inconnu', 'Aucune définition pour ce paramètre.', 'Déclarer le paramètre dans le registre des paramètres'));
    }
    final version = versions.where((v) => v.cle == definition.cle).fold<int>(0, (m, v) => v.version > m ? v.version : m) + 1;
    final fiche = Parametre(
      cle: definition.cle,
      famille: definition.famille,
      type: definition.type,
      choix: definition.choix,
      valeur: valeur,
      defaut: definition.defaut,
      dateEffet: dateEffet,
      version: version,
      auteur: auteur,
      creeLe: creeLe,
      motif: motif,
      sensible: definition.sensible,
      mobile: definition.mobile,
      source: definition.source,
    );
    final r = validerFiche(fiche, versions, usages);
    return r == null ? ResultatParametre.ok(fiche) : ResultatParametre.refuse(r);
  }

  /// La version 0 : le défaut SEMÉ, identique sur tous les postes (ni date ni auteur variables), de sorte que deux semis indépendants ne divergent pas.
  static Parametre semer(DefinitionParametre d) => Parametre(
        cle: d.cle,
        famille: d.famille,
        type: d.type,
        choix: d.choix,
        valeur: d.defaut,
        defaut: d.defaut,
        dateEffet: null,
        version: 0,
        auteur: 'semis',
        creeLe: null,
        motif: 'Défaut semé',
        sensible: d.sensible,
        mobile: d.mobile,
        source: d.source,
      );
}
