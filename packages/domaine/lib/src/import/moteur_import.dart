/// MODULE D'IMPORTATION (IMP) : le moteur générique, port de `SIGH.importer` (prototype_html/assets/js/modules/import.js).
///
/// UN MOTEUR, DES JEUX DÉCLARATIFS (`jeux_import.dart`). Chaque jeu dit ses colonnes (type, obligatoire, référentiel de contrôle), sa clé de
/// dédoublonnage et ses règles métier ; le moteur fait le reste, toujours dans le même ordre : contrôler les colonnes, contrôler chaque cellule,
/// dédoublonner (dans le fichier, puis contre le magasin), appliquer les règles métier, contrôler le lot entier (RG-10 pour les soldes).
/// RIEN n'est écrit avant la confirmation. Un refus se NOMME : ligne, colonne, valeur, motif et geste de correction. Un fichier refusé est
/// CONSIGNÉ (lot « refusé ») et n'écrit rien. Un lot accepté s'écrit d'un seul geste : toutes les fiches ou aucune, chacune portant `source`,
/// `lotImport`, `validePar` et `dateImport`. Un lot s'ANNULE en archivant ses fiches (RG-14), jamais en les supprimant.
///
/// Le moteur ne lit ni ne parle à aucun fichier : il reçoit des LIGNES (tableaux de cellules) que la couche d'entrée-sortie du poste tire d'un
/// classeur .xlsx (paquet `excel`) ou d'un .csv. Il écrit par un PORT ([PortImport]) que le magasin du poste, la mère et les tests implémentent.
/// Les vecteurs viennent de la maquette (`prototype_html/build/vecteurs-import.js`).
library;

import '../droits/droit_import.dart';
import '../format/recherche.dart' show normaliser;
import 'identite_lot.dart';

typedef FicheImport = Map<String, Object?>;

/// Niveaux d'un constat.
const importRefus = 'refus';
const importAvertissement = 'avertissement';

/// Un constat nommé : ligne (0 = le fichier entier), colonne, valeur lue, code stable, motif et geste de correction.
class ProblemeImport {
  const ProblemeImport({
    required this.n,
    required this.colonne,
    required this.valeur,
    required this.code,
    required this.motif,
    required this.geste,
    required this.niveau,
  });
  final int n;
  final String colonne;
  final Object? valeur;
  final String code, motif, geste, niveau;

  Map<String, Object?> versJson() => {'n': n, 'colonne': colonne, 'valeur': valeur, 'code': code, 'motif': motif, 'geste': geste, 'niveau': niveau};
  bool get estRefus => niveau == importRefus;
  ProblemeImport avecLigne(int ligne) =>
      ProblemeImport(n: ligne, colonne: colonne, valeur: valeur, code: code, motif: motif, geste: geste, niveau: niveau);
}

/// Un choix d'une colonne « liste » : [valeur] est ce qui s'écrit, [label] ce que l'agent saisit ou lit.
class ValeurListe {
  const ValeurListe(this.valeur, [String? label]) : label = label ?? valeur;
  final String valeur, label;
}

/// Ce qu'on répond quand une valeur est sous le minimum (RG-03 pour la quantité) : code, motif et geste propres à la colonne.
class SousMinImport {
  const SousMinImport(this.code, this.motif, this.geste);
  final String code, motif, geste;
}

class ColonneImport {
  const ColonneImport(
    this.cle,
    this.label,
    this.type, {
    this.obligatoire = false,
    this.liste,
    this.min,
    this.max,
    this.longueurMax,
    this.motif,
    this.motifTexte,
    this.exemple,
    this.aide,
    this.sousMin,
    this.capacite,
    this.unique = false,
  });

  /// Types : `texte`, `entier`, `decimal`, `date`, `liste`, `tarif` (montant, NC ou tiret ; `unique` y ajoute « prix unique »).
  final String cle, label, type;
  final bool obligatoire;
  final List<ValeurListe> Function(dynamic ctx)? liste;
  final num? min, max;
  final int? longueurMax;
  final RegExp? motif;
  final String? motifTexte, aide;
  final Object? exemple;
  final SousMinImport? sousMin;

  /// Une colonne qui porte `capacite: 'paie'` n'est dans le modèle, et acceptée au fichier, que pour un profil qui détient cette capacité (lue de la matrice : écrire dans le
  /// module de la paie), jamais d'un nom de rôle.
  final String? capacite;

  /// Colonne de prix : la valeur `unique` dit « prix unique » (jamais un montant fabriqué).
  final bool unique;
}

/// Une colonne RETIRÉE du modèle (le groupe sanguin du répertoire, la quantité d'un référentiel) : un fichier qui la porte est REFUSÉ en la nommant.
class ColonneRetiree {
  const ColonneRetiree(this.label, this.motif);
  final String label, motif;
}

/// Une ligne du fichier une fois lue : [n] est son rang dans la feuille (l'en-tête est la ligne 1).
class LigneImport {
  LigneImport(this.n, this.v, this.brut);
  final int n;
  final Map<String, Object?> v;
  final List<String> brut;
  final List<ProblemeImport> problemes = [];

  /// `valide`, `avertissement`, `refus`, `ignore` (fiche déjà tenue, mode « ignorer »), `inchange`, `non` (refusée par son auteur : décision ligne à ligne).
  String etat = 'valide';

  /// Une ligne qui n'écrit rien sans être un refus : `ignore`, `inchange`, `non`. Elle est comptée, jamais perdue en silence.
  String? sansEcriture;

  /// Le détail que la vérification montre pour la ligne (stock avant la ligne, lot retenu, écart d'un comptage…).
  String? detail;
}

class CompteImport {
  CompteImport({this.valides = 0, this.avertissements = 0, this.refus = 0, this.ignores = 0, this.inchanges = 0, this.non = 0});
  int valides, avertissements, refus, ignores, inchanges, non;
  Map<String, Object?> versJson() =>
      {'valides': valides, 'avertissements': avertissements, 'refus': refus, 'ignores': ignores, 'inchanges': inchanges, 'non': non};
}

/// Le résultat de l'analyse d'un fichier : rien n'est écrit.
class AnalyseImport {
  AnalyseImport(this.jeu, this.fichier, this.lignesBrutes);
  final String jeu, fichier;
  final List<List<Object?>> lignesBrutes;
  int nbLignes = 0;
  final List<LigneImport> lignes = [];
  final List<ProblemeImport> globaux = [];
  bool accepte = false;

  /// Le nombre de lignes qui s'écriraient (ni refusées, ni ignorées, ni inchangées, ni refusées par leur auteur).
  int aEcrire = 0;

  /// Le profil n'a pas le droit d'importer ce jeu : le moteur REFUSE (masquer un bouton ne protège rien), et le refus ne se consigne pas.
  bool droitRefuse = false;
  final CompteImport compte = CompteImport();
  String? empreinte;

  /// Tous les constats à plat : ceux du fichier, puis ceux de chaque ligne.
  List<ProblemeImport> get problemes => [...globaux, for (final l in lignes) ...l.problemes];
}

/// Le PORT d'écriture du moteur : le magasin du poste, la mère ou la mémoire d'un test. Une écriture refusée par le moteur (garde d'exercice clos)
/// lève une exception ; le moteur défait alors ce qu'il vient de poser.
/// Le PROFIL qui importe, et ce que le moteur lit de la matrice : jamais un nom de rôle en dur. Le droit (voir, importer, annuler), la sensibilité du jeu, son mode de
/// doublon, la capacité paie et la supervision viennent de la section `import` de `rbac.json` (superposée à chaud par les fiches RBAC). Le moteur REFUSE sans le droit :
/// masquer un bouton ne protège rien.
class ProfilImport {
  const ProfilImport({required this.role, required this.libelleRole, required this.matrice, this.bornes = const {}, this.reservesALaMere = const {}, this.libellesRoles = const {}, this.fileul = false, this.surFileul = false});
  final String role, libelleRole;

  /// LOT 8B : les libellés des rôles du manifeste (rôles renommés compris), pour les refus qui NOMMENT un autre profil (« une date antérieure est une autorité de la Directrice Administrative et de la Direction »).
  final Map<String, String> libellesRoles;

  /// LOT 8B : ce profil agit depuis un FILEUL rattaché (ou pour le compte d'une demande qui en vient) : la décision d'un prix est tenue par la mère, un Oui vaut proposition.
  final bool fileul;

  /// LOT TFIN-2 : le poste QUI ÉCRIT est lui-même un fileul rattaché (jamais vrai quand la mère rejoue la demande d'un fileul : `fileul` l'est, `surFileul` non). Une version de prix ne s'écrit jamais
  /// chez un fileul (famille R) : le jeu du référentiel produits y écrit la fiche et laisse la version 1 à la mère.
  final bool surFileul;

  /// LOT 8 : les jeux que CE poste ne peut pas écrire parce qu'il est un fileul rattaché et que le jeu est RESTREINT et écrit de la configuration de la mère (le personnel, le stock détail
  /// initial, le bon de transfert : voir `voieImportFileul`). Le moteur refuse l'écriture, nommée ; l'analyse reste permise (le fichier peut être vérifié ici).
  final Set<String> reservesALaMere;
  final MatriceImport matrice;

