// LOT IDENT (16/11/2026, décision de la Direction, section AQ point 15) : UNE MISE À JOUR DES INFORMATIONS DE LA CLINIQUE SE PROPAGE PARTOUT.
//
// Mesure faite avant ce lot (test `identite_propagation_sync_test.dart`, contre la vraie mère et deux vrais fileuls) :
//  - la MÈRE diffusait déjà `identiteLegale` (les versions datées) aux fileuls (famille R) ; elle la diffusait AUSSI aux téléphones (une fiche de configuration de clinique, RG-13) ;
//  - les OPTIONS D'IMPRESSION (logo de part et d'autre, filigrane) vivaient dans `reglages`, collection que la mère ne diffuse pas : posées sur un poste, elles restaient sur ce poste ;
//  - un FILEUL ne pouvait poser aucune version (« réglé sur la mère ») : il fallait aller au poste de la mère ;
//  - rien ne refusait, au moteur, le geste d'un profil sans droit d'écriture (seule la commande était masquée).
//
// Désormais, comme les décisions de validation (lot CONT) :
//  - le droit est celui de la FICHE RBAC : l'écriture de « Paramètres fiscaux » (`cfg-fiscalite`) ou de « Identité et papier à en-tête » (`cfg-branding`), jamais un nom de rôle ;
//  - sur la MÈRE, la version est posée (ou l'option réglée) directement, après le même contrôle de droit (le moteur refuse, masquer le bouton ne protège rien) ;
//  - sur un FILEUL, la demande est SIGNÉE (qui, rôle, quand) et DÉPOSÉE dans `demandesIdentite` (famille A : le fileul dépose, la mère complète du verdict). La mère REVÉRIFIE sous le rôle
//    de l'auteur, à la date de la SIGNATURE, ajoute la version (jamais une réécriture : la précédente se clôt la veille) et la propage par la configuration ; refus nommé, jamais avalé ;
//  - un rejeu ne double jamais (seule une demande « déposée » est traitée ; une seconde version à la même date d'effet est refusée `VERSION_EXISTANTE`) ;
//  - les options d'impression ont leur collection (`optionsImpression`, famille R) : elles voyagent comme l'identité ;
//  - RIEN de tout cela ne part vers un téléphone ([collectionsIdentiteJamaisMobile], RG-13), et le relais web ne reçoit que des enveloppes chiffrées qu'il ne lit pas.
library;

import '../droits/matrice.dart';
import '../validation/validation.dart' show valInstant;
import 'cfa_regles.dart' show CfaFiche;
import 'cfb_fiscal_date.dart';

/// Les demandes d'identité d'un fileul (famille A de la synchronisation : le fileul dépose, la mère complète du verdict).
const String idCollectionDemandes = 'demandesIdentite';

/// Les options d'impression de la clinique (une fiche par option, `OPT-<clé>`) : famille R, la mère seule écrit, les postes reçoivent.
const String idCollectionOptions = 'optionsImpression';

/// Identité, demandes et options d'impression : un réglage de CLINIQUE. Jamais vers un téléphone (RG-13) : aucun écran du mobile ne les lit.
const Set<String> collectionsIdentiteJamaisMobile = {'identiteLegale', idCollectionDemandes, idCollectionOptions};

const String idEtatDeposee = 'deposee', idEtatAppliquee = 'appliquee', idEtatRefusee = 'refusee';

/// Les écrans dont l'ÉCRITURE donne le droit de poser l'identité ou ses options (lus de la fiche RBAC par rôle, jamais un nom de rôle).
const List<String> idEcransEcriture = ['cfg-fiscalite', 'cfg-branding'];

/// Les valeurs par DÉFAUT des options d'impression (défauts semés : la maquette lit `S.reglage('impression.doubleLogo', true)` et `'impression.filigrane'`).
const Map<String, Object?> idOptionsDefauts = {'doubleLogo': true, 'filigrane': ''};

/// Les filigranes que l'écran propose (vide : aucun).
const List<String> idFiligranes = ['', 'Document officiel', 'Confidentiel'];

/// Le rôle a-t-il le droit d'ÉCRIRE l'identité ? Vrai si la fiche RBAC lui donne l'écriture d'au moins un des deux écrans. Sans matrice : faux (jamais un droit supposé).
bool idDroitEcriture(MatriceDroits? matrice, String? role) => matrice != null && role != null && idEcransEcriture.any((e) => matrice.peutEditer(role, e));

/// `IDENTITE_DROIT_REQUIS` : le contrôle est REFAIT par le moteur, que la commande ait été masquée ou non. [droit] est le résultat de [idDroitEcriture].
CfbRefus? idControleDroit({required bool droit, required String libelleRole}) => droit
    ? null
    : CfbRefus('IDENTITE_DROIT_REQUIS',
        'Poser les informations de la clinique (identité, en-tête, options d’impression) demande le droit d’écrire « Paramètres fiscaux » ou « Identité et papier à en-tête » : « $libelleRole » ne l’a pas.',
        'Demander à un profil dont la fiche des droits accorde l’écriture de ces écrans.');

