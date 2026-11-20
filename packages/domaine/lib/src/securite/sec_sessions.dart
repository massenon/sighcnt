/// SESSIONS DE POSTE : ACTIVES, SUSPENDUES, CLOTURÉES (retour de la Direction du 01/11/2026) et SÉCURITÉ DES UTILISATEURS.
/// Port de `SIGH.sessions` (parcours.js) et de `m14-sessions` / `m14-securite-utilisateurs` (m14-securite.js).
/// Vecteurs : `test/vecteurs/sessions_securite.json`, engendrés par `prototype_html/build/vecteurs-sessions.js` : les écrans réels de la maquette
/// pilotés dans Chrome (clic « Clôturer », confirmation, relecture du magasin).
///
/// Une session clôturée NE ROUVRE PAS et ne se supprime pas (RG-14) : le registre garde la fiche, la date, l'heure et l'auteur de la clôture (RG-12).
/// `etat` et non `statut` : `statut` est le champ d'archivage du magasin. Tout refus porte un `code`, un `motif` lisible et un `geste` de correction.
library;

import '../format/format_fr.dart' show dateHeure;
import 'sec_comptes.dart' show FicheSec, secRolesDoubleFacteur, secVrai;
import 'sec_exploitation.dart' show secSessions;

/// Un refus NOMMÉ : jamais muet.
class RefusSec {
  const RefusSec(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
}

/// Le résultat d'une règle : soit [patch] (ce qu'il faut écrire sur la fiche), soit [refus].
class ResultatSec {
  const ResultatSec.ok([this.patch = const {}]) : refus = null;
  const ResultatSec.refus(this.refus) : patch = const {};
  final FicheSec patch;
  final RefusSec? refus;
  bool get ok => refus == null;
}

ResultatSec _refus(String code, String motif, String geste) => ResultatSec.refus(RefusSec(code, motif, geste));

// --- Sessions ----------------------------------------------------------------------------------------------------------------------------------

/// `SIGH.sessions.ETATS`.
const secEtatsSession = {'active': 'Active', 'suspendue': 'Suspendue', 'cloturee': 'Clôturée'};

String secLibelleEtatSession(String etat) => secEtatsSession[etat] ?? etat;

/// Une session OUVERTE est active ou suspendue ; la clôturée est finie.
bool secSessionOuverte(FicheSec f) => '${f['etat'] ?? 'active'}' != 'cloturee';

/// Les douze fiches de DÉMONSTRATION (amorçage de l'écran, tirage à graine 3413, comptes actifs) : `source: 'demonstration'`. Une session dont l'inactivité
/// atteint quinze minutes est suspendue.
List<FicheSec> secSessionsDemonstration(Iterable<FicheSec> comptesActifs, DateTime aujourdhui) {
  final rows = secSessions(comptesActifs, aujourdhui);
  var i = 0;
  return [
    for (final s in rows)
      {
        'id': 'SES-D${(++i).toString().padLeft(2, '0')}',
        'statut': 'actif',
        'source': 'demonstration',
        'utilisateurId': s.id,
        'identifiant': s.identifiant,
        'nomComplet': s.nomComplet,
        'role': s.role,
        'poste': s.poste,
        'adresseIp': s.adresseIp,
        'debut': s.debut.toIso8601String(),
        'derniereActivite': s.debut.toIso8601String(),
        'inactivite': s.inactivite,
        'etat': s.verrouillage ? 'suspendue' : 'active',
      }
  ];
}

/// La fiche d'une session RÉELLE de ce poste, créée à la connexion (`assurerSession`).
FicheSec secNouvelleSession(
        {required String identifiant, required String nomComplet, required String role, required String poste, required DateTime maintenant}) =>
    {
      'identifiant': identifiant,
      'nomComplet': nomComplet,
      'role': role,
      'poste': poste,
      'adresseIp': null,
      'source': 'poste',
      'debut': maintenant.toIso8601String(),
      'derniereActivite': maintenant.toIso8601String(),
      'inactivite': 0,
      'etat': 'active',
    };

/// Qui demande la clôture, et depuis quelle session.
class SecActeurSession {
  const SecActeurSession({required this.role, required this.identifiant, required this.nom, this.sessionId});
  final String role;
  final String identifiant;
  final String nom;
  final String? sessionId;
}

/// CLOTURER. Ordre des contrôles de la maquette : session inconnue, déjà clôturée, droit d'édition de l'écran, session PROPRE sans confirmation explicite.
/// Le patch porte la date et l'heure, l'auteur (nom et identifiant), le motif et si l'agent a clôturé sa propre session.
ResultatSec secCloturerSession({
  required FicheSec? fiche,
  required SecActeurSession acteur,
  required bool droitEditer,
  required DateTime maintenant,
  bool confirmePropre = false,
  String? motif,
}) {
  if (fiche == null) return _refus('SESSION_INCONNUE', 'Cette session n’existe pas au registre.', 'Actualiser la liste des sessions.');
  if ('${fiche['etat']}' == 'cloturee') {
    final le = DateTime.tryParse('${fiche['clotureLe'] ?? ''}');
    return _refus(
        'DEJA_CLOTUREE',
        'Cette session est déjà clôturée (le ${le == null ? '' : dateHeure(le.toLocal())}, par ${fiche['cloturePar'] ?? 'un administrateur'}). Une session clôturée ne se rouvre pas.',
        'L’agent ouvre une nouvelle session en se reconnectant.');
  }
  if (!droitEditer) {
    return _refus('DROIT_REFUSE', 'Le profil courant ne peut pas clôturer de session.', 'Demander la clôture à l’administrateur système.');
  }
  final propre = acteur.sessionId != null && acteur.sessionId == '${fiche['id']}';
  if (propre && !confirmePropre) {
    return _refus('SESSION_PROPRE', 'C’est VOTRE session : la clôturer vous déconnecte aussitôt de ce poste.',
        'Confirmer explicitement la clôture de votre propre session.');
  }
  return ResultatSec.ok({
    'etat': 'cloturee',
    'clotureLe': maintenant.toIso8601String(),
    'cloturePar': acteur.nom,
    'clotureParIdentifiant': acteur.identifiant,
    'clotureMotif': motif,
    'cloturePropre': propre,
  });
}

/// Le titre et le message de la confirmation de l'écran (la maquette distingue la session propre).
({String titre, String message, String libelleOk}) secConfirmationCloture({required String nomComplet, required String poste, required bool propre}) => (
      titre: propre ? 'Clôturer VOTRE session ?' : 'Clôturer la session de $nomComplet ?',
      message: propre
          ? 'Il s’agit de votre propre session : vous serez déconnecté immédiatement de ce poste et ramené à la connexion. L’opération est journalisée.'
          : 'L’utilisateur sera déconnecté du poste $poste à son prochain geste. L’opération est journalisée. Une session clôturée ne se rouvre pas.',
      libelleOk: propre ? 'Clôturer ma session' : 'Clôturer la session',
    );

/// La session de ce poste est-elle clôturée au registre ? (contrôle au prochain geste)
bool secSessionCloturee(FicheSec? f) => f != null && '${f['etat']}' == 'cloturee';

/// Le tableau de l'écran : une ligne par fiche non archivée, la plus récente d'abord ; l'inactivité n'est relevée que pour le jeu de démonstration.
List<FicheSec> secLignesSessions(Iterable<FicheSec> fiches) {
  final l = [for (final f in fiches) if ('${f['statut']}' != 'archive') f];
  l.sort((a, b) => '${b['debut'] ?? ''}'.compareTo('${a['debut'] ?? ''}'));
  return [
    for (final f in l)
      {
        'id': f['id'],
        'identifiant': f['identifiant'],
        'nomComplet': f['nomComplet'],
        'role': f['role'],
        'poste': f['poste'],
        'adresseIp': f['adresseIp'],
        'debut': f['debut'],
        'etat': f['etat'] ?? 'active',
        'inactivite': '${f['source']}' == 'demonstration' ? f['inactivite'] : null,
        'clotureLe': f['clotureLe'],
        'cloturePar': f['cloturePar'],
      }
  ];
}

/// Les cinq indicateurs de l'écran, dans l'ordre : ouvertes, postes distincts (ouvertes), suspendues, clôturées.
({int ouvertes, int postes, int suspendues, int cloturees}) secKpisSessions(List<FicheSec> lignes) {
  final ouvertes = lignes.where((r) => '${r['etat']}' != 'cloturee').toList();
  return (
    ouvertes: ouvertes.length,
    postes: ouvertes.map((r) => '${r['poste']}').toSet().length,
    suspendues: lignes.where((r) => '${r['etat']}' == 'suspendue').length,
    cloturees: lignes.where((r) => '${r['etat']}' == 'cloturee').length,
  );
}

// --- Politique de sécurité des comptes ---------------------------------------------------------------------------------------------------------

const secPolitiqueDefaut = <String, int>{
  'longueurMin': 8,
  'expirationJours': 90,
  'historique': 5,
  'echecsMax': 3,
  'blocageMin': 15,
  'inactiviteMin': 15,
};

class SecParametrePolitique {
  const SecParametrePolitique(this.cle, this.libelle, this.unite, this.min, this.max, this.source, this.application);
  final String cle;
  final String libelle;
  final String unite;
  final int min;
  final int max;
  final String source;
  final String application;
}

/// Les six paramètres modifiables, avec leur SOURCE et ce que l'application en fait. La profondeur de l'historique est une PROPOSITION À VALIDER.
const secParametresPolitique = [
  SecParametrePolitique('longueurMin', 'Longueur minimale du mot de passe', 'caractères', 8, 64, 'Politique affichée par l’écran de réinitialisation (écart E1107)',
      'Affichée, non appliquée : la création de compte exige 8 caractères'),
  SecParametrePolitique('expirationJours', 'Durée de validité du mot de passe', 'jours', 0, 365, 'Renouvellement à 90 jours affiché par la maquette (écart E1107)',
      'Calculée par cet écran (mots de passe à renouveler)'),
  SecParametrePolitique('historique', 'Historique des mots de passe interdits', 'derniers', 0, 24, 'Proposition à valider : aucun document ne fixe cette profondeur',
      'Non appliquée par la maquette'),
  SecParametrePolitique('echecsMax', 'Échecs de connexion avant blocage', 'échecs', 1, 10, 'CDCT §12.2 (verrouillage après échecs successifs) ; trois échecs retenus au poste (A5)',
      'Appliquée par le poste ; la maquette bloque à la main et refuse la connexion d’un compte bloqué'),
  SecParametrePolitique('blocageMin', 'Durée du verrou après échecs', 'minutes', 1, 1440, 'Quinze minutes retenues au poste (A5)',
      'Appliquée par le poste, non par le serveur de la maquette'),
  SecParametrePolitique('inactiviteMin', 'Inactivité avant verrouillage de l’écran', 'minutes', 1, 120, 'CDCT §12.2 (déconnexion automatique sur poste partagé : 15 minutes)',
      'Appliquée : verrou de session de ce poste'),
];

/// Valide un jeu de valeurs : entières, dans les bornes de chaque paramètre. Le patch est la politique complète.
ResultatSec secValiderPolitique(Map<String, Object?> valeurs) {
  final patch = <String, Object?>{};
  for (final p in secParametresPolitique) {
    final v = valeurs[p.cle];
    final n = v is num ? v : (v == null ? null : num.tryParse('$v'));
    if (n == null || !n.isFinite || n.floor() != n || n < p.min || n > p.max) {
      return _refus('VALEUR_HORS_BORNES', '${p.libelle} : une valeur entière entre ${p.min} et ${p.max} est attendue.', 'Corriger la valeur de « ${p.libelle} ».');
    }
    patch[p.cle] = n.toInt();
  }
  return ResultatSec.ok(patch);
}

int _entier(Object? v, int repli) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? repli);

