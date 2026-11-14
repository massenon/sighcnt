import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sigh_domaine/sigh_domaine.dart';

import '../import/port_magasin.dart';
import '../sync/configuration_sync.dart' show collectionsConfiguration;
import '../sync/fusion_activite.dart' show champsCompteurs;
import '../sync/pont_activite.dart' show collectionsActivite;
import 'magasin.dart';
import 'tarifs_poste.dart';

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
///
/// LOT IMP-D (décision N de la Direction, 12/11/2026) : un fileul importe AUSSI directement dans son propre magasin, la mère restant l'autorité de la configuration. Pour un jeu dont toutes
/// les cibles sont de la configuration, [importerEtDemander] écrit chez le fileul tout de suite (par le MÊME chemin que l'import de la mère : `appliquer`, sous la garde qui ne laisse
/// passer que ce geste) ET dépose la demande automatiquement, en UN geste ; [traiterVerdicts] fait ensuite ce que le verdict commande (restituer sur refus, lever le marquage sur
/// confirmation) ; [annulerLotDuFileul] annule tant que la mère n'a pas statué. LOT IMP-E (décision du 13/11/2026) : le Grand Stock s'écrit AUSSI chez le fileul (produits, lots,
/// mouvements), avec idempotence : identité commune des fiches, valeur de départ des compteurs, fiche propre au poste tant que la mère n'a pas confirmé. Le personnel reste à la mère.
class DemandesImportPoste {
  DemandesImportPoste(this.m, {required this.role, required this.auteur, required this.matrice, required this.aujourdhui, this.etiquette = 'P', this.fileulRattache = false});
  final Magasin m;
  final String role;
  final String Function() auteur;

  /// La matrice d'import EN FORCE (celle de `rbac.json` superposée à chaud) : le droit et la sensibilité du jeu sont lus d'ici.
  final MatriceDroits matrice;
  final DateTime Function() aujourdhui;

  /// L'étiquette du poste, qui rend unique l'identifiant d'une demande déposée.
  final String etiquette;

  /// Ce poste est un fileul rattaché (la décision d'un prix est alors tenue par la mère).
  final bool fileulRattache;

  /// Les collections que la mère seule écrit au poste : celles de la configuration (garde « réglé sur la mère » des fileuls rattachés).
  static Set<String> collectionsDeLaMere() => collectionsConfiguration();

  /// La VOIE de ce jeu sur ce poste (lot IMP-D). Hors fileul rattaché (la mère, un poste autonome) tout s'écrit directement.
  static VoieImportFileul voie({required bool fileulRattache, required DeclarationImport? declaration}) => !fileulRattache || declaration == null
      ? VoieImportFileul.directe
      : voieImportFileul(declaration, configuration: collectionsDeLaMere());

  /// LOT 8B : les libellés des rôles que les refus de prix NOMMENT (ceux qui décident, ceux qui datent dans le passé), pour que « une autorité de la Directrice Administrative et de la Direction »
  /// ne devienne pas « de da et direction ».
  static Map<String, String> libellesDesRoles(MatriceDroits? m) => {
        for (final r in {...tarRolesValidation, ...tarRolesDatePassee}) r: m?.libelle(r) ?? r,
      };

  /// LOT 8B : ce que la validation d'un prix à l'import laisse à FAIRE (le marquage « tarif d'attente » levé, la projection des fiches de lecture refaite, comme après un Oui à l'écran).
  /// À appeler sur la MÈRE, après qu'un lot du jeu `tarifs` a été écrit (par elle ou pour le compte d'une demande) ; sans effet pour un autre jeu et pour un lot de propositions.
  void apresImportDePrix(Fiche? lot) {
    // Lot TFIN-2 : les prix d'achat validés d'emblée (jeu `tarifs-produits`) font la même suite : la fiche du produit suit la version en vigueur (`TarifsPoste._projeterProduit`).
    if (lot == null || (lot['jeu'] != 'tarifs' && lot['jeu'] != 'tarifs-produits')) return;
    final tarifs = TarifsPoste(m, role: role, auteur: auteur, libelles: libellesDesRoles(matrice), horloge: aujourdhui, etiquette: etiquette);
    final versions = [for (final e in ((lot['ecrits'] as List?) ?? const []).cast<Map>()) if (e['collection'] == 'versionsTarif') m.collection('versionsTarif').parId(e['id'])].whereType<Fiche>();
    tarifs.apresImport([for (final v in versions) if (v['statut'] == 'valide') v]);
  }

