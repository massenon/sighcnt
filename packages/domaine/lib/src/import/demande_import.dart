/// LA DEMANDE D'IMPORT D'UN FILEUL À LA MÈRE (lot IMP-C, réponse Q5 de la Direction du 10/11/2026), puis L'ÉCRITURE DIRECTE DU FILEUL (lot IMP-D, décision N du 12/11/2026).
///
/// LOT IMP-D : la Direction a choisi que « un fileul peut importer directement dans son propre magasin », la mère restant l'AUTORITÉ de la configuration. Un fileul écrit donc chez
/// lui, tout de suite, ET une demande part automatiquement à la mère ([voieImportFileul], [PortDemandeImport]). Trois issues, aucune muette :
///  * la mère APPLIQUE : elle rejoue l'analyse et doit produire EXACTEMENT le même résultat ([resultatIdentique]) ; les fiches de la mère portent les mêmes identifiants que celles du fileul
///    ([identifiantDeDemande]), elles remplacent donc les siennes à l'arrivée de la configuration : une identité de ligne, jamais deux versions d'un même code ;
///  * la mère REFUSE (droit, doublon, règle métier, résultat différent) : le fileul RESTITUE son lot ([restituerLotDirect], archivage RG-14, jamais une suppression), sauf les fiches sur
///    lesquelles une pièce émise s'appuie déjà (elles restent, marquées, une pièce émise ne se réécrit jamais) ; le verdict nomme le code, le motif et le geste ;
///  * la mère est INJOIGNABLE : la demande reste en attente dans la file du fileul (famille A, hors ligne d'abord), ses fiches portent le marquage « en attente de la mère » ([champEnAttenteMere]),
///    jamais un « appliqué » qui n'est pas confirmé ([libelleEtatDemandeImport]).
/// En cas de conflit, la MÈRE gagne, toujours.
///
/// Le poste du gestionnaire de stock est un FILEUL. Un référentiel de configuration (famille R : la mère seule écrit) importé à un fileul est refusé par la règle existante
/// (« Réglé sur la mère », `CONFIGURATION_DE_LA_MERE`) : il passe donc par une DEMANDE D'IMPORT vérifiée. Ce fichier ne porte que les règles pures :
///
///  * [jeuExigeLaMere] : quand un jeu passe par une demande (un de ses collections cibles est de configuration) ;
///  * [composerDemandeImport] : ce que le fileul dépose, APRÈS avoir fait la même vérification que la mère (rien n'est envoyé d'un fichier refusé) ;
///  * [traiterDemandeImport] : ce que la MÈRE fait de la demande : elle REJOUE l'analyse sous le rôle et le nom de l'auteur (un bouton absent au fileul ne protège rien, et un autre
///    poste a pu créer la même fiche entre-temps), puis applique par le MÊME chemin que l'import local (`appliquer`) ou refuse en NOMMANT le code, le motif et le geste.
///
///
/// LOT IDEM (décisions de la Direction du 13/11/2026, section V) : le MÊME inventaire, importé par deux fileuls ou deux fois, est reconnu comme le MÊME lot. L'identité d'un lot dérive de son
/// CONTENU normalisé (`identite_lot.dart`) et donne aux fiches d'un lot des identifiants identiques chez tous les postes. La mère confirme le lot UNE fois ; une autre demande du même contenu est
/// « déjà confirmée, adoptée » (jamais un refus, rien n'est réécrit, [VerdictDemandeImport.adoptee]) ; un fileul dont la série diffère (nouvelle tentative après une annulation) rebase son écriture
/// ([SuiteDuVerdict.rebaser]). Chaque étape (verdict, restitution, adoption, consignation d'un refus) rejouée est un NO-OP prouvé.
///
/// La demande est une fiche descriptive (`demandesImport`) : le fileul la dépose, la mère la complète du verdict, qui revient au fileul par le même chemin (précédent : `propositionsTarif`
/// du lot T6). Les lignes du fichier voyagent dans la demande (la mère doit pouvoir rejouer) : elles sont EFFACÉES de la fiche dès que la mère a rendu son verdict, et un verdict
/// d'un jeu restreint ne recopie aucune valeur de cellule (motifs fixes, comme l'historique d'un lot, RG-13).
library;

import 'moteur_import.dart';
import 'identite_lot.dart';
import '../droits/droit_import.dart';

/// La collection des demandes (famille A de la synchronisation : champ à champ, dans les deux sens).
const String demandesImportCollection = 'demandesImport';

/// États d'une demande : `en_attente` (déposée, la mère n'a pas encore statué), `appliquee`, `refusee`.
const String demandeImportEnAttente = 'en_attente', demandeImportAppliquee = 'appliquee', demandeImportRefusee = 'refusee';

/// Lot IMP-D : le fileul a ANNULÉ son lot avant la réponse de la mère ; la demande est retirée (la mère ne la traite plus). Une demande déjà tranchée ne se retire pas.
const String demandeImportRetiree = 'retiree';

/// Lot IMP-D : où en est la restitution du fileul après un refus de la mère (champ `restitution` de la demande, écrit par le fileul).
const String restitutionFaite = 'faite', restitutionPartielle = 'partielle';