/// La politique en vigueur : la fiche, complétée par les valeurs de référence.
Map<String, int> secPolitique(FicheSec? fiche) => {for (final e in secPolitiqueDefaut.entries) e.key: _entier(fiche?[e.key], e.value)};

// --- Comptes : bloqués, à réinitialiser ---------------------------------------------------------------------------------------------------------

/// Un compte est bloqué quand l'administrateur l'a bloqué, quand ses échecs ont atteint le seuil, ou (au poste) quand le verrou après échecs est en cours.
bool secEstBloque(FicheSec u, Map<String, int> politique, {bool verrouEnCours = false}) =>
    secVrai(u['bloque']) || _entier(u['echecs'], 0) >= politique['echecsMax']! || verrouEnCours;

/// Jours restants avant l'expiration du mot de passe ; `null` si la date de définition n'est pas relevée ou si le mot de passe n'expire pas.
int? secJoursAvantExpiration(FicheSec u, Map<String, int> politique, DateTime aujourdhui) {
  final d = DateTime.tryParse('${u['motDePasseDefiniLe'] ?? ''}');
  if (d == null || politique['expirationJours'] == 0) return null;
  final ms = aujourdhui.millisecondsSinceEpoch - d.millisecondsSinceEpoch;
  return politique['expirationJours']! - (ms / 86400000).floor();
}