/// La valeur d'une option d'impression : la fiche `OPT-<clé>`, sinon le défaut semé.
Object? idOption(Iterable<CfaFiche> options, String cle) {
  for (final f in options) {
    if (f['id'] == 'OPT-$cle' && f['statut'] != 'archive' && f.containsKey('valeur')) return f['valeur'];
  }
  return idOptionsDefauts[cle];
}

/// Les options d'impression que la demande propose, contrôlées : clés connues, `doubleLogo` booléen, `filigrane` dans la liste. Refus nommé `OPTION_IMPRESSION_INVALIDE`.
CfbRefus? idControleOptions(Map<String, Object?> options) {
  for (final e in options.entries) {
    if (!idOptionsDefauts.containsKey(e.key)) {
      return CfbRefus('OPTION_IMPRESSION_INVALIDE', 'Option d’impression inconnue : « ${e.key} ».', 'Choisir « doubleLogo » ou « filigrane ».');
    }
    if (e.key == 'doubleLogo' && e.value is! bool) {
      return const CfbRefus('OPTION_IMPRESSION_INVALIDE', 'Le logo de part et d’autre est une case à cocher : oui ou non.', 'Cocher ou décocher la case.');
    }
    if (e.key == 'filigrane' && !idFiligranes.contains('${e.value ?? ''}')) {
      return CfbRefus('OPTION_IMPRESSION_INVALIDE', 'Filigrane inconnu : « ${e.value} ».', 'Choisir « Document officiel », « Confidentiel » ou aucun.');
    }
  }
  return null;
}

/// Les fiches `OPT-<clé>` à ÉCRIRE pour poser [options] : celles dont la valeur change seulement (rien d'écrit si rien ne change). Chaque entrée : la fiche complète et l'ancienne valeur.
List<({CfaFiche fiche, Object? avant, bool creation})> idEcrituresOptions(Iterable<CfaFiche> existantes, Map<String, Object?> options, {required String acteur, required DateTime maintenant}) {
  final out = <({CfaFiche fiche, Object? avant, bool creation})>[];
  for (final e in options.entries) {
    final avant = idOption(existantes, e.key);
    if ('$avant' == '${e.value}') continue;
    final deja = existantes.any((f) => f['id'] == 'OPT-${e.key}');
    out.add((
      fiche: {'id': 'OPT-${e.key}', 'statut': 'actif', 'cle': e.key, 'valeur': e.value, 'modifieLe': valInstant(maintenant), 'modifiePar': acteur},
      avant: avant,
      creation: !deja,
    ));
  }
  return out;
}

/// Ce que le dépôt rend : un refus nommé, ou la fiche à INSÉRER dans [idCollectionDemandes].
class VerdictDepotIdentite {
  const VerdictDepotIdentite.refus(this.refus) : fiche = null;
  const VerdictDepotIdentite.ok(this.fiche) : refus = null;
  final CfbRefus? refus;
  final Map<String, Object?>? fiche;
  bool get ok => refus == null;
}

/// Les demandes qui attendent encore la mère (« déposée », archivées exclues), de la plus ancienne à la plus récente.
List<Map<String, Object?>> idDemandesEnAttente(Iterable<Map<String, Object?>> demandes) => [
      for (final d in demandes)
        if (d['statut'] != 'archive' && d['etat'] == idEtatDeposee) d
    ]..sort((a, b) => '${a['demandeLe']}${a['id']}'.compareTo('${b['demandeLe']}${b['id']}'));

