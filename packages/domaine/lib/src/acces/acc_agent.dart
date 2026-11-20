/// IDENTITÉ NOMINATIVE DE L'AGENT (A1 du document des limites, décision de la Direction du 31/10/2026).
///
/// Jusqu'ici la coque du poste ne portait que le RÔLE : l'« acteur » d'un geste était le libellé du rôle (E800, E625, E687), la fonction et le secteur
/// étaient déduits du rôle (E170, E375), et deux comptables étaient indiscernables. [Agent] est la session NOMINATIVE : un compte (`utilisateurs`)
/// rattaché à un dossier RH (`personnel`, `soignants`). Tout geste qui s'attribue (validation, demande, prélèvement, journal RG-12) lit l'agent,
/// et les contrôles de séparation des tâches (demandeur différent du validateur) comparent l'IDENTIFIANT, jamais le libellé.
///
/// Sans session (poste de développement, tests), chaque rôle a un « agent de démonstration » DÉTERMINISTE ([agentDemonstration]) : même identifiant à
/// chaque appel, nom = libellé du rôle. Il est marqué [Agent.demonstration] : ce n'est pas une personne, et aucun écran ne doit le présenter comme tel.
library;

/// Un agent connecté (ou l'agent de démonstration d'un rôle).
class Agent {
  const Agent({
    required this.utilisateurId,
    required this.nom,
    required this.role,
    this.matricule = '',
    this.fonction,
    this.secteur,
    this.personnelId,
    this.identifiant = '',
    this.demonstration = false,
  });

  /// Identifiant du COMPTE (`utilisateurs.id`) : la clé de toute comparaison de personnes.
  final String utilisateurId;

  /// Nom affiché, celui du dossier RH (`nomComplet`) ; pour un agent de démonstration, le libellé du rôle.
  final String nom;
  final String role;

  /// Matricule du dossier RH (`personnel.matricule`), vide si le compte n'est rattaché à aucun agent.
  final String matricule;

  /// Fonction métier (`personnel.fonction` : medecin, sage_femme, tsl…), `null` si le compte n'a pas de dossier RH : la fonction est alors DÉDUITE du
  /// rôle par le moteur d'habilitations, comme avant.
  final String? fonction;

  /// Code NS 145 du secteur (MAT, LAB, ACC…), `null` si inconnu. Ne se devine pas : voir [agentSecteurDeService].
  final String? secteur;

  /// Identifiant du dossier RH (`personnel.id`), `null` si le compte n'est pas rattaché.
  final String? personnelId;

  /// Identifiant de connexion (`prenom.nom`).
  final String identifiant;

  /// `true` : agent de démonstration d'un rôle, pas une personne.
  final bool demonstration;

  /// La même personne ? Comparaison sur l'IDENTIFIANT du compte (jamais le nom ni le rôle). Deux agents de démonstration d'un même rôle sont
  /// réputés identiques : ils représentent « n'importe qui de ce rôle ».
  bool estLe(Agent? autre) => autre != null && autre.utilisateurId == utilisateurId;

  /// Ce que porte une fiche écrite par cet agent : à ajouter à côté du nom, jamais à sa place.
  Map<String, Object?> toJson() => {
        'utilisateurId': utilisateurId,
        'matricule': matricule,
        'nom': nom,
        'role': role,
        if (fonction != null) 'fonction': fonction,
        if (secteur != null) 'secteur': secteur,
        if (personnelId != null) 'personnelId': personnelId,
      };

  @override
  bool operator ==(Object o) => o is Agent && o.utilisateurId == utilisateurId && o.nom == nom && o.role == role;

  @override
  int get hashCode => Object.hash(utilisateurId, nom, role);

  @override
  String toString() => 'Agent($utilisateurId, $nom, $role)';
}

/// L'agent de démonstration d'un rôle : identifiant `demo:<rôle>`, nom = [nom] (le libellé du rôle) ou le rôle lui-même. DÉTERMINISTE.
Agent agentDemonstration(String role, {String? nom}) =>
    Agent(utilisateurId: 'demo:$role', nom: (nom == null || nom.isEmpty) ? role : nom, role: role, demonstration: true);

