/// Écrans d'accès (AUTH) — la CONNEXION. Règles de `prototype_html/assets/js/modules/auth.js` (écran `index`) rejouées sur les vecteurs de la
/// maquette (`vecteurs-acces.js`).
///
/// CE QUE FAIT [accEvaluer], ET CE QU'ELLE NE FAIT PAS. Elle RECONNAÎT un compte du jeu (`utilisateurs`) et construit son agent nominatif ; elle ne
/// vérifie JAMAIS le mot de passe, et [accMotDePasseVerifie] le dit. La vérification du haché Argon2id (A5) est faite AVANT elle par le service
/// d'identifiants du poste (`apps/poste/lib/core/identifiants.dart`) ; les règles pures de cette authentification (politique, verrou, renouvellement)
/// sont dans `acc_identifiants.dart`.
library;

import 'acc_agent.dart';

/// [accEvaluer] ne vérifie pas le mot de passe : c'est le service d'identifiants du poste qui le fait. Une constante plutôt qu'un commentaire.
const bool accMotDePasseVerifie = false;

/// Nombre de tentatives après lequel la maquette annonce que le compte serait verrouillé.
const int accTentativesMax = 3;

/// Message de la maquette quand l'un des deux champs est vide, selon le rang de la tentative (compteur commun aux refus de saisie et aux refus du
/// serveur : `tentatives++` aux deux endroits).
String accMessageSaisieVide(int tentative) => tentative >= accTentativesMax
    ? 'Trois tentatives infructueuses. Conformément à la politique de sécurité, le compte serait verrouillé et l’événement journalisé.'
    : 'Identifiant et mot de passe obligatoires (tentative $tentative sur $accTentativesMax).';

/// Un refus du serveur ne dit PAS lequel des deux est faux : « identifiant inconnu » et « mot de passe erroné » distingués, c'est un annuaire offert à
/// qui essaie.
const String accMessageRefus = 'Identifiant ou mot de passe incorrect.';
const String accMessageCompteArchive = 'Ce compte a été archivé : il n’ouvre plus de session (RG-14).';

/// Motifs consignés dans `tentativesConnexion` (RG-12) — ceux du serveur et de l'écran.
const String accMotifIdentifiantInconnu = 'Identifiant inconnu';
/// Un compte BLOQUÉ par l'administrateur (écran « Sécurité des utilisateurs ») n'ouvre pas de session : le même texte que le serveur de la maquette.
const String accMessageCompteBloque = 'Ce compte a été bloqué par l’administrateur système : il n’ouvre plus de session tant qu’il n’est pas débloqué.';
/// Ce que la connexion dit quand la session a été CLOTURÉE par un administrateur (même texte que la maquette, `?motif=session-cloturee`).
const String accMessageSessionCloturee = 'Votre session a été clôturée par un administrateur. Elle ne se rouvre pas : reconnectez-vous pour en ouvrir une nouvelle.';
const String accMotifCompteBloque = 'Compte bloqué par l’administrateur';
const String accMotifCompteArchive = 'Compte archivé — accès retiré par l’administrateur';
const String accMotifRoleArchive = 'Rôle archivé — accès retiré par l’administrateur';

enum AccIssue { accepte, refuse, compteArchive, roleArchive, compteBloque }

class AccCompte {
  const AccCompte({required this.identifiant, required this.nom, required this.role, this.mfa = false, this.agent});
  final String identifiant;
  final String nom;
  final String role;
  final bool mfa;

  /// L'agent NOMINATIF du compte (A1) : identifiant du compte, matricule, fonction et secteur issus du dossier RH. `null` pour un compte construit à la
  /// main (poste de développement `SIGH_ROLE`, tests) : la coque lui donne alors l'agent de démonstration de son rôle.
  final Agent? agent;
}

class AccDecision {
  const AccDecision(this.issue, {this.compte, required this.message, this.motif, this.libelleRole});
  final AccIssue issue;
  final AccCompte? compte;

  /// Le texte de l'encadré rouge de l'écran.
  final String message;

  /// Le motif écrit dans `tentativesConnexion` ; `null` quand la connexion est acceptée.
  final String? motif;