/// Lot IMP-D : le marquage d'une fiche écrite chez un fileul que la mère n'a pas encore confirmée (valeur : l'identifiant de la demande). La fiche de la mère, qui la remplace à l'arrivée
/// de la configuration, ne le porte pas : le marquage tombe donc de lui-même à la confirmation. Il est posé aussi sur une fiche CONSERVÉE après un refus (voir [champRefuseeParMere]).
const String champEnAttenteMere = 'enAttenteMere';

/// Lot IMP-D : une fiche que la mère a refusée mais qu'une pièce émise utilise déjà (valeur : le motif nommé). Elle reste en place, marquée, jamais réécrite.
const String champRefuseeParMere = 'refuseeParMere';

/// LOT IMP-E : une fiche écrite par une demande porte `serieDemande` (la série des identifiants, la même chez le fileul et chez la mère, dérivée du CONTENU du lot depuis le lot IDEM :
/// voir `identite_lot.dart`) : c'est ce qui lui donne une IDENTITÉ COMMUNE à tous les postes et qui permet de reconnaître un rejeu.

/// LOT IMP-E : la valeur de DÉPART de chaque compteur d'une fiche écrite par une demande (stock d'un produit, quantité restante d'un lot), posée à l'écriture. C'est le point de départ
/// COMMUN du compteur : le fileul et la mère écrivent la même valeur, aucun des deux ne la publie comme une variation (sinon elle s'additionnerait à celle de l'autre). Seules les sorties
/// et les entrées POSTÉRIEURES voyagent, comptées depuis ce départ.
const String champDepartCompteurs = 'departCompteurs';

/// LOT IMP-E : une fiche écrite chez un fileul que la mère n'a pas confirmée (en attente) ou a refusée (gardée parce qu'une pièce s'appuie dessus) est PROPRE À CE POSTE : elle ne part
/// pas au journal, aucun autre poste ne la voit. Un stock ne se rend visible aux autres postes qu'une fois la mère d'accord (jamais de stock doublé par deux fileuls, jamais une
/// quantité que la mère refuserait ensuite).
bool ficheLocaleAuPoste(Map<String, Object?> f) => '${f[champEnAttenteMere] ?? ''}'.isNotEmpty || '${f[champRefuseeParMere] ?? ''}'.isNotEmpty;

/// Un jeu passe par une demande quand un fileul rattaché ne peut écrire l'une de ses collections cibles : [collectionsDeLaMere] est l'ensemble des collections de configuration
/// (garde « réglé sur la mère »). UN JEU RESTREINT n'y passe JAMAIS : ses lignes (identité, salaire, soldes) ne voyagent pas dans une fiche partagée, la rémunération du personnel n'étant
/// publiée à personne (RG-13) ; voir [jeuReserveALaMere].
bool jeuExigeLaMere(DeclarationImport d, Set<String> collectionsDeLaMere) => !d.restreint && d.collections.any(collectionsDeLaMere.contains);

/// Un jeu RESTREINT qui écrit de la configuration ne s'importe qu'au poste de la MÈRE : le fileul le dit au lieu de proposer un envoi (le personnel, par exemple).
bool jeuReserveALaMere(DeclarationImport d, Set<String> collectionsDeLaMere) => d.restreint && d.collections.any(collectionsDeLaMere.contains);

/// Ce que fait un import sur un FILEUL RATTACHÉ (lot IMP-D). Sur la mère, ou sur un poste autonome, tout s'écrit directement : aucune voie particulière.
enum VoieImportFileul {
  /// Aucune cible de configuration : le jeu s'écrit chez le fileul comme avant, sans demande (l'activité voyage par ses propres règles de fusion).
  directe,

  /// Une cible au moins est de la configuration (famille R) : écriture directe chez le fileul ET demande automatique à la mère. LOT IMP-E (décision de la Direction du 13/11/2026) : cela vaut
  /// aussi pour le Grand Stock (produits, lots, mouvements), qui s'écrit chez le gestionnaire de stock. Le double comptage que l'on craignait existait (mesuré, E2520) ; il est levé
  /// par l'identité commune des fiches d'une demande, leur valeur de départ ([champDepartCompteurs]) et le caractère propre au poste d'une fiche non confirmée ([ficheLocaleAuPoste]).
  directeEtDemande,

  /// Jeu RESTREINT qui écrit de la configuration (le personnel : identité et salaire) : ses lignes ne voyagent jamais dans une demande (RG-13), il s'importe au poste de la mère.
  reserveeALaMere,
}

/// La voie d'un jeu sur un fileul rattaché. [configuration] : les collections que la mère seule écrit.
VoieImportFileul voieImportFileul(DeclarationImport d, {required Set<String> configuration}) {
  if (!d.collections.any(configuration.contains)) return VoieImportFileul.directe;
  if (d.restreint) return VoieImportFileul.reserveeALaMere;
  return VoieImportFileul.directeEtDemande;
}

/// Les collections que le fileul peut écrire chez lui dans CE geste d'import : les cibles du jeu, et rien d'autre.
Set<String> collectionsAutoriseesAuFileul(JeuImport jeu) => {...jeu.cibles};

/// L'identifiant d'une fiche écrite par une demande d'import (lot IMP-D). Le fileul l'écrit chez lui et la mère le rejoue avec la MÊME formule : la fiche de la mère remplace donc celle du
/// fileul (même `id`) au lieu de la doubler. [rang] est le rang de la fiche dans sa collection au sein du geste (1, 2, …) ; il est le même des deux côtés parce que la mère n'applique que si
/// elle écrit exactement les mêmes lignes ([resultatIdentique]).
String identifiantDeDemande(String collection, String demandeId, int rang) {
  final p = collection.length < 3 ? collection : collection.substring(0, 3);
  return '${p.toUpperCase()}-$demandeId-$rang';
}

