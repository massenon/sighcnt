/// CODE DE SECOURS ET RÉINITIALISATION DU MOT DE PASSE (PRD-POSTE-premiere-installation, EF-INST-09, arbitrage de la Direction du 02/11/2026).
/// Les RÈGLES, en Dart pur et testables sans disque ni Flutter ; le calcul du haché Argon2id reste dans l'application du poste.
///
/// RÈGLE DE LA CIBLE UNIQUEMENT : la maquette n'a ni code de secours ni réinitialisation par un administrateur. Elles n'ont donc pas de vecteur tiré de
/// la maquette ; elles sont couvertes par `test/acc_secours_test.dart` et consignées dans `docs/architecture/ECARTS-MAQUETTE.md`.
///
/// CE QUE L'ON GARDE : l'EMPREINTE du code de secours (haché et sel), jamais le code. Un code perdu ne se retrouve pas.
library;

import 'dart:math' as math;

import 'acc_identifiants.dart';

// ------------------------------------------------------------------------------------------------------------------------------------------------
// Code de secours
// ------------------------------------------------------------------------------------------------------------------------------------------------

/// Longueur du code de secours, en caractères (hors séparateurs d'affichage).
const int accLongueurCodeSecours = 25;

/// Alphabet du code : majuscules et chiffres SANS caractères ambigus (ni 0/O, ni 1/I/L), pour être recopié ou dicté sans erreur.
const String accAlphabetCodeSecours = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Un code de secours ALÉATOIRE de [accLongueurCodeSecours] caractères. [alea] : `Random.secure()` en production ; un test injecte une graine.
String accGenererCodeSecours(math.Random alea) =>
    List.generate(accLongueurCodeSecours, (_) => accAlphabetCodeSecours[alea.nextInt(accAlphabetCodeSecours.length)]).join();

/// L'affichage par groupes de cinq (`XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`) : plus lisible, recopié sans erreur. Le séparateur n'est pas une partie du code.
String accFormaterCodeSecours(String code) {
  final c = accNormaliserCodeSecours(code);
  final groupes = <String>[for (var i = 0; i < c.length; i += 5) c.substring(i, i + 5 > c.length ? c.length : i + 5)];
  return groupes.join('-');
}

/// Ce que l'agent a tapé, ramené à la forme comparée : majuscules, sans espaces ni tirets.
String accNormaliserCodeSecours(String saisie) => saisie.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

/// La saisie a-t-elle la FORME d'un code ? (longueur et alphabet). Ne dit rien de sa justesse : la comparaison se fait sur l'empreinte.
bool accCodeSecoursBienForme(String saisie) {
  final c = accNormaliserCodeSecours(saisie);
  return c.length == accLongueurCodeSecours && c.split('').every(accAlphabetCodeSecours.contains);
}

/// Le code de secours ne vaut que pour un compte ADMINISTRATEUR (il ne rouvre pas le compte d'un agent).
bool accSecoursPourRole(String role) => role == 'admin';

/// La fiche de l'empreinte du code, SANS le code : [hash] et [sel] sont déjà encodés (base64) par l'appelant. `consommeLe` vaut `null` tant que le code
/// n'a pas servi ; un code consommé ne se rejoue pas.
Map<String, Object?> accFicheSecours({
  required String utilisateurId,
  required String hash,
  required String sel,
  required AccParametresHachage parametres,
  required DateTime maintenant,
  required String creePar,
}) =>
    {
      'id': 'SEC-$utilisateurId',
      'utilisateurId': utilisateurId,
      ...parametres.toJson(),
      'sel': sel,
      'hash': hash,
      'creeLe': maintenant.toIso8601String(),
      'creePar': creePar,
      'consommeLe': null,
    };

/// Le code de cette fiche est-il encore utilisable ?
bool accSecoursUtilisable(Map<String, Object?>? fiche) => fiche != null && fiche['consommeLe'] == null && '${fiche['hash'] ?? ''}'.isNotEmpty;

// ------------------------------------------------------------------------------------------------------------------------------------------------
// Verrou du CHEMIN de récupération
// ------------------------------------------------------------------------------------------------------------------------------------------------

/// Essais faux après lesquels le chemin est bloqué.
const int accEssaisSecoursAvantBlocage = 5;

/// Durée du blocage du chemin de récupération.
const Duration accDureeBlocageSecours = Duration(minutes: 15);

/// L'état du chemin : un seul compteur pour le CHEMIN (et non par compte), de sorte que la réponse ne dise jamais si l'identifiant existe.
typedef EtatSecours = Map<String, Object?>;

/// Le chemin est-il bloqué à [maintenant] ? Rend l'heure de fin du blocage, ou `null`.
DateTime? accSecoursBloqueJusqua(EtatSecours etat, DateTime maintenant) {
  final fin = DateTime.tryParse('${etat['bloqueJusqua'] ?? ''}');
  return fin != null && fin.isAfter(maintenant) ? fin : null;
}

