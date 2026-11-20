import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/config_poste.dart';
import '../../core/controleur_poste.dart';
import '../../core/identifiants.dart';
import '../../core/parametres_poste.dart';
import '../../donnees/magasin.dart';
import '../../mere/activation.dart';
import '../../mere/client_mere.dart';

/// Ce qu'un geste de la console rend : accompli (avec ce qui s'est passé) ou REFUSÉ (avec la cause nommée). Jamais un échec muet.
class MrcResultat {
  const MrcResultat.ok(this.message) : ok = true;
  const MrcResultat.refus(this.message) : ok = false;
  final bool ok;
  final String message;
}

/// Les sources des huit écrans : l'interface par laquelle ils lisent l'état et appellent les gestes. Injectable, pour tester sans réseau ni service
/// Windows. Par défaut, une valeur est « non disponible » avec son motif et un geste est refusé en disant POURQUOI : une source réelle ne surcharge QUE
/// ce que le moteur, le système ou la spécification fournit vraiment.
abstract class MrcSources {
  DateTime maintenant() => DateTime.now();

  // --- Ce que le moteur de la mère expose -------------------------------------------------------------------------------------------------
  Future<EtatMere> etat() => throw StateError('aucune source de l’état de la mère n’est branchée');
  Future<Supervision> supervision() => throw StateError('aucune source de supervision n’est branchée');

  // --- Service et démarrage (M-15) -----------------------------------------------------------------------------------------------------
  Future<ParametresPoste?> parametres() async => null;
  MrcValeur<bool> serviceEnMarche() => const MrcValeur.indisponible('ce poste ne pilote pas le service de la mère');
  MrcValeur<int> port() => const MrcValeur.indisponible('aucune adresse d’administration n’est configurée');
  MrcValeur<String> adresseAdmin() => const MrcValeur.indisponible('aucune adresse d’administration n’est configurée');
  MrcValeur<String> adresseEcoute() => const MrcValeur.indisponible('le moteur n’annonce pas son adresse d’écoute');
  MrcValeur<String> demarrageAutomatique() => const MrcValeur.indisponible('le service Windows et l’unité systemd ne sont pas faits (E8, installateur)');
  Future<MrcResultat> arreter() async => const MrcResultat.refus('ce poste ne pilote pas le service de la mère');
  Future<MrcResultat> redemarrer() async => const MrcResultat.refus('ce poste ne pilote pas le service de la mère');
  Future<MrcResultat> desactiver(String secretMere) async => const MrcResultat.refus('ce poste ne pilote pas l’activation du mode mère');

  // --- Base de données locale (M-16) ----------------------------------------------------------------------------------------------------
  MrcValeur<String> tailleBase() => const MrcValeur.indisponible('le moteur n’expose pas la taille de la base');
  MrcValeur<String> schemaBase() => const MrcValeur.indisponible('le moteur ne tient pas de numéro de version de schéma');
  MrcValeur<List<Map<String, Object?>>> migrations() => const MrcValeur.indisponible('le moteur ne tient pas de registre de migrations (le schéma est posé à la création)');
  MrcValeur<bool> projectionDisponible() => const MrcValeur.indisponible('le moteur Dart de la mère ne tient pas de projection relationnelle');
  Future<MrcResultat> verifierParite() async => const MrcResultat.refus(
      'la parité tables et magasin existe dans la maquette (api/parite.php) ; le moteur Dart de la mère ne tient pas de projection relationnelle, il n’y a rien à comparer');
  Future<MrcResultat> reconstruireTables() async =>
      const MrcResultat.refus('le moteur Dart de la mère ne tient pas de projection relationnelle (api/projection.php n’existe que dans la maquette)');

  // --- Réseau local (M-17) ---------------------------------------------------------------------------------------------------------------
  Future<List<String>> adressesLocales() async => const [];
  MrcValeur<String> certificatTls() => const MrcValeur.indisponible('état du certificat non connu');
  Future<MrcResultat> testerAcces(String hote, int port) async => const MrcResultat.refus('aucun test réseau n’est branché');
  Future<MrcResultat> renouvelerCertificat() async => const MrcResultat.refus('aucun certificat à renouveler');

  // --- Planificateur (M-18) -------------------------------------------------------------------------------------------------------------
  Future<MrcResultat> executerTache(String code) async => const MrcResultat.refus('ce poste n’a pas de planificateur');