/// Le PORT d'une demande d'import (lot IMP-D) : décore le port d'un poste pour que les fiches écrites reçoivent leur identifiant de demande ([identifiantDeDemande]) au lieu du « plus un »
/// du poste. Le fileul le pose avec [marquerEnAttente] (ses fiches portent [champEnAttenteMere] jusqu'à la confirmation de la mère) ; la mère le pose sans marquage.
class PortDemandeImport extends PortImport {
  /// [compteurs] : les champs compteurs de chaque collection (stock d'un produit, quantité restante d'un lot), dont la valeur d'écriture est posée comme DÉPART ([champDepartCompteurs]).
  PortDemandeImport(this.base, {required this.demandeId, this.marquerEnAttente = false, this.compteurs = const {}, this.identiteLot, String? marquage}) : marquage = marquage ?? demandeId;
  final PortImport base;

  /// La SÉRIE des identifiants de fiche (depuis le lot IDEM : dérivée du contenu du lot, la même chez tous les postes qui importent ce contenu ; avant, l'identifiant de la demande).
  final String demandeId;

  /// LOT IDEM : l'identité de CONTENU du lot, posée sur chaque fiche écrite (lot d'import compris) pour que le même inventaire se reconnaisse partout.
  final String? identiteLot;

  /// La valeur du marquage « en attente de la mère » : l'identifiant de la DEMANDE (propre à ce fileul), jamais la série (commune à plusieurs fileuls).
  final String marquage;
  final bool marquerEnAttente;
  final Map<String, Set<String>> compteurs;
  final Map<String, int> _rangs = {};

  @override
  ProfilImport get profil => base.profil;
  @override
  List<FicheImport> toutes(String collection) => base.toutes(collection);
  @override
  String get jour => base.jour;
  @override
  String get utilisateur => base.utilisateur;

  /// Écrit la fiche sous l'identifiant `(demande, collection, rang)`. LOT IMP-E : c'est IDEMPOTENT. Une fiche de cette demande qui existe déjà à ce rang (rejeu de la demande, reprise du
  /// journal, redémarrage) est rendue telle quelle, sans écriture ni ligne de journal : une demande ne compte jamais deux fois la même fiche. La fiche porte la série de sa demande
  /// ([champSerieDemande]) et, pour un compteur, sa valeur de DÉPART ([champDepartCompteurs]).
  @override
  FicheImport inserer(String collection, FicheImport fiche) {
    final rang = _rangs.update(collection, (n) => n + 1, ifAbsent: () => 1);
    final id = fiche['id'] ?? identifiantDeDemande(collection, demandeId, rang);
    final deja = base.parId(collection, id);
    if (deja != null && deja[champSerieDemande] == demandeId) {
      // Une fiche ARCHIVÉE sous cette série ne se réutilise jamais (elle a été annulée ou restituée : une nouvelle tentative prend sa propre série).
      if (deja['statut'] == 'archive') throw StateError('la fiche $id de la série $demandeId est archivée : une nouvelle tentative doit prendre une autre série');
      return deja;
    }
    final champs = compteurs[collection] ?? const <String>{};
    final depart = {for (final k in champs) if (fiche[k] is num) k: fiche[k]};
    return base.inserer(collection, {
      ...fiche,
      'id': id,
      champSerieDemande: demandeId,
      if (identiteLot != null) champIdentiteLot: identiteLot,
      if (depart.isNotEmpty) champDepartCompteurs: depart,
      if (marquerEnAttente && collection != collectionLots) champEnAttenteMere: marquage,
    });
  }

  @override
  void retirer(String collection, Object? id) => base.retirer(collection, id);
  @override
  bool archiver(String collection, Object? id, String motif) => base.archiver(collection, id, motif);
  @override
  void restaurer(String collection, Object? id) => base.restaurer(collection, id);
  @override
  void mettreAJour(String collection, Object? id, FicheImport patch) => base.mettreAJour(collection, id, patch);
  @override
  void journaliser(String action, String module, String entite, String reference, Object? avant, Object? apres) =>
      base.journaliser(action, module, entite, reference, avant, apres);
}

/// LOT IMP-E : le lot d'import déjà écrit par cette demande (il porte la série de la demande), ou `null`. Sert de preuve qu'un rejeu n'a rien à écrire.
FicheImport? lotDeLaDemande(PortImport port, String demandeId) =>
    port.toutes(collectionLots).where((l) => l[champSerieDemande] == demandeId && l['etat'] == 'applique').firstOrNull;

/// LOT IDEM : le lot appliqué qui porte cette identité de CONTENU (écrit par n'importe quelle demande, sous n'importe quelle tentative), ou `null`.
FicheImport? lotDeLIdentite(PortImport port, String identite) =>
    port.toutes(collectionLots).where((l) => l[champIdentiteLot] == identite && l['etat'] == 'applique').firstOrNull;

