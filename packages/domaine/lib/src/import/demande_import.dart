/// LA DEMANDE D'IMPORT D'UN FILEUL À LA MÈRE (lot IMP-C, réponse Q5 de la Direction du 10/11/2026).
///
/// Le poste du gestionnaire de stock est un FILEUL. Un référentiel de configuration (famille R : la mère seule écrit) importé à un fileul est refusé par la règle existante
/// (« Réglé sur la mère », `CONFIGURATION_DE_LA_MERE`) : il passe donc par une DEMANDE D'IMPORT vérifiée. Ce fichier ne porte que les règles pures :
///
///  * [jeuExigeLaMere] : quand un jeu passe par une demande (un de ses collections cibles est de configuration) ;
///  * [composerDemandeImport] : ce que le fileul dépose, APRÈS avoir fait la même vérification que la mère (rien n'est envoyé d'un fichier refusé) ;
///  * [traiterDemandeImport] : ce que la MÈRE fait de la demande : elle REJOUE l'analyse sous le rôle et le nom de l'auteur (un bouton absent au fileul ne protège rien, et un autre
///    poste a pu créer la même fiche entre-temps), puis applique par le MÊME chemin que l'import local (`appliquer`) ou refuse en NOMMANT le code, le motif et le geste.
///
/// La demande est une fiche descriptive (`demandesImport`) : le fileul la dépose, la mère la complète du verdict, qui revient au fileul par le même chemin (précédent : `propositionsTarif`
/// du lot T6). Les lignes du fichier voyagent dans la demande (la mère doit pouvoir rejouer) : elles sont EFFACÉES de la fiche dès que la mère a rendu son verdict, et un verdict
/// d'un jeu restreint ne recopie aucune valeur de cellule (motifs fixes, comme l'historique d'un lot, RG-13).
library;

import 'moteur_import.dart';
import '../droits/droit_import.dart';

/// La collection des demandes (famille A de la synchronisation : champ à champ, dans les deux sens).
const String demandesImportCollection = 'demandesImport';

/// États d'une demande : `en_attente` (déposée, la mère n'a pas encore statué), `appliquee`, `refusee`.
const String demandeImportEnAttente = 'en_attente', demandeImportAppliquee = 'appliquee', demandeImportRefusee = 'refusee';

/// Un jeu passe par une demande quand un fileul rattaché ne peut écrire l'une de ses collections cibles : [collectionsDeLaMere] est l'ensemble des collections de configuration
/// (garde « réglé sur la mère »).
bool jeuExigeLaMere(DeclarationImport d, Set<String> collectionsDeLaMere) => d.collections.any(collectionsDeLaMere.contains);

/// La fiche déposée par le fileul. [analyse] est celle qu'il a faite lui-même (acceptée, au moins une ligne à écrire) : un fichier refusé ne part jamais.
Map<String, Object?> composerDemandeImport({
  required String id,
  required JeuImport jeu,
  required AnalyseImport analyse,
  required String role,
  required String par,
  required String jour,
  required bool restreint,
}) {
  assert(analyse.accepte && analyse.aEcrire > 0, 'une demande ne part que d\'un fichier vérifié');
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
  };
}

/// Le verdict de la mère sur une demande.
class VerdictDemandeImport {
  const VerdictDemandeImport.appliquee({required this.lot, required this.ecrits})
      : appliquee = true,
        code = null,
        motif = null,
        geste = null;
  const VerdictDemandeImport.refusee(String this.code, String this.motif, String this.geste, {this.lot})
      : appliquee = false,
        ecrits = 0;
  final bool appliquee;
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
VerdictDemandeImport traiterDemandeImport(FicheImport demande, PortImport port, JeuImport? Function(String id) jeu) {
  final j = jeu('${demande['jeu']}');
  if (j == null) {
    return VerdictDemandeImport.refusee('JEU_INCONNU', 'le jeu « ${demande['jeu']} » n’existe pas à la mère', 'Refaire la demande depuis la page du jeu, avec une version à jour du poste.');
  }
  final rd = refusDroitImport(j, 'importer', port);
  if (rd != null) return VerdictDemandeImport.refusee(rd.code!, rd.motif!, rd.geste!);
  final lignes = [
    for (final l in (demande['lignes'] as List? ?? const [])) [for (final c in (l as List)) c]
  ];
  final a = analyserLignes(j, lignes, '${demande['fichier'] ?? ''}', port)..empreinte = demande['empreinte'] as String?;
  if (!a.accepte) {
    // Rejoué à la mère, le fichier ne passe plus (un autre poste a pu écrire la même fiche) : refusé en NOMMANT la première cause, consigné à l'historique de la mère.
    final premier = [for (final p in a.problemes.map((p) => masquerProbleme(j, p, port))) if (p.estRefus) p].firstOrNull;
    final lot = consigner(j, a, port);
    return VerdictDemandeImport.refusee(
        premier?.code ?? 'ANALYSE_REFUSEE',
        premier == null
            ? 'le fichier ne passe plus l’analyse à la mère'
            : 'rejoué à la mère, le fichier est refusé${premier.n > 0 ? ' (ligne ${premier.n}, ${premier.colonne})' : ''} : ${premier.motif}',
        premier?.geste ?? 'Corrigez le fichier puis refaites la demande.',
        lot: lot == null ? null : '${lot['reference']}');
  }
  final r = appliquer(j, a, port);
  if (r.ok) return VerdictDemandeImport.appliquee(lot: '${r.lot!['reference']}', ecrits: r.ecrits);
  return VerdictDemandeImport.refusee(r.code ?? 'ECRITURE_REFUSEE', r.motif ?? 'l’écriture a été refusée', r.geste ?? 'Rien n’a été écrit.', lot: r.lot == null ? null : '${r.lot!['reference']}');
}
