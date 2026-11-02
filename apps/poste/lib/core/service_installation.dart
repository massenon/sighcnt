import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import 'etat_installation.dart';
import 'identifiants.dart';
import 'parametres_poste.dart';

/// L'ASSISTANT DE PREMIÈRE INSTALLATION (PRD-POSTE-premiere-installation, PLAN étapes 2 à 8). Tient l'état d'installation du poste, le range dans ses
/// paramètres persistants, et fait les deux gestes qui touchent aux comptes : créer le premier administrateur, clore l'assistant.
///
/// Un service par magasin, comme [ServiceIdentifiants]. TANT QU'IL N'EST PAS ATTACHÉ à un stockage ([attacher]), il est inactif et le poste garde son chemin
/// d'avant (écran de connexion) : les tests et `SIGH_ASSISTANT=non` n'en sont pas détournés.
class ServiceInstallation extends ChangeNotifier {
  ServiceInstallation._(this._magasin);
  final Magasin _magasin;
  static final Expando<ServiceInstallation> _services = Expando<ServiceInstallation>('ServiceInstallation');

  static ServiceInstallation de(Magasin m) => _services[m] ??= ServiceInstallation._(m);

  StockageParametres? _stockage;
  ParametresPoste? _parametres;
  EtatInstallation _etat = EtatInstallation.vide;

  /// L'état courant de l'assistant sur CE poste.
  EtatInstallation get etat => _etat;

  /// Les paramètres du poste tels que le service les a lus (mode, relais…), `null` tant qu'il n'est pas attaché.
  ParametresPoste? get parametres => _parametres;

  bool get actif => _stockage != null;

  /// Branche le stockage des paramètres et relit l'état d'installation.
  Future<void> attacher(StockageParametres stockage, ParametresPoste parametres) async {
    _stockage = stockage;
    _parametres = parametres;
    _etat = parametres.installation;
    notifyListeners();
  }

  /// Nombre de comptes qui PEUVENT se connecter : ceux dont un mot de passe est défini. Les fiches `utilisateurs` du jeu de démonstration, sans mot de passe,
  /// ne comptent pas : elles ne permettent aucune connexion.
  int comptesConnectables() => _magasin.collection('identifiants').toutes.length;

  /// Faut-il proposer l'assistant au démarrage ? Oui si le service est actif, que le poste n'a jamais été installé et qu'aucun compte ne peut se connecter.
  bool propose() => actif && posteVide(_etat, nombreComptes: comptesConnectables());

  /// La modale « Configurations à faire » doit-elle s'offrir ? Oui tant que l'assistant est en cours.
  bool get enCours => actif && _etat.phase == PhaseInstallation.enCours;

  /// Range le nouvel état dans les paramètres du poste. Relit d'abord le fichier : l'activation de la mère y écrit aussi (mode, relais), on ne l'écrase pas.
  Future<void> poser(EtatInstallation e) async {
    final st = _stockage;
    if (st == null) throw StateError('L’assistant d’installation n’est pas attaché à un stockage.');
    final courant = (await st.lire()) ?? _parametres!;
    _parametres = courant.avec(installation: e);
    await st.ecrire(_parametres!);
    _etat = e;
    notifyListeners();
  }

  /// Relit les paramètres (après une activation de la mère qui a écrit le fichier) pour que le service voie le mode et le relais réels.
  Future<void> relire() async {
    final st = _stockage;
    if (st == null) return;
    final p = await st.lire();
    if (p != null) {
      _parametres = p;
      _etat = p.installation;
      notifyListeners();
    }
  }

  static final RegExp _identifiantValide = RegExp(r'^[a-z0-9][a-z0-9._-]{2,}$');

  /// Les règles de l'identifiant d'un compte : trois caractères au moins, minuscules, chiffres, point, tiret ; le refus est nommé.
  static String? controlerIdentifiant(String saisie) {
    final id = saisie.trim();
    if (id.isEmpty) return 'L’identifiant est obligatoire.';
    if (!_identifiantValide.hasMatch(id)) return 'Identifiant invalide : trois caractères au moins, minuscules, chiffres, point, tiret ou tiret bas (ex. prenom.nom).';
    return null;
  }

  /// Crée le PREMIER administrateur : la fiche du compte, le haché de son mot de passe (choisi par la personne, aucun mot de passe provisoire) et son code de
  /// secours. Refuse en nommant : identifiant invalide ou déjà pris, nom vide, mot de passe non conforme ou deux saisies différentes. Rien n'est écrit en cas
  /// de refus.
  Future<ResultatCreationAdmin> creerPremierAdministrateur({
    required String identifiant,
    required String nom,
    required String motDePasse,
    required String confirmation,
    required DateTime maintenant,
  }) async {
    final id = identifiant.trim();
    final refusId = controlerIdentifiant(id);
    if (refusId != null) return ResultatCreationAdmin.refus(refusId);
    if (nom.trim().isEmpty) return const ResultatCreationAdmin.refus('Le nom complet est obligatoire.');
    final utilisateurs = _magasin.collection('utilisateurs');
    if (utilisateurs.toutes.any((u) => '${u['identifiant']}' == id)) {
      return const ResultatCreationAdmin.refus('Cet identifiant existe déjà. Choisissez-en un autre.');
    }
    final refusMdp = accControlerNouveauMotDePasse(motDePasse, confirmation, identifiant: id);
    if (refusMdp != null) return ResultatCreationAdmin.refus(refusMdp);

    var rang = 0;
    for (final u in utilisateurs.toutes) {
      final n = int.tryParse('${u['id']}'.replaceFirst('USR', ''));
      if (n != null && n > rang) rang = n;
    }
    final cle = 'USR${(rang + 1).toString().padLeft(3, '0')}';
    // Le journal ne connaît jamais d'action anonyme (RG-12) : le geste est écrit au nom de la personne qui s'installe.
    _magasin.utilisateur = nom.trim();
    utilisateurs.inserer({
      'id': cle,
      'statut': 'actif',
      'identifiant': id,
      'nomComplet': nom.trim(),
      'role': 'admin',
      'service': 'Administration',
      'poste': 'Administrateur système',
      'actif': true,
      'mfa': false,
      'echecs': 0,
      'creeLe': maintenant.toIso8601String().substring(0, 10),
      'source': 'installation',
    }, prefixe: 'USR');
    final ident = ServiceIdentifiants.de(_magasin);
    await ident.definir(cle, motDePasse, par: nom.trim(), doitChanger: false, maintenant: maintenant);
    final code = await ident.genererCodeSecours(cle, par: 'Installation initiale', maintenant: maintenant);
    _magasin.journaliser('Installation initiale', 'M14', 'Poste', cle, null, {'identifiant': id});
    await poser(_etat.creer(maintenant: maintenant, par: id));
    final decision = accEvaluer(
        identifiant: id,
        utilisateurs: utilisateurs.toutes,
        rolesArchives: const {},
        libelleRole: (r) => r,
        personnel: _magasin.collection('personnel').actives,
        soignants: _magasin.collection('soignants').actives);
    return ResultatCreationAdmin.ok(decision.compte!, code);
  }
}

/// Le résultat de la création du premier administrateur : le compte et son code de secours (affiché UNE fois), ou un refus nommé.
class ResultatCreationAdmin {
  const ResultatCreationAdmin.ok(AccCompte this.compte, String this.codeSecours) : message = null;
  const ResultatCreationAdmin.refus(String this.message)
      : compte = null,
        codeSecours = null;
  final AccCompte? compte;
  final String? codeSecours;
  final String? message;
  bool get ok => compte != null;
}