/// LOT IDEM : la TENTATIVE de ce poste pour ce contenu : 1 la première fois, puis une de plus par série déjà utilisée ici (fiches, annulées, restituées ou archivées, et lots consignés). Une
/// fiche archivée n'est jamais réutilisée : le même fichier réimporté après une annulation (ou un refus de la mère) s'écrit sous une série neuve.
int tentativeDuLotImport(JeuImport j, PortImport port, String identite) {
  final series = <String>{};
  for (final c in [...j.cibles, collectionLots]) {
    for (final f in port.toutes(c)) {
      if (f[champIdentiteLot] == identite && '${f[champSerieDemande] ?? ''}'.isNotEmpty) series.add('${f[champSerieDemande]}');
    }
  }
  return series.length + 1;
}

/// LOT IDEM : ce que le FILEUL fixe avant d'écrire : l'identité de contenu du fichier et la série de ses fiches (la même chez tous les postes pour la première tentative).
({String identite, String serie}) preparerLotImport(JeuImport j, List<List<Object?>> lignes, PortImport port) {
  final identite = identiteLotImport(j.id, lignes);
  return (identite: identite, serie: serieDuLotImport(identite, tentativeDuLotImport(j, port, identite)));
}

/// LOT IMP-E : applique la demande, UNE SEULE fois. Si le lot de cette demande existe déjà (rejeu de la demande, redémarrage entre l'écriture et le verdict, reprise du journal), c'est un
/// NO-OP : aucune fiche, aucun lot, aucune ligne de journal de plus ; le lot déjà écrit est rendu. Sinon, c'est `appliquer`, sous les identifiants de la demande.
ResultatImport appliquerDemande(JeuImport j, AnalyseImport analyse, PortDemandeImport port) {
  final deja = lotDeLaDemande(port, port.demandeId);
  if (deja != null) return ResultatImport.ok(lot: deja, ecrits: (deja['ecrits'] as List? ?? const []).length);
  return appliquer(j, analyse, port);
}

/// Les rangs (numéros de ligne du fichier) qu'une analyse ÉCRIRAIT : ni refusés, ni ignorés, ni inchangés, ni refusés par leur auteur.
List<int> rangsAEcrire(AnalyseImport a) => [for (final l in a.lignes) if (l.sansEcriture == null && l.etat != 'refus') l.n];

/// La mère ne confirme que le MÊME résultat que celui que le fileul a écrit (lot IMP-D). Rend `null` si les lignes écrites sont identiques, sinon le constat nommé : les lignes que la mère
/// n'écrirait pas (déjà tenues chez elle) et celles qu'elle écrirait en plus.
({String motif, String geste})? resultatIdentique(List<int> ecritsParLeFileul, List<int> ecritsParLaMere) {
  final a = ecritsParLeFileul.toSet(), b = ecritsParLaMere.toSet();
  if (a.length == b.length && a.containsAll(b)) return null;
  String liste(Iterable<int> n) {
    final l = (n.toList()..sort());
    return l.length <= 10 ? l.join(', ') : '${l.take(10).join(', ')} et ${l.length - 10} autre(s)';
  }

  final enMoins = a.difference(b), enPlus = b.difference(a);
  return (
    motif: 'la mère ne produirait pas le même résultat que chez vous${enMoins.isEmpty ? '' : ' : elle n’écrirait pas la ligne ${liste(enMoins)} (déjà tenue chez elle)'}${enPlus.isEmpty ? '' : '${enMoins.isEmpty ? ' :' : ','} elle écrirait en plus la ligne ${liste(enPlus)}'}',
    geste: 'Votre écriture locale est restituée. Les fiches de la mère vous arrivent par la configuration : refaites l’import avec le fichier à jour.',
  );
}

/// La fiche déposée par le fileul. [analyse] est celle qu'il a faite lui-même (acceptée, au moins une ligne à écrire) : un fichier refusé ne part jamais.
Map<String, Object?> composerDemandeImport({
  required String id,
  required JeuImport jeu,
  required AnalyseImport analyse,
  required String role,
  required String par,
  required String jour,
  required bool restreint,
  String? lotLocal,
  Object? lotLocalId,
  String? serie,
  String? identiteLot,
}) {
  assert(analyse.accepte && analyse.aEcrire > 0, 'une demande ne part que d\'un fichier vérifié');
  // Lot IMP-D : `lotLocal` dit que le fileul a DÉJÀ écrit le fichier chez lui (écriture directe) ; `rangsEcrits` est ce qu'il a écrit, que la mère doit reproduire à l'identique.
  final directe = lotLocal != null;
  return {
    'id': id,
    'statut': 'actif',
    'jeu': jeu.id,
    'jeuLibelle': jeu.libelle,
    'fichier': analyse.fichier,
    'empreinte': analyse.empreinte,
    'lignes': [for (final l in analyse.lignesBrutes) [for (final c in l) c]],
    'nbLignes': analyse.nbLignes,
    'aEcrire': analyse.aEcrire,
    'nbAvertissements': analyse.compte.avertissements,
    'restreint': restreint,
    'etat': demandeImportEnAttente,
    'demandePar': par,
    'demandeRole': role,
    'demandeLe': jour,
    if (directe) ...{
      'ecritureDirecte': true,
      // L'identité des fiches écrites : la demande est RENOMMÉE par le pont en arrivant à la mère (l'étiquette du poste préfixe son identifiant de synchronisation), la série des
      // identifiants de fiche ne doit pas l'être : elle voyage dans ce champ.
      'serieIdentifiants': serie ?? id,
      if (identiteLot != null) 'identiteLot': identiteLot,
      'lotLocal': lotLocal,
      'lotLocalId': lotLocalId,
      'rangsEcrits': rangsAEcrire(analyse),
    },
  };
}

