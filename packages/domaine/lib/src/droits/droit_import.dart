/// LE DROIT D'IMPORT, PAR JEU (lot IMP-A de la maquette, lot IMP-C du poste).
///
/// Le droit d'importer n'est PAS le droit d'éditer l'écran `imp-*` : c'est un axe propre, par jeu (`voir`, `importer`, `annuler`), déclaré au manifeste de la maquette
/// (`N.IMPORTS`), porté par la fiche RBAC (`droitsImport`) et exporté dans la section `import` de `packages/rbac/data/rbac.json`. Ce fichier le LIT, jamais un nom de
/// rôle en dur : la matrice engendrée est la base, la superposition à chaud des fiches (`a_chaud.dart`) la recalcule comme `N.droitImport()`.
///
/// Résolution (identique à la maquette) : rôle archivé, FERMÉ ; écran du jeu ou module d'import fermé par une activité fermée, FERMÉ pour tous les rôles, administrateur
/// compris ; puis la fiche RBAC, champ par champ (UNE SURCHARGE ACCORDE AUTANT QU'ELLE RESTREINT) ; à défaut, la matrice d'origine du jeu (`defaut`). `importer` et
/// `annuler` supposent `voir`. Un rôle créé en exploitation n'est dans aucune matrice d'origine : il part de zéro.
library;

/// La déclaration d'un jeu : tout ce que le manifeste de la maquette en dit (les hôtes du bouton, la sensibilité, le mode de doublon).
class DeclarationImport {
  const DeclarationImport({
    required this.id,
    required this.libelle,
    required this.ecran,
    required this.module,
    required this.hotes,
    required this.sensibilite,
    required this.doublon,
    required this.collections,
    this.defaut = const {},
  });

  final String id, libelle, ecran, module, sensibilite, doublon;

  /// Les écrans qui portent le bouton « Importer les données » (fabrique unique `BoutonImporter`).
  final List<String> hotes;

  /// Les collections que le jeu écrit.
  final List<String> collections;

  /// La matrice D'ORIGINE : rôle → `V` voir, `I` importer, `A` annuler.
  final Map<String, String> defaut;

  /// Un jeu RESTREINT ne recopie JAMAIS une valeur de cellule dans l'historique ni le rapport (RG-13).
  bool get restreint => sensibilite == 'restreinte';