/// UNE fabrique : l'agent qui agit, ou l'agent de démonstration de son rôle. C'est ce que lisent `acteur(contexte)` (kit) et le journal.
Agent acteurDepuis({Agent? agent, required String role, String? libelleRole}) =>
    agent ?? agentDemonstration(role, nom: libelleRole);

/// Le secteur NS 145 d'un service du personnel. Table EXTRAITE des services réellement portés par `personnel` et des comptes d'origine de la
/// maquette (`SIGH_COMPTES_ORIGINE`, `api/auth.php`) : un service absent d'ici n'a pas de secteur (`null`), il n'est pas deviné.
/// « Soins infirmiers » est rattaché à la SALLE DE SOINS (SOI) : la maquette range ses infirmiers en SUR ou HOS selon le poste, ce que le service seul
/// ne dit pas (écart E1102).
const Map<String, String> agentSecteurDeService = {
  'Accueil': 'ACC',
  'Comptabilité': 'ADM',
  'Direction': 'ADM',
  'Administration': 'ADM',
  'Imagerie / Échographie': 'ECH',
  'Laboratoire': 'LAB',
  'Maternité': 'MAT',
  'Médecine générale': 'MGE',
  'Chirurgie': 'CHI',
  'Pharmacie': 'CPH',
  'Soins infirmiers': 'SOI',
};

/// Le secteur d'un agent : la fiche du compte d'abord (`secteur`), sinon son service RH, sinon celui du compte ; `null` si rien ne permet de le dire.
String? agentSecteurDe(Map<String, Object?> compte, Map<String, Object?>? employe) {
  String? vrai(Object? v) => (v == null || '$v'.isEmpty) ? null : '$v';
  final direct = vrai(compte['secteur']);
  if (direct != null) return direct;
  for (final service in [employe?['service'], compte['service']]) {
    final s = vrai(service);
    if (s != null && agentSecteurDeService.containsKey(s)) return agentSecteurDeService[s];
  }
  return null;
}

/// Construit l'agent d'un compte (`utilisateurs`) à partir du dossier RH désigné par `employeId` (`personnel`). `soignants` sert de contrôle de la
/// fonction : un soignant référencé à son dossier garde la qualité que l'organigramme lui donne (médecin, sage-femme, infirmier).
Agent agentDepuisCompte(
  Map<String, Object?> compte, {
  Iterable<Map<String, Object?>> personnel = const [],
  Iterable<Map<String, Object?>> soignants = const [],
}) {
  String? vrai(Object? v) => (v == null || '$v'.isEmpty) ? null : '$v';
  final employeId = vrai(compte['employeId']) ?? vrai(compte['personnelId']);
  Map<String, Object?>? employe;
  if (employeId != null) {
    for (final p in personnel) {
      if ('${p['id']}' == employeId) {
        employe = p;
        break;
      }
    }
  }
  Map<String, Object?>? soignant;
  if (employeId != null) {
    for (final s in soignants) {
      if ('${s['personnelId']}' == employeId && '${s['statut'] ?? 'actif'}' != 'archive') {
        soignant = s;
        break;
      }
    }
  }
  final identifiant = '${compte['identifiant'] ?? ''}';
  final role = '${compte['role'] ?? ''}';
  final nom = vrai(compte['nomComplet']) ?? vrai(employe?['nomComplet']) ?? vrai(compte['nom']) ?? identifiant;
  return Agent(
    utilisateurId: vrai(compte['id']) ?? identifiant,
    nom: nom,
    role: role,
    matricule: vrai(compte['matricule']) ?? vrai(employe?['matricule']) ?? '',
    fonction: vrai(compte['fonction']) ?? vrai(employe?['fonction']) ?? vrai(soignant?['qualite']),
    secteur: agentSecteurDe(compte, employe),
    personnelId: employe == null ? null : vrai(employe['id']),
    identifiant: identifiant,
  );
}