/// Le patch de l'état après un essai FAUX (identifiant inconnu, code faux, code consommé, compte non administrateur : tous comptent pareil).
({EtatSecours patch, bool bloque}) accSecoursApresEchec(EtatSecours etat, DateTime maintenant) {
  final n = ((etat['essais'] is num) ? (etat['essais'] as num).toInt() : 0) + 1;
  if (n >= accEssaisSecoursAvantBlocage) {
    return (patch: {'essais': 0, 'bloqueJusqua': maintenant.add(accDureeBlocageSecours).toIso8601String()}, bloque: true);
  }
  return (patch: {'essais': n}, bloque: false);
}

/// Après un succès, le compteur retombe.
EtatSecours accSecoursApresSucces() => {'essais': 0, 'bloqueJusqua': null};

/// Le message UNIQUE affiché à tout essai faux : il ne distingue jamais un identifiant inconnu d'un code erroné (un refus qui dit lequel est un annuaire).
const String accMessageSecoursRefus = 'Identifiant ou code de secours incorrect.';

String accMessageSecoursBloque(DateTime fin) {
  String d(int n) => n.toString().padLeft(2, '0');
  return 'Trop d’essais. La récupération est bloquée jusqu’à ${d(fin.hour)}:${d(fin.minute)}.';
}

// ------------------------------------------------------------------------------------------------------------------------------------------------
// Réinitialisation par un administrateur
// ------------------------------------------------------------------------------------------------------------------------------------------------

/// Longueur du mot de passe temporaire.
const int accLongueurMotDePasseTemporaire = 14;

/// Durée de validité du mot de passe temporaire.
const Duration accValiditeMotDePasseTemporaire = Duration(hours: 24);

/// Un mot de passe temporaire ALÉATOIRE : 14 caractères qui respectent la politique du poste (au moins deux de chaque famille).
String accGenererMotDePasseTemporaire(math.Random alea) => accGenererMotDePasseProvisoire(alea, longueur: accLongueurMotDePasseTemporaire);

/// La date d'échéance d'un mot de passe temporaire défini à [maintenant].
DateTime accEcheanceTemporaire(DateTime maintenant) => maintenant.add(accValiditeMotDePasseTemporaire);

/// Le mot de passe temporaire est-il périmé ? Faux si la fiche n'en porte pas (mot de passe ordinaire).
bool accTemporairePerime(Map<String, Object?> fiche, DateTime maintenant) {
  final fin = DateTime.tryParse('${fiche['temporaireJusqua'] ?? ''}');
  return fin != null && !fin.isAfter(maintenant);
}

/// Le refus affiché quand le mot de passe temporaire est juste mais périmé, et le motif écrit dans `tentativesConnexion`.
const String accMessageTemporairePerime = 'Ce mot de passe temporaire a expiré (24 h). Demandez à un administrateur d’en générer un nouveau.';
const String accMotifTemporairePerime = 'Mot de passe temporaire expiré';

/// Le refus nommé d'une réinitialisation.
class RefusReinit {
  const RefusReinit(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
}

/// Qui peut réinitialiser quel compte. Rend le refus NOMMÉ, ou `null` si c'est permis.
/// - seul un administrateur réinitialise ;
/// - jamais son propre compte par ce chemin (il utilise le code de secours) ;
/// - un simple administrateur ne touche pas à un super administrateur.
/// Le poste ne porte aujourd'hui qu'UN rôle `admin` : [acteurSuper] et [cibleSuper] valent `false` tant que la Direction n'a pas défini ce qu'est un
/// super administrateur du poste (question ouverte du plan).
RefusReinit? accRefusReinitialisation({
  required String acteurRole,
  required String acteurId,
  required String cibleId,
  bool acteurSuper = false,
  bool cibleSuper = false,
}) {
  if (acteurRole != 'admin') {
    return const RefusReinit('reinit_non_admin', 'Seul un administrateur réinitialise un mot de passe.', 'Prévenir un administrateur.');
  }
  if (acteurId == cibleId) {
    return const RefusReinit('reinit_propre_compte', 'Un administrateur ne réinitialise pas son propre compte par ce chemin.',
        'Demander à un autre administrateur, ou utiliser le code de secours depuis l’écran de connexion.');
  }
  if (cibleSuper && !acteurSuper) {
    return const RefusReinit('reinit_super_admin', 'Seul un super administrateur réinitialise le compte d’un super administrateur.',
        'Demander à un super administrateur.');
  }
  return null;
}

/// Le contrôle d'un nouveau mot de passe choisi APRÈS une réinitialisation : la politique du poste, la concordance des deux saisies, et différent de
/// l'ancien ET du temporaire. `null` = accepté.
String? accControlerMotDePasseApresReinit(String a, String b, {String? identifiant, String? ancien, String? temporaire}) {
  final base = accControlerNouveauMotDePasse(a, b, identifiant: identifiant, ancien: ancien);
  if (base != null) return base;
  if (temporaire != null && a == temporaire) return 'Le nouveau mot de passe doit être différent du mot de passe temporaire.';
  return null;
}