/// Le verdict de la mère sur une demande.
class VerdictDemandeImport {
  const VerdictDemandeImport.appliquee({required this.lot, required this.ecrits, this.adoptee = false, this.serie})
      : appliquee = true,
        code = null,
        motif = null,
        geste = null;
  const VerdictDemandeImport.refusee(String this.code, String this.motif, String this.geste, {this.lot})
      : appliquee = false,
        adoptee = false,
        serie = null,
        ecrits = 0;
  final bool appliquee;

  /// LOT IDEM : « déjà confirmé, adopté ». Le même contenu avait déjà été confirmé par la mère pour une AUTRE demande : elle ne réécrit rien, elle rend ce lot. Jamais un refus.
  final bool adoptee;

  /// LOT IDEM : la série des identifiants du lot que la mère tient (celle de la demande, ou celle du lot adopté quand elle diffère).
  final String? serie;
  final String? code, motif, geste;

  /// La référence du lot écrit (appliquée) ou du fichier consigné refusé (refusée, si le moteur en a consigné un).
  final String? lot;
  final int ecrits;

  /// Les champs que la mère écrit sur la demande : l'état, le verdict nommé, le lot ; les lignes du fichier sont EFFACÉES (aucune valeur de cellule ne reste à la demande).
  Map<String, Object?> versChamps({required String traitePar, required String traiteLe}) => {
        'etat': appliquee ? demandeImportAppliquee : demandeImportRefusee,
        'resultatCode': code ?? '',
        'resultatMotif': motif ?? '',
        'resultatGeste': geste ?? '',
        'resultatLot': lot ?? '',
        'resultatEcrits': ecrits,
        'resultatAdoptee': adoptee,
        'resultatSerie': serie ?? '',
        'traitePar': traitePar,
        'traiteLe': traiteLe,
        'lignes': <Object?>[],
      };
}