  // --- Mises à jour (M-21) --------------------------------------------------------------------------------------------------------------
  MrcValeur<String> versionMere() => const MrcValeur.indisponible('la version de l’application n’est pas lue à l’exécution');
  MrcValeur<int> schemaMere() => const MrcValeur.indisponible('le moteur ne tient pas de numéro de version de schéma');
  MrcValeur<String> versionAppareil(String uuid) => const MrcValeur.indisponible('le moteur n’enregistre pas la version d’application des appareils');
  MrcValeur<int> schemaAppareil(String uuid) => const MrcValeur.indisponible('le moteur n’enregistre pas la version de schéma des appareils');
  Future<MrcResultat> planifierDeploiement() async =>
      const MrcResultat.refus('aucun mécanisme de distribution des mises à jour n’existe encore (installateur MSIX ou DEB : E8)');

  // --- Assistant de première mise en service (M-20) ---------------------------------------------------------------------------------------
  /// Les CONSTATS des étapes : `true` fait, `false` pas fait, `null` non vérifiable.
  Future<Map<String, bool?>> constats(ConfigPoste cfg, EtatMere? etat) async => {for (final e in mrcEtapes) e.id: null};

  /// Consigne la confirmation nommée d'une étape (qui, quand, quel choix) ; rien ne se consigne sans agent.
  MrcResultat consigner(String etape, {String? choix, required String par}) => const MrcResultat.refus('aucun registre de mise en service n’est branché');

  // --- Import de migration (M-22) ---------------------------------------------------------------------------------------------------------
  Future<String> lireFichier(String chemin) => throw StateError('lecture de fichier non branchée');
  Set<String> codesExistants(MrcProfilImport profil) => const {};
  List<Map<String, Object?>> lots() => const [];
  MrcResultat importer(MrcAnalyse analyse, {required String fichier, required String par}) => const MrcResultat.refus('aucun magasin n’est branché');
  MrcResultat consignerRefus(MrcAnalyse analyse, {required String fichier, required String par}) => const MrcResultat.refus('aucun magasin n’est branché');
}

/// Les sources réelles : le client du service de la mère, le contrôleur du poste (mode, activation, service) et le magasin du poste. Rien ici n'est
/// inventé : ce qu'aucune de ces sources ne fournit reste « non disponible » (voir [MrcSources]).
class MrcSourcesReelles extends MrcSources {
  MrcSourcesReelles({this.client, this.controleur, required this.magasin, DateTime Function()? horloge}) : _horloge = horloge;
  final ClientMere? client;
  final ControleurPoste? controleur;
  final Magasin magasin;
  final DateTime Function()? _horloge;

  @override
  DateTime maintenant() => (_horloge ?? magasin.horloge)();

  @override
  Future<EtatMere> etat() => (client ?? (throw StateError('le poste n’est pas relié au service de la mère'))).etat();

  @override
  Future<Supervision> supervision() => (client ?? (throw StateError('le poste n’est pas relié au service de la mère'))).supervision();

  @override
  Future<ParametresPoste?> parametres() async => controleur == null ? null : await controleur!.activation.parametres();

  @override
  MrcValeur<bool> serviceEnMarche() => controleur == null
      ? const MrcValeur.indisponible('ce poste ne pilote pas le service de la mère')
      : MrcValeur.de(controleur!.activation.service.enMarche);

  @override
  MrcValeur<int> port() => client == null || !client!.base.hasPort
      ? const MrcValeur.indisponible('aucune adresse d’administration n’est configurée')
      : MrcValeur.de(client!.base.port);

  @override
  MrcValeur<String> adresseAdmin() => client == null
      ? const MrcValeur.indisponible('aucune adresse d’administration n’est configurée')
      : MrcValeur.de('${client!.base.scheme}://${client!.base.host}${client!.base.hasPort ? ':${client!.base.port}' : ''}');

  /// Constat du code du moteur (`Mere.demarrer` lie le service à `InternetAddress.loopbackIPv4`) : un test démarre le vrai service et vérifie qu'une
  /// adresse du réseau local ne le joint pas.
  @override
  MrcValeur<String> adresseEcoute() => const MrcValeur.de('127.0.0.1 (boucle locale)');

  @override
  MrcValeur<String> certificatTls() => const MrcValeur.de('aucun : le service sert en HTTP, sans TLS');