  factory DeclarationImport.depuisJson(Map<String, Object?> j) => DeclarationImport(
        id: '${j['id']}',
        libelle: '${j['libelle']}',
        ecran: '${j['ecran']}',
        module: '${j['module']}',
        hotes: [for (final h in (j['hotes'] as List? ?? const [])) '$h'],
        sensibilite: '${j['sensibilite'] ?? 'courante'}',
        doublon: '${j['doublon'] ?? 'refuser'}',
        collections: [for (final c in (j['collections'] as List? ?? const [])) '$c'],
        defaut: {for (final e in ((j['defaut'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
      );
}

/// Ce qu'un rôle détient sur un jeu.
class DroitImport {
  const DroitImport({required this.jeu, required this.voir, required this.importer, required this.annuler});
  final String jeu;
  final bool voir, importer, annuler;

  static DroitImport ferme(String jeu) => DroitImport(jeu: jeu, voir: false, importer: false, annuler: false);

  @override
  bool operator ==(Object o) => o is DroitImport && o.jeu == jeu && o.voir == voir && o.importer == importer && o.annuler == annuler;

  @override
  int get hashCode => Object.hash(jeu, voir, importer, annuler);

  @override
  String toString() => 'DroitImport($jeu, voir: $voir, importer: $importer, annuler: $annuler)';
}

/// La matrice d'import : la déclaration des jeux et, pour chaque rôle, ce qu'il détient.
class MatriceImport {
  MatriceImport({
    required this.declarations,
    required Map<String, Map<String, DroitImport>> parRole,
    required this.superviseurs,
    required this.capacitePaie,
  }) : _parRole = parRole;

  final List<DeclarationImport> declarations;
  final Set<String> superviseurs, capacitePaie;
  final Map<String, Map<String, DroitImport>> _parRole;

  /// Aucune déclaration : un poste dont `rbac.json` ne porte pas la section `import` n'importe rien.
  static final MatriceImport vide = MatriceImport(declarations: const [], parRole: const {}, superviseurs: const {}, capacitePaie: const {});

  /// `json` = la section `import` de `rbac.json`.
  factory MatriceImport.depuisJson(Object? json) {
    if (json is! Map) return vide;
    final decl = [for (final j in (json['jeux'] as List? ?? const [])) DeclarationImport.depuisJson((j as Map).cast<String, Object?>())];
    final parRole = <String, Map<String, DroitImport>>{};
    ((json['parRole'] as Map?) ?? const {}).forEach((role, jeux) {
      parRole['$role'] = {
        for (final e in (jeux as Map).entries)
          '${e.key}': () {
            final t = (e.value as List).cast<num>();
            return DroitImport(jeu: '${e.key}', voir: t[0] != 0, importer: t[0] != 0 && t[1] != 0, annuler: t[0] != 0 && t[2] != 0);
          }(),
      };
    });
    return MatriceImport(
      declarations: decl,
      parRole: parRole,
      superviseurs: {for (final r in (json['superviseurs'] as List? ?? const [])) '$r'},
      capacitePaie: {for (final r in (json['capacitePaie'] as List? ?? const [])) '$r'},
    );
  }

  DeclarationImport? declaration(String jeu) => declarations.where((d) => d.id == jeu).firstOrNull;

  /// `N.droitImport(role, jeu)` : jamais déduit du droit d'éditer l'écran, jamais d'un nom de rôle. Rôle ou jeu inconnu : FERMÉ.
  DroitImport droit(String role, String jeu) => _parRole[role]?[jeu] ?? DroitImport.ferme(jeu);

  /// Les rôles que la matrice connaît.
  Iterable<String> get roles => _parRole.keys;

  /// `N.importsVisibles(role)` : les jeux que ce rôle voit, matière de la rangée « Importation de données ».
  List<DeclarationImport> visibles(String role) => [for (final d in declarations) if (droit(role, d.id).voir) d];

  /// `N.importsDeLHote(ecran, role)` : les jeux qu'un écran héberge sous le bouton « Importer les données » ET que ce rôle peut importer.
  List<DeclarationImport> deLHote(String ecran, String role) => [for (final d in declarations) if (d.hotes.contains(ecran) && droit(role, d.id).importer) d];

  /// `N.superviseImport(role)` : détenir le droit d'ANNULER sur CHAQUE jeu. Tiré du droit, jamais d'une liste de rôles.
  bool supervise(String role) => declarations.isNotEmpty && declarations.every((d) => droit(role, d.id).annuler);

  /// `N.capacitePaie(role)` : écrire dans le module de la paie (M11), qui décide de la colonne « Salaire de base » du jeu du personnel.
  bool aLaCapacitePaie(String role) => capacitePaie.contains(role);
}

/// Les trois cases résolues d'un jeu pour un rôle, comme `N.droitImport` : [defaut] (`VIA`), la surcharge de la fiche ([surcharge] : `voir`, `importer`, `annuler`),
/// l'archivage du rôle et la fermeture de l'activité. Ne lit JAMAIS le droit d'éditer l'écran.
DroitImport resoudreDroitImport({
  required String jeu,
  required String defaut,
  Map<String, Object?>? surcharge,
  required bool roleArchive,
  required bool ouvert,
}) {
  if (roleArchive || !ouvert) return DroitImport.ferme(jeu);
  bool? b(Object? v) => v == null ? null : v == true;
  final voir = b(surcharge?['voir']) ?? defaut.contains('V');
  if (!voir) return DroitImport.ferme(jeu);
  return DroitImport(
    jeu: jeu,
    voir: true,
    importer: b(surcharge?['importer']) ?? defaut.contains('I'),
    annuler: b(surcharge?['annuler']) ?? defaut.contains('A'),
  );
}