bool secAReinitialiser(FicheSec u, Map<String, int> politique, DateTime aujourdhui) {
  if (u['doitChangerMotDePasse'] == true) return true;
  final j = secJoursAvantExpiration(u, politique, aujourdhui);
  return j != null && j < 0;
}

/// Le double facteur est exigé pour ce rôle ?
bool secDoubleFacteurExige(String role) => secRolesDoubleFacteur.contains(role);

class SecActeurCompte {
  const SecActeurCompte({required this.identifiant, required this.nom});
  final String identifiant;
  final String nom;
}

/// BLOQUER : motif obligatoire, jamais son propre compte, pas deux fois.
ResultatSec secBloquerCompte(FicheSec? u, {required String? motif, required SecActeurCompte acteur, required Map<String, int> politique, required DateTime maintenant}) {
  if (u == null) return _refus('COMPTE_INCONNU', 'Ce compte n’existe pas.', 'Actualiser la liste.');
  if ((motif ?? '').trim().length < 3) return _refus('MOTIF_OBLIGATOIRE', 'Un motif est obligatoire pour bloquer un compte.', 'Saisir le motif du blocage.');
  if ('${u['identifiant']}' == acteur.identifiant) {
    return _refus('COMPTE_PROPRE', 'Vous ne pouvez pas bloquer votre propre compte.', 'Demander à un autre administrateur de le faire.');
  }
  if (secEstBloque(u, politique)) return _refus('DEJA_BLOQUE', 'Ce compte est déjà bloqué.', 'Le débloquer si l’accès doit être rendu.');
  return ResultatSec.ok({'bloque': true, 'bloqueLe': maintenant.toIso8601String(), 'bloquePar': acteur.nom, 'bloqueMotif': motif!.trim()});
}