  @override
  Future<MrcResultat> arreter() async {
    final ctl = controleur;
    if (ctl == null) return super.arreter();
    final s = ctl.activation.service;
    if (!s.enMarche) return const MrcResultat.refus('le service est déjà arrêté');
    try {
      await s.arreter();
      return const MrcResultat.ok('Service arrêté proprement. Les postes gardent leurs gestes en file locale et les renverront au redémarrage.');
    } catch (e) {
      return MrcResultat.refus('l’arrêt a échoué : $e');
    }
  }

  @override
  Future<MrcResultat> redemarrer() async {
    final ctl = controleur;
    if (ctl == null) return super.redemarrer();
    final s = ctl.activation.service;
    try {
      if (s.enMarche) await s.arreter();
    } catch (e) {
      return MrcResultat.refus('l’arrêt préalable a échoué : $e');
    }
    try {
      await s.demarrer();
      return const MrcResultat.ok('Service redémarré.');
    } catch (e) {
      return MrcResultat.refus('le service est arrêté et n’a pas pu redémarrer : $e');
    }
  }

  @override
  Future<MrcResultat> desactiver(String secretMere) async {
    final ctl = controleur;
    if (ctl == null) return super.desactiver(secretMere);
    if (secretMere.trim().isEmpty) return const MrcResultat.refus('le secret de la mère est obligatoire pour libérer la place au relais');
    try {
      await ctl.desactiver(secretMere: secretMere);
      return MrcResultat.ok(ctl.avertissement ?? 'Mode mère désactivé : le service est arrêté, les données sont conservées. Ce poste redevient fileul.');
    } on ActivationRefusee catch (e) {
      return MrcResultat.refus(e.motif);
    } catch (e) {
      return MrcResultat.refus('$e');
    }
  }

