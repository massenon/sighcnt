import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sigh_domaine/sigh_domaine.dart' show cpcGardeEcritures;

typedef Fiche = Map<String, Object?>;

/// Refus NOMMÉ d'une écriture par une GARDE posée sur la collection (`S.garder` de la maquette) : un exercice clos refuse toute écriture, d'où
/// qu'elle vienne. Rien n'a été écrit ; le refus est journalisé (RG-12).
class EcritureRefusee implements Exception {
  const EcritureRefusee(this.collection, this.operation, this.motif);
  final String collection;
  final String operation;
  final String motif;
  @override
  String toString() => motif;
}

/// Une collection du magasin (`S.collection(nom)` de la maquette) : fiches actives / archivées, archivage LOGIQUE annulable (RG-14 : jamais de
/// suppression physique). Lecture SYNCHRONE — c'est ce qui permet aux écrans de se composer comme ceux de la maquette.
///
/// C'est la COUTURE vers la persistance : ce magasin est en mémoire, hydraté depuis le jeu de démonstration ; la base locale et le journal
/// d'opérations (plan S4) viendront derrière la même interface sans toucher aux écrans.
class CollectionMagasin extends ChangeNotifier {
  CollectionMagasin(this.nom, Iterable<Fiche> fiches,
      {this.journal, this.module = '—', this.entite})
      : _fiches = [
          for (final f in fiches) {...f}
        ];
  final String nom;
  final List<Fiche> _fiches;

  /// RG-12 : toute écriture est journalisée (qui, quand, quoi, valeurs avant / après) — aucune action anonyme. `null` : collection de journal.
  final void Function(String action, String module, String entite,
      String reference, Object? avant, Object? apres)? journal;
  final String module;
  final String? entite;

  /// POINT D'EXTENSION (additif) : des gardes de lecture seule posées SUR la collection — `garde(operation, fiche)` rend le motif du refus ou
  /// `null`. Opérations : `inserer`, `modifier` (la fiche telle qu'elle serait après la mise à jour), `archiver`. Une garde refusée journalise et lève
  /// [EcritureRefusee] AVANT toute écriture : masquer un bouton ne protège rien.
  final List<String? Function(String operation, Fiche fiche)> _gardes = [];
  void garder(String? Function(String operation, Fiche fiche) garde) =>
      _gardes.add(garde);

  void _controler(String operation, Fiche fiche) {
    for (final g in _gardes) {
      final motif = g(operation, fiche);
      if (motif != null) {
        journal?.call('Écriture refusée', '—', nom,
            '${fiche['id'] ?? fiche['numero'] ?? ''}', null, {'op': operation, 'motif': motif});
        throw EcritureRefusee(nom, operation, motif);
      }
    }
  }

  static String _ref(Fiche f) =>
      '${f['numero'] ?? f['reference'] ?? f['code'] ?? f['id']}';

  /// Insère une fiche (`col.insert`) : un identifiant `<PREFIXE><rang>` est attribué s'il manque ; rend la fiche et la fonction qui l'ARCHIVE
  /// (une insertion ne se défait pas par suppression physique, RG-14).
  ({Fiche fiche, VoidCallback annuler}) inserer(Fiche f,
      {String prefixe = 'ID'}) {
    final nouvelle = {...f};
    if (_gardes.isNotEmpty) _controler('inserer', nouvelle);
    nouvelle['id'] ??=
        '$prefixe${(_fiches.length + 1).toString().padLeft(5, '0')}';
    // La maquette insère EN TÊTE (`db[name].unshift`) : l'ordre d'une collection se voit (tris à égalité, ordre d'un lot transmis à la MECeF).
    _fiches.insert(0, nouvelle);
    journal?.call(
        'Création', module, entite ?? nom, _ref(nouvelle), null, null);
    notifyListeners();
    return (fiche: nouvelle, annuler: () => archiver(nouvelle['id']));
  }

  static bool estArchivee(Fiche f) => f['statut'] == 'archive';

  List<Fiche> get actives => [
        for (final f in _fiches)
          if (!estArchivee(f)) f
      ];
  List<Fiche> get archivees => [
        for (final f in _fiches)
          if (estArchivee(f)) f
      ];
  List<Fiche> get toutes => List.unmodifiable(_fiches);
  Fiche? parId(Object? id) => _fiches.where((f) => f['id'] == id).firstOrNull;

  /// Plafonne le tampon : seules les `max` fiches les plus RÉCENTES (en tête) sont gardées (réservé au journal d'audit, dont le plafond est celui de la maquette).
  void plafonner(int max) {
    if (_fiches.length > max) _fiches.removeRange(max, _fiches.length);
  }

