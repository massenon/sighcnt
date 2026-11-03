/// AUTHENTIFICATION LOCALE (A5 du document des limites, décision de la Direction du 31/10/2026) : les RÈGLES, en Dart pur et testables sans disque ni
/// Flutter. Le calcul du haché Argon2id (paquet `cryptography`) vit dans l'application du poste ; ici : la politique de mot de passe, les paramètres du
/// hachage, la forme de la fiche de la collection technique `identifiants`, le verrou après échecs et le renouvellement.
///
/// CE QUE LA FICHE `identifiants` PORTE : un haché, un sel PAR COMPTE, les paramètres qui ont servi à le calculer (pour pouvoir les durcir sans
/// invalider les anciens), des dates et un compteur d'échecs. JAMAIS le mot de passe. Cette collection n'est ni dans le jeu de démonstration, ni dans
/// le journal d'audit (RG-12 y inscrit le geste, jamais la valeur), ni dans les exports.
library;

import 'dart:math' as math;

// ------------------------------------------------------------------------------------------------------------------------------------------------
// Paramètres du hachage
// ------------------------------------------------------------------------------------------------------------------------------------------------

/// Les paramètres d'Argon2id d'une fiche. [memoireKio] : blocs de 1 Kio (paramètre `memory` du paquet `cryptography`).
///
/// [production] : 19 456 Kio (19 Mio), 2 passes, 1 voie, sortie de 32 octets, soit la configuration minimale recommandée par l'OWASP pour Argon2id
/// (https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html). Calculé en Dart pur, il demande de l'ordre d'une à quelques
/// secondes sur un poste de bureau : acceptable pour une connexion, jamais pour un traitement en boucle. Un poste plus lent peut MONTER les paramètres
/// (la fiche garde ceux de sa création ; un haché ancien reste vérifiable).
/// [tests] : paramètres RÉDUITS, injectables pour que la suite reste rapide ; jamais utilisés en production.
class AccParametresHachage {
  const AccParametresHachage({required this.memoireKio, required this.iterations, required this.parallelisme, required this.longueur});

  final int memoireKio;
  final int iterations;
  final int parallelisme;
  final int longueur;

  static const production = AccParametresHachage(memoireKio: 19456, iterations: 2, parallelisme: 1, longueur: 32);
  static const tests = AccParametresHachage(memoireKio: 16, iterations: 1, parallelisme: 1, longueur: 16);

  Map<String, Object?> toJson() =>
      {'algorithme': 'argon2id', 'memoireKio': memoireKio, 'iterations': iterations, 'parallelisme': parallelisme, 'longueur': longueur};

  /// Relit les paramètres d'une fiche (ceux qui ont servi à la créer), ou [repli] si la fiche est incomplète.
  static AccParametresHachage depuisFiche(Map<String, Object?> f, {AccParametresHachage repli = production}) => AccParametresHachage(
      memoireKio: _entier(f['memoireKio']) ?? repli.memoireKio,
      iterations: _entier(f['iterations']) ?? repli.iterations,
      parallelisme: _entier(f['parallelisme']) ?? repli.parallelisme,
      longueur: _entier(f['longueur']) ?? repli.longueur);

  @override
  bool operator ==(Object o) =>
      o is AccParametresHachage && o.memoireKio == memoireKio && o.iterations == iterations && o.parallelisme == parallelisme && o.longueur == longueur;

  @override
  int get hashCode => Object.hash(memoireKio, iterations, parallelisme, longueur);
}

int? _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

/// Longueur du sel PAR COMPTE, en octets (16, recommandation de la RFC 9106).
const int accLongueurSel = 16;

// ------------------------------------------------------------------------------------------------------------------------------------------------
// Politique de mot de passe (CDCT §12.2), APPLIQUÉE
// ------------------------------------------------------------------------------------------------------------------------------------------------

/// La longueur minimale : la politique que la maquette AFFICHE (E1076, E883) et que le poste APPLIQUE.
const int accLongueurMinMotDePasse = 8;

/// Renouvellement obligatoire, en jours (« Renouvellement obligatoire tous les 90 jours »).
const int accRenouvellementJours = 90;