  /// Le réglage `importBornes` (lignes maximales par jeu), lu en base ; un jeu sans réglage prend [borneParDefaut].
  final Map<String, int> bornes;

  static const int borneParDefaut = 5000;
  static const int borneMaximale = 100000;

  DroitImport droit(String jeu) => matrice.droit(role, jeu);
  bool get supervise => matrice.supervise(role);
  bool get capacitePaie => matrice.aLaCapacitePaie(role);
  DeclarationImport? declaration(String jeu) => matrice.declaration(jeu);

  /// Un jeu sans déclaration est traité comme RESTREINT : dans le doute, aucune valeur de cellule n'est recopiée.
  bool restreint(String jeu) => declaration(jeu)?.restreint ?? true;
  String modeDoublon(String jeu) => declaration(jeu)?.doublon ?? 'refuser';
  int borne(String jeu) {
    final v = bornes[jeu];
    return v != null && v > 0 ? v : borneParDefaut;
  }
}

abstract class PortImport {
  /// Le profil qui importe : droits, sensibilité des jeux, bornes (jamais un nom de rôle en dur).
  ProfilImport get profil;

  List<FicheImport> toutes(String collection);
  List<FicheImport> actives(String collection) => [
        for (final f in toutes(collection))
          if (f['statut'] != 'archive') f
      ];
  FicheImport? parId(String collection, Object? id) => toutes(collection).where((f) => f['id'] == id).firstOrNull;

  /// Date du jour, `AAAA-MM-JJ`.
  String get jour;

  /// Nom de l'agent connecté (jamais d'action anonyme, RG-12).
  String get utilisateur;

  /// Insère une fiche et rend celle qui est stockée (avec son `id`). Lève si le moteur la refuse.
  FicheImport inserer(String collection, FicheImport fiche);

  /// Retire une fiche posée dans le geste en cours (annulation d'une création, avant tout autre usage). Jamais pour une fiche déjà publiée.
  void retirer(String collection, Object? id);

  /// Archive (RG-14). Rend `false` si le moteur refuse.
  bool archiver(String collection, Object? id, String motif);
  void restaurer(String collection, Object? id);
  void mettreAJour(String collection, Object? id, FicheImport patch);
  void journaliser(String action, String module, String entite, String reference, Object? avant, Object? apres);
}

/// LOT IDEM : ce que le moteur LIT pour dire « cette fiche est déjà tenue » : les fiches nées d'une demande, archivées parce que leur lot a été DÉFAIT (annulé, ou restitué après le refus
/// de la mère), ne comptent plus. Sans cela le même fichier ne se réimporterait jamais après une annulation légitime (l'article archivé existerait encore). Une fiche archivée à la main,
/// ou celle d'un lot que personne n'a défait, continue de compter : seule la défaite d'un lot libère ses fiches. Lecture seule : toute écriture va au port d'origine.
class _VueSansLotsDefaits extends PortImport {
  _VueSansLotsDefaits(this.base) : _defaits = {for (final l in base.toutes(collectionLots)) if (l['etat'] == 'annule' || l['etat'] == 'restitue') l['reference']};
  final PortImport base;
  final Set<Object?> _defaits;
  @override
  ProfilImport get profil => base.profil;
  @override
  String get jour => base.jour;
  @override
  String get utilisateur => base.utilisateur;
  @override
  List<FicheImport> toutes(String collection) => collection == collectionLots
      ? base.toutes(collection)
      : [
          for (final f in base.toutes(collection))
            if (!(f['statut'] == 'archive' && f[champSerieDemande] != null && _defaits.contains(f['lotImport']))) f
        ];
  @override
  FicheImport inserer(String collection, FicheImport fiche) => base.inserer(collection, fiche);
  @override
  void retirer(String collection, Object? id) => base.retirer(collection, id);
  @override
  bool archiver(String collection, Object? id, String motif) => base.archiver(collection, id, motif);
  @override
  void restaurer(String collection, Object? id) => base.restaurer(collection, id);
  @override
  void mettreAJour(String collection, Object? id, FicheImport patch) => base.mettreAJour(collection, id, patch);
  @override
  void journaliser(String action, String module, String entite, String reference, Object? avant, Object? apres) =>
      base.journaliser(action, module, entite, reference, avant, apres);
}

/// Refus nommé d'une annulation ou d'une application : code stable, motif et geste.
class ResultatImport {
  const ResultatImport.ok({this.lot, this.ecrits = 0, this.archives = 0, this.analyse})
      : ok = true,
        code = null,
        motif = null,
        geste = null;
  const ResultatImport.refus(this.code, this.motif, this.geste, {this.lot, this.analyse})
      : ok = false,
        ecrits = 0,
        archives = 0;
  final bool ok;
  final String? code, motif, geste;
  final FicheImport? lot;
  final int ecrits, archives;
  final AnalyseImport? analyse;
}

/// Une dépendance qui interdit l'annulation d'un lot (un acte s'appuie déjà sur ses fiches).
class DependanceImport {
  const DependanceImport(this.code, this.motif, this.geste);
  final String code, motif, geste;
}

typedef EcrireFiche = FicheImport Function(String collection, FicheImport fiche);

/// Déclare au lot une fiche écrite hors de [EcrireFiche] (la fabrique du geste d'écran l'a écrite : un bon de transfert, une version de prix) ou une MODIFICATION de fiche tenue
/// (`avant` : l'état restitué par l'atomicité et par l'annulation, au lieu d'être archivé).
typedef DeclarerFiche = void Function(String collection, Object? id, {Map<String, Object?>? avant});

/// LOT IMP-E : ce que la restitution propre à un jeu a fait : les fiches archivées et celles qu'il a GARDÉES (`{collection, id, code, motif}`, une pièce émise ne se réécrit jamais).
typedef RestitutionJeu = ({int archives, List<Map<String, Object?>> gardees});

/// La réponse du geste d'annulation propre à un jeu.
class ResultatAnnulationImport {
  const ResultatAnnulationImport.ok(this.archives)
      : ok = true,
        code = null,
        motif = null,
        geste = null;
  const ResultatAnnulationImport.refus(String this.code, String this.motif, String this.geste)
      : ok = false,
        archives = 0;
  final bool ok;
  final int archives;
  final String? code, motif, geste;
}

/// Un jeu d'import, déclaratif. Les fonctions reçoivent le contexte (ce que le magasin sait déjà) lu UNE fois par analyse.
class JeuImport {
  const JeuImport({
    required this.id,
    required this.ecran,
    required this.libelle,
    required this.module,
    required this.statut,
    required this.description,
    required this.source,
    required this.cibles,
    required this.fichierModele,
    required this.colonnes,
    required this.contexte,
    required this.cle,
    required this.existe,
    required this.regles,
    required this.ecrire,
    required this.dependances,
    this.limite,
    this.gesteExiste,
    this.reglesLot,
    this.colonnesRetirees = const [],
    this.annuler,
    this.restituer,
  });
  final String id, ecran, libelle, module, statut, description, source, fichierModele;
  final String? limite, gesteExiste;
  final List<String> cibles;
  final List<ColonneImport> colonnes;

  /// Les colonnes que le modèle ne porte plus : un fichier qui en porte une est refusé en la nommant.
  final List<ColonneRetiree> colonnesRetirees;

  /// Un jeu qui ne s'annule pas par l'archivage de ses fiches (les versions de prix sont immuables, un transfert restitue des stocks) porte son propre geste d'annulation.
  final ResultatAnnulationImport Function(FicheImport lot, String? motif, PortImport port)? annuler;

  /// LOT IMP-E : une écriture de fileul que la mère REFUSE se restitue par l'archivage de ses fiches (RG-14) ; un jeu qui porte des QUANTITÉS (le Grand Stock) ne peut pas s'en tenir là :
  /// un mouvement écrit ne se réécrit pas (il se contre-passe par un mouvement inverse nommé), un stock ne devient jamais négatif (RG-03) et un article déjà sorti ne se restitue pas.
  /// [libelleMotif] : le motif d'archivage ; [motifMarque] : le motif de la mère, posé sur les fiches gardées.
  final RestitutionJeu Function(FicheImport lot, String libelleMotif, String motifMarque, PortImport port)? restituer;
  final dynamic Function(PortImport port) contexte;
  final List<String> Function(Map<String, Object?> v) cle;
  final String? Function(Map<String, Object?> v, dynamic ctx) existe;
  final List<ProblemeImport> Function(Map<String, Object?> v, dynamic ctx, Map<String, Object?> sc, int n) regles;
  final List<ProblemeImport> Function(List<LigneImport> lignes, dynamic ctx)? reglesLot;
  final void Function(List<LigneImport> lignes, EcrireFiche ecrire, FicheImport lot, dynamic ctx, PortImport port, DeclarerFiche declarer) ecrire;
  final DependanceImport? Function(FicheImport lot, PortImport port) dependances;

