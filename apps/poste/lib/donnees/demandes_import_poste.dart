import 'package:sigh_domaine/sigh_domaine.dart';

import '../import/port_magasin.dart';
import '../sync/configuration_sync.dart' show collectionsConfiguration;
import 'magasin.dart';

/// LA DEMANDE D'IMPORT AU POSTE (lot IMP-C, réponse Q5 de la Direction) : la colle entre les règles pures de `packages/domaine/lib/src/import/demande_import.dart` (rejouées sur le
/// magasin d'un test et sur les vecteurs de la maquette) et le magasin du poste. Aucune règle d'import ici.
///
///  * FILEUL rattaché : un jeu dont une collection cible est de CONFIGURATION (famille R, la mère seule écrit) ne s'écrit pas ici (garde « réglé sur la mère », `CONFIGURATION_DE_LA_MERE`) :
///    la fenêtre propose d'envoyer une DEMANDE, après la même vérification que la mère ferait. Le fileul DÉPOSE une fiche `demandesImport` (famille A, voir `pont_activite.dart`) ; il
///    voit ensuite son état (en attente, appliquée, refusée avec son code, son motif et son geste).
///  * MÈRE : [appliquerDemandes] traite les demandes en attente, une à une, dans l'ordre du dépôt : elle REJOUE l'analyse sous le rôle et le nom de l'auteur, applique par le même chemin
///    que l'import local ou refuse en nommant, écrit le verdict sur la fiche (qui revient au fileul par le pont) et efface les lignes du fichier.
///
/// Un import de la mère elle-même reste local et direct : aucune demande.
class DemandesImportPoste {
  DemandesImportPoste(this.m, {required this.role, required this.auteur, required this.matrice, required this.aujourdhui, this.etiquette = 'P'});
  final Magasin m;
  final String role;
  final String Function() auteur;

  /// La matrice d'import EN FORCE (celle de `rbac.json` superposée à chaud) : le droit et la sensibilité du jeu sont lus d'ici.
  final MatriceDroits matrice;
  final DateTime Function() aujourdhui;

  /// L'étiquette du poste, qui rend unique l'identifiant d'une demande déposée.
  final String etiquette;

  /// Les collections que la mère seule écrit au poste : celles de la configuration (garde « réglé sur la mère » des fileuls rattachés).
  static Set<String> collectionsDeLaMere() => collectionsConfiguration();

  /// Le jeu passe-t-il par une demande sur ce poste ? Seulement sur un FILEUL RATTACHÉ, et seulement quand une collection cible est de configuration.
  static bool passeParUneDemande({required bool fileulRattache, required DeclarationImport? declaration}) =>
      fileulRattache && declaration != null && jeuExigeLaMere(declaration, collectionsDeLaMere());

  /// Un jeu RESTREINT qui écrit de la configuration ne s'importe qu'à la mère : sur un fileul rattaché, la fenêtre le dit et ne propose rien.
  static bool reserveALaMere({required bool fileulRattache, required DeclarationImport? declaration}) =>
      fileulRattache && declaration != null && jeuReserveALaMere(declaration, collectionsDeLaMere());

  String get _jour {
    final d = aujourdhui();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// FILEUL : dépose la demande d'un fichier DÉJÀ vérifié (accepté, au moins une ligne à écrire). Rend la fiche déposée.
  Fiche deposer(JeuImport jeu, AnalyseImport analyse) {
    final col = m.collection(demandesImportCollection);
    final id = 'DIM$etiquette${aujourdhui().microsecondsSinceEpoch}${col.toutes.length}';
    final fiche = composerDemandeImport(
        id: id, jeu: jeu, analyse: analyse, role: role, par: auteur(), jour: _jour, restreint: matrice.matriceImport.declaration(jeu.id)?.restreint ?? true);
    // Le journal ne recopie aucune valeur de cellule : le jeu, le fichier et les comptes seulement (RG-12, RG-13).
    m.journaliser('Demande d’import déposée à la mère', 'IMP', 'DemandeImport', id, null, {'jeu': jeu.id, 'fichier': analyse.fichier, 'lignes': analyse.nbLignes, 'role': role});
    col.inserer(fiche);
    return col.parId(id) ?? fiche;
  }

  /// MÈRE : traite les demandes en attente. Chacune refait la MÊME analyse sous le rôle et le nom de son auteur (un bouton absent au fileul ne protège rien, et un autre poste a pu
  /// créer la même fiche) ; le verdict est écrit sur la demande et revient au fileul par le pont. Rend le nombre de demandes traitées.
  int appliquerDemandes() {
    final col = m.collection(demandesImportCollection);
    final enAttente = [for (final d in col.toutes) if (d['statut'] != 'archive' && d['etat'] == demandeImportEnAttente) d]
      ..sort((a, b) => '${a['demandeLe']}${a['id']}'.compareTo('${b['demandeLe']}${b['id']}'));
    var n = 0;
    for (final d in enAttente) {
      final roleAuteur = '${d['demandeRole']}', parAuteur = '${d['demandePar']}';
      final port = PortMagasin(m,
          aujourdhui: aujourdhui,
          nomAgent: parAuteur,
          profil: ProfilImport(role: roleAuteur, libelleRole: matrice.libelle(roleAuteur) ?? roleAuteur, matrice: matrice.matriceImport, bornes: _bornes()));
      final VerdictDemandeImport v;
      try {
        v = traiterDemandeImport(d, port, jeuImportParId);
      } catch (e) {
        // Jamais muet : une exception se nomme aussi, et la demande reste lisible du fileul.
        col.mettreAJour('${d['id']}', {
          'etat': demandeImportRefusee,
          'resultatCode': 'ECRITURE_REFUSEE',
          'resultatMotif': '$e',
          'resultatGeste': 'Rien n’a été écrit. Corrigez la cause puis refaites la demande.',
          'traitePar': 'Mère',
          'traiteLe': _jour,
          'lignes': <Object?>[],
        });
        n++;
        continue;
      }
      col.mettreAJour('${d['id']}', v.versChamps(traitePar: 'Mère', traiteLe: _jour));
      m.journaliser(v.appliquee ? 'Demande d’import appliquée' : 'Demande d’import refusée', 'IMP', 'DemandeImport', '${d['id']}',
          {'etat': demandeImportEnAttente}, {'jeu': d['jeu'], 'par': parAuteur, 'code': v.code, 'lot': v.lot});
      n++;
    }
    return n;
  }

  Map<String, int> _bornes() {
    final v = m.collection('reglages').parId('importBornes')?['valeur'];
    return v is Map ? {for (final e in v.entries) if (e.value is num && (e.value as num) > 0) '${e.key}': (e.value as num).floor()} : <String, int>{};
  }

  /// Les demandes que CE poste a déposées, de la plus récente à la plus ancienne (le fileul voit l'état de chacune).
  List<Fiche> sesDemandes({String? jeu}) => [
        for (final d in m.collection(demandesImportCollection).toutes)
          if (d['statut'] != 'archive' && '${d['demandePar']}' == auteur() && (jeu == null || d['jeu'] == jeu)) d
      ]..sort((a, b) => '${b['demandeLe']}${b['id']}'.compareTo('${a['demandeLe']}${a['id']}'));
}