  /// Le libellé du rôle (refus « rôle archivé » : la modale le nomme).
  final String? libelleRole;
  bool get accepte => issue == AccIssue.accepte;

  /// Toujours `false` au poste : voir [accMotDePasseVerifie].
  bool get motDePasseVerifie => accMotDePasseVerifie;
}

/// Reconnaît l'identifiant parmi les comptes du jeu. Ordre des contrôles = celui du serveur : compte inconnu → refus générique ; compte archivé → refus
/// nommé (RG-14) ; puis, côté écran, rôle archivé depuis la matrice des droits → refus nommé avec modale. Le mot de passe n'est JAMAIS vérifié ici.
AccDecision accEvaluer({
  required String identifiant,
  required Iterable<Map<String, Object?>> utilisateurs,
  required Set<String> rolesArchives,
  required String Function(String role) libelleRole,
  Iterable<Map<String, Object?>> personnel = const [],
  Iterable<Map<String, Object?>> soignants = const [],
}) {
  final id = identifiant.trim();
  Map<String, Object?>? u;
  for (final x in utilisateurs) {
    if ('${x['identifiant']}' == id) {
      u = x;
      break;
    }
  }
  if (u == null) {
    return const AccDecision(AccIssue.refuse, message: accMessageRefus, motif: accMotifIdentifiantInconnu);
  }
  final role = '${u['role'] ?? ''}';
  final compte = AccCompte(
      identifiant: id,
      nom: '${u['nomComplet'] ?? u['nom'] ?? id}',
      role: role,
      mfa: u['mfa'] == true,
      agent: agentDepuisCompte(u, personnel: personnel, soignants: soignants));
  if ('${u['statut'] ?? 'actif'}' != 'actif') {
    return AccDecision(AccIssue.compteArchive, compte: compte, message: accMessageCompteArchive, motif: accMotifCompteArchive);
  }
  if (u['bloque'] == true) {
    return AccDecision(AccIssue.compteBloque, compte: compte, message: accMessageCompteBloque, motif: accMotifCompteBloque);
  }
  if (rolesArchives.contains(role)) {
    final l = libelleRole(role);
    return AccDecision(AccIssue.roleArchive,
        compte: compte, message: 'Connexion refusée — le profil « $l » a été retiré.', motif: accMotifRoleArchive, libelleRole: l);
  }
  return AccDecision(AccIssue.accepte, compte: compte, message: '');
}

/// La fiche écrite dans `tentativesConnexion` pour un refus (l'administrateur la retrouve dans « Rôles & permissions »). `horodatage` : ISO.
Map<String, Object?> accTentative({
  required String identifiant,
  required AccDecision decision,
  required DateTime maintenant,
}) =>
    {
      'identifiant': decision.compte?.identifiant ?? identifiant.trim(),
      'nom': decision.compte?.nom ?? identifiant.trim(),
      'role': decision.compte?.role ?? '—',
      'motif': decision.motif ?? accMotifIdentifiantInconnu,
      'horodatage': maintenant.toIso8601String(),
      'poste': 'Écran de connexion',
      'traitee': false,
    };

/// Les lignes de la modale « Connexion refusée » (rôle archivé).
List<(String, String)> accLignesRefus(AccDecision d, String dateHeure) => [
      ('Compte', d.compte?.nom ?? ''),
      ('Profil demandé', d.libelleRole ?? ''),
      ('Date et heure', dateHeure),
      ('Suite donnée', 'La tentative est journalisée et signalée à l’administrateur.'),
    ];

/// Les quatre règles de la politique de mot de passe affichées par la réinitialisation (CDCT §12.2). La maquette les AFFICHE avec des coches vertes mais
/// ne les APPLIQUE PAS : seule la concordance des deux saisies est contrôlée (écart consigné).
const List<String> accRegleMotDePasse = [
  '8 caractères minimum',
  'Au moins une majuscule et une minuscule',
  'Au moins un chiffre et un caractère spécial',
  'Renouvellement obligatoire tous les 90 jours',
];

/// `auth-reset` : le seul contrôle de la maquette. `null` = accepté.
String? accControlerReinitialisation(String a, String b) => a != b ? 'Les deux mots de passe ne correspondent pas.' : null;
