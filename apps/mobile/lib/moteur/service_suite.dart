/// La SUITE du mobile : visite prénatale (CPN), visite post-natale (CPoN), surveillance mère-bébé, orientation de la réception, lot de tournée.
///
/// Dart pur, comme `service_soignant.dart` (qu'il n'altère pas : il s'en sert). Les règles sont dans `packages/domaine` (`mob_suite.dart`) ; ce service
/// LIT le lot, REFAIT le contrôle d'habilitation au moteur (un bouton absent ne protège rien), puis écrit UNE opération `creer` par geste, jamais une
/// suppression (RG-14), toujours sous un agent nommé (RG-12).
library;

import 'package:sigh_domaine/sigh_domaine.dart';

import 'service_soignant.dart';

/// Ce que le moteur réel offre en plus de [MoteurMobile] : la source du service, l'agent, l'identité de l'appareil, le rafraîchissement et la
/// réinitialisation de l'appairage. Une interface à part : la changer ne touche ni le moteur du soignant ni ses faux de test.
abstract class ExtensionsMobile {
  SourceMobile get source;

  /// L'agent nommé à l'appairage (réception de secours comprise : RG-12).
  String get agent;

  /// L'identifiant de l'appareil connu de la mère (`uuid`), s'il est joignable.
  Future<String?> appareil();

  /// Relit l'état du moteur (lot, file d'envoi, refus).
  Future<void> actualiser();

  /// Retire l'appairage de ce téléphone. Les saisies non parties restent dans la file locale : le refus de [mobControlerReinitialisation] protège ce cas.
  Future<void> reinitialiserAppairage();
}

class ServiceSuite {
  ServiceSuite(this.source, {required this.profil, required this.agent, this.fonction = '', DateTime Function()? maintenant, this.soignant})
      : _maintenant = maintenant ?? DateTime.now;

  /// Le service d'un soignant : mêmes source, session et horloge que [ServiceSoignant] (rien n'est lu deux fois différemment).
  factory ServiceSuite.depuisSoignant(ServiceSoignant s) => ServiceSuite(s.source,
      profil: mobProfilSimulateur(s.session.fonction), agent: s.session.agent, fonction: s.session.fonction, maintenant: () => s.maintenant, soignant: s);

  /// Le service de la réception de secours.
  factory ServiceSuite.reception(ExtensionsMobile ext, {DateTime Function()? maintenant}) =>
      ServiceSuite(ext.source, profil: 'reception', agent: ext.agent, maintenant: maintenant);

  final SourceMobile source;

  /// Le profil du simulateur : `soignant`, `medecin`, `sagefemme` ou `reception`.
  final String profil;
  final String agent, fonction;
  final ServiceSoignant? soignant;
  final DateTime Function() _maintenant;

  DateTime get maintenant => _maintenant();

  /// Une commande interdite est ABSENTE : l'interface ne dessine que ce que ce profil ouvre.
  bool peut(String ecran) => mobEcranOuvertAuProfil(profil, ecran);

  // --- lecture ------------------------------------------------------------------------------------------------------------------------------

  /// L'âge du patient du lot (la CPN signale l'âge à risque) ; refuse un patient hors lot en le nommant (`PATIENT_HORS_LOT`).
  Future<int?> ageDe(String patientId) async => (await soignant!.dossier(patientId)).resume.age;

  /// Le nom du patient, pour le sous-titre de l'écran.
  Future<String> nomDe(String patientId) async => (await soignant!.dossier(patientId)).resume.nom;

  /// Les dossiers ouverts à l'accueil de secours (patients créés par une réception de secours), du plus récent au plus ancien.
  Future<List<FichePatient>> dossiersOuverts() async {
    final l = [
      for (final x in await source.liste('patients'))
        if (!x.archive && x.data['origine'] == 'reception_secours') FichePatient(id: x.id, champs: x.data)
    ];
    return l.reversed.toList();
  }

  /// Le lot : nombre de dossiers et fin de validité, vus à l'instant.
  Future<MobLotVue> lot() async {
    final n = soignant == null ? 0 : (await soignant!.patients()).length;
    return mobLotVue(expire: await source.lotExpire(), dossiers: n, maintenant: maintenant);
  }

  // --- écriture : un geste = une opération ---------------------------------------------------------------------------------------------------

  Future<Map<String, Object?>> _preparerClinique(String ecran, String patientId) async {
    mobControlerEcran(profil, ecran);
    mobControlerActeur(agent);
    mobControlerLot(await source.lotExpire(), maintenant);
    return (await soignant!.dossier(patientId)).fiche;
  }

  Future<String> enregistrerCpn(String patientId, Map<String, String> saisie) async {
    final p = await _preparerClinique('cpn', patientId);
    return source.creer(mobCollectionCpn, mobChampsCpn(patient: p, patientId: patientId, saisie: saisie, acteur: agent, fonction: fonction, maintenant: maintenant));
  }

  Future<String> enregistrerCpon(String patientId, Map<String, String> saisie) async {
    final p = await _preparerClinique('cpon', patientId);
    return source.creer(mobCollectionCpon, mobChampsCpon(patient: p, patientId: patientId, saisie: saisie, acteur: agent, fonction: fonction, maintenant: maintenant));
  }

  Future<String> enregistrerSurveillance(String patientId, Map<String, String> saisie) async {
    final p = await _preparerClinique('surveillance', patientId);
    return source.creer(mobCollectionSurveillance,
        mobChampsSurveillance(patient: p, patientId: patientId, saisie: saisie, acteur: agent, fonction: fonction, maintenant: maintenant));
  }

  /// Oriente un patient de l'accueil de secours. Le dossier doit avoir été ouvert à l'accueil de secours ; la réception n'a pas de lot qui expire.
  Future<String> orienter(String dossierId, {required String destination, required String degre}) async {
    mobControlerEcran(profil, 'orientation');
    mobControlerActeur(agent);
    final dossiers = await dossiersOuverts();
    mobControlerOrientation([for (final d in dossiers) d.champs]);
    final d = dossiers.where((x) => x.id == dossierId).firstOrNull;
    if (d == null) {
      throw const RefusMobile('DOSSIER_INCONNU', 'Ce dossier n’a pas été ouvert à l’accueil de secours de ce téléphone.', 'Choisir un dossier de la liste');
    }
    return source.creer(
        mobCollectionOrientation,
        mobChampsOrientation(dossier: d.champs, dossierId: d.id, destination: destination, degre: degre, acteur: agent, maintenant: maintenant));
  }
}