/// Un caractère spécial : tout ce qui n'est ni lettre ni chiffre ni espace.
final RegExp _special = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
final RegExp _majuscule = RegExp(r'\p{Lu}', unicode: true);
final RegExp _minuscule = RegExp(r'\p{Ll}', unicode: true);
final RegExp _chiffre = RegExp(r'\p{N}', unicode: true);

/// Les règles NON satisfaites par [mot], dans l'ordre d'affichage. Liste vide = politique respectée.
/// [identifiant] : un mot de passe ne contient pas l'identifiant de connexion (quand il compte au moins quatre caractères).
List<String> accRegleManquantes(String mot, {String? identifiant}) {
  final manque = <String>[];
  if (mot.runes.length < accLongueurMinMotDePasse) manque.add('$accLongueurMinMotDePasse caractères minimum');
  if (!_majuscule.hasMatch(mot) || !_minuscule.hasMatch(mot)) manque.add('Au moins une majuscule et une minuscule');
  if (!_chiffre.hasMatch(mot) || !_special.hasMatch(mot)) manque.add('Au moins un chiffre et un caractère spécial');
  final id = (identifiant ?? '').trim().toLowerCase();
  if (id.length >= 4 && mot.toLowerCase().contains(id)) manque.add('Ne doit pas contenir l’identifiant de connexion');
  return manque;
}

/// Le refus à afficher (une phrase qui NOMME les règles manquantes), ou `null` si le mot de passe est conforme.
String? accRefusPolitique(String mot, {String? identifiant}) {
  final m = accRegleManquantes(mot, identifiant: identifiant);
  return m.isEmpty ? null : 'Mot de passe non conforme à la politique : ${m.join(' ; ')}.';
}

/// Le contrôle COMPLET d'un nouveau mot de passe : politique, concordance des deux saisies, différent de l'ancien. `null` = accepté.
String? accControlerNouveauMotDePasse(String a, String b, {String? identifiant, String? ancien}) {
  if (a != b) return 'Les deux mots de passe ne correspondent pas.';
  final p = accRefusPolitique(a, identifiant: identifiant);
  if (p != null) return p;
  if (ancien != null && a == ancien) return 'Le nouveau mot de passe doit être différent de l’actuel.';
  return null;
}

/// Alphabet du mot de passe provisoire : sans caractères ambigus (0/O, 1/l/I), pour être dicté ou recopié sans erreur.
const String _majusc = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const String _minusc = 'abcdefghijkmnpqrstuvwxyz';
const String _chiffres = '23456789';
const String _specials = '!#\$%&*+=?@';

/// Un mot de passe provisoire ALÉATOIRE qui respecte la politique (16 caractères : au moins deux de chaque famille). [alea] : `Random.secure()` en
/// production (aucune valeur fixe, jamais écrite dans le dépôt) ; un test injecte un générateur à graine pour le rejouer.
String accGenererMotDePasseProvisoire(math.Random alea, {int longueur = 16}) {
  String un(String s) => s[alea.nextInt(s.length)];
  final tous = _majusc + _minusc + _chiffres + _specials;
  final c = <String>[un(_majusc), un(_majusc), un(_minusc), un(_minusc), un(_chiffres), un(_chiffres), un(_specials), un(_specials)];
  while (c.length < longueur) {
    c.add(un(tous));
  }
  // Mélange de Fisher-Yates : les familles obligatoires ne restent pas en tête.
  for (var i = c.length - 1; i > 0; i--) {
    final j = alea.nextInt(i + 1);
    final t = c[i];
    c[i] = c[j];
    c[j] = t;
  }
  return c.join();
}

// ------------------------------------------------------------------------------------------------------------------------------------------------
// Verrou après échecs, renouvellement
// ------------------------------------------------------------------------------------------------------------------------------------------------

/// Échecs consécutifs après lesquels le compte se verrouille : le chiffre que la maquette AFFICHE (« verrouillage à 3 essais », E883 ; `accTentativesMax`
/// de l'écran de connexion).
const int accEchecsAvantVerrou = 3;