/// Ce que la MÈRE fait d'une demande. [port] porte le profil ET le nom de l'AUTEUR de la demande (le rôle est celui du fileul qui l'a déposée : la mère ne lui prête pas ses droits),
/// et la matrice d'import EN FORCE à la mère. [jeu] retrouve un jeu par son identifiant.
///
/// Refus nommés : `JEU_INCONNU` ; `DROIT_IMPORT_REFUSE` (le rôle de l'auteur ne détient plus le droit, relu ICI) ; le code du premier refus de l'analyse REJOUÉE (`DOUBLON_MAGASIN` quand un
/// autre poste a créé la même fiche entre-temps, etc.) ; `RIEN_A_ECRIRE` ; `ECRITURE_REFUSEE`. Un jeu RESTREINT ne recopie aucune valeur de cellule dans le motif.
VerdictDemandeImport traiterDemandeImport(FicheImport demande, PortImport port, JeuImport? Function(String id) jeu, {Map<String, Set<String>> compteurs = const {}}) {
  final j = jeu('${demande['jeu']}');
  if (j == null) {
    return VerdictDemandeImport.refusee('JEU_INCONNU', 'le jeu « ${demande['jeu']} » n’existe pas à la mère', 'Refaire la demande depuis la page du jeu, avec une version à jour du poste.');
  }
  final rd = refusDroitImport(j, 'importer', port);
  if (rd != null) return VerdictDemandeImport.refusee(rd.code!, rd.motif!, rd.geste!);
  // LOT IMP-E : une demande que la mère a DÉJÀ appliquée (redémarrage entre l'écriture et le verdict, demande reçue deux fois) rend le même verdict sans rien réécrire. Sans cette preuve,
  // la seconde analyse refuserait le fichier comme un doublon de ce que la mère vient elle-même d'écrire.
  final serie = '${demande['serieIdentifiants'] ?? demande['id']}';
  final identiteDeclaree = demande['identiteLot'] is String ? demande['identiteLot'] as String : null;
  final directe = demande['ecritureDirecte'] == true;
  final lignesDeposees = [
    for (final l in (demande['lignes'] as List? ?? const [])) [for (final c in (l as List)) c]
  ];
  if (directe && identiteDeclaree != null) {
    // LOT IDEM : l'identité déclarée doit être celle du CONTENU (les lignes voyagent dans la demande tant que la mère n'a pas statué) et la série celle de cette identité : une demande ne
    // peut pas se faire passer pour un autre lot (jamais d'adoption d'un lot qui n'est pas le sien).
    final lignesIncoherentes = lignesDeposees.isNotEmpty && identiteLotImport(j.id, lignesDeposees) != identiteDeclaree;
    if (lignesIncoherentes || !serieEstDeLIdentite(serie, identiteDeclaree)) {
      return VerdictDemandeImport.refusee('IDENTITE_LOT_INCOHERENTE', 'l’identité du lot déclarée par la demande ne correspond pas au contenu du fichier',
          'Refaites l’import depuis la page du jeu, avec une version à jour du poste : la demande est recalculée sur le fichier.');
    }
  }
  if (directe) {
    final deja = lotDeLaDemande(port, serie);
    // Les lignes que la demande a écrites doivent être celles du lot tenu : sinon ce n'est pas le même résultat (le fileul a écrit autre chose chez lui).
    VerdictDemandeImport? adopter(FicheImport lot) {
      final rangsLot = lot['rangsEcrits'];
      if (demande['rangsEcrits'] is List && rangsLot is List) {
        final diff = resultatIdentique([for (final n in (demande['rangsEcrits'] as List)) (n as num).toInt()], [for (final n in rangsLot) (n as num).toInt()]);
        if (diff != null) return VerdictDemandeImport.refusee('RESULTAT_DIFFERENT', diff.motif, diff.geste);
      }
      final origine = lot[champDemandeOrigine];
      return VerdictDemandeImport.appliquee(
          lot: '${lot['reference']}',
          ecrits: (lot['ecrits'] as List? ?? const []).length,
          adoptee: origine != null && '$origine' != '${demande['id']}',
          serie: '${lot[champSerieDemande] ?? serie}');
    }

    if (deja != null) return adopter(deja)!;
    if (identiteDeclaree != null) {
      final autre = lotDeLIdentite(port, identiteDeclaree);
      if (autre != null) return adopter(autre)!;
    }
    final annule = port.toutes(collectionLots).where((l) => l[champSerieDemande] == serie && l['etat'] == 'annule').firstOrNull;
    if (annule != null) {
      return VerdictDemandeImport.refusee('LOT_ANNULE_A_LA_MERE', 'le lot de cette série (${annule['reference']}) a été annulé à la mère',
          'Refaites l’import : une nouvelle tentative prend une série neuve (jamais une fiche archivée réutilisée).');
    }
  }
  final lignes = lignesDeposees;
  final a = analyserLignes(j, lignes, '${demande['fichier'] ?? ''}', port)..empreinte = demande['empreinte'] as String?;
  if (!a.accepte) {
    // Rejoué à la mère, le fichier ne passe plus (un autre poste a pu écrire la même fiche) : refusé en NOMMANT la première cause, consigné à l'historique de la mère.
    final premier = [for (final p in a.problemes.map((p) => masquerProbleme(j, p, port))) if (p.estRefus) p].firstOrNull;
    // LOT IDEM : un REJEU de la même demande refusée ne consigne pas un second lot refusé (le fichier refusé est consigné UNE fois par demande).
    var lot = port.toutes(collectionLots).where((l) => l['etat'] == 'refuse' && l[champDemandeOrigine] == demande['id']).firstOrNull;
    if (lot == null) {
      lot = consigner(j, a, port);
      if (lot != null) port.mettreAJour(collectionLots, lot['id'], {champDemandeOrigine: demande['id']});
    }
    return VerdictDemandeImport.refusee(
        premier?.code ?? 'ANALYSE_REFUSEE',
        premier == null
            ? 'le fichier ne passe plus l’analyse à la mère'
            : 'rejoué à la mère, le fichier est refusé${premier.n > 0 ? ' (ligne ${premier.n}, ${premier.colonne})' : ''} : ${premier.motif}',
        premier?.geste ?? 'Corrigez le fichier puis refaites la demande.',
        lot: lot == null ? null : '${lot['reference']}');
  }
  // LOT IMP-D : une demande dont le fileul a déjà écrit chez lui n'est confirmée que si la mère écrit EXACTEMENT les mêmes lignes ; ses fiches reçoivent les identifiants de la demande
  // (ceux du fileul) pour le remplacer au lieu de le doubler. Un résultat différent est refusé en nommant les lignes, rien n'est écrit, le fileul restitue.
  if (directe && demande['rangsEcrits'] is List) {
    final diff = resultatIdentique([for (final n in (demande['rangsEcrits'] as List)) (n as num).toInt()], rangsAEcrire(a));
    if (diff != null) return VerdictDemandeImport.refusee('RESULTAT_DIFFERENT', diff.motif, diff.geste);
  }
  final r = directe ? appliquerDemande(j, a, PortDemandeImport(port, demandeId: serie, compteurs: compteurs, identiteLot: identiteDeclaree)) : appliquer(j, a, port);
  if (r.ok) {
    // LOT IDEM : le lot écrit se souvient de la demande qui l'a écrit (confirmation) et des lignes écrites : une AUTRE demande du même contenu l'adopte sans rien réécrire.
    port.mettreAJour(collectionLots, r.lot!['id'], {champDemandeOrigine: demande['id'], 'rangsEcrits': rangsAEcrire(a)});
    return VerdictDemandeImport.appliquee(lot: '${r.lot!['reference']}', ecrits: r.ecrits, serie: directe ? serie : null);
  }
  return VerdictDemandeImport.refusee(r.code ?? 'ECRITURE_REFUSEE', r.motif ?? 'l’écriture a été refusée', r.geste ?? 'Rien n’a été écrit.', lot: r.lot == null ? null : '${r.lot!['reference']}');
}

// --- Lot IMP-D : ce que le fileul fait du verdict de la mère -------------------------------------------------------------------------

/// Le résultat d'une RESTITUTION : les fiches archivées et celles que le fileul GARDE parce qu'une pièce émise s'appuie déjà dessus (une pièce émise ne se réécrit jamais).
class ResultatRestitution {
  const ResultatRestitution.ok({required this.archives, this.gardees = const []})
      : ok = true,
        code = null,
        motif = null,
        geste = null;
  const ResultatRestitution.refus(String this.code, String this.motif, String this.geste)
      : ok = false,
        archives = 0,
        gardees = const [];
  final bool ok;
  final int archives;

