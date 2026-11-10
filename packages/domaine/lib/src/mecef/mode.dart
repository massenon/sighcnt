/// MECeF, lot L3 : le MODE de certification (boîtier ou e-MECeF) et le point d'extension de l'appareil.
///
/// Décision de la Direction du 09/11/2026 : AUCUN numéro simulé ne se présente comme fiscal. Le mode se règle dans les paramètres du poste (clé
/// [mecefCleMode], défaut [mecefModeDefaut], versionné par date par le registre du lot L0) ; la valeur se LIT en base, jamais ici.
///
/// Rien n'est inventé : aucun document remis ne donne le modèle du boîtier, son interface ni son protocole, ni le dossier d'interface e-MECeF de la DGI
/// (voir les questions ouvertes du plan, section L3). Ce fichier ne contient donc ni adresse, ni jeton, ni format de message : seulement l'interface
/// [AdaptateurMecef] que l'adaptateur réel du lot M3 implémentera, et l'implémentation [AdaptateurNonConfigure] qui REFUSE en nommant (code, motif, geste).
/// Sans adaptateur configuré, la vente est encaissée et reste EN ATTENTE de certification : elle ne reçoit aucun numéro, et la retransmission ne consomme
/// pas l'unique essai du caissier.
///
/// Port de `adaptateurMecef` de la maquette (`prototype_html/assets/js/parcours.js`), pour le mode e-MECeF (vecteurs `mecef_mode.json`). Écart assumé : en
/// mode boîtier la maquette garde son appareil de démonstration (elle simule, et le dit) ; le POSTE, lui, n'a aucun adaptateur : le mode boîtier y refuse
/// aussi, avec son propre motif.
library;

import 'montants.dart' show RefusMecef;

/// La clé du paramètre dans le registre du lot L0 (`definitionsParametres`).
const String mecefCleMode = 'mecef.mode';

/// Les deux modes proposés (identifiants STOCKÉS : on ne les renomme pas) ; le défaut est le boîtier physique.
const List<String> mecefModes = ['boitier', 'emecef'];
const String mecefModeDefaut = 'boitier';

/// Le libellé affiché de chaque mode.
const Map<String, String> mecefLibellesModes = {'boitier': 'Boîtier physique', 'emecef': 'e-MECeF'};

/// Le code du refus nommé quand aucun adaptateur n'est configuré.
const String mecefCodeNonConfigure = 'MECEF_NON_CONFIGURE';

/// Le mode en vigueur d'une valeur lue en base : la valeur si elle est l'un des deux modes, sinon le défaut (une valeur inconnue ne casse pas la caisse).
String mecefModeEnVigueur(Object? valeur) => valeur is String && mecefModes.contains(valeur) ? valeur : mecefModeDefaut;

/// Ce que le poste demande à l'appareil : une vente à certifier. Les montants sont ENTIERS (fonction unique des montants, E2299).
class DemandeCertification {
  const DemandeCertification({
    required this.cle,
    required this.total,
    required this.base,
    required this.aib,
    this.ifuAcheteur,
    this.nomAcheteur,
    this.aibTaux = 0,
  });
  final String cle;
  final int total;
  final int base;
  final int aib;
  final String? ifuAcheteur;
  final String? nomAcheteur;
  final num aibTaux;
}

/// Ce que l'appareil répond : un numéro (et l'horodatage de l'appareil), ou un refus nommé. Aucun numéro n'est jamais fabriqué par l'appelant.
class ReponseCertification {
  const ReponseCertification.ok(String this.numero, this.horodatage) : refus = null;
  const ReponseCertification.refus(RefusMecef this.refus)
      : numero = null,
        horodatage = null;
  final String? numero;
  final String? horodatage;
  final RefusMecef? refus;
  bool get ok => numero != null;
}

/// LE POINT D'EXTENSION de la certification. L'adaptateur du boîtier (modèle, interface et protocole à fournir par le fournisseur) et celui d'e-MECeF (dossier
/// d'interface DGI) l'implémenteront ; aucun n'existe (lot M3). Le boîtier est une entrée-sortie : [emettre] est asynchrone, et l'orchestration du poste, qui
/// reste synchrone tant que l'adaptateur n'est pas configuré, devra le devenir (lot M3).
abstract class AdaptateurMecef {
  /// Le mode que cet adaptateur sert (`boitier` ou `emecef`).
  String get mode;

  /// Vrai quand l'appareil est branché et sait répondre. Faux : rien n'est émis, [refus] dit pourquoi.
  bool get configure;

  /// Le refus nommé à rendre tant que l'adaptateur n'est pas configuré ; `null` quand il l'est.
  RefusMecef? get refus;

  /// Certifie une vente. Un adaptateur non configuré ne répond jamais par un numéro.
  Future<ReponseCertification> emettre(DemandeCertification demande);
}

/// L'adaptateur « non configuré » : il REFUSE en nommant (code, motif, geste) et ne fabrique rien. Le motif de l'e-MECeF est celui que la Direction a arrêté
/// (« non configuré : dossier d'interface DGI requis ») ; celui du boîtier dit que son adaptateur n'est pas livré.
class AdaptateurNonConfigure implements AdaptateurMecef {
  const AdaptateurNonConfigure(this.mode);
  @override
  final String mode;

  @override
  bool get configure => false;

  @override
  RefusMecef get refus => mode == 'emecef'
      ? const RefusMecef(
          mecefCodeNonConfigure,
          'e-MECeF non configuré : dossier d’interface DGI requis.',
          'La vente reste en attente de certification. Choisir le mode « Boîtier physique », ou fournir le dossier d’interface de la DGI.')
      : const RefusMecef(
          mecefCodeNonConfigure,
          'Boîtier non configuré : aucun adaptateur n’est branché à ce poste (modèle, interface et protocole du boîtier non documentés).',
          'La vente reste en attente de certification. Elle se retransmettra quand l’adaptateur du boîtier sera livré (lot M3).');

  @override
  Future<ReponseCertification> emettre(DemandeCertification demande) async => ReponseCertification.refus(refus);
}

/// L'adaptateur du mode en vigueur. Tant qu'aucun adaptateur réel n'existe (lot M3), les deux modes rendent un [AdaptateurNonConfigure].
AdaptateurMecef adaptateurPourMode(Object? valeurMode) => AdaptateurNonConfigure(mecefModeEnVigueur(valeurMode));

/// Les champs que le refus laisse sur la pièce : elle reste EN ATTENTE de certification (état stocké `en_attente`), sans numéro, avec le code et le motif du
/// refus, et le mode sous lequel la tentative a eu lieu. Même contenu que la maquette (vecteurs `mecef_mode.json`).
Map<String, Object?> champsEnAttenteCertification(RefusMecef refus, String mode) => {
      'statutMecef': 'en_attente',
      'codeRetour': refus.code,
      'motifRefusMecef': refus.motif,
      'modeMecef': mode,
    };