/// Durée du verrou du compte : quinze minutes (CDCT §12.2, A5). L'administrateur le lève plus tôt en définissant un nouveau mot de passe.
const Duration accDureeVerrouCompte = Duration(minutes: 15);

typedef FicheIdentifiant = Map<String, Object?>;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// Le compte est-il verrouillé à [maintenant] ? Rend l'heure de fin du verrou, ou `null`.
DateTime? accVerrouJusqua(FicheIdentifiant f, DateTime maintenant) {
  final fin = _date(f['verrouJusqua']);
  if (fin == null) return null;
  return fin.isAfter(maintenant) ? fin : null;
}

/// Le patch d'une fiche après un ÉCHEC : le compteur monte ; au seuil, le verrou se pose pour [accDureeVerrouCompte] et le compteur repart de zéro
/// (un verrou levé donne droit à un nouvel essai complet, il ne laisse pas l'agent à un échec de la prochaine lourdeur).
({Map<String, Object?> patch, bool verrouille}) accApresEchec(FicheIdentifiant f, DateTime maintenant) {
  final n = (_entier(f['echecs']) ?? 0) + 1;
  if (n >= accEchecsAvantVerrou) {
    return (
      patch: {'echecs': 0, 'verrouJusqua': maintenant.add(accDureeVerrouCompte).toIso8601String(), 'dernierEchecLe': maintenant.toIso8601String()},
      verrouille: true
    );
  }
  return (patch: {'echecs': n, 'dernierEchecLe': maintenant.toIso8601String()}, verrouille: false);
}

/// Le patch d'une fiche après un SUCCÈS : le compteur et le verrou retombent.
Map<String, Object?> accApresSucces(DateTime maintenant) =>
    {'echecs': 0, 'verrouJusqua': null, 'dernierSuccesLe': maintenant.toIso8601String()};

/// Le mot de passe a-t-il dépassé son renouvellement (90 jours) ? Faux si la fiche ne porte pas de date d'expiration.
bool accExpire(FicheIdentifiant f, DateTime maintenant) {
  final fin = _date(f['expireLe']);
  return fin != null && !fin.isAfter(maintenant);
}

/// Le changement est-il OBLIGATOIRE à la prochaine connexion ? Oui si la fiche le demande (mot de passe provisoire, première connexion) ou si le
/// renouvellement est échu.
bool accChangementObligatoire(FicheIdentifiant f, DateTime maintenant) => f['doitChanger'] == true || accExpire(f, maintenant);

/// La fiche d'un identifiant, SANS le secret : [hash] et [sel] sont déjà encodés (base64) par l'appelant.
FicheIdentifiant accFicheIdentifiant({
  required String utilisateurId,
  required String hash,
  required String sel,
  required AccParametresHachage parametres,
  required DateTime maintenant,
  required String definiPar,
  required bool doitChanger,
}) =>
    {
      'id': utilisateurId,
      'utilisateurId': utilisateurId,
      ...parametres.toJson(),
      'version': 19,
      'sel': sel,
      'hash': hash,
      'definiLe': maintenant.toIso8601String(),
      'definiPar': definiPar,
      'expireLe': maintenant.add(const Duration(days: accRenouvellementJours)).toIso8601String(),
      'doitChanger': doitChanger,
      'echecs': 0,
      'verrouJusqua': null,
    };

/// Le motif écrit dans `tentativesConnexion` (RG-12), selon le refus. Le MESSAGE montré à l'agent, lui, ne distingue jamais « inconnu » de « erroné »
/// (un refus qui dit lequel est un annuaire offert à qui essaie).
const String accMotifMotDePasseErrone = 'Mot de passe erroné';
const String accMotifCompteVerrouille = 'Compte verrouillé après échecs répétés';
const String accMotifVerrouPose = 'Verrou posé après échecs répétés';
const String accMotifSansIdentifiant = 'Aucun mot de passe défini pour ce compte';

String accMessageVerrou(DateTime fin) {
  String d(int n) => n.toString().padLeft(2, '0');
  return 'Compte verrouillé après $accEchecsAvantVerrou tentatives infructueuses. Réessayer à ${d(fin.hour)}:${d(fin.minute)}, ou demander à l’administrateur de définir un nouveau mot de passe.';
}