  bool get supporte => statut == 'supporte';
}

/// Le constat d'un champ dans une règle de ligne (la ligne est posée par le moteur).
ProblemeImport constat(String colonne, Object? valeur, String code, String niveau, String motif, String geste) =>
    ProblemeImport(n: 0, colonne: colonne, valeur: valeur, code: code, motif: motif, geste: geste, niveau: niveau);

// --- Outils -----------------------------------------------------------------------------------------------------------------------

/// Une cellule en texte, comme `String(v)` de la maquette : un nombre entier s'écrit sans décimale.
String texteDe(Object? v) {
  if (v == null) return '';
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
  return '$v';
}

Object? _nettoyer(Object? v) => v is String ? v.replaceAll(RegExp('[\u00A0\u202F]'), ' ').trim() : v;
bool _vide(Object? v) => v == null || (v is String && v.trim().isEmpty);

bool _dateValide(int a, int m, int j) {
  final d = DateTime.utc(a, m, j);
  return d.year == a && d.month == m && d.day == j;
}

String _deux(int n) => n.toString().padLeft(2, '0');

/// `X.versDate` : un numéro de série Excel (système 1900) en `AAAA-MM-JJ`. Le jour 60 d'Excel (29/02/1900) n'a jamais existé.
String? importVersDate(num n) {
  final s = n.floor();
  if (s < 1) return null;
  final d = DateTime.utc(1899, 12, 30).add(Duration(days: s > 59 ? s : s + 1));
  return '${d.year.toString().padLeft(4, '0')}-${_deux(d.month)}-${_deux(d.day)}';
}

/// Jours entiers entre deux dates ISO, sans heure.
int importJoursEntre(String a, String b) {
  DateTime u(String x) => DateTime.utc(int.parse(x.substring(0, 4)), int.parse(x.substring(5, 7)), int.parse(x.substring(8, 10)));
  return (u(b).difference(u(a)).inHours / 24).round();
}

int importAgeAu(String naissance, String jour) {
  final a = (importJoursEntre(naissance, jour) / 365.25).floor();
  return a < 0 ? 0 : a;
}

num _entierSiPossible(num n) => n == n.truncate() ? n.toInt() : n;

List<ValeurListe> valeursListe(ColonneImport c, dynamic ctx) => c.liste == null ? const [] : c.liste!(ctx);

/// Le résultat du typage d'une cellule : vide, une valeur, ou une erreur nommée.
class _Cellule {
  _Cellule.vide()
      : vide = true,
        valeur = null,
        erreur = null;
  _Cellule.valeur(this.valeur)
      : vide = false,
        erreur = null;
  _Cellule.erreur(this.erreur)
      : vide = false,
        valeur = null;
  final bool vide;
  final Object? valeur;
  final ProblemeImport? erreur;
}

ProblemeImport _err(String code, String motif, String geste) =>
    ProblemeImport(n: 0, colonne: '', valeur: '', code: code, motif: motif, geste: geste, niveau: importRefus);

_Cellule _lireCellule(ColonneImport col, Object? brut, dynamic ctx) {
  final v = _nettoyer(brut);
  if (_vide(v)) return _Cellule.vide();
  switch (col.type) {
    case 'texte':
      final t = texteDe(v);
      if (col.motif != null && !col.motif!.hasMatch(t)) {
        return _Cellule.erreur(_err('FORMAT_INVALIDE', col.motifTexte ?? 'format non conforme', 'Corrigez la valeur selon le format indiqué dans l’onglet Instructions.'));
      }
      if (col.longueurMax != null && t.length > col.longueurMax!) {
        return _Cellule.erreur(_err('TROP_LONG', 'texte de ${t.length} caractères (maximum ${col.longueurMax})', 'Raccourcissez la valeur à ${col.longueurMax} caractères au plus.'));
      }
      return _Cellule.valeur(t);
    case 'entier':
    case 'decimal':
      num? n;
      if (v is num) {
        n = v;
      } else {
        final s = texteDe(v).replaceAll(RegExp(r'\s'), '').replaceFirst(',', '.');
        n = RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s) ? num.parse(s) : null;
      }
      if (n == null || (n is double && !n.isFinite)) {
        return _Cellule.erreur(_err('TYPE_INVALIDE', 'nombre attendu, « ${texteDe(v)} » n’en est pas un', 'Saisissez un nombre sans lettre ni symbole monétaire.'));
      }
      if (col.type == 'entier' && n != n.truncate()) {
        return _Cellule.erreur(_err('TYPE_INVALIDE', 'nombre entier attendu, « ${texteDe(v)} » porte une décimale', 'Arrondissez à l’unité (le franc CFA n’a pas de décimale).'));
      }
      if (col.min != null && n < col.min!) {
        if (col.sousMin != null) return _Cellule.erreur(_err(col.sousMin!.code, col.sousMin!.motif, col.sousMin!.geste));
        return _Cellule.erreur(_err('HORS_BORNES', 'valeur ${_entierSiPossible(n)} inférieure au minimum ${col.min}', 'Saisissez une valeur d’au moins ${col.min}.'));
      }
      if (col.max != null && n > col.max!) {
        return _Cellule.erreur(_err('HORS_BORNES', 'valeur ${_entierSiPossible(n)} supérieure au maximum ${col.max}', 'Saisissez une valeur d’au plus ${col.max}.'));
      }
      return _Cellule.valeur(_entierSiPossible(n));
    case 'date':
      String? iso;
      if (v is num) {
        iso = importVersDate(v);
      } else {
        final t = texteDe(v);
        final m1 = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
        final m2 = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t);
        if (m1 != null && _dateValide(int.parse(m1[1]!), int.parse(m1[2]!), int.parse(m1[3]!))) {
          iso = '${m1[1]}-${m1[2]}-${m1[3]}';
        } else if (m2 != null && _dateValide(int.parse(m2[3]!), int.parse(m2[2]!), int.parse(m2[1]!))) {
          iso = '${m2[3]}-${_deux(int.parse(m2[2]!))}-${_deux(int.parse(m2[1]!))}';
        }
      }
      if (iso == null) {
        return _Cellule.erreur(_err('TYPE_INVALIDE', 'date attendue, « ${texteDe(v)} » n’en est pas une', 'Saisissez la date au format AAAA-MM-JJ ou JJ/MM/AAAA.'));
      }
      return _Cellule.valeur(iso);
    case 'liste':
      final choix = valeursListe(col, ctx);
      final cle = normaliser(texteDe(v)).trim();
      final trouve = choix.where((c) => normaliser(c.valeur) == cle || normaliser(c.label) == cle).firstOrNull;
      if (trouve == null) {
        return _Cellule.erreur(_err('VALEUR_HORS_LISTE', '« ${texteDe(v)} » n’est pas une valeur permise',
            'Choisissez parmi : ${choix.take(8).map((c) => c.label).join(', ')}${choix.length > 8 ? ', …' : ''}.'));
      }
      return _Cellule.valeur(trouve.valeur);
    case 'tarif':
      final tv = texteDe(v).trim();
      if (RegExp('^(-|\u2013|\u2014)\$').hasMatch(tv)) return _Cellule.valeur({'etat': 'manquant'});
      if (RegExp(r'^(nc|non couvert)$', caseSensitive: false).hasMatch(tv)) return _Cellule.valeur({'etat': 'nc'});
      if (col.unique && RegExp(r'^(unique|prix unique)$', caseSensitive: false).hasMatch(tv)) return _Cellule.valeur({'etat': 'unique'});
      final nn = v is num ? v : num.tryParse(tv.replaceAll(RegExp(r'\s'), '').replaceFirst(',', '.'));
      if (nn == null || !nn.isFinite || nn != nn.truncate() || nn < 0) {
        return _Cellule.erreur(_err('TYPE_INVALIDE', '« ${texteDe(v)} » n’est ni un montant entier, ni NC, ni un tiret', 'Saisissez un montant en francs, NC (non couvert) ou un tiret (valeur manquante).'));
      }
      return _Cellule.valeur({'etat': 'montant', 'montant': nn.toInt()});
  }
  return _Cellule.valeur(v);
}

String _clefEntete(Object? s) => normaliser(texteDe(s).replaceAll('*', '')).replaceAll(RegExp(r'\s+'), ' ').trim();

// --- Le droit, la sensibilité et les colonnes selon le profil -------------------------------------------------------------------------

/// Un refus de droit se NOMME : le profil, le jeu, le geste (`refusDroit` de la maquette).
ResultatImport? refusDroitImport(JeuImport j, String geste, PortImport port) {
  final p = port.profil;
  final d = p.droit(j.id);
  final ok = switch (geste) { 'voir' => d.voir, 'importer' => d.importer, 'annuler' => d.annuler, _ => false };
  if (ok) return null;
  final verbe = const {'voir': 'voir', 'importer': 'importer', 'annuler': 'annuler un lot de'}[geste] ?? geste;
  return ResultatImport.refus(
      'DROIT_IMPORT_REFUSE',
      'le profil « ${p.libelleRole.isEmpty ? 'inconnu' : p.libelleRole} » ne détient pas le droit de $verbe le jeu « ${j.libelle} »',
      'Demander ce droit à l’administrateur : il se règle par jeu dans « Rôles & permissions », section Importation.');
}