/// Le DÉPÔT d'une demande par un FILEUL : champs d'identité (une version datée : [dateEffet] et [motif] exigés) et/ou options d'impression. Les contrôles sont ceux de la pose directe : droit
/// de la fiche RBAC (`IDENTITE_DROIT_REQUIS`), champs (`IFU_FORMAT`, `NOM_REQUIS`…), motif, date d'effet, exercice clos, date déjà prise. Une demande identique déjà en attente est refusée en
/// nommant (`DEMANDE_DEJA_DEPOSEE`). Ne modifie rien : rend la fiche à écrire. [etiquette] distingue deux postes qui déposent à la même microseconde.
VerdictDepotIdentite idDeposerDemande({
  required Iterable<CfaFiche> versions,
  required Iterable<CfaFiche> demandes,
  required Map<String, Object?> champs,
  Map<String, Object?> options = const {},
  Object? dateEffet,
  String? motif,
  required String role,
  required String libelleRole,
  required bool droit,
  required String acteur,
  required DateTime maintenant,
  Iterable<CfaFiche> exercices = const [],
  String etiquette = 'F',
}) {
  final d = idControleDroit(droit: droit, libelleRole: libelleRole);
  if (d != null) return VerdictDepotIdentite.refus(d);
  if (champs.isEmpty && options.isEmpty) {
    return const VerdictDepotIdentite.refus(CfbRefus('DEMANDE_VIDE', 'Rien à déposer : aucun champ d’identité, aucune option d’impression.', 'Modifier au moins une information.'));
  }
  final o = idControleOptions(options);
  if (o != null) return VerdictDepotIdentite.refus(o);
  if (champs.isNotEmpty) {
    // Même contrôle que la pose directe, sans la garde « fileul » : décider n'est pas écrire la configuration.
    final essai = cfbNouvelleVersionIdentite(versions, champs, dateEffet: dateEffet, motif: motif, acteur: acteur, maintenant: maintenant, aujourdhui: maintenant, exercices: exercices, fileul: false);
    if (!essai.ok) return VerdictDepotIdentite.refus(essai.refus);
    for (final x in idDemandesEnAttente(demandes)) {
      if ('${x['dateEffet']}' == isoJour(dateEffet ?? maintenant) && (x['champs'] as Map?)?.isNotEmpty == true) {
        return VerdictDepotIdentite.refus(CfbRefus('DEMANDE_DEJA_DEPOSEE', 'Une version de l’identité prenant effet le ${isoJour(dateEffet ?? maintenant)} est déjà déposée par ${x['demandePar']}.',
            'Rien à faire : la mère l’applique dès qu’elle est joignable. Le travail courant n’est pas bloqué.'));
      }
    }
  }
  return VerdictDepotIdentite.ok({
    'id': 'DI$etiquette${maintenant.microsecondsSinceEpoch}${demandes.length}',
    'statut': 'actif',
    'etat': idEtatDeposee,
    if (champs.isNotEmpty) ...{'champs': cfbNormaliserIdentite(champs), 'dateEffet': isoJour(dateEffet ?? maintenant), 'motif': (motif ?? '').trim()},
    if (options.isNotEmpty) 'options': {...options},
    'demandePar': acteur,
    'demandeRole': role,
    'demandeLe': valInstant(maintenant),
  });
}

/// Ce que la mère rend après avoir rejoué une demande : l'écriture de la version (ou `null`), les options à écrire, et les champs du verdict à poser sur la demande.
class ApplicationDemandeIdentite {
  const ApplicationDemandeIdentite({required this.ecriture, required this.options, required this.champsDemande, required this.refus});
  final CfbEcritureIdentite? ecriture;
  final List<({CfaFiche fiche, Object? avant, bool creation})> options;

  /// À fusionner dans la fiche de la demande : `etat`, `traiteLe`, et, en cas de refus, `resultatCode`, `resultatMotif`, `resultatGeste`.
  final Map<String, Object?> champsDemande;
  final CfbRefus? refus;
  bool get ok => refus == null;
}

/// La MÈRE applique une demande « déposée » : mêmes contrôles que la pose directe, sous le rôle et le nom de l'AUTEUR, à la date de sa SIGNATURE. [droitDeLAuteur] est le droit de la fiche
/// RBAC pour le RÔLE de l'auteur (lu de la matrice de la mère, jamais déclaré par le fileul). `null` si la demande n'est pas « déposée » (idempotence : un rejeu, une demande déjà appliquée
/// ou refusée, ne se retraite jamais). Ne modifie rien.
ApplicationDemandeIdentite? idAppliquerDemande(
  Map<String, Object?> demande, {
  required Iterable<CfaFiche> versions,
  required Iterable<CfaFiche> options,
  required bool droitDeLAuteur,
  required String libelleRoleAuteur,
  required DateTime maintenant,
  Iterable<CfaFiche> exercices = const [],
}) {
  if (demande['etat'] != idEtatDeposee) return null;
  final signeLe = DateTime.tryParse('${demande['demandeLe']}') ?? maintenant;
  ApplicationDemandeIdentite refuse(CfbRefus r) => ApplicationDemandeIdentite(ecriture: null, options: const [], refus: r, champsDemande: {
        'etat': idEtatRefusee,
        'traiteLe': valInstant(maintenant),
        'resultatCode': r.code,
        'resultatMotif': r.motif,
        if (r.geste != null) 'resultatGeste': r.geste,
      });
  final d = idControleDroit(droit: droitDeLAuteur, libelleRole: libelleRoleAuteur);
  if (d != null) return refuse(d);
  final champs = ((demande['champs'] as Map?) ?? const {}).cast<String, Object?>();
  final opts = ((demande['options'] as Map?) ?? const {}).cast<String, Object?>();
  final o = idControleOptions(opts);
  if (o != null) return refuse(o);
  CfbEcritureIdentite? e;
  if (champs.isNotEmpty) {
    e = cfbNouvelleVersionIdentite(versions, champs,
        dateEffet: demande['dateEffet'], motif: '${demande['motif'] ?? ''}', acteur: '${demande['demandePar']}', maintenant: signeLe, aujourdhui: signeLe, exercices: exercices, fileul: false, origine: 'demande d’un fileul');
    if (!e.ok) return refuse(e.refus!);
  }
  return ApplicationDemandeIdentite(
      ecriture: e,
      options: idEcrituresOptions(options, opts, acteur: '${demande['demandePar']}', maintenant: signeLe),
      refus: null,
      champsDemande: {'etat': idEtatAppliquee, 'traiteLe': valInstant(maintenant)});
}