  /// Met à jour des champs de la fiche (`col.update`) et rend la fonction qui RESTITUE l'état d'avant. Rien n'est supprimé : un champ ajouté
  /// par la mise à jour est retiré à l'annulation.
  VoidCallback mettreAJour(Object? id, Fiche patch) {
    final f = parId(id);
    if (f == null) return () {};
    if (_gardes.isNotEmpty) _controler('modifier', {...f, ...patch});
    final avant = <String, Object?>{for (final k in patch.keys) k: f[k]};
    final existait = {for (final k in patch.keys) k: f.containsKey(k)};
    f.addAll(patch);
    journal?.call('Modification', module, entite ?? nom, _ref(f), avant,
        {for (final k in patch.keys) k: patch[k]});
    notifyListeners();
    return () {
      for (final k in patch.keys) {
        existait[k]! ? f[k] = avant[k] : f.remove(k);
      }
      journal?.call('Annulation', module, entite ?? nom, _ref(f), null, null);
      notifyListeners();
    };
  }

  /// Archive la fiche (`statut: 'archive'`, ancien statut conservé) et rend la fonction qui ANNULE — une annulation doit être possible
  /// et visible (CLAUDE.md, « quatre pièges »).
  VoidCallback archiver(Object? id) {
    final f = parId(id);
    if (f == null || estArchivee(f)) return () {};
    if (_gardes.isNotEmpty) _controler('archiver', f);
    f['statutAvantArchivage'] = f['statut'];
    f['statut'] = 'archive';
    journal?.call('Archivage', module, entite ?? nom, _ref(f),
        {'statut': f['statutAvantArchivage']}, {'statut': 'archive'});
    notifyListeners();
    return () => restaurer(id);
  }

  void restaurer(Object? id) {
    final f = parId(id);
    if (f == null || !estArchivee(f)) return;
    final avant = f.remove('statutAvantArchivage');
    if (avant == null) {
      f.remove('statut');
    } else {
      f['statut'] = avant;
    }
    journal?.call('Restauration', module, entite ?? nom, _ref(f),
        {'statut': 'archive'}, {'statut': avant});
    notifyListeners();
  }
}

class Magasin {
  Magasin([
    Map<String, Iterable<Fiche>> jeux = const {},
    this.poste = 'POSTE',
    this.referentiels = const {},
  ]) : _jeux = {for (final e in jeux.entries) e.key: e.value};

  /// Référentiels STATIQUES de la maquette (`D.ANALYSES`, `D.TYPES_CHAMBRE`…) : ils ne sont pas des collections, on ne les écrit pas.
  final Map<String, Object?> referentiels;

  List<Fiche> referentiel(String nom) => [
        for (final f in (referentiels[nom] as List? ?? const []))
          (f as Map).cast<String, Object?>()
      ];
  final Map<String, Iterable<Fiche>> _jeux;
  final Map<String, CollectionMagasin> _c = {};

  /// Identifiant du poste, porté par chaque entrée du journal.
  final String poste;

  /// Agent connecté, posé par la coque : le journal ne connaît jamais d'action anonyme.
  String utilisateur = 'Système';

  /// Horloge du journal (fixable par un test).
  DateTime Function() horloge = DateTime.now;