  @override
  Future<List<String>> adressesLocales() async {
    try {
      final l = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      return [for (final i in l) for (final a in i.addresses) a.address];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<MrcResultat> testerAcces(String hote, int port) async {
    try {
      final s = await Socket.connect(hote, port, timeout: const Duration(seconds: 3));
      s.destroy();
      return MrcResultat.ok('$hote:$port répond depuis ce poste.');
    } catch (e) {
      return MrcResultat.refus('$hote:$port ne répond pas depuis ce poste ($e)');
    }
  }

  @override
  Future<MrcResultat> executerTache(String code) async => const MrcResultat.refus(
      'le planificateur est le service api/cron.php de la maquette ; le moteur Dart de la mère n’en a pas encore (E1, tâche T19). Rien n’a été exécuté');

  @override
  Future<MrcResultat> renouvelerCertificat() async =>
      const MrcResultat.refus('aucun certificat à renouveler : le service n’utilise pas TLS (le moteur sert en HTTP)');

  @override
  Future<Map<String, bool?>> constats(ConfigPoste cfg, EtatMere? etat) async {
    final reg = magasin.collection('miseEnService');
    bool consigne(String id) => reg.actives.any((f) => f['etape'] == id);
    final ids = ServiceIdentifiants.de(magasin);
    final admins = magasin.collection('utilisateurs').actives.where((u) => u['role'] == 'admin' && u['actif'] != false);
    final svc = serviceEnMarche();
    return {
      // Aucune donnée du poste ne dit que l'identité a été saisie : « fait » uniquement sur confirmation consignée.
      'identite': consigne('identite') ? true : null,
      'administrateur': admins.any((u) => ids.possede('${u['id']}')),
      'jeu_depart': consigne('jeu_depart'),
      'activation': cfg.estMere ? (svc.disponible ? svc.valeur : null) : false,
      'appairage': etat?.appareils.any((a) => !a.revoque),
    };
  }

  @override
  MrcResultat consigner(String etape, {String? choix, required String par}) {
    if (mrcEtape(etape) == null) return MrcResultat.refus('étape inconnue : $etape');
    final reg = magasin.collection('miseEnService');
    final existante = reg.actives.where((f) => f['etape'] == etape).firstOrNull;
    final fiche = {
      'etape': etape,
      if (choix != null) 'choix': choix,
      'consigneePar': par,
      'consigneeLe': maintenant().toIso8601String(),
    };
    if (existante != null) {
      reg.mettreAJour(existante['id'], fiche);
    } else {
      reg.inserer({'id': 'MES-$etape', ...fiche}, prefixe: 'MES');
    }
    return MrcResultat.ok('Étape consignée par $par.');
  }

  @override
  Future<String> lireFichier(String chemin) => File(chemin).readAsString();

  @override
  Set<String> codesExistants(MrcProfilImport profil) =>
      {for (final f in magasin.collection(profil.collection).toutes) if (f['code'] != null) '${f['code']}'};

  @override
  List<Map<String, Object?>> lots() {
    final propres = magasin.collection('lotsImport').actives;
    final connus = {for (final l in propres) '${l['reference']}'};
    // Les lots REPRIS à la migration avant cet écran (article déjà marqué `lotImport` : l'inventaire SAGE du 15/07/2026) se relisent sur les articles.
    final repris = <String, List<Fiche>>{};
    for (final f in magasin.collection('produits').actives) {
      final lot = f['lotImport'];
      if (lot == null || connus.contains('$lot')) continue;
      (repris['$lot'] ??= []).add(f);
    }
    return [
      ...propres,
      for (final e in repris.entries)
        {
          'reference': e.key,
          'source': e.value.first['source'] ?? 'non disponible',
          'date': e.value.first['dateImport'],
          'lignes': e.value.length,
          'rejetees': 0,
          'validePar': e.value.first['validePar'],
          'etat': 'importé',
        }
    ];
  }

  /// Consigne un fichier REFUSÉ : une fiche de lot « refusé » (qui, quand, combien de lignes fautives) ; aucune donnée métier n'est écrite.
  @override
  MrcResultat consignerRefus(MrcAnalyse analyse, {required String fichier, required String par}) {
    final date = maintenant();
    final lots = magasin.collection('lotsImport');
    final reference = mrcReferenceLot(analyse.profil, date, [for (final f in lots.toutes) '${f['reference']}']);
    lots.inserer({
      'id': reference,
      'reference': reference,
      'profil': analyse.profil.id,
      'source': analyse.profil.source,
      'fichier': fichier,
      'date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'lignes': 0,
      'rejetees': analyse.nbRefusees,
      'validePar': par,
      'etat': 'refusé',
    }, prefixe: 'LOT');
    return MrcResultat.ok('Refus consigné : ${analyse.nbRefusees} ligne(s) fautive(s), rien n’a été écrit.');
  }

  /// Écrit un lot ACCEPTÉ d'un seul geste : toutes les fiches ou aucune. Le fichier a déjà été analysé en entier ; l'écriture est un remplacement unique de la
  /// collection (impossible à moitié), suivi d'UNE entrée de journal (RG-12) et de la fiche du lot.
  @override
  MrcResultat importer(MrcAnalyse analyse, {required String fichier, required String par}) {
    if (!analyse.accepte) return const MrcResultat.refus('le fichier n’a pas été accepté en entier : rien n’est écrit');
    final profil = analyse.profil;
    final date = maintenant();
    final lots = magasin.collection('lotsImport');
    final reference = mrcReferenceLot(profil, date, [for (final f in lots.toutes) '${f['reference']}']);
    final jour = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final fiches = mrcFichesProduits(analyse, lot: reference, date: jour, validePar: par);
    final cible = magasin.collection(profil.collection);
    var rang = 0;
    for (final f in cible.toutes) {
      final n = int.tryParse('${f['id']}'.replaceAll(RegExp(r'\D'), ''));
      if (n != null && n > rang) rang = n;
    }
    final nouvelles = [
      for (final f in fiches) {'id': 'PRD${(++rang).toString().padLeft(4, '0')}', ...f}
    ];
    cible.remplacerContenu([...nouvelles, ...cible.toutes]);
    magasin.journaliser('Import', 'M6', profil.collection, reference, null,
        {'lignes': fiches.length, 'source': profil.source, 'fichier': fichier, 'validePar': par});
    lots.inserer({
      'id': reference,
      'reference': reference,
      'profil': profil.id,
      'source': profil.source,
      'fichier': fichier,
      'date': jour,
      'lignes': fiches.length,
      'rejetees': 0,
      'validePar': par,
      'etat': 'importé',
    }, prefixe: 'LOT');
    return MrcResultat.ok('Lot $reference importé : ${fiches.length} ligne(s) dans « ${profil.collection} », validé par $par.');
  }
}