  /// Les fiches conservées : `{collection, id, code, motif}` (le motif dit la pièce qui s'appuie dessus).
  final List<Map<String, Object?>> gardees;
  final String? code, motif, geste;

  /// `faite` quand tout est archivé, `partielle` quand une fiche a dû rester.
  String get etat => gardees.isEmpty ? restitutionFaite : restitutionPartielle;
}

/// RESTITUE le lot qu'un fileul a écrit chez lui quand la mère refuse ([codeRefus], [motifRefus] : le verdict, recopié au lot). Ce n'est pas une suppression (RG-14) : les fiches sont
/// ARCHIVÉES, comme à l'annulation d'un lot (`annulerLot`), les MODIFICATIONS du lot sont restituées dans l'ordre inverse.
///
/// Ce n'est pas le geste d'un agent mais la suite d'une décision de la mère : le droit d'annuler n'est donc PAS relu (un agent qui peut importer sans pouvoir annuler voit quand même
/// son écriture restituée). La règle de sûreté est ailleurs : une fiche qu'une pièce émise utilise déjà (la dépendance du jeu, relue FICHE PAR FICHE) n'est pas archivée ; elle reste,
/// marquée [champRefuseeParMere] avec le motif de la mère, et le verdict le dit. Idempotent : un lot déjà restitué ne se restitue pas deux fois.
ResultatRestitution restituerLotDirect(JeuImport? Function(String id) jeu, Object? lotId, {required String codeRefus, required String motifRefus, required PortImport port}) {
  final lot = port.parId(collectionLots, lotId);
  if (lot == null) return const ResultatRestitution.refus('LOT_INCONNU', 'le lot écrit chez vous est introuvable', 'Actualisez l’historique des lots.');
  if (lot['etat'] == 'restitue') {
    // LOT IDEM : une restitution REJOUÉE rend ce qu'elle avait fait (fiches archivées, fiches gardées), sans rien contre-passer de plus : une restitution partielle ne devient jamais « faite ».
    final detail = lot['restitueGardeesDetail'];
    return ResultatRestitution.ok(
        archives: (lot['restitueArchives'] as num?)?.toInt() ?? 0,
        gardees: detail is List ? [for (final g in detail) (g as Map).cast<String, Object?>()] : const []);
  }
  if (lot['etat'] != 'applique') {
    return ResultatRestitution.refus('LOT_NON_APPLIQUE', 'seul un lot appliqué se restitue (état actuel : ${lot['etat']})', 'Aucune action : ce lot a déjà été annulé.');
  }
  final j = jeu('${lot['jeu']}');
  final ecrits = (lot['ecrits'] as List).cast<Map>().map((e) => e.cast<String, Object?>()).toList();
  final libelleMotif = 'Restitution du lot ${lot['reference']} : refusé par la mère ($codeRefus)';
  final motifMarque = '$codeRefus : $motifRefus';
  final faits = <Map<String, Object?>>[];
  final gardees = <Map<String, Object?>>[];
  var archives = 0;
  if (j?.restituer != null) {
    // Un jeu qui porte des quantités restitue à sa façon (mouvements inverses nommés, jamais de stock négatif, article déjà sorti gardé).
    final r = j!.restituer!(lot, libelleMotif, motifMarque, port);
    archives = r.archives;
    gardees.addAll(r.gardees);
  } else {
    for (final e in ecrits) {
      if (e['avant'] != null) continue; // une modification se restitue plus bas, dans l'ordre inverse de son écriture
      final f = port.parId('${e['collection']}', e['id']);
      if (f == null || f['statut'] == 'archive') continue;
      // Une pièce émise s'appuie-t-elle sur CETTE fiche ? La dépendance du jeu est relue sur un lot d'une seule fiche.
      final dep = j?.dependances({'reference': lot['reference'], 'jeu': lot['jeu'], 'ecrits': [e]}, port);
      if (dep != null) {
        port.mettreAJour('${e['collection']}', e['id'], {champRefuseeParMere: motifMarque});
        gardees.add({'collection': e['collection'], 'id': e['id'], 'code': dep.code, 'motif': dep.motif});
        continue;
      }
      if (port.archiver('${e['collection']}', e['id'], libelleMotif)) {
        faits.add(e);
      } else {
        port.mettreAJour('${e['collection']}', e['id'], {champRefuseeParMere: motifMarque});
        gardees.add({'collection': e['collection'], 'id': e['id'], 'code': 'ARCHIVAGE_REFUSE', 'motif': 'le moteur a refusé d’archiver la fiche (garde ou exercice clos)'});
      }
    }
    archives = faits.length;
  }
  for (final m in ecrits.reversed) {
    final avant = m['avant'];
    if (avant is Map && port.parId('${m['collection']}', m['id']) != null) port.mettreAJour('${m['collection']}', m['id'], avant.cast<String, Object?>());
  }
  port.mettreAJour(collectionLots, lot['id'], {
    'etat': 'restitue',
    'restitueLe': port.jour,
    'motifRestitution': motifMarque,
    'restitueGardees': gardees.length,
    'restitueArchives': archives,
    'restitueGardeesDetail': gardees,
  });
  port.journaliser('Import restitué (refusé par la mère)', 'IMP', 'LotImport', '${lot['reference']}', {'etat': 'applique'}, {'etat': 'restitue', 'code': codeRefus, 'fiches': archives, 'gardees': gardees.length});
  return ResultatRestitution.ok(archives: archives, gardees: gardees);
}

