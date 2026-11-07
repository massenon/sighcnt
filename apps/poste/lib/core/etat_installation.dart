/// L'ÉTAT D'INSTALLATION DU POSTE (PRD-POSTE-premiere-installation, EF-INST-01 et 03, PLAN étape 2).
///
/// DONNÉE LOCALE DU POSTE, jamais synchronisée : elle décrit CE poste (où en est son assistant), pas la clinique. Chaque poste a la sienne. Elle vit dans
/// les paramètres persistants du poste ([ParametresPoste]), pas dans le magasin partagé.
///
/// Les quatre étapes de la modale « Configurations à faire » (arbitrage de la Direction du 02/11/2026) :
///  A `mere`            : activer la mère (relais, secret, clé de clinique). Faite, ou REPORTÉE si le relais est injoignable.
///  B `configurations`  : les configurations de la clinique (écrans `cfg-*`).
///  C `comptes`         : les comptes des autres agents, dont un SECOND administrateur (obligatoire avant la clôture).
///  D `appairages`      : les postes fileuls et les mobiles.
library;

/// Où en est le poste.
enum PhaseInstallation {
  /// Rien n'a été installé : l'assistant propose « Première installation » ou « Rejoindre une clinique » (si le poste n'a aucun compte non plus).
  nonInstalle,

  /// Le premier compte existe, l'assistant n'est pas clos : la modale s'ouvre sur le tableau de bord.
  enCours,

  /// L'assistant est clos : il n'apparaît plus qu'à l'administrateur système.
  cloturee,
}

/// L'état d'une étape. `reportee` n'existe que pour la mère (relais injoignable).
enum EtapeEtat { aFaire, reportee, faite }

/// Les identifiants des étapes, dans l'ordre.
const List<String> etapesInstallation = ['mere', 'configurations', 'comptes', 'appairages'];

const Map<String, String> libellesEtapesInstallation = {
  'mere': 'Activer la mère',
  'configurations': 'Configurer la clinique',
  'comptes': 'Créer les comptes des agents',
  'appairages': 'Appairer les postes et les mobiles',
};

class EtatInstallation {
  const EtatInstallation({this.creeLe, this.creePar, this.etapes = const {}, this.clotureLe, this.cloturePar, this.lignesVerifiees = const {}});

  /// L'état d'un poste jamais installé.
  static const vide = EtatInstallation();

  final DateTime? creeLe;
  final String? creePar;

  /// `etape -> 'reportee' | 'faite'` ; une étape absente est « à faire ».
  final Map<String, String> etapes;
  final DateTime? clotureLe;
  final String? cloturePar;

  /// Les écrans de configuration que l'administrateur a vérifiés SANS rien y changer (la détection ne voit que ce qui s'écrit).
  final Set<String> lignesVerifiees;

  PhaseInstallation get phase =>
      clotureLe != null ? PhaseInstallation.cloturee : (creeLe != null ? PhaseInstallation.enCours : PhaseInstallation.nonInstalle);

  EtapeEtat etat(String etape) => switch (etapes[etape]) {
        'faite' => EtapeEtat.faite,
        'reportee' => EtapeEtat.reportee,
        _ => EtapeEtat.aFaire,
      };

  /// L'étape A est-elle réglée (faite ou reportée) ? Les autres étapes l'EXIGENT : la mère s'active d'abord, mais elle peut attendre le relais.
  bool get mereReglee => etat('mere') != EtapeEtat.aFaire;

  /// Pourquoi l'étape est verrouillée (le motif affiché à côté de la ligne grisée), ou `null` si elle est ouverte. L'étape A n'est jamais verrouillée.
  String? motifVerrou(String etape) {
    if (etape == 'mere') return null;
    if (!mereReglee) return 'Activer d’abord la mère : une configuration saisie avant n’est diffusée à personne.';
    return null;
  }

  /// Toutes les étapes sont-elles `faite` ? La clôture exige en plus deux administrateurs (contrôlé par l'appelant, qui connaît les comptes).
  bool get toutesFaites => etapesInstallation.every((e) => etat(e) == EtapeEtat.faite);

  /// Combien d'étapes sont faites, sur quatre (la progression affichée).
  int get nombreFaites => etapesInstallation.where((e) => etat(e) == EtapeEtat.faite).length;

  /// Le premier compte vient d'être créé.
  EtatInstallation creer({required DateTime maintenant, required String par}) =>
      EtatInstallation(creeLe: maintenant, creePar: par, etapes: etapes, clotureLe: clotureLe, cloturePar: cloturePar, lignesVerifiees: lignesVerifiees);

  /// Marque une étape. Une étape inconnue est refusée (une faute de frappe ne doit pas passer pour une étape faite).
  EtatInstallation marquer(String etape, EtapeEtat valeur) {
    if (!etapesInstallation.contains(etape)) throw ArgumentError('Étape d’installation inconnue : $etape');
    final suite = Map<String, String>.of(etapes);
    switch (valeur) {
      case EtapeEtat.aFaire:
        suite.remove(etape);
      case EtapeEtat.reportee:
        suite[etape] = 'reportee';
      case EtapeEtat.faite:
        suite[etape] = 'faite';
    }
    return EtatInstallation(creeLe: creeLe, creePar: creePar, etapes: suite, clotureLe: clotureLe, cloturePar: cloturePar, lignesVerifiees: lignesVerifiees);
  }

  EtatInstallation cloturer({required DateTime maintenant, required String par}) =>
      EtatInstallation(creeLe: creeLe, creePar: creePar, etapes: etapes, clotureLe: maintenant, cloturePar: par, lignesVerifiees: lignesVerifiees);

  EtatInstallation verifierLigne(String ecran) =>
      EtatInstallation(creeLe: creeLe, creePar: creePar, etapes: etapes, clotureLe: clotureLe, cloturePar: cloturePar, lignesVerifiees: {...lignesVerifiees, ecran});

  Map<String, Object?> toJson() => {
        'lignes_verifiees': lignesVerifiees.toList(),
        'cree_le': creeLe?.toIso8601String(),
        'cree_par': creePar,
        'etapes': etapes,
        'cloture_le': clotureLe?.toIso8601String(),
        'cloture_par': cloturePar,
      };

  /// Relit l'état ; une clé absente (poste d'avant l'assistant) donne l'état VIDE, jamais une erreur.
  factory EtatInstallation.depuisJson(Object? j) {
    if (j is! Map) return vide;
    final e = j['etapes'];
    return EtatInstallation(
      creeLe: DateTime.tryParse('${j['cree_le'] ?? ''}'),
      creePar: j['cree_par'] as String?,
      etapes: e is Map ? {for (final k in e.keys) if (etapesInstallation.contains('$k')) '$k': '${e[k]}'} : const {},
      clotureLe: DateTime.tryParse('${j['cloture_le'] ?? ''}'),
      cloturePar: j['cloture_par'] as String?,
      lignesVerifiees: j['lignes_verifiees'] is List ? {for (final x in j['lignes_verifiees'] as List) '$x'} : const {},
    );
  }
}

/// Faut-il proposer l'assistant au démarrage ? Oui seulement si le poste n'a JAMAIS été installé ET n'a aucun compte. Un poste qui porte déjà des comptes
/// (jeu de démonstration, tests, poste d'avant l'assistant) garde son chemin : l'assistant ne le détourne jamais.
bool posteVide(EtatInstallation etat, {required int nombreComptes}) => etat.phase == PhaseInstallation.nonInstalle && nombreComptes == 0;