/// LOT 8 : un jeu réservé au poste de la mère ne s'écrit pas sur un fileul rattaché (le moteur refuse, masquer le bouton ne protège rien). Le refus se NOMME.
ResultatImport? refusReserveALaMere(JeuImport j, PortImport port) => port.profil.reservesALaMere.contains(j.id)
    ? ResultatImport.refus('JEU_RESERVE_A_LA_MERE', 'le jeu « ${j.libelle} » est réservé au poste de la mère : ce poste est un fileul rattaché',
        'Importez ce fichier au poste de la mère : un jeu restreint qui écrit la configuration ne voyage pas dans une demande (RG-13).')
    : null;

/// Les colonnes du modèle SELON LE PROFIL : une colonne de capacité (« Salaire de base », capacité paie) n'existe que pour qui la détient.
List<ColonneImport> colonnesDe(JeuImport j, PortImport port) => [
      for (final c in j.colonnes)
        if (c.capacite == null || (c.capacite == 'paie' && port.profil.capacitePaie)) c
    ];

/// Les colonnes qu'un fichier ne doit pas porter : celles d'une capacité que le profil n'a pas, et les colonnes retirées du modèle. Un fichier qui en porte une est REFUSÉ
/// en la nommant : l'ignorer en silence ferait croire qu'elle a été reprise.
List<({String label, String code, String motif, String geste})> colonnesInterdites(JeuImport j, PortImport port) {
  final out = <({String label, String code, String motif, String geste})>[];
  for (final c in j.colonnes) {
    if (c.capacite != null && !(c.capacite == 'paie' && port.profil.capacitePaie)) {
      out.add((
        label: c.label,
        code: 'COLONNE_RESERVEE',
        motif: 'la colonne « ${c.label} » est réservée aux profils qui détiennent la capacité « ${c.capacite} » : elle n’est pas dans votre modèle',
        geste: 'Retirez la colonne « ${c.label} » du fichier ; elle se renseigne à l’écran par un profil habilité.'
      ));
    }
  }
  for (final c in j.colonnesRetirees) {
    out.add((label: c.label, code: 'COLONNE_RETIREE', motif: c.motif, geste: 'Retirez la colonne « ${c.label} » du fichier.'));
  }
  return out;
}

/// Les motifs FIXES d'un jeu RESTREINT (patients, personnel, soldes d'ouverture, couvertures, immobilisations, budgets, courriers, stock mouvementé) : un constat garde la
/// ligne, la colonne, le code et le geste, JAMAIS la valeur de la cellule ni un motif qui la cite (le nom d'un agent déjà tenu, les totaux d'une pièce). Même table que la
/// maquette (`MOTIFS_FIXES`).
const Map<String, String> motifsFixesImport = {
  'CHAMP_OBLIGATOIRE': 'valeur obligatoire absente',
  'TYPE_INVALIDE': 'valeur d’un autre type que celui attendu',
  'FORMAT_INVALIDE': 'format non conforme',
  'TROP_LONG': 'texte plus long que le maximum',
  'HORS_BORNES': 'valeur hors des bornes',
  'VALEUR_HORS_LISTE': 'valeur hors de la liste permise',
  'DOUBLON_FICHIER': 'ligne en double dans le fichier',
  'DOUBLON_MAGASIN': 'une fiche équivalente est déjà tenue',
  'DATE_FUTURE': 'date dans le futur',
  'SALAIRE_ABSENT': 'salaire de base non renseigné',
  'TELEPHONE_ABSENT': 'aucun téléphone',
  'POLICE_ABSENTE': 'assuré sans numéro de police',
  'COMPTE_INCONNU': 'compte absent du plan comptable',
  'CLASSE_NON_REPORTABLE': 'compte de gestion : il ne se reporte pas',
  'DEUX_SENS': 'débit et crédit renseignés ensemble',
  'LIGNE_NULLE': 'ligne sans montant',
  'DATES_MULTIPLES': 'plusieurs dates dans le fichier',
  'RG10_DESEQUILIBRE': 'écriture non équilibrée (RG-10)',
  'A_NOUVEAU_EXISTANT': 'l’exercice porte déjà un à-nouveau',
  'COLONNE_RESERVEE': 'colonne réservée à un autre profil',
  'COLONNE_RETIREE': 'colonne retirée du modèle',
  'ARTICLE_INCONNU': 'article absent du référentiel produits',
  'RG03_STOCK_INSUFFISANT': 'stock du magasin insuffisant (RG-03)',
  'RG03_STOCK_NEGATIF': 'quantité négative (RG-03)',
  'LOT_OBLIGATOIRE': 'lot et péremption obligatoires (RG-05)',
  'LOT_INCOMPLET': 'lot et péremption vont ensemble',
  'LOT_INCONNU': 'lot absent pour cet article',
  'LOT_PERIME': 'lot périmé',
  'LOT_NON_FEFO': 'lot qui ne part pas en premier (FEFO, RG-05)',
  'PEREMPTION_PASSEE': 'lot déjà périmé',
  'QUANTITE_NULLE': 'quantité nulle',
  'DETAIL_DEJA_MOUVEMENTE': 'article déjà mouvementé : le stock détail initial ne se pose qu’une fois',
  'DETAIL_DEJA_EN_STOCK': 'stock détail déjà présent',
  'STOCK_INCOHERENT': 'stocks gros et détail incohérents avec le stock total',
  'IGNORE_EXISTANT': 'fiche déjà tenue : ligne ignorée',
  'PATIENT_INCONNU': 'dossier absent du répertoire',
  'POLICE_INCONNUE': 'police absente des souscripteurs',
  'POLICE_AUTRE_COMPAGNIE': 'police d’une autre compagnie',
  'DATE_EFFET_ANTERIEURE': 'date d’effet antérieure à la couverture en cours',
  'CARTE_SANS_EXPIRATION': 'carte sans date d’expiration',
  'FACTURE_DEJA_EMISE': 'facture déjà émise à partir de cette date',
  'VALEUR_NULLE': 'valeur nulle',
  'COMPTE_NON_IMMOBILISATION': 'compte qui n’est pas un compte d’immobilisation',
  'BIEN_CEDE': 'bien déjà cédé',
  'EXERCICE_CLOS': 'exercice clos : lecture seule',
  'EXERCICE_EN_CLOTURE': 'exercice en clôture',
  'NUMERO_INCOHERENT': 'numéro hors série',
  'CORRESPONDANT_ABSENT': 'correspondant non renseigné',
  'SERVICE_ABSENT': 'service non renseigné',
  'DESTINATION_ABSENTE': 'aucun service destinataire',
  'DESTINATIONS_MULTIPLES': 'plusieurs services destinataires : une feuille est un seul bon',
  'BON_UNIQUE': 'plusieurs valeurs pour un bon unique',
  'FEUILLE_UNIQUE': 'plusieurs valeurs pour une feuille unique',
};

/// `masquer(j, p)` : pour un jeu RESTREINT, la valeur n'est pas recopiée et le motif est remplacé par une phrase fixe propre au code.
ProblemeImport masquerProbleme(JeuImport j, ProblemeImport p, PortImport port) {
  if (!port.profil.restreint(j.id)) return p;
  return ProblemeImport(
      n: p.n,
      colonne: p.colonne,
      valeur: '',
      code: p.code,
      motif: motifsFixesImport[p.code] ?? 'constat de contrôle (le détail n’est pas recopié)',
      geste: p.geste,
      niveau: p.niveau);
}

/// Tous les constats à plat, MASQUÉS pour un jeu restreint : c'est ce qui entre à l'historique et au rapport.
List<ProblemeImport> problemesConsignes(JeuImport j, AnalyseImport a, PortImport port) => [for (final p in a.problemes) masquerProbleme(j, p, port)];

List<Object?> ligneExemple(JeuImport j, [PortImport? port]) => [for (final c in (port == null ? j.colonnes : colonnesDe(j, port))) c.exemple ?? ''];

// --- Analyse ---------------------------------------------------------------------------------------------------------------------