/// Un lot écrit chez un fileul s'annule tant que la mère n'a pas statué. Une fois confirmé par elle, il ne s'annule plus ICI (la mère détient les mêmes fiches : l'annuler chez le fileul seul
/// ferait diverger les deux), et un lot déjà refusé se restitue tout seul. Rend le refus nommé, ou `null` quand l'annulation est permise ([demande] `null` : lot sans demande).
({String code, String motif, String geste})? refusAnnulationLotDirect(FicheImport? demande) {
  if (demande == null || demande['ecritureDirecte'] != true) return null;
  switch (demande['etat']) {
    case demandeImportAppliquee:
      return (
        code: 'LOT_CONFIRME_PAR_LA_MERE',
        motif: 'la mère a confirmé ce lot${demande['resultatLot'] == null || '${demande['resultatLot']}'.isEmpty ? '' : ' (lot ${demande['resultatLot']} chez elle)'} : elle détient les mêmes fiches et décide de la configuration',
        geste: 'Demandez l’annulation du lot à la mère, sur le poste principal : les fiches vous reviennent par la configuration.',
      );
    case demandeImportRefusee:
      return (
        code: 'RESTITUTION_PAR_LA_MERE',
        motif: 'la mère a refusé ce lot : votre écriture locale est restituée automatiquement',
        geste: 'Rien à faire : lisez le motif sur la demande.',
      );
  }
  return null;
}

/// Les champs qui RETIRENT une demande que le fileul annule avant la réponse de la mère (elle ne la traite plus ; les lignes du fichier sont effacées).
Map<String, Object?> champsRetraitDemande({required String par, required String jour}) =>
    {'etat': demandeImportRetiree, 'retireePar': par, 'retireeLe': jour, 'lignes': <Object?>[]};

/// Ce que le fileul doit faire d'une demande dont il a écrit le lot chez lui, d'après son état.
enum SuiteDuVerdict {
  /// Rien : la demande attend la mère, ou tout est déjà fait.
  aucune,

  /// La mère a refusé : restituer le lot local.
  restituer,

  /// La mère a confirmé : lever le marquage « en attente de la mère » des fiches qu'elle n'a pas encore remplacées.
  leverLeMarquage,

  /// LOT IDEM : la mère tient déjà ce contenu sous une AUTRE série que celle de ce fileul (il l'avait réimporté après une annulation) : son écriture locale est rebasée, c'est-à-dire
  /// restituée (jamais doublée) ; les fiches de la mère lui arrivent par la configuration. Ce n'est pas un refus.
  rebaser,
}

SuiteDuVerdict suiteDuVerdict(FicheImport demande) {
  if (demande['ecritureDirecte'] != true) return SuiteDuVerdict.aucune;
  switch (demande['etat']) {
    case demandeImportRefusee:
      return demande['restitution'] == restitutionFaite || demande['restitution'] == restitutionPartielle ? SuiteDuVerdict.aucune : SuiteDuVerdict.restituer;
    case demandeImportAppliquee:
      if (demande['marquageLeve'] == true || demande['restitution'] == restitutionFaite || demande['restitution'] == restitutionPartielle) return SuiteDuVerdict.aucune;
      final sienne = '${demande['serieIdentifiants'] ?? ''}', tenue = '${demande['resultatSerie'] ?? ''}';
      if (demande['resultatAdoptee'] == true && tenue.isNotEmpty && sienne.isNotEmpty && sienne != tenue) return SuiteDuVerdict.rebaser;
      return SuiteDuVerdict.leverLeMarquage;
  }
  return SuiteDuVerdict.aucune;
}

/// L'état d'une demande tel que le fileul le LIT : libellé et ton (`attention`, `succes`, `danger`, `neutre`). Un lot écrit chez le fileul n'est JAMAIS dit « appliqué » avant que la mère
/// l'ait confirmé : tant que la demande attend, le libellé dit « écrit chez vous, en attente de la mère ».
({String libelle, String ton}) libelleEtatDemandeImport(FicheImport demande) {
  final directe = demande['ecritureDirecte'] == true;
  switch (demande['etat']) {
    case demandeImportAppliquee:
      if (demande['resultatAdoptee'] == true) {
        return (
          libelle: demande['restitution'] == restitutionPartielle ? 'Déjà confirmé par la mère, adopté (restitution partielle de l’écriture locale)' : 'Déjà confirmé par la mère, adopté',
          ton: 'succes'
        );
      }
      return (libelle: 'Appliquée par la mère', ton: 'succes');
    case demandeImportRefusee:
      final r = demande['restitution'];
      if (!directe) return (libelle: 'Refusée par la mère', ton: 'danger');
      if (r == restitutionFaite) return (libelle: 'Refusée par la mère, écriture restituée', ton: 'danger');
      if (r == restitutionPartielle) return (libelle: 'Refusée par la mère, restitution partielle', ton: 'danger');
      return (libelle: 'Refusée par la mère, restitution en cours', ton: 'danger');
    case demandeImportRetiree:
      return (libelle: 'Retirée par vous', ton: 'neutre');
    case demandeImportEnAttente:
      return directe ? (libelle: 'Écrit chez vous, en attente de la mère', ton: 'attention') : (libelle: 'En attente de la mère', ton: 'attention');
  }
  return (libelle: '${demande['etat']}', ton: 'neutre');
}