  static const _modules = {
    'factures': 'M8',
    'avoirs': 'M8',
    'taches': 'SOCLE',
    'patients': 'M1',
    'ordonnances': 'M2',
    'demandesAnalyses': 'M5',
    'demandesImagerie': 'M2',
    'ecritures': 'M12',
    'naturesFacture': 'CFG',
    'actes': 'CFG',
    'produits': 'M6',
    'mouvements': 'M6',
    'remboursements': 'M8',
    'facturesMere': 'M9',
    'dispensations': 'M6',
    'emplacements': 'M6',
    'inventaires': 'M6',
    'lots': 'M6',
    'transferts': 'M6',
    'valorisationsSage': 'M6',
    'besoins': 'M7',
    'commandes': 'M7',
    'facturesFournisseurs': 'M7',
    'fournisseurs': 'M7',
    'livraisons': 'M7',
    'pvReceptions': 'M7',
    'catalogueTarifs': 'M8',
    'visitesHospi': 'M3',
    'appels': 'M2',
    'reunions': 'M13',
    'courriers': 'M13',
    'evenementsEtablissement': 'M13',
    'planAnnuel': 'M13',
    'ambulance': 'M13',
    'ambulances': 'M13',
    'materiel': 'M13',
    'contreReferences': 'M1',
    'documentsPatient': 'M1',
    'fichesReference': 'M1',
    'pieces': 'M1',
    'secteurs': 'CFG',
    'postes': 'CFG',
    'analyses': 'M5',
    'typesPiece': 'CFG',
    'modelesMessage': 'CFG',
    'rappels': 'CFG',
    'certificats': 'CFG',
    'ressources': 'CFG',
    'fileAttente': 'M2',
    'soins': 'M2',
    'administrations': 'M3',
    'admissions': 'M3',
    'checklistsBloc': 'M3',
    'cpa': 'M3',
    'crOperatoires': 'M3',
    'observations': 'M3',
    'rapportsMedicaux': 'M3',
    'releves': 'M3',
    'scoresGlasgow': 'M3',
    'surveillancesTransfusion': 'M3',
    'accouchements': 'M4',
    'cpon': 'M4',
    'crMaternite': 'M4',
    'deces': 'M4',
    'dossiersObstetricaux': 'M4',
    'grossesses': 'M4',
    'naissances': 'M4',
    'partogrammes': 'M4',
    'planificationFamiliale': 'M4',
    'ptme': 'M4',
    'registreSONU': 'M4',
    'soinsCuratifsMaternite': 'M4',
    'suiviMaternite': 'M4',
    'chambres': 'M3',
    'lits': 'M3',
    'rendezvous': 'M2',
    'visites': 'M2',
    'antecedents': 'M1',
    'documents': 'GED',
    'examensLabo': 'M5',
    'unitesLabo': 'M5',
    'variablesLabo': 'M5',
    'plagesReactif': 'M5',
    'donneurs': 'M5',
    'poches': 'M5',
    'personnel': 'M10',
    'contrats': 'M10',
    'conges': 'M10',
    'missions': 'M10',
    'prestataires': 'M10',
    'fichesPoste': 'M10',
    'planning': 'M10',
    'presences': 'M10',
    'evaluations': 'M10',
    'assurancesPersonnel': 'M10',
    'grillePrimes': 'M10',
    'historiquePrimes': 'M10',
    'regimesTravail': 'M10',
    'baremeNS131': 'M10',
    'historiqueBareme': 'M10',
    'examensImagerie': 'M2',
    'variablesImagerie': 'M2',
    'clichesImagerie': 'M2',
    'resultatsImagerie': 'M2',
    'consultations': 'M2',
    'dossiersConsultation': 'M2',
    'prescriptions': 'M2',
    'constantes': 'M1',
    'pathologies': 'M2',
    'soignants': 'M2',
    'notifications': 'M14',
    'souscripteurs': 'M9',
    'garanties': 'M9',
    'couverturesAssurance': 'M9',
    'enquetes': 'M13',
    'reponsesEnquetes': 'M13',
    'jetonsEnquete': 'M13',
    'echeancesFiscales': 'M12',
    'comptes': 'M12',
    'banques': 'M12',
    'budgets': 'M12',
    'immobilisations': 'M12',
    'rapprochements': 'M12',
    'depenses': 'M12',
    'centresCouts': 'M12',
    'assureurs': 'M9',
    'relances': 'M9',
    'utilisateurs': 'M14',
    'rbac': 'M14',
    'tentativesConnexion': 'M14',
    'fichiersSauvegarde': 'M14',
    'tachesPlanifiees': 'M14',
    'executionsTaches': 'M14',
    'rolesBase': 'M14',
    'modulesManifeste': 'M14',
    'participations': 'M10',
    'pretsEtudes': 'M11',
    'avances': 'M11',
    'heuresSup': 'M11',
    'bulletins': 'M11',
    'exercices': 'M12',
    'objectifsPilotage': 'M12',
  };

  /// Une collection absente est VIDE, jamais une erreur : l'écran dit « aucun enregistrement » (état vide), comme la maquette.
  CollectionMagasin collection(String nom) => _c.putIfAbsent(nom, () {
        final c = CollectionMagasin(nom, _jeux[nom] ?? const [],
            journal: nom == 'audit' ? null : journaliser,
            module: _modules[nom] ?? '—');
        // `S.garder('ecritures', …)` de la maquette : la lecture seule d'un exercice clos est tenue AU MOTEUR, sur la collection — masquer un bouton ne
        // protège rien. La garde relit les exercices À CHAQUE écriture (une clôture validée ferme aussitôt).
        if (nom == 'ecritures') {
          c.garder((op, f) => cpcGardeEcritures(collection('exercices').toutes, f['date']));
        }
        return c;
      });

  /// Journal d'audit (RG-12), plafonné à 400 entrées comme la maquette ; les anciennes sont écartées du tampon, jamais réécrites.
  void journaliser(String action, String module, String entite,
      String reference, Object? avant, Object? apres,
      {bool succes = true}) {
    final a = collection('audit');
    final n = a.toutes.length + 1;
    a.inserer({
      'id': 'LOG${n.toString().padLeft(5, '0')}',
      'dateHeure': horloge().toIso8601String(),
      'utilisateur': utilisateur,
      'action': action,
      'module': module,
      'entite': entite,
      'reference': reference,
      'poste': poste,
      'succes': succes,
      if (avant != null) 'avant': avant,
      if (apres != null) 'apres': apres,
    });
    a.plafonner(400);
  }