/// Analyse des lignes (la première est l'en-tête) contre un jeu. [port] fournit le contexte et le profil ; RIEN n'est écrit.
AnalyseImport analyserLignes(JeuImport j, List<List<Object?>> lignes, String fichier, PortImport port) {
  final res = AnalyseImport(j.id, fichier, lignes);
  void globalement(String code, String colonne, String motif, String geste, [String niveau = importRefus, Object? valeur = '']) {
    res.globaux.add(ProblemeImport(n: 0, colonne: colonne, valeur: valeur, code: code, motif: motif, geste: geste, niveau: niveau));
  }

  // LE MOTEUR REFUSE AUSSI : pas de droit d'importer ce jeu, pas d'analyse (le refus ne se consigne pas : rien n'a été tenté par un détenteur).
  final rd = refusDroitImport(j, 'importer', port);
  if (rd != null) {
    globalement(rd.code!, '', rd.motif!, rd.geste!);
    res.droitRefuse = true;
    return res;
  }
  if (lignes.isEmpty) {
    globalement('FICHIER_VIDE', '', 'le fichier ne contient aucune ligne', 'Téléchargez le modèle, remplissez l’onglet Données et téléversez-le de nouveau.');
    return res;
  }
  // LA TAILLE MAXIMALE, avant tout travail : un refus nommé, jamais une constante muette (réglage `importBornes`).
  final borne = port.profil.borne(j.id);
  if (lignes.length - 1 > borne) {
    globalement('FICHIER_TROP_GROS', '', 'le fichier porte ${lignes.length - 1} lignes ; le maximum réglé pour ce jeu est $borne',
        'Découpez le fichier en plusieurs fichiers de $borne lignes au plus, ou faites relever la taille maximale du jeu par un profil qui supervise les importations (onglet « Tailles maximales » de l’accueil du module).');
    return res;
  }
  final cols = colonnesDe(j, port);
  final entete = [for (final h in lignes.first) _clefEntete(h)];
  final interdites = [for (final c in colonnesInterdites(j, port)) if (entete.contains(_clefEntete(c.label))) c];
  if (interdites.isNotEmpty) {
    for (final c in interdites) {
      globalement(c.code, c.label, c.motif, c.geste);
    }
    return res;
  }
  final idx = <String, int>{};
  final manquantes = <ColonneImport>[];
  for (final c in cols) {
    final i = entete.indexOf(_clefEntete(c.label));
    if (i < 0) {
      if (c.obligatoire) {
        manquantes.add(c);
      } else {
        globalement('COLONNE_ABSENTE', c.label, 'colonne facultative « ${c.label} » absente du fichier', 'Ses valeurs resteront vides ; ajoutez-la au besoin.', importAvertissement);
      }
    } else {
      idx[c.cle] = i;
    }
  }
  if (manquantes.isNotEmpty) {
    for (final c in manquantes) {
      globalement('COLONNE_MANQUANTE', c.label, 'colonne obligatoire « ${c.label} » absente de la première ligne du fichier',
          'Ajoutez la colonne « ${c.label} » en respectant l’orthographe exacte du modèle, ou téléchargez le modèle de nouveau.');
    }
    return res;
  }
  final connus = {for (final c in cols) _clefEntete(c.label)};
  for (final h in lignes.first) {
    if (!_vide(h) && !connus.contains(_clefEntete(h))) {
      globalement('COLONNE_IGNOREE', texteDe(h), 'colonne « ${texteDe(h)} » inconnue : elle est ignorée', 'Retirez-la du fichier si elle est inutile.', importAvertissement);
    }
  }
  final ctx = j.contexte(_VueSansLotsDefaits(port));
  final extras = <int, String>{};
  final sc = <String, Object?>{'articles': <String, Map<String, Object?>>{}, 'extras': extras, 'pose': <Object?, num>{}};
  final mode = port.profil.modeDoublon(j.id);
  final exemple = [for (final x in ligneExemple(j, port)) texteDe(x).trim()];
  final vus = <String, int>{};
  // LOT IDEM : ce fichier est-il DÉJÀ tenu ? Une fiche active écrite par une demande porte l'identité de CONTENU de son lot : le même inventaire (peu importe le fileul, le moment ou
  // le format) est reconnu comme le même lot. Ses lignes ne sont alors ni refusées ni réécrites : elles sont IGNORÉES et NOMMÉES (idempotence), jamais comptées deux fois.
  final identiteDuFichier = identiteLotImport(j.id, lignes);
  String? lotTenu;
  for (final c in j.cibles) {
    for (final f in port.toutes(c)) {
      if (f[champIdentiteLot] == identiteDuFichier && f['statut'] != 'archive') {
        lotTenu = '${f[champSerieDemande] ?? ''}';
        break;
      }
    }
    if (lotTenu != null) break;
  }
  for (var r = 1; r < lignes.length; r++) {
    final brute = lignes[r];
    if (brute.every(_vide)) continue;
    Object? cellule(ColonneImport c) {
      final i = idx[c.cle]!;
      return i < brute.length ? brute[i] : '';
    }

    final lecture = [for (final c in cols) texteDe(_nettoyer(cellule(c) ?? '')).trim()];
    if (r == 1 && lecture.join('|') == exemple.join('|')) continue; // la ligne d'exemple du modèle, restée telle quelle
    final n = r + 1;
    final ligne = LigneImport(n, {}, lecture);
    var ok = true;
    for (final c in cols) {
      final b = cellule(c);
      final lc = _lireCellule(c, b, ctx);
      if (lc.erreur != null) {
        ok = false;
        final e = lc.erreur!;
        ligne.problemes.add(ProblemeImport(n: n, colonne: c.label, valeur: texteDe(b), code: e.code, motif: e.motif, geste: e.geste, niveau: importRefus));
        ligne.v[c.cle] = null;
      } else if (lc.vide) {
        ligne.v[c.cle] = null;
        if (c.obligatoire) {
          ok = false;
          ligne.problemes.add(ProblemeImport(
              n: n, colonne: c.label, valeur: '', code: 'CHAMP_OBLIGATOIRE', motif: 'valeur obligatoire absente', geste: 'Renseignez la colonne « ${c.label} » de la ligne $n.', niveau: importRefus));
        }
      } else {
        ligne.v[c.cle] = lc.valeur;
      }
    }
    if (ok) {
      final cles = j.cle(ligne.v);
      int? doublon;
      for (final k in cles) {
        if (doublon == null && vus.containsKey(k)) doublon = vus[k];
      }
      if (doublon != null) {
        ligne.problemes.add(ProblemeImport(
            n: n, colonne: cols.first.label, valeur: lecture.first, code: 'DOUBLON_FICHIER', niveau: importRefus, motif: 'identique à la ligne $doublon du même fichier', geste: 'Retirez l’une des deux lignes.'));
      } else {
        for (final k in cles) {
          vus[k] = n;
        }
      }
      final existe = j.existe(ligne.v, ctx);
      if (existe != null && lotTenu != null && doublon == null) {
        ligne.problemes.add(ProblemeImport(
            n: n,
            colonne: cols.first.label,
            valeur: lecture.first,
            code: 'LOT_DEJA_IMPORTE',
            niveau: 'ignore',
            motif: 'ce fichier est déjà importé : la fiche existe par le lot de série $lotTenu (même contenu)',
            geste: 'Rien à faire : le fichier est déjà dans le magasin, il n’est ni réécrit ni compté deux fois.'));
        ligne.sansEcriture = 'ignore';
      } else if (existe != null && mode == 'ignorer' && doublon == null) {
        // IGNORER LES EXISTANTS (I8, jeux de la liste fermée seulement) : la ligne n'écrit rien, elle est COMPTÉE et NOMMÉE au rapport, jamais perdue en silence.
        ligne.problemes.add(ProblemeImport(
            n: n,
            colonne: cols.first.label,
            valeur: lecture.first,
            code: 'IGNORE_EXISTANT',
            niveau: 'ignore',
            motif: existe,
            geste: 'Ligne ignorée : la fiche existe déjà et un import ne modifie jamais une fiche tenue.'));
        ligne.sansEcriture = 'ignore';
      } else {
        if (existe != null) {
          ligne.problemes.add(ProblemeImport(
              n: n, colonne: cols.first.label, valeur: lecture.first, code: 'DOUBLON_MAGASIN', niveau: importRefus, motif: existe, geste: j.gesteExiste ?? 'Retirez la ligne.'));
        }
        sc['ligne'] = ligne;
        for (final p in j.regles(ligne.v, ctx, sc, n)) {
          ligne.problemes.add(p.avecLigne(n));
        }
      }
    }
    final refus = ligne.problemes.any((p) => p.estRefus);
    ligne.etat = refus ? 'refus' : (ligne.sansEcriture ?? (ligne.problemes.any((p) => p.niveau == importAvertissement) ? 'avertissement' : 'valide'));
    if (refus) ligne.sansEcriture = null;
    ligne.detail = extras[n];
    res.lignes.add(ligne);
  }
  res.nbLignes = res.lignes.length;
  if (res.nbLignes == 0) {
    globalement('FICHIER_VIDE', '', 'aucune ligne de données (la ligne d’exemple du modèle n’est pas importée)', 'Remplacez la ligne d’exemple par vos données, ou ajoutez des lignes.');
    return res;
  }
  if (j.reglesLot != null && !res.lignes.any((l) => l.etat == 'refus')) {
    res.globaux.addAll(j.reglesLot!(res.lignes, ctx));
  }
  for (final l in res.lignes) {
    switch (l.etat) {
      case 'refus':
        res.compte.refus++;
      case 'ignore':
        res.compte.ignores++;
      case 'inchange':
        res.compte.inchanges++;
      case 'non':
        res.compte.non++;
      case 'avertissement':
        res.compte.avertissements++;
      default:
        res.compte.valides++;
    }
  }
  res.aEcrire = res.lignes.where((l) => l.sansEcriture == null && l.etat != 'refus').length;
  res.accepte = !res.globaux.any((p) => p.estRefus) && res.compte.refus == 0 && res.nbLignes > 0;
  return res;
}

