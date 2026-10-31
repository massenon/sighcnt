import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

/// L'état de la session du poste. Elle est SUSPENDUE par le verrou, jamais fermée : le travail en cours reste monté sous l'écran verrouillé.
enum EtatSession { deconnectee, connectee, verrouillee }

/// La session du poste (équivalent de `S.session()` / `S.setSession()` de la maquette) et le VERROU d'inactivité (CDCT §12.2, vague 22).
///
/// CE QUE CE N'EST PAS : une authentification. La maquette obtient son jeton du serveur, qui vérifie le haché ; le poste n'a pas d'authentification
/// réelle (tâche A5 du document des limites : hachage Argon2id, sel par compte). [connecter] pose un compte RECONNU dans le jeu, sans preuve — la session
/// du poste n'est pas une barrière tant que A5 n'est pas faite, et les écrans le disent.
///
/// L'horloge est INJECTÉE : un test avance le temps (`horloge`) sans attendre quinze minutes.
class SessionPoste extends ChangeNotifier {
  SessionPoste({
    DateTime Function()? horloge,
    this.exigeConnexion = false,
    AccCompte? compte,
    Duration delai = accDelaiVerrou,
  })  : horloge = horloge ?? DateTime.now,
        verrou = AccVerrou(delai: delai),
        _compte = compte,
        _etat = (compte != null || !exigeConnexion) ? EtatSession.connectee : EtatSession.deconnectee {
    verrou.activite(this.horloge());
  }

  /// Une session déjà ouverte pour [role] (le poste de développement, `SIGH_ROLE`) : le verrou joue, la connexion n'est pas demandée.
  SessionPoste.ouverte(String role, {String? nom, DateTime Function()? horloge, Duration delai = accDelaiVerrou})
      : this(horloge: horloge, compte: AccCompte(identifiant: role, nom: nom ?? role, role: role), delai: delai);

  final DateTime Function() horloge;

  /// `true` : tant que personne ne s'est connecté, la coque ne montre que l'écran de connexion.
  final bool exigeConnexion;
  final AccVerrou verrou;
  AccCompte? _compte;
  EtatSession _etat;

  EtatSession get etat => _etat;
  AccCompte? get compte => _compte;
  String? get role => _compte?.role;

  /// L'adresse de retour posée au verrouillage (sans la consommer).
  AccRetour? get retour => verrou.retour;

  /// Ouvre la session d'un compte reconnu. Le compte à rebours repart.
  void connecter(AccCompte c) {
    _compte = c;
    _etat = EtatSession.connectee;
    verrou.abandonner();
    verrou.activite(horloge());
    notifyListeners();
  }

  /// Ferme la session (l'agent change de compte).
  void deconnecter() {
    _compte = null;
    _etat = exigeConnexion ? EtatSession.deconnectee : EtatSession.connectee;
    verrou.abandonner();
    notifyListeners();
  }

  /// Un geste de l'agent (clic, touche, défilement, mouvement) : relance le compte à rebours. Sans effet sur une session verrouillée.
  void activite() => verrou.activite(horloge());

  /// Le délai d'inactivité est-il écoulé ? Si oui, la session est SUSPENDUE et l'écran à retrouver retenu. Rend vrai quand le verrou vient de se poser.
  bool verifier(String ecranCourant, {String? onglet}) {
    if (_etat != EtatSession.connectee || !verrou.echu(horloge())) return false;
    verrou.verrouiller(horloge(), ecranCourant, onglet: onglet);
    _etat = EtatSession.verrouillee;
    notifyListeners();
    return true;
  }

  /// Le déverrouillage rend la session et CONSOMME l'adresse de retour (usage unique). `null` : retour à l'accueil du rôle.
  AccRetour? deverrouiller() {
    final r = verrou.deverrouiller(horloge());
    _etat = EtatSession.connectee;
    notifyListeners();
    return r;
  }

  /// « Se connecter avec un autre compte » : la session et l'adresse de retour disparaissent.
  void abandonner() {
    _compte = null;
    _etat = exigeConnexion ? EtatSession.deconnectee : EtatSession.connectee;
    verrou.abandonner();
    notifyListeners();
  }
}