  static List<Fiche> _lire(String json) => [
        for (final f in jsonDecode(json) as List)
          (f as Map).cast<String, Object?>()
      ];

  static Future<Magasin> depuisAssets(List<String> noms,
          [String dossier = 'assets/donnees/jeu']) async =>
      Magasin({
        for (final n in noms)
          n: _lire(await rootBundle.loadString('$dossier/$n.json'))
      }, 'POSTE', {
        ...(jsonDecode(await rootBundle.loadString('$dossier/referentiels.json'))
                as Map)
            .cast<String, Object?>()
      });

  /// Pour les tests : mêmes fichiers, lus sur le disque.
  static Magasin depuisDossier(List<String> noms,
          [String dossier = 'assets/donnees/jeu']) =>
      Magasin({
        for (final n in noms)
          n: _lire(File('$dossier/$n.json').readAsStringSync())
      }, 'POSTE', {
        ...(jsonDecode(File('$dossier/referentiels.json').readAsStringSync())
                as Map)
            .cast<String, Object?>()
      });

  /// Collections que les écrans portés lisent (le jeu est engendré par `prototype_html/build/gen-poste-jeu.js`).
  static const collectionsDuJeu = [
    'factures',
    'patients',
    'avoirs',
    'taches',
    'demandesAnalyses',
    'demandesImagerie',
    'ordonnances',
    'ecritures',
    'audit',
    'naturesFacture',
    'actes',
    'produits',
    'souscripteurs',
    'garanties',
    'couverturesAssurance',
    'mouvements',
    'facturesMere',
    'remboursements',
    'dispensations',
    'emplacements',
    'inventaires',
    'lots',
    'transferts',
    'valorisationsSage',
    'besoins',
    'commandes',
    'facturesFournisseurs',
    'fournisseurs',
    'livraisons',
    'pvReceptions',
    'catalogueTarifs',
    'examensLabo',
    'unitesLabo',
    'variablesLabo',
    'plagesReactif',
    'donneurs',
    'poches',
    'personnel',
    'contrats',
    'conges',
    'missions',
    'prestataires',
    'fichesPoste',
    'planning',
    'presences',
    'evaluations',
    'assurancesPersonnel',
    'grillePrimes',
    'historiquePrimes',
    'regimesTravail',
    'baremeNS131',
    'historiqueBareme',
    'examensImagerie',
    'variablesImagerie',
    'clichesImagerie',
    'resultatsImagerie',
    'consultations',
    'dossiersConsultation',
    'prescriptions',
    'constantes',
    'pathologies',
    'soignants',
    'notifications',
    'visitesHospi',
    'appels',
    'reunions',
    'courriers',
    'evenementsEtablissement',
    'planAnnuel',
    'ambulance',
    'ambulances',
    'materiel',
    'contreReferences',
    'documentsPatient',
    'fichesReference',
    'pieces',
    'secteurs',
    'postes',
    'analyses',
    'typesPiece',
    'modelesMessage',
    'rappels',
    'certificats',
    'ressources',
    'fileAttente',
    'soins',
    'administrations',
    'admissions',
    'checklistsBloc',
    'cpa',
    'crOperatoires',
    'observations',
    'rapportsMedicaux',
    'releves',
    'scoresGlasgow',
    'surveillancesTransfusion',
    'accouchements',
    'cpon',
    'crMaternite',
    'deces',
    'dossiersObstetricaux',
    'grossesses',
    'naissances',
    'partogrammes',
    'planificationFamiliale',
    'ptme',
    'registreSONU',
    'soinsCuratifsMaternite',
    'suiviMaternite',
    'chambres',
    'lits',
    'rendezvous',
    'visites',
    'antecedents',
    'documents',
    'enquetes',
    'reponsesEnquetes',
    'jetonsEnquete',
    'echeancesFiscales',
    'comptes',
    'banques',
    'budgets',
    'immobilisations',
    'rapprochements',
    'depenses',
    'centresCouts',
    'assureurs',
    'relances',
    'utilisateurs',
    'rbac',
    'tentativesConnexion',
    'fichiersSauvegarde',
    'tachesPlanifiees',
    'executionsTaches',
    'rolesBase',
    'modulesManifeste',
    'participations',
    'pretsEtudes',
    'avances',
    'heuresSup',
    'bulletins',
    'exercices',
    'objectifsPilotage'
  ];
}
