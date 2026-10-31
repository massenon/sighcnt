/// Écrans d'accès (AUTH) — le VERROUILLAGE DE SESSION après inactivité (CDCT §12.2, vague 22 de la maquette).
///
/// Deux exigences, dont la seconde rend le dispositif acceptable : la session est SUSPENDUE, pas fermée — on ne déconnecte pas quelqu'un qui s'est
/// absenté deux minutes de trop ; et au déverrouillage l'agent RETROUVE l'écran qu'il avait, à l'onglet près. L'adresse de retour est à USAGE UNIQUE :
/// consommée par le déverrouillage, elle ne renvoie pas au hasard au rechargement suivant. Machine à états pure : l'horloge est passée en argument, un
/// test avance le temps sans attendre.
library;

/// Quinze minutes (`VERROU_DELAI_DEFAUT` de `app.js`).
const Duration accDelaiVerrou = Duration(minutes: 15);

/// Où ramener l'agent : l'écran et, s'il y en avait un, l'onglet (`#onglet=…`).
class AccRetour {
  const AccRetour(this.ecran, [this.onglet]);
  final String ecran;
  final String? onglet;

  /// L'adresse telle que la maquette la pose (`m2-agenda.php#onglet=semaine`).
  String adresse([String ext = 'php']) => '$ecran.$ext${onglet == null ? '' : '#onglet=$onglet'}';

  @override
  bool operator ==(Object o) => o is AccRetour && o.ecran == ecran && o.onglet == onglet;
  @override
  int get hashCode => Object.hash(ecran, onglet);
}

/// L'adresse de retour d'une PAGE → son écran. L'extension a changé le 23/09/2026 : on accepte les deux, un verrou posé avant le changement doit
/// encore ramener l'agent à son écran.
AccRetour? accRetourDepuisAdresse(String? adresse) {
  if (adresse == null || adresse.isEmpty) return null;
  final parties = adresse.split('#');
  final id = parties.first.replaceFirst(RegExp(r'\.(php|html)$'), '');
  if (id.isEmpty) return null;
  final m = RegExp(r'onglet=([^&]+)').firstMatch(parties.length > 1 ? parties[1] : '');
  return AccRetour(id, m?.group(1));
}

class AccVerrou {
  AccVerrou({this.delai = accDelaiVerrou});
  final Duration delai;
  DateTime? _derniere;
  AccRetour? _retour;
  bool _verrouille = false;

  bool get verrouille => _verrouille;

  /// L'adresse de retour posée au verrouillage, sans la consommer.
  AccRetour? get retour => _retour;

  /// Un geste de l'agent (clic, touche, défilement) relance le compte à rebours.
  void activite(DateTime maintenant) {
    if (!_verrouille) _derniere = maintenant;
  }

  /// Le délai est-il écoulé ? Strictement : à quinze minutes pile, l'écran n'est pas encore verrouillé (le minuteur de la maquette tire APRÈS le délai).
  bool echu(DateTime maintenant) => !_verrouille && _derniere != null && maintenant.difference(_derniere!) > delai;

  /// Suspend la session et retient l'écran à retrouver.
  void verrouiller(DateTime maintenant, String ecran, {String? onglet}) {
    _verrouille = true;
    _retour = AccRetour(ecran, onglet);
  }

  /// Le déverrouillage CONSOMME l'adresse de retour (usage unique) et rend la main. `null` : pas d'adresse, retour à l'accueil du rôle.
  AccRetour? deverrouiller(DateTime maintenant) {
    final r = _retour;
    _retour = null;
    _verrouille = false;
    _derniere = maintenant;
    return r;
  }

  /// « Se connecter avec un autre compte » : la session et l'adresse de retour disparaissent.
  void abandonner() {
    _retour = null;
    _verrouille = false;
    _derniere = null;
  }
}

/// Le message de l'écran verrouillé : ce que l'agent va retrouver (lever l'inquiétude de perdre la saisie en cours est la première raison de ne pas
/// désactiver le verrouillage). `libelle` : l'intitulé de l'écran au manifeste ; `null` (adresse inconnue) = pas de message.
String? accMessageRetour(String? libelle) => libelle == null ? null : 'Au déverrouillage, vous reviendrez sur « $libelle ».';

const String accTitreRetour = 'Votre session est suspendue, pas fermée.';

String accSousTitreVerrou(Duration delai) =>
    'Verrouillage automatique après ${(delai.inSeconds / 60).round()} minutes d’inactivité, sur les postes partagés — accueil et caisse (CDCT §12.2).';