ResultatSec secDebloquerCompte(FicheSec? u, {required SecActeurCompte acteur, required Map<String, int> politique, required DateTime maintenant, bool verrouEnCours = false}) {
  if (u == null) return _refus('COMPTE_INCONNU', 'Ce compte n’existe pas.', 'Actualiser la liste.');
  if (!secEstBloque(u, politique, verrouEnCours: verrouEnCours)) return _refus('NON_BLOQUE', 'Ce compte n’est pas bloqué.', 'Aucun déblocage à faire.');
  return ResultatSec.ok({'bloque': false, 'echecs': 0, 'debloqueLe': maintenant.toIso8601String(), 'debloquePar': acteur.nom});
}

/// IMPOSER LA RÉINITIALISATION : l'agent choisit un nouveau mot de passe à sa prochaine connexion. Aucun secret ne passe par ce geste.
ResultatSec secImposerReinitialisation(FicheSec? u, {required SecActeurCompte acteur, required DateTime maintenant}) {
  if (u == null) return _refus('COMPTE_INCONNU', 'Ce compte n’existe pas.', 'Actualiser la liste.');
  if (u['doitChangerMotDePasse'] == true) {
    return _refus('DEJA_IMPOSEE', 'La réinitialisation est déjà imposée à ce compte : l’agent doit choisir un nouveau mot de passe à sa prochaine connexion.', 'Rien à faire.');
  }
  return ResultatSec.ok({'doitChangerMotDePasse': true, 'reinitialisationImposeeLe': maintenant.toIso8601String(), 'reinitialisationImposeePar': acteur.nom});
}

/// CLOTURER LES SESSIONS d'un compte : refus nommés quand il n'en a aucune ou quand l'une d'elles est celle de l'administrateur lui-même.
RefusSec? secRefusCloturerSessionsCompte(List<FicheSec> ouvertes, {String? sessionPropre}) {
  if (ouvertes.isEmpty) return const RefusSec('AUCUNE_SESSION', 'Ce compte n’a aucune session ouverte.', 'Rien à clôturer.');
  if (sessionPropre != null && ouvertes.any((f) => '${f['id']}' == sessionPropre)) {
    return const RefusSec('SESSION_PROPRE', 'L’une de ces sessions est la vôtre.', 'Clôturez-la depuis « Sessions actives », avec sa confirmation explicite.');
  }
  return null;
}
