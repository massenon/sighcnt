import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import '../mere/activation.dart' show ActivationRefusee;
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
    // Après la clôture, un administrateur ne s'archive pas s'il laisse moins de deux administrateurs actifs : le moteur le refuse, pas seulement l'écran.
    if (!_gardePosee) {
      _gardePosee = true;
      final refus = 'laisserait %d administrateur actif : il en faut au moins ${ServiceInstallation.administrateursRequis}. Créez ou restaurez un autre administrateur d’abord.';
      String? motif(String idCompte) {
        final restants = administrateursActifs(sauf: idCompte);
        return restants >= administrateursRequis ? null : refus.replaceFirst('%d', '$restants');
      }

      // Après la clôture, un administrateur ne PERD pas son rôle, son activité ni son mot de passe s'il laisse moins de deux administrateurs actifs : le moteur
      // le refuse (archivage, changement de rôle, désactivation, blocage), pas seulement l'écran.
      _magasin.collection('utilisateurs').garder((op, f) {
        if (_etat.phase != PhaseInstallation.cloturee) return null;
        final ancien = _magasin.collection('utilisateurs').parId(f['id']) ?? f;
        if ('${ancien['role']}' != 'admin') return null;
        final quitte = switch (op) {
          'archiver' => true,
          'modifier' => '${f['role']}' != 'admin' || '${f['statut'] ?? 'actif'}' != 'actif' || f['actif'] == false || f['bloque'] == true,
          _ => false,
        };
        if (!quitte) return null;
        final m = motif('${ancien['id']}');
        return m == null ? null : 'Cette opération $m';
      });
      // Retirer son mot de passe (archiver son haché) revient à fermer le compte.
      _magasin.collection('identifiants').garder((op, f) {
        if (op != 'archiver' || _etat.phase != PhaseInstallation.cloturee) return null;
        final compte = _magasin.collection('utilisateurs').parId(f['utilisateurId'] ?? f['id']);
        if (compte == null || '${compte['role']}' != 'admin') return null;
        final m = motif('${compte['id']}');
        return m == null ? null : 'Retirer ce mot de passe $m';
      });
    }
    notifyListeners();
  }

  bool _gardePosee = false;

  /// Le geste réel d'activation de la mère (posé par `main`, qui détient le contrôleur du poste). `null` : l'activation n'est pas disponible sur ce poste.
  Future<void> Function({required String relais, required String secretMere, required String cleClinique, String? nomPoste})? activerMere;

  /// Le geste réel de rattachement (posé par `main`, qui détient le moteur de synchronisation) : redirige vers la mère et consomme le code d'appairage.
  Future<void> Function({required String adresse, required String code})? rattacherMoteur;

  /// Appelé une fois le poste rattaché : `main` y démarre l'application de la configuration reçue.
  void Function(String adresse)? surRattache;

  static final RegExp _adresse = RegExp(r'^https?://[^\s/:]+(:\d{1,5})?(/.*)?$');

  /// Les règles de l'adresse de la mère : `http://hôte:port` (ex. `http://192.168.1.10:9000`).
  static String? controlerAdresse(String saisie) {
    final a = saisie.trim();
    if (a.isEmpty) return 'L’adresse de la mère est obligatoire.';
    if (!_adresse.hasMatch(a)) return 'Adresse invalide : saisissez http://adresse:port (ex. http://192.168.1.10:9000).';
    return null;
  }

  /// REJOINDRE UNE CLINIQUE : redirige le moteur vers la mère, consomme le code d'appairage, range l'adresse et marque le poste RATTACHÉ. L'assistant n'a
  /// plus rien à proposer sur un poste rattaché : il est clos d'office. Rend le refus NOMMÉ (code expiré, déjà utilisé, mère injoignable…), ou `null`.
  Future<String?> rejoindre({required String adresse, required String code, required DateTime maintenant}) async {
    final refusAdresse = controlerAdresse(adresse);
    if (refusAdresse != null) return refusAdresse;
    if (code.trim().isEmpty) return 'Le code d’appairage est obligatoire.';
    final geste = rattacherMoteur;
    if (geste == null) return 'Le rattachement à une clinique n’est pas disponible sur ce poste.';
    final a = adresse.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      await geste(adresse: a, code: code.trim().toUpperCase());
    } on StateError catch (e) {
      return _motifAppairage(e.message);
    } catch (e) {
      return 'La mère n’a pas répondu à $a (${e.runtimeType}). Vérifiez l’adresse, le réseau et que la mère est démarrée.';
    }
    final st = _stockage;
    if (st != null) {
      final courant = (await st.lire()) ?? _parametres!;
      final clos = EtatInstallation.vide.creer(maintenant: maintenant, par: 'Rattachement').cloturer(maintenant: maintenant, par: 'Rattachement');
      _parametres = courant.avec(adresseMere: a, rejoint: true, installation: clos);
      await st.ecrire(_parametres!);
      _etat = clos;
    }
    _magasin.journaliser('Poste rattaché à la clinique', 'M14', 'Poste', a, null, null);
    surRattache?.call(a);
    notifyListeners();
    return null;
  }

  static String _motifAppairage(String brut) {
    final code = brut.split(' — ').first.trim();
    return switch (code) {
      'code_expire' => 'Ce code d’appairage a expiré (15 minutes). Demandez-en un nouveau sur la mère.',
      'code_utilise' => 'Ce code d’appairage a déjà servi. Demandez-en un nouveau sur la mère.',
      'code_invalide' || 'code_inconnu' => 'Code d’appairage inconnu. Vérifiez-le ou demandez-en un nouveau sur la mère.',
      _ => 'La mère a refusé l’appairage : $brut',
    };
  }

  /// Ce poste a-t-il rejoint une clinique ? (fileul rattaché : ses configurations sont reprises de la mère, en lecture seule.)
  bool get rattache => _parametres?.rejoint ?? false;

  /// Nombre d'administrateurs que la clôture exige (arbitrage de la Direction, 02/11/2026).
  static const int administrateursRequis = 2;

  /// Les administrateurs ACTIFS qui peuvent se connecter (un mot de passe défini), hors [sauf].
  int administrateursActifs({String? sauf}) {
    final ident = ServiceIdentifiants.de(_magasin);
    return _magasin
        .collection('utilisateurs')
        .actives
        .where((u) => '${u['role']}' == 'admin' && '${u['statut'] ?? 'actif'}' == 'actif' && '${u['id']}' != sauf && ident.possede('${u['id']}'))
        .length;
  }

  /// Pourquoi l'assistant ne peut pas encore être clos, ou `null` s'il peut l'être.
  String? motifRefusCloture() {
    final n = administrateursActifs();
    if (n < administrateursRequis) {
      return 'Un second administrateur est obligatoire : $n administrateur actif pour l’instant. Créez-le à « Utilisateurs », puis définissez-lui un mot de passe.';
    }
    if (!_etat.toutesFaites) return 'Il reste des étapes à faire (${_etat.nombreFaites} sur ${etapesInstallation.length}).';
    return null;
  }

  /// Clôt l'assistant : refusé en nommant tant qu'il manque une étape ou un second administrateur. Journalisé (RG-12).
  Future<String?> cloturer({required String par, required DateTime maintenant}) async {
    final refus = motifRefusCloture();
    if (refus != null) return refus;
    _magasin.journaliser('Assistant d’installation clos', 'M14', 'Poste', par, null, {'administrateurs': administrateursActifs()});
    await poser(_etat.cloturer(maintenant: maintenant, par: par));
    return null;
  }

  /// Active la mère (étape A) par le geste réel du poste, puis range le résultat. Rend le refus NOMMÉ, ou `null` si c'est fait. Un relais injoignable laisse
  /// l'étape ouverte : l'appelant propose alors de la REPORTER ([reporterMere]).
  Future<ActivationRefusee?> activer({required String relais, required String secretMere, required String cleClinique, String? nomPoste}) async {
    final geste = activerMere;
    if (geste == null) return ActivationRefusee('activation_indisponible', 'L’activation de la mère n’est pas disponible sur ce poste.');
    try {
      await geste(relais: relais, secretMere: secretMere, cleClinique: cleClinique, nomPoste: nomPoste);
    } on ActivationRefusee catch (e) {
      return e;
    }
    _magasin.journaliser('Mère activée', 'M14', 'Poste', _parametres?.uuidPoste ?? '', null, {'relais': relais});
    await relire();
    await poser(_etat.marquer('mere', EtapeEtat.faite));
    return null;
  }

  /// Reporte l'étape A : le poste travaille en autonome, rien n'est diffusé tant que la mère n'est pas activée.
  Future<void> reporterMere() async {
    _magasin.journaliser('Activation de la mère reportée', 'M14', 'Poste', _parametres?.uuidPoste ?? '', null, null);
    await poser(_etat.marquer('mere', EtapeEtat.reportee));
  }


  /// Combien d'appareils (postes fileuls, mobiles) sont appairés à la mère : posé par `main` (la console de la mère le sait). `null` : non disponible.
  Future<int> Function()? compterAppareils;

  /// Le dernier nombre d'appareils appairés relevé par la détection (`null` : jamais relevé).
  int? appareilsAppaires;

  /// Les collections que chaque écran de configuration écrit : l'`entite` de ses entrées de journal. Une configuration est « faite » quand une écriture
  /// la concerne depuis l'installation, ou quand l'administrateur l'a vérifiée sans rien y changer. EXCEPTION ([configurationsAValider]) : l'identité
  /// légale et les obligations fiscales se VALIDENT (Direction, 06/11/2026) ; leur ligne n'est faite que si TOUTES leurs fiches actives portent `valideLe`.
  static const Map<String, Set<String>> collectionsDesConfigurations = {
    'cfg-entetes': {'ressources'},
    'cfg-fiscalite': {'identiteLegale'},
    'cfg-modules': {'modulesActifs'},
    'cfg-tarifs': {'actes', 'analyses', 'catalogueTarifs', 'produits', 'typesPiece'},
    'cfg-natures-facture': {'naturesFacture'},
    'cfg-comptabilite': {'obligationsFiscales'},
    'mecef-config': {'reglages'},
    'm14-roles': {'rbac'},
  };

  /// Les écrans dont la ligne se coche PAR VALIDATION seulement : ni une écriture au journal, ni la case « vérifié » ne comptent.
  static const Set<String> configurationsAValider = {'cfg-fiscalite', 'cfg-comptabilite'};

  /// La configuration d'un écran à valider est-elle validée ? Toutes les fiches actives de sa collection portent `valideLe` (une fiche sans validation,
  /// ou une collection vide, rend faux : rien n'a été vérifié par la Direction, la DAF ou l'administrateur).
  bool configurationValidee(String ecran) {
    final cols = collectionsDesConfigurations[ecran] ?? const <String>{};
    for (final n in cols) {
      final actives = _magasin.collection(n).actives;
      if (actives.isEmpty) return false;
      if (actives.any((f) => f['valideLe'] == null || '${f['valideLe']}'.trim().isEmpty)) return false;
    }
    return cols.isNotEmpty;
  }

  /// Pour chaque écran de configuration : a-t-il été configuré (écriture au journal depuis l'installation) ou vérifié ? Pour un écran à valider, `ecrit`
  /// vaut « validé » et `verifie` reste faux quoi qu'ait coché l'administrateur.
  Map<String, ({bool ecrit, bool verifie})> lignesConfiguration() {
    final depuis = _etat.creeLe;
    final ecrites = <String>{};
    for (final a in _magasin.collection('audit').toutes) {
      if (!const {'Création', 'Modification', 'Archivage', 'Restauration'}.contains('${a['action']}')) continue;
      final d = DateTime.tryParse('${a['dateHeure']}');
      if (depuis != null && d != null && d.isBefore(depuis)) continue;
      ecrites.add('${a['entite']}');
    }
    return {
      for (final e in collectionsDesConfigurations.entries)
        e.key: configurationsAValider.contains(e.key)
            ? (ecrit: configurationValidee(e.key), verifie: false)
            : (ecrit: e.value.any(ecrites.contains), verifie: _etat.lignesVerifiees.contains(e.key)),
    };
  }

  /// DÉTECTE les étapes faites, sans que l'administrateur les coche : configurations (toutes écrites ou vérifiées), comptes (deux administrateurs ou plus),
  /// appairages (au moins un appareil appairé à la mère). Une détection ne fait que MARQUER « faite » : une étape rouverte à la main reste rouverte jusqu'à
  /// ce que la détection la revoie vraie. Rien n'est détecté tant que la mère n'est pas réglée (les autres étapes sont verrouillées).
  Future<void> detecter() async {
    if (!enCours || !_etat.mereReglee) return;
    var e = _etat;
    final lignes = lignesConfiguration();
    if (lignes.values.every((l) => l.ecrit || l.verifie)) e = e.marquer('configurations', EtapeEtat.faite);
    if (administrateursActifs() >= administrateursRequis) e = e.marquer('comptes', EtapeEtat.faite);
    final compter = compterAppareils;
    if (compter != null) {
      try {
        appareilsAppaires = await compter();
        if (appareilsAppaires! > 0) e = e.marquer('appairages', EtapeEtat.faite);
      } catch (_) {
        // La console de la mère ne répond pas : l'étape reste ce qu'elle était.
      }
    }
    if (e.etapes.toString() != _etat.etapes.toString()) {
      await poser(e);
    } else {
      notifyListeners();
    }
  }

  /// L'administrateur a ouvert un écran de configuration et n'a rien à y changer.
  Future<void> verifierConfiguration(String ecran) async {
    await poser(_etat.verifierLigne(ecran));
    await detecter();
  }

  /// Marque une étape comme faite (ou la rouvre).
  Future<void> marquer(String etape, EtapeEtat valeur) => poser(_etat.marquer(etape, valeur));

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