/// L'analyse d'un fichier déjà lu en lignes, ou d'un fichier illisible (le lecteur du poste rend alors [motifIllisible]).
AnalyseImport analyserFichier(JeuImport j, List<List<Object?>>? lignes, String fichier, PortImport port, {String? motifIllisible, String? empreinte}) {
  AnalyseImport a;
  final rd = refusDroitImport(j, 'importer', port);
  if (rd != null) {
    // Pas de droit : le moteur REFUSE avant de lire le fichier, et le refus ne se consigne pas.
    a = AnalyseImport(j.id, fichier, const []);
    a.droitRefuse = true;
    a.globaux.add(ProblemeImport(n: 0, colonne: '', valeur: '', code: rd.code!, motif: rd.motif!, geste: rd.geste!, niveau: importRefus));
  } else if (lignes == null) {
    a = AnalyseImport(j.id, fichier, const []);
    a.globaux.add(ProblemeImport(
        n: 0,
        colonne: '',
        valeur: fichier,
        code: 'FORMAT_FICHIER',
        niveau: importRefus,
        motif: 'fichier illisible : ${motifIllisible ?? 'format inconnu'}',
        geste: 'Déposez un classeur .xlsx (modèle téléchargé) ou un fichier .csv encodé en UTF-8.'));
  } else {
    a = analyserLignes(j, lignes, fichier, port);
  }
  a.empreinte = empreinte;
  return a;
}

// --- La taille maximale d'un fichier, par jeu -----------------------------------------------------------------------------------

/// La réponse de `definirBorne` : un refus se NOMME ; sinon [bornes] est le réglage `importBornes` à écrire en base, [avant] la valeur qu'il remplace.
class ResultatBorneImport {
  const ResultatBorneImport.ok({required this.bornes, required this.avant, required this.lignes})
      : ok = true,
        code = null,
        motif = null,
        geste = null;
  const ResultatBorneImport.refus(String this.code, String this.motif, String this.geste)
      : ok = false,
        bornes = const {},
        avant = 0,
        lignes = 0;
  final bool ok;
  final String? code, motif, geste;
  final Map<String, int> bornes;
  final int avant, lignes;
}

/// `definirBorne(jeuId, lignes, motif)` de la maquette : un réglage en base par jeu (jamais une constante du code). Réservé aux profils qui SUPERVISENT les importations
/// (droit d'annuler sur chaque jeu : tiré de la matrice), entier de 1 à [ProfilImport.borneMaximale], motivé.
ResultatBorneImport definirBorneImport(String jeuId, Object? lignes, String? motif, PortImport port, {JeuImport? Function(String id)? jeu}) {
  final j = (jeu ?? (String id) => null)(jeuId);
  if (j == null && port.profil.declaration(jeuId) == null) {
    return ResultatBorneImport.refus('JEU_INCONNU', 'aucun jeu d’import « $jeuId »', 'Choisir un jeu de la liste.');
  }
  if (!port.profil.supervise) {
    return const ResultatBorneImport.refus('REGLAGE_RESERVE',
        'la taille maximale d’un fichier se règle par un profil qui supervise les importations (droit d’annuler sur tous les jeux)', 'Demander le réglage à la Directrice Administrative ou à l’administrateur.');
  }
  final n = lignes is num ? lignes : num.tryParse('${lignes ?? ''}'.trim());
  if (lignes == null || '$lignes'.trim().isEmpty || n == null || !n.isFinite || n != n.floor() || n < 1 || n > ProfilImport.borneMaximale) {
    return const ResultatBorneImport.refus('BORNE_INVALIDE', 'la taille maximale est un nombre entier de lignes, de 1 à ${ProfilImport.borneMaximale}', 'Saisir un nombre entier de lignes.');
  }
  if ((motif ?? '').trim().isEmpty) return const ResultatBorneImport.refus('MOTIF_REQUIS', 'un réglage de taille se motive', 'Saisir le motif du réglage.');
  final avant = port.profil.borne(jeuId);
  return ResultatBorneImport.ok(bornes: {...port.profil.bornes, jeuId: n.toInt()}, avant: avant, lignes: n.toInt());
}

// --- Lots -----------------------------------------------------------------------------------------------------------------------

const collectionLots = 'lotsImportation';

String referenceLot(PortImport port) {
  final an = port.jour.substring(0, 4);
  var max = 0;
  for (final l in port.toutes(collectionLots)) {
    final m = RegExp(r'^IMP-(\d{4})-(\d+)$').firstMatch('${l['reference'] ?? ''}');
    if (m != null && m[1] == an) {
      final k = int.parse(m[2]!);
      if (k > max) max = k;
    }
  }
  return 'IMP-$an-${(max + 1).toString().padLeft(3, '0')}';
}

List<Map<String, Object?>> _erreursPlafonnees(List<ProblemeImport> ps) => [for (final p in ps.take(100)) p.versJson()];

/// Consigne un fichier REFUSÉ : une fiche de lot « refusé » ; aucune donnée métier n'est écrite. Les constats d'un jeu restreint sont MASQUÉS (aucune valeur de cellule).
/// Un refus de droit ne se consigne pas : rien n'a été tenté par un détenteur du droit.
FicheImport? consigner(JeuImport j, AnalyseImport a, PortImport port) {
  if (a.droitRefuse) return null;
  final ps = problemesConsignes(j, a, port);
  final lot = port.inserer(collectionLots, {
    'reference': referenceLot(port),
    'jeu': j.id,
    'jeuLibelle': j.libelle,
    'fichier': a.fichier,
    'empreinte': a.empreinte,
    'date': port.jour,
    'par': port.utilisateur,
    'etat': 'refuse',
    'nbLignes': a.nbLignes,
    'nbAvertissements': a.compte.avertissements,
    'nbRefus': a.compte.refus + a.globaux.where((p) => p.estRefus).length,
    'ecrits': <Object?>[],
    'erreurs': _erreursPlafonnees(ps),
    'erreursTotal': ps.length,
  });
  port.journaliser('Import refusé', 'IMP', 'LotImport', '${lot['reference']}', null, {'jeu': j.id, 'fichier': a.fichier, 'refus': lot['nbRefus']});
  return lot;
}

/// Les lignes ignorées (mode « ignorer »), pour le lot : le nombre ET la liste (borne de 500, le total reste exact). Jeu RESTREINT : la liste dit les LIGNES ignorées, jamais
/// la valeur de leur clé.
Map<String, Object?> _ignoresDe(JeuImport j, AnalyseImport a, PortImport port) {
  final l = a.lignes.where((x) => x.etat == 'ignore').toList();
  final restreint = port.profil.restreint(j.id);
  return {
    'ignoresTotal': l.length,
    'ignores': [for (final x in l.take(500)) restreint ? {'n': x.n} : {'n': x.n, 'cle': x.brut.first}],
  };
}