  /// LOT 8 : les jeux que ce poste ne peut PAS écrire (le moteur refuse, nommé) : sur un fileul rattaché, ceux dont la voie est « réservée à la mère » (jeu restreint qui écrit la configuration :
  /// le personnel, le stock détail initial, le bon de transfert). Ailleurs, aucun.
  static Set<String> reservesALaMere({required bool fileulRattache, required MatriceImport matrice}) => {
        if (fileulRattache)
          for (final d in matrice.declarations)
            if (voie(fileulRattache: true, declaration: d) == VoieImportFileul.reserveeALaMere) d.id
      };

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
          profil: ProfilImport(
              role: roleAuteur,
              libelleRole: matrice.libelle(roleAuteur) ?? roleAuteur,
              matrice: matrice.matriceImport,
              bornes: _bornes(),
              libellesRoles: libellesDesRoles(matrice),
              // La demande vient d'un fileul : la décision d'un prix reste à la mère, le Oui vaut proposition (comme à la vérification du fileul).
              fileul: true));
      final VerdictDemandeImport v;
      try {
        v = traiterDemandeImport(d, port, jeuImportParId, compteurs: champsCompteurs);
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
      // LOT IDEM : une demande déjà traitée une fois (`traitePar`) que la mère rejoue (verdict perdu, demande reçue deux fois) rend le même verdict sans le journaliser de nouveau.
      final dejaTraitee = '${d['traitePar'] ?? ''}'.isNotEmpty;
      col.mettreAJour('${d['id']}', v.versChamps(traitePar: 'Mère', traiteLe: _jour));
      if (v.appliquee && !dejaTraitee) {
        apresImportDePrix(m.collection(collectionLots).toutes.where((l) => l['reference'] == v.lot).firstOrNull);
      }
      if (!dejaTraitee) {
        m.journaliser(
            v.appliquee ? (v.adoptee ? 'Demande d’import adoptée (déjà confirmée)' : 'Demande d’import appliquée') : 'Demande d’import refusée', 'IMP', 'DemandeImport', '${d['id']}',
            {'etat': demandeImportEnAttente}, {'jeu': d['jeu'], 'par': parAuteur, 'code': v.code, 'lot': v.lot});
      }
      n++;
    }
    return n;
  }

  Map<String, int> _bornes() {
    final v = m.collection('reglages').parId('importBornes')?['valeur'];
    return v is Map ? {for (final e in v.entries) if (e.value is num && (e.value as num) > 0) '${e.key}': (e.value as num).floor()} : <String, int>{};
  }

  /// Le port d'écriture de ce poste (pour les tests qui analysent un fichier sur ce magasin).
  @visibleForTesting
  PortImport portPourTests(ProfilImport profil) => PortMagasin(m, aujourdhui: aujourdhui, nomAgent: auteur(), profil: profil);

  PortMagasin _port({String? nomAgent}) => PortMagasin(m,
      aujourdhui: aujourdhui,
      nomAgent: nomAgent ?? auteur(),
      profil: ProfilImport(
          role: role,
          libelleRole: matrice.libelle(role) ?? role,
          matrice: matrice.matriceImport,
          bornes: _bornes(),
          libellesRoles: libellesDesRoles(matrice),
          fileul: fileulRattache,
          surFileul: fileulRattache));

  /// Les collections que l'import de [jeu] peut écrire chez ce fileul : ses cibles, rien d'autre.
  Set<String> _autorisees(JeuImport jeu, [Iterable<Map>? ecrits]) => {...collectionsAutoriseesAuFileul(jeu), if (ecrits != null) for (final e in ecrits) '${e['collection']}'};

  /// FILEUL (voie `directeEtDemande`) : écrit le fichier VÉRIFIÉ chez lui, tout de suite, ET dépose la demande à la mère, en UN geste. L'écriture passe par le même chemin que l'import de
  /// la mère (`appliquer`, droit d'importer relu par le moteur), sous les identifiants de la demande (la mère les rejouera à l'identique) ; chaque fiche porte le marquage « en attente
  /// de la mère ». Un refus du moteur n'écrit rien et ne dépose rien. Si le dépôt échoue après l'écriture, l'écriture est restituée : jamais une écriture sans demande.
  ///
  /// Rend le résultat du moteur et la demande déposée (`null` : rien n'est parti).
  ({ResultatImport resultat, Fiche? demande}) importerEtDemander(JeuImport jeu, AnalyseImport analyse) {
    final col = m.collection(demandesImportCollection);
    final id = 'DIM$etiquette${aujourdhui().microsecondsSinceEpoch}${col.toutes.length}';
    // LOT IDEM : la série des identifiants de fiche dérive du CONTENU du fichier (la même chez tous les postes qui importent ce contenu), le marquage « en attente » reste celui de la demande.
    final lot = preparerLotImport(jeu, analyse.lignesBrutes, _port());
    final r = m.pendantImportFileul(
        _autorisees(jeu),
        () => appliquerDemande(
            jeu, analyse, PortDemandeImport(_port(), demandeId: lot.serie, marquage: id, identiteLot: lot.identite, marquerEnAttente: true, compteurs: champsCompteurs)));
    if (!r.ok) return (resultat: r, demande: null);
    final fiche = composerDemandeImport(
        id: id,
        jeu: jeu,
        analyse: analyse,
        role: role,
        par: auteur(),
        jour: _jour,
        restreint: matrice.matriceImport.declaration(jeu.id)?.restreint ?? true,
        lotLocal: '${r.lot!['reference']}',
        lotLocalId: r.lot!['id'],
        serie: lot.serie,
        identiteLot: lot.identite);
    try {
      // Le journal ne recopie aucune valeur de cellule (RG-12, RG-13).
      m.journaliser('Import écrit chez le fileul, demande déposée à la mère', 'IMP', 'DemandeImport', id, null,
          {'jeu': jeu.id, 'fichier': analyse.fichier, 'lignes': analyse.nbLignes, 'lot': fiche['lotLocal'], 'role': role});
      col.inserer(fiche);
    } catch (e) {
      m.pendantImportFileul(_autorisees(jeu), () => restituerLotDirect(jeuImportParId, r.lot!['id'], codeRefus: 'DEMANDE_NON_DEPOSEE', motifRefus: '$e', port: _port()));
      return (
        resultat: ResultatImport.refus('DEMANDE_NON_DEPOSEE', 'la demande à la mère n’a pas pu être déposée : $e', 'Rien n’est resté écrit chez vous : l’écriture a été restituée. Refaites l’import.'),
        demande: null
      );
    }
    return (resultat: r, demande: col.parId(id) ?? fiche);
  }

  /// La demande dont CE poste a écrit le lot [lotId] chez lui (voie directe), ou `null`.
  Fiche? demandeDuLot(Object? lotId) => [for (final d in m.collection(demandesImportCollection).toutes) if (d['statut'] != 'archive' && d['lotLocalId'] == lotId) d].firstOrNull;

  /// FILEUL : annule un lot écrit chez lui. Tant que la mère n'a pas statué, le lot s'annule comme tout lot (droit d'annuler du jeu, archivage RG-14) ET la demande est retirée (la mère
  /// ne la traite plus). Confirmé par la mère, le lot ne s'annule plus ici (elle détient les mêmes fiches) : refus nommé. Rend le résultat du moteur.
  ResultatImport annulerLotDuFileul(Object? lotId, {String? motif}) {
    final lot = m.collection(collectionLots).parId(lotId);
    if (lot == null) return const ResultatImport.refus('LOT_INCONNU', 'lot introuvable', 'Actualisez l’historique.');
    final demande = demandeDuLot(lotId);
    final refus = refusAnnulationLotDirect(demande);
    if (refus != null) return ResultatImport.refus(refus.code, refus.motif, refus.geste);
    final jeu = jeuImportParId('${lot['jeu']}');
    final ecrits = ((lot['ecrits'] as List?) ?? const []).cast<Map>();
    final r = m.pendantImportFileul(
        {if (jeu != null) ...collectionsAutoriseesAuFileul(jeu), for (final e in ecrits) '${e['collection']}'}, () => annulerLot(jeuImportParId, lotId, motif, _port()));
    if (r.ok && demande != null && demande['etat'] == demandeImportEnAttente) {
      m.collection(demandesImportCollection).mettreAJour('${demande['id']}', champsRetraitDemande(par: auteur(), jour: _jour), journaliser: false);
      m.journaliser('Demande d’import retirée (lot annulé)', 'IMP', 'DemandeImport', '${demande['id']}', {'etat': demandeImportEnAttente}, {'etat': demandeImportRetiree});
    }
    return r;
  }

  /// FILEUL : fait ce que le verdict de la mère commande pour les lots écrits ICI. Refusée : le lot est RESTITUÉ (archivage, jamais une suppression ; les fiches qu'une pièce émise
  /// utilise restent, marquées) et la demande le dit. Confirmée : le marquage « en attente de la mère » est levé des fiches que la configuration de la mère n'a pas encore remplacées.
  /// Idempotent. Rend le nombre de demandes suivies.
  int traiterVerdicts() {
    final col = m.collection(demandesImportCollection);
    var n = 0;
    for (final d in List<Fiche>.of(col.toutes)) {
      if (d['statut'] == 'archive' || d['ecritureDirecte'] != true) continue;
      final lot = m.collection(collectionLots).parId(d['lotLocalId']);
      if (lot == null) continue; // la demande d'un autre poste : à lui de la suivre
      final ecrits = ((lot['ecrits'] as List?) ?? const []).cast<Map>();
      final jeu = jeuImportParId('${d['jeu']}');
      switch (suiteDuVerdict(d)) {
        case SuiteDuVerdict.aucune:
          break;
        case SuiteDuVerdict.restituer:
          final r = m.pendantImportFileul(
              {if (jeu != null) ...collectionsAutoriseesAuFileul(jeu), for (final e in ecrits) '${e['collection']}'},
              () => restituerLotDirect(jeuImportParId, d['lotLocalId'],
                  codeRefus: '${d['resultatCode']}', motifRefus: '${d['resultatMotif']}', port: _port(nomAgent: '${d['demandePar']}')));
          // Un lot déjà annulé à la main n'a rien à restituer : la demande le dit comme restitué.
          final dejaFait = !r.ok && r.code == 'LOT_NON_APPLIQUE';
          if (r.ok || dejaFait) {
            col.mettreAJour('${d['id']}', {
              'restitution': dejaFait ? restitutionFaite : r.etat,
              'restitutionLe': _jour,
              'restitutionArchives': r.archives,
              'restitutionGardees': [for (final g in r.gardees) {'collection': g['collection'], 'id': g['id'], 'code': g['code'], 'motif': g['motif']}],
            }, journaliser: false);
            n++;
          }
        case SuiteDuVerdict.rebaser:
          // LOT IDEM : la mère tient déjà ce contenu sous une autre série (ce fileul l'avait réimporté après une annulation) : son écriture locale est RESTITUÉE (archivage, contre-passations
          // nommées, un article déjà sorti reste, marqué) ; les fiches de la mère lui arrivent par la configuration. Ce n'est pas un refus : la demande reste « appliquée, adoptée ».
          final r = m.pendantImportFileul(
              {if (jeu != null) ...collectionsAutoriseesAuFileul(jeu), for (final e in ecrits) '${e['collection']}'},
              () => restituerLotDirect(jeuImportParId, d['lotLocalId'],
                  codeRefus: 'LOT_ADOPTE',
                  motifRefus: 'la mère tient déjà ce contenu sous la série ${d['resultatSerie']} : votre écriture locale (série ${d['serieIdentifiants']}) est remplacée par la sienne',
                  port: _port(nomAgent: '${d['demandePar']}')));
          final dejaFait = !r.ok && r.code == 'LOT_NON_APPLIQUE';
          if (r.ok || dejaFait) {
            col.mettreAJour('${d['id']}', {
              'restitution': dejaFait ? restitutionFaite : r.etat,
              'restitutionLe': _jour,
              'restitutionArchives': r.archives,
              'restitutionGardees': [for (final g in r.gardees) {'collection': g['collection'], 'id': g['id'], 'code': g['code'], 'motif': g['motif']}],
              'marquageLeve': true,
            }, journaliser: false);
            n++;
          }
        case SuiteDuVerdict.leverLeMarquage:
          // LOT IMP-E : une fiche d'une collection que le pont synchronise (stock, lots, mouvements) n'est confirmée que par l'ARRIVÉE de la fiche de la mère (le pont lève alors le marquage) :
          // lever le marquage avant ferait partir au journal la version du fileul avant celle de la mère. La demande reste « à suivre » tant qu'il en reste une.
          var attendues = 0;
          for (final e in ecrits) {
            final c = '${e['collection']}';
            final f = m.collection(c).parId(e['id']);
            if (f == null || f[champEnAttenteMere] != d['id']) continue;
            if (collectionsActivite.contains(c)) {
              attendues++;
            } else {
              m.collection(c).retirerChamp(e['id'], champEnAttenteMere);
            }
          }
          if (attendues == 0) {
            col.mettreAJour('${d['id']}', {'marquageLeve': true}, journaliser: false);
            n++;
          }
      }
    }
    return n;
  }

  /// Les demandes que CE poste a déposées, de la plus récente à la plus ancienne (le fileul voit l'état de chacune).
  List<Fiche> sesDemandes({String? jeu}) => [
        for (final d in m.collection(demandesImportCollection).toutes)
          if (d['statut'] != 'archive' && '${d['demandePar']}' == auteur() && (jeu == null || d['jeu'] == jeu)) d
      ]..sort((a, b) => '${b['demandeLe']}${b['id']}'.compareTo('${a['demandeLe']}${a['id']}'));
}
