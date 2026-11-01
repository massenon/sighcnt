import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

/// L'état de la session du poste. Elle est SUSPENDUE par le verrou, jamais fermée : le travail en cours reste monté sous l'écran verrouillé.
enum EtatSession { deconnectee, connectee, verrouillee }

/// La session du poste (équivalent de `S.session()` / `S.setSession()` de la maquette) et le VERROU d'inactivité (CDCT §12.2, vague 22).
///
/// CE QUE CE N'EST PAS : le contrôle du mot de passe. [connecter] pose un compte DÉJÀ vérifié : la preuve (haché Argon2id, verrou après échecs, A5) est
/// faite avant, par `ServiceIdentifiants.verifier`. Le compte porte l'agent NOMINATIF (A1) : identifiant, matricule, fonction, secteur.
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

  /// La fiche de CETTE session au registre (`sessionsUtilisateur`), posée à la connexion ; `null` pour un poste sans session nominative.
  String? sessionId;

  /// Posé à la connexion : dit si la fiche de la session a été CLOTURÉE au registre (par l'administrateur, de ce poste ou d'un autre). Contrôlé au prochain
  /// geste de l'agent ; une session clôturée ne se rouvre pas.
  bool Function(String sessionId)? estCloturee;

  /// Posé à la connexion : le verrou suspend / reprend la fiche de la session au registre (`active` / `suspendue`).
  void Function(String sessionId, String etat)? surEtat;

  /// Pourquoi la session s'est fermée d'elle-même (`'cloturee'`) : l'écran de connexion le DIT. `null` après une déconnexion voulue.
  String? motifFermeture;

  DateTime? _dernierControle;

  EtatSession get etat => _etat;
  AccCompte? get compte => _compte;
  String? get role => _compte?.role;

  /// L'agent NOMINATIF de la session (A1) : celui du compte reconnu ; pour un compte construit à la main (poste de développement, tests), l'agent de
  /// démonstration de son rôle, nommé comme le compte. `null` tant que personne n'est connecté.
  Agent? get agent {
    final c = _compte;
    if (c == null) return null;
    return c.agent ?? agentDemonstration(c.role, nom: c.nom);
  }

  /// L'adresse de retour posée au verrouillage (sans la consommer).
  AccRetour? get retour => verrou.retour;

  /// Ouvre la session d'un compte reconnu. Le compte à rebours repart.
  void connecter(AccCompte c) {
    _compte = c;
    _etat = EtatSession.connectee;
    verrou.abandonner();
    verrou.activite(horloge());
    motifFermeture = null;
    notifyListeners();
  }

  /// Ferme la session (l'agent change de compte).
  void deconnecter() {
    sessionId = null;
    estCloturee = null;
    surEtat = null;
    motifFermeture = null;
    _compte = null;
    _etat = exigeConnexion ? EtatSession.deconnectee : EtatSession.connectee;
    verrou.abandonner();
    notifyListeners();
  }

  /// Un geste de l'agent (clic, touche, défilement, mouvement) : relance le compte à rebours. Sans effet sur une session verrouillée.
  /// C'est aussi le PROCHAIN GESTE où une clôture se constate : la session clôturée ferme le poste (contrôle au plus deux fois par seconde).
  void activite() {
    verrou.activite(horloge());
    verifierCloture();
  }

  /// La session de ce poste a-t-elle été clôturée au registre ? Si oui : elle se ferme, le poste retombe sur la connexion et dit pourquoi. Rend vrai quand
  /// la fermeture vient d'avoir lieu.
  bool verifierCloture({bool force = false}) {
    final id = sessionId;
    final test = estCloturee;
    if (id == null || test == null || _compte == null) return false;
    final maintenant = horloge();
    final dernier = _dernierControle;
    if (!force && dernier != null && maintenant.difference(dernier).inMilliseconds < 500) return false;
    _dernierControle = maintenant;
    if (!test(id)) return false;
    fermerParCloture();
    return true;
  }

  /// Ferme la session parce qu'elle a été clôturée : l'agent se reconnecte, et c'est une AUTRE session.
  void fermerParCloture() {
    deconnecter();
    motifFermeture = 'cloturee';
    notifyListeners();
  }

  /// Le délai d'inactivité est-il écoulé ? Si oui, la session est SUSPENDUE et l'écran à retrouver retenu. Rend vrai quand le verrou vient de se poser.
  bool verifier(String ecranCourant, {String? onglet}) {
    if (_etat != EtatSession.connectee || !verrou.echu(horloge())) return false;
    verrou.verrouiller(horloge(), ecranCourant, onglet: onglet);
    _etat = EtatSession.verrouillee;
    if (sessionId != null) surEtat?.call(sessionId!, 'suspendue');
    notifyListeners();
    return true;
  }

  /// « Verrouiller l'écran » demandé par l'agent (menu du profil) : la session est SUSPENDUE sans attendre le délai, l'écran retenu pour le retour. Rend vrai
  /// quand le verrou vient de se poser ; sans effet si la session n'est pas ouverte.
  bool verrouillerMaintenant(String ecranCourant, {String? onglet}) {
    if (_etat != EtatSession.connectee) return false;
    verrou.verrouiller(horloge(), ecranCourant, onglet: onglet);
    _etat = EtatSession.verrouillee;
    if (sessionId != null) surEtat?.call(sessionId!, 'suspendue');
    notifyListeners();
    return true;
  }

  /// Le déverrouillage rend la session et CONSOMME l'adresse de retour (usage unique). `null` : retour à l'accueil du rôle.
  AccRetour? deverrouiller() {
    // Une session clôturée pendant le verrouillage ne se reprend pas : elle se ferme, l'agent se reconnecte.
    if (verifierCloture(force: true)) return null;
    final r = verrou.deverrouiller(horloge());
    _etat = EtatSession.connectee;
    if (sessionId != null) surEtat?.call(sessionId!, 'active');
    notifyListeners();
    return r;
  }

  /// « Se connecter avec un autre compte » : la session et l'adresse de retour disparaissent.
  void abandonner() {
    sessionId = null;
    estCloturee = null;
    surEtat = null;
    _compte = null;
    _etat = exigeConnexion ? EtatSession.deconnectee : EtatSession.connectee;
    verrou.abandonner();
    notifyListeners();
  }
}