/// Applique un lot ACCEPTÉ d'un seul geste : toutes les fiches ou aucune. Le MOTEUR REFUSE sans le droit d'importer (relu ICI, au moment d'écrire). L'analyse est REJOUÉE
/// sur les lignes d'origine (le magasin a pu changer entre l'analyse et la confirmation) ; en cas d'échec d'écriture, ce qui vient d'être posé est retiré (les
/// modifications de fiches tenues sont restituées) et le fichier est consigné.
ResultatImport appliquer(JeuImport j, AnalyseImport analyse, PortImport port) {
  final rd = refusDroitImport(j, 'importer', port);
  if (rd != null) return rd;
  final rm = refusReserveALaMere(j, port);
  if (rm != null) return rm;
  if (!analyse.accepte) {
    return const ResultatImport.refus('ANALYSE_REFUSEE', 'le fichier n’a pas passé l’analyse', 'Corrigez les refus listés, puis téléversez de nouveau.');
  }
  final rejeu = analyserLignes(j, analyse.lignesBrutes, analyse.fichier, port)..empreinte = analyse.empreinte;
  if (!rejeu.accepte) {
    final c = consigner(j, rejeu, port)!;
    return ResultatImport.refus('MAGASIN_CHANGE', 'le magasin a changé depuis l’analyse ; le fichier est refusé et consigné (${c['reference']})',
        'Relisez le rapport du lot ${c['reference']} et téléversez de nouveau.',
        lot: c, analyse: rejeu);
  }
  if (rejeu.aEcrire == 0 && rejeu.lignes.isNotEmpty && rejeu.lignes.every((l) => l.sansEcriture == 'ignore') && rejeu.problemes.any((p) => p.code == 'LOT_DEJA_IMPORTE')) {
    final p = rejeu.problemes.firstWhere((p) => p.code == 'LOT_DEJA_IMPORTE');
    return ResultatImport.refus('LOT_DEJA_IMPORTE', p.motif, p.geste);
  }
  if (rejeu.aEcrire == 0) {
    return const ResultatImport.refus('RIEN_A_ECRIRE', 'aucune ligne ne s’écrirait : toutes sont ignorées, inchangées ou refusées par leur auteur (Non)', 'Rien à confirmer : aucun lot n’est consigné.');
  }
  final ctx = j.contexte(_VueSansLotsDefaits(port));
  final reference = referenceLot(port);
  final lot = <String, Object?>{'reference': reference};
  final ecrits = <Map<String, Object?>>[];
  final par = port.utilisateur, jour = port.jour;
  // `avant` : une MODIFICATION de fiche tenue (la couverture close, le miroir du dossier), pas une création : l'atomicité et l'annulation la RESTITUENT au lieu de l'archiver.
  void declarer(String collection, Object? id, {Map<String, Object?>? avant}) => ecrits.add({'collection': collection, 'id': id, if (avant != null) 'avant': avant});
  FicheImport ecrireFiche(String collection, FicheImport fiche) {
    final stockee = port.inserer(collection, {
      'statut': 'actif',
      'source': 'Import ${j.libelle} (${analyse.fichier.isEmpty ? 'fichier' : analyse.fichier})',
      'lotImport': reference,
      'validePar': par,
      'dateImport': jour,
      ...fiche,
    });
    ecrits.add({'collection': collection, 'id': stockee['id']});
    return stockee;
  }

  try {
    j.ecrire([for (final l in rejeu.lignes) if (l.sansEcriture == null && l.etat != 'refus') l], ecrireFiche, lot, ctx, port, declarer);
  } catch (e) {
    for (final x in ecrits.reversed) {
      final avant = x['avant'];
      if (avant is Map) {
        port.mettreAJour('${x['collection']}', x['id'], avant.cast<String, Object?>());
      } else {
        port.retirer('${x['collection']}', x['id']);
      }
    }
    final motif = e is StateError ? e.message : e.toString();
    rejeu.globaux.add(ProblemeImport(
        n: 0, colonne: '', valeur: '', code: 'ECRITURE_REFUSEE', niveau: importRefus, motif: motif, geste: 'Rien n’a été écrit. Corrigez la cause puis téléversez de nouveau.'));
    final consigne = consigner(j, rejeu, port)!;
    return ResultatImport.refus('ECRITURE_REFUSEE', motif, 'Rien n’a été écrit ; le fichier est consigné (${consigne['reference']}).', lot: consigne);
  }
  final ps = problemesConsignes(j, rejeu, port);
  final rec = port.inserer(collectionLots, {
    'reference': reference,
    'jeu': j.id,
    'jeuLibelle': j.libelle,
    'fichier': analyse.fichier,
    'empreinte': analyse.empreinte,
    'date': jour,
    'par': par,
    'validePar': par,
    'etat': 'applique',
    'nbLignes': rejeu.nbLignes,
    'nbAvertissements': rejeu.compte.avertissements,
    'nbRefus': 0,
    'nbIgnores': rejeu.compte.ignores,
    'nbInchanges': rejeu.compte.inchanges,
    'nbNon': rejeu.compte.non,
    'ecrits': ecrits,
    'erreurs': _erreursPlafonnees(ps),
    'erreursTotal': rejeu.problemes.length,
    ..._ignoresDe(j, rejeu, port),
  });
  port.journaliser('Import', 'IMP', 'LotImport', reference, null, {'jeu': j.id, 'fichier': analyse.fichier, 'lignes': rejeu.nbLignes, 'fiches': ecrits.length});
  return ResultatImport.ok(lot: rec, ecrits: ecrits.length);
}

/// Annule un lot appliqué : ses fiches sont ARCHIVÉES (RG-14), jamais supprimées ; les MODIFICATIONS du lot sont restituées dans l'ordre inverse. Refusé sans le droit
/// d'annuler le jeu, refusé pour le lot d'un AUTRE agent sauf pour un profil qui supervise (`LOT_D_UN_AUTRE`), refusé en nommant la dépendance si un acte s'appuie dessus.
ResultatImport annulerLot(JeuImport? Function(String id) jeu, Object? lotId, String? motif, PortImport port) {
  final lot = port.parId(collectionLots, lotId);
  if (lot == null) return const ResultatImport.refus('LOT_INCONNU', 'lot introuvable', 'Actualisez l’historique.');
  if (lot['etat'] != 'applique') {
    return ResultatImport.refus('LOT_NON_APPLIQUE', 'seul un lot appliqué s’annule (état actuel : ${lot['etat']})', 'Aucune action : ce lot n’a rien écrit ou est déjà annulé.');
  }
  final j = jeu('${lot['jeu']}');
  if (j != null) {
    final rd = refusDroitImport(j, 'annuler', port);
    if (rd != null) return rd;
  }
  // Un lot se défait par son AUTEUR ; celui d'un autre relève de la SUPERVISION (droit d'annuler sur chaque jeu).
  if (lot['par'] != port.utilisateur && !port.profil.supervise) {
    return ResultatImport.refus('LOT_D_UN_AUTRE', 'le lot ${lot['reference']} a été écrit par un autre agent', 'Seul son auteur, ou un profil qui supervise les importations, peut l’annuler.');
  }
  final dep = j?.dependances(lot, port);
  if (dep != null) return ResultatImport.refus(dep.code, dep.motif, dep.geste);
  final ecrits = (lot['ecrits'] as List).cast<Map>().map((e) => e.cast<String, Object?>()).toList();
  final libelleMotif = 'Annulation du lot ${lot['reference']}${motif != null && motif.isNotEmpty ? ' : $motif' : ''}';
  // Un jeu qui ne s'annule pas par archivage (versions de prix immuables, transfert qui restitue des stocks) porte son propre geste d'annulation.
  if (j?.annuler != null) {
    final ra = j!.annuler!(lot, motif, port);
    if (!ra.ok) return ResultatImport.refus(ra.code!, ra.motif!, ra.geste!);
    port.mettreAJour(collectionLots, lot['id'], {'etat': 'annule', 'annulePar': port.utilisateur, 'annuleLe': port.jour, 'motifAnnulation': motif});
    port.journaliser('Import annulé', 'IMP', 'LotImport', '${lot['reference']}', {'etat': 'applique'}, {'etat': 'annule', 'fiches': ra.archives});
    return ResultatImport.ok(lot: port.parId(collectionLots, lot['id']), archives: ra.archives);
  }
  final faits = <Map<String, Object?>>[];
  Map<String, Object?>? echec;
  for (final e in ecrits) {
    if (echec != null) break;
    final f = port.parId('${e['collection']}', e['id']);
    if (f == null || f['statut'] == 'archive') continue;
    if (e['avant'] != null) continue; // une modification se restitue plus bas, dans l'ordre inverse de son écriture
    // Une VERSION de prix est immuable et ne s'archive pas (RG-14) : celles que pose la création d'un article restent lisibles à l'historique du prix.
    if (e['collection'] == 'versionsTarif') continue;
    if (!port.archiver('${e['collection']}', e['id'], libelleMotif)) {
      echec = e;
    } else {
      faits.add(e);
    }
  }
  if (echec != null) {
    for (final e in faits) {
      port.restaurer('${e['collection']}', e['id']);
    }
    return ResultatImport.refus('ARCHIVAGE_REFUSE', 'le moteur a refusé d’archiver une fiche de « ${echec['collection']} » (exercice clos ou fiche verrouillée)',
        'Rien n’a été annulé. Rouvrez l’exercice ou traitez la fiche à la main.');
  }
  // Les MODIFICATIONS du lot (couverture reprise à son état, miroir du dossier) se restituent en ordre INVERSE : la dernière écrite est défaite la première.
  for (final m in ecrits.reversed) {
    final avant = m['avant'];
    if (avant is Map && port.parId('${m['collection']}', m['id']) != null) port.mettreAJour('${m['collection']}', m['id'], avant.cast<String, Object?>());
  }
  port.mettreAJour(collectionLots, lot['id'], {'etat': 'annule', 'annulePar': port.utilisateur, 'annuleLe': port.jour, 'motifAnnulation': motif});
  port.journaliser('Import annulé', 'IMP', 'LotImport', '${lot['reference']}', {'etat': 'applique'}, {'etat': 'annule', 'fiches': faits.length});
  return ResultatImport.ok(lot: port.parId(collectionLots, lot['id']), archives: faits.length);
}

// --- Modèles et rapports (le contenu des feuilles ; l'écriture du classeur est l'affaire du poste) -------------------------------------

String _typeLisible(ColonneImport c) =>
    const {
      'texte': 'Texte',
      'entier': 'Nombre entier',
      'decimal': 'Nombre',
      'date': 'Date (AAAA-MM-JJ ou JJ/MM/AAAA)',
      'liste': 'Liste de valeurs',
      'tarif': 'Montant, NC ou tiret'
    }[c.type] ??
    c.type;

String _valeursPermises(ColonneImport c, dynamic ctx) {
  if (c.type == 'liste') return valeursListe(c, ctx).map((x) => x.label).join(' ; ');
  if (c.type == 'entier') return 'entier${c.min != null ? ' ≥ ${c.min}' : ''}${c.max != null ? ' et ≤ ${c.max}' : ''}';
  if (c.type == 'tarif') return 'montant entier en FCFA ; NC ; tiret (-)${c.unique ? ' ; UNIQUE (prix unique)' : ''}';
  if (c.motifTexte != null) return c.motifTexte!;
  if (c.longueurMax != null) return 'jusqu’à ${c.longueurMax} caractères';
  return '';
}

/// Le contenu des trois feuilles du modèle : « Données » (en-têtes exacts et une ligne d'exemple), « Instructions » (colonnes, formats, valeurs
/// permises) et « Listes » (les référentiels de contrôle). [validations] : pour chaque colonne « liste », la formule de sa liste déroulante.
class ModeleImport {
  ModeleImport(this.donnees, this.instructions, this.listes, this.validations, this.colonnesTexte);
  final List<List<Object?>> donnees, instructions, listes;
  final List<({int colonne, String formule})> validations;
  final List<int> colonnesTexte;
}

ModeleImport modeleImport(JeuImport j, PortImport port) {
  final ctx = j.contexte(port);
  final cols = colonnesDe(j, port);
  final donnees = <List<Object?>>[
    [for (final c in cols) c.label],
    ligneExemple(j, port),
  ];
  final instructions = <List<Object?>>[
    ['Modèle d’importation : ${j.libelle}'],
    ['Source : ${j.source}'],
    [j.statut == 'proposition' ? 'Statut du jeu : PROPOSITION À VALIDER. ${j.limite ?? ''}' : 'Statut du jeu : supporté.'],
    [''],
    ['Mode d’emploi'],
    ['1. Remplissez l’onglet « Données » à partir de la ligne 2 : une ligne par enregistrement. La ligne 2 est un exemple, remplacez-la ou supprimez-la (elle est ignorée tant qu’elle reste identique à l’exemple).'],
    ['2. Ne changez ni l’ordre ni l’orthographe des en-têtes de la ligne 1 : ils sont reconnus à l’identique. Les colonnes obligatoires doivent toutes figurer.'],
    ['3. Téléversez le fichier : l’analyse complète s’exécute avant toute écriture, ligne par ligne. Un refus nomme la ligne, la colonne, la valeur, le motif et le geste de correction.'],
    ['4. Si une seule ligne est refusée, le fichier entier est refusé et rien n’est écrit. Corrigez et téléversez de nouveau.'],
    ['5. Un lot confirmé s’annule (les fiches sont archivées, jamais supprimées) tant qu’aucun acte ne s’appuie dessus.'],
    [
      const {
            'refuser': '6. Doublon : une ligne dont la fiche existe déjà REFUSE le fichier entier ; un import ne modifie jamais une fiche tenue.',
            'ignorer': '6. Doublon : une ligne dont la fiche existe déjà est IGNORÉE (ni écrite, ni modifiée) ; leur nombre et leur liste figurent au rapport du lot.',
            'versionner': '6. Doublon : une ligne dont le prix diffère crée une NOUVELLE VERSION datée (jamais d’écrasement) ; une ligne identique est comptée « inchangée ».',
          }[port.profil.modeDoublon(j.id)] ??
          '',
    ],
    [''],
    ['Colonne', 'Obligatoire', 'Type', 'Valeurs permises', 'Exemple', 'Explication'],
    for (final c in cols) [c.label, c.obligatoire ? 'oui' : 'non', _typeLisible(c), _valeursPermises(c, ctx), c.exemple ?? '', c.aide ?? ''],
  ];
  final colsListes = <({String titre, List<String> valeurs})>[];
  for (final c in cols) {
    if (c.type != 'liste') continue;
    colsListes.add((titre: c.label, valeurs: [for (final x in valeursListe(c, ctx)) x.label]));
  }
  final hauteur = colsListes.fold<int>(0, (m, l) => l.valeurs.length > m ? l.valeurs.length : m);
  final listes = <List<Object?>>[
    [for (final l in colsListes) l.titre],
    for (var i = 0; i < hauteur; i++) [for (final l in colsListes) i < l.valeurs.length ? l.valeurs[i] : ''],
  ];
  final validations = <({int colonne, String formule})>[];
  var k = 0;
  for (var ci = 0; ci < cols.length; ci++) {
    if (cols[ci].type != 'liste') continue;
    final lettre = String.fromCharCode(65 + k);
    final fin = colsListes[k].valeurs.length + 1;
    validations.add((colonne: ci, formule: 'Listes!\$$lettre\$2:\$$lettre\$${fin < 2 ? 2 : fin}'));
    k++;
  }
  return ModeleImport(
    donnees,
    instructions,
    colsListes.isEmpty ? [['Aucune liste pour ce jeu']] : listes,
    validations,
    [for (var ci = 0; ci < cols.length; ci++) if (cols[ci].type == 'texte') ci],
  );
}

/// Le modèle CSV : BOM, point-virgule, guillemets doublés.
String modeleCsvImport(JeuImport j, [PortImport? port]) {
  String ligne(List<Object?> a) => a.map((x) => '"${texteDe(x).replaceAll('"', '""')}"').join(';');
  return '\uFEFF${ligne([for (final c in (port == null ? j.colonnes : colonnesDe(j, port))) c.label])}\r\n${ligne(ligneExemple(j, port))}\r\n';
}

/// Le contenu de la feuille « Erreurs » du rapport téléchargeable. [sansValeur] : un jeu RESTREINT n'a pas de colonne « Valeur » (aucune valeur de cellule recopiée) ;
/// [masquer] rend idempotent le masquage d'un lot déjà consigné.
List<List<Object?>> rapportImport(List<Map<String, Object?>> problemes, {bool sansValeur = false}) {
  const lib = {'refus': 'refus', 'avertissement': 'avertissement', 'ignore': 'ignorée', 'info': 'information'};
  return [
    sansValeur ? ['Ligne', 'Colonne', 'Niveau', 'Code', 'Motif', 'Geste de correction'] : ['Ligne', 'Colonne', 'Valeur', 'Niveau', 'Code', 'Motif', 'Geste de correction'],
    for (final p in problemes)
      [
        p['n'] ?? '',
        p['colonne'] ?? '',
        if (!sansValeur) texteDe(p['valeur']),
        lib[p['niveau']] ?? p['niveau'],
        p['code'],
        p['motif'],
        p['geste']
      ],
  ];
}

/// Le contenu de la feuille « Résumé » du rapport.
List<List<Object?>> resumeRapportImport(String jeuLibelle, String fichier, String lot, int nbLignes, int nbProblemes, {int ignores = 0, bool sansValeur = false}) => [
      ['Rapport d’importation'],
      ['Jeu', jeuLibelle],
      ['Fichier', fichier],
      ['Lot', lot],
      ['Lignes lues', nbLignes],
      ['Problèmes', nbProblemes],
      ['Lignes ignorées (fiche déjà tenue)', ignores],
      if (sansValeur) ['Valeurs de cellule', 'non recopiées (jeu restreint, RG-13)'],
    ];

// --- Lecture CSV et empreinte ----------------------------------------------------------------------------------------------------

/// Lit un CSV : séparateur `;`, `,` ou tabulation détecté sur la première ligne, guillemets doublés, BOM, lignes finales vides retirées.
List<List<String>> importLireCsv(String texte) {
  var t = texte;
  if (t.isNotEmpty && t.codeUnitAt(0) == 0xFEFF) t = t.substring(1);
  final premiere = t.split(RegExp(r'\r?\n')).first;
  var sep = ';';
  var meilleur = -1;
  for (final s in [';', ',', '\t']) {
    final n = premiere.split(s).length;
    if (n > meilleur) {
      meilleur = n;
      sep = s;
    }
  }
  final lignes = <List<String>>[];
  var ligne = <String>[];
  var champ = StringBuffer();
  var guillemets = false;
  for (var i = 0; i < t.length; i++) {
    final ch = t[i];
    if (guillemets) {
      if (ch == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          champ.write('"');
          i++;
        } else {
          guillemets = false;
        }
      } else {
        champ.write(ch);
      }
    } else if (ch == '"') {
      guillemets = true;
    } else if (ch == sep) {
      ligne.add(champ.toString());
      champ = StringBuffer();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < t.length && t[i + 1] == '\n') i++;
      ligne.add(champ.toString());
      champ = StringBuffer();
      lignes.add(ligne);
      ligne = <String>[];
    } else {
      champ.write(ch);
    }
  }
  if (champ.isNotEmpty || ligne.isNotEmpty) {
    ligne.add(champ.toString());
    lignes.add(ligne);
  }
  while (lignes.isNotEmpty && lignes.last.every((v) => v.trim().isEmpty)) {
    lignes.removeLast();
  }
  return lignes;
}

/// CRC-32 (empreinte du fichier consignée au lot), en hexadécimal sans zéros de tête, comme la maquette.
String importCrc32(List<int> octets) {
  var c = 0xFFFFFFFF;
  for (final b in octets) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
  }
  return ((c ^ 0xFFFFFFFF) & 0xFFFFFFFF).toRadixString(16);
}
