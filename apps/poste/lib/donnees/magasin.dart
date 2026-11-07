import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sigh_domaine/sigh_domaine.dart' show Agent, cpaDoublonsDuPlan, cpcGardeArchives, cpcGardeClotures, cpcGardeEcritures;

import 'persistance.dart';

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

  /// Ajoute une fiche À LA FIN, sans journal : l'amorçage de démonstration d'un écran (`db[nom].push` de la maquette, sans `log`). Jamais pour une écriture
  /// de l'agent : celle-là passe par [inserer] et se journalise (RG-12).
  void ajouterSansJournal(Fiche f, {bool enTete = false}) {
    if (enTete) {
      _fiches.insert(0, {...f});
    } else {
      _fiches.add({...f});
    }
    notifyListeners();
  }

  /// Applique une fiche REÇUE d'un autre poste (la mère) : insérée si elle manque, remplacée sinon. Sans journal local (la mère l'a déjà écrit), sans garde
  /// (la garde protège contre l'écriture de l'agent, pas contre la mère) et sans prendre la tête de la collection. Rend vrai si quelque chose a changé.
  bool appliquerDistante(Fiche f) {
    final id = f['id'];
    final i = _fiches.indexWhere((x) => x['id'] == id);
    if (i < 0) {
      _fiches.add({...f});
    } else {
      if (_memeContenu(_fiches[i], f)) return false;
      _fiches[i]
        ..clear()
        ..addAll(f);
    }
    notifyListeners();
    return true;
  }

  static bool _memeContenu(Fiche a, Fiche b) => jsonEncode(a) == jsonEncode(b);

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

  /// Remplace TOUT le contenu de la collection (CFG › « Jeux de test » : vider les données d'activité, régénérer le jeu de démonstration). Aucun journal ici :
  /// l'appelant inscrit le geste dans le journal conservé (RG-12). Les gardes de la collection ne jouent pas — c'est une remise à neuf, non une écriture de fiche.
  void remplacerContenu(Iterable<Fiche> fiches) {
    _fiches
      ..clear()
      ..addAll([
        for (final f in fiches) {...f}
      ]);
    notifyListeners();
  }

  /// Met à jour des champs de la fiche (`col.update`) et rend la fonction qui RESTITUE l'état d'avant. Rien n'est supprimé : un champ ajouté
  /// par la mise à jour est retiré à l'annulation.
  VoidCallback mettreAJour(Object? id, Fiche patch, {bool journaliser = true}) {
    final f = parId(id);
    if (f == null) return () {};
    if (_gardes.isNotEmpty) _controler('modifier', {...f, ...patch});
    final avant = <String, Object?>{for (final k in patch.keys) k: f[k]};
    final existait = {for (final k in patch.keys) k: f.containsKey(k)};
    f.addAll(patch);
    if (journaliser) {
      journal?.call('Modification', module, entite ?? nom, _ref(f), avant, {for (final k in patch.keys) k: patch[k]});
    }
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
  ])  : _jeux = {for (final e in jeux.entries) e.key: e.value},
        _origine = {for (final e in jeux.entries) e.key: e.value},
        _idsOrigine = {
          for (final e in jeux.entries) e.key: {for (final f in e.value) '${f['id']}'}
        };

  /// Le jeu d'origine tel que livré (jamais modifié : les collections en tiennent des COPIES) et son index par identifiant, construit à la demande.
  final Map<String, Iterable<Fiche>> _origine;
  final Map<String, Map<String, Fiche>> _indexOrigine = {};

  /// La fiche du jeu d'origine d'identifiant [id], ou `null` (fiche créée depuis). Sert de point de départ commun aux compteurs (stock, règlements).
  Fiche? ficheOrigine(String nom, String id) =>
      (_indexOrigine[nom] ??= {for (final f in (_origine[nom] ?? const <Fiche>[])) '${f['id']}': f})[id];

  /// Les identifiants des fiches du jeu D'ORIGINE livré avec le poste, par collection (avant toute fusion avec le disque). Ces fiches existent à l'identique sur
  /// TOUS les postes : leur identité de synchronisation est leur identifiant même.
  final Map<String, Set<String>> _idsOrigine;
  Set<String> idsOrigine(String nom) => _idsOrigine[nom] ?? const <String>{};

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

  /// L'agent NOMINATIF de la session (A1) : quand il est posé, chaque entrée du journal porte aussi son identifiant de compte et son matricule, pas
  /// seulement un nom. `null` : aucune session nominative (le journal garde alors [utilisateur] seul, comme avant).
  Agent? acteur;

  /// La coque pose l'acteur de la session : le nom du journal en découle. Un seul geste, pour que le nom et l'identifiant ne divergent jamais.
  void poserActeur(Agent a) {
    acteur = a;
    utilisateur = a.nom;
  }

  // --- Persistance -------------------------------------------------------------------------------------------------------------------------------
  Persistance? _persistance;
  final Set<String> _sales = {};
  Timer? _minuterie;
  Duration _delaiEcriture = const Duration(milliseconds: 400);
  Future<void> _enCours = Future.value();

  /// Les problèmes de relecture du dernier démarrage (fichier illisible mis de côté), à dire à l'écran.
  List<String> get problemesPersistance => _persistance?.problemes ?? const [];

  /// BRANCHE LE DISQUE. Ce qui a été écrit lors d'un démarrage précédent REMPLACE le jeu d'origine, collection par collection ; une collection jamais
  /// écrite reste celle du jeu. Ensuite chaque écriture marque sa collection, et une minuterie (400 ms après le dernier geste) ne réécrit que celles
  /// qui ont changé : sérialiser tout le magasin à chaque geste serait quadratique. À appeler UNE fois, avant la première lecture d'une collection.
  Future<void> brancherPersistance(Persistance p,
      {Duration delai = const Duration(milliseconds: 400), Set<String> fusionnables = const {}}) async {
    if (_persistance != null) throw StateError('La persistance est déjà branchée.');
    if (_c.isNotEmpty) throw StateError('La persistance se branche avant la première lecture d\'une collection.');
    _delaiEcriture = delai;
    final ecrit = await p.lireTout();
    final meta = await p.lireMeta();
    // UN JEU D'ORIGINE QUI CHANGE NE SE PERD PAS (Direction, 03/11/2026) : quand le jeu livré avec le poste a changé depuis le dernier lancement, les fiches
    // des collections de [fusionnables] (référentiels, paramétrage) qui MANQUENT au magasin enregistré y sont ajoutées. On n'écrase rien, on ne retire rien :
    // ce que l'agent a saisi ou modifié reste, ce que la nouvelle version apporte arrive. L'activité de démonstration, elle, n'est jamais rajoutée.
    final empreinte = _empreinteJeu(fusionnables);
    final fusionnees = <String, List<Fiche>>{};
    if (ecrit.isNotEmpty && meta['jeu'] != empreinte) {
      for (final n in fusionnables) {
        final present = ecrit[n];
        if (present == null) continue;
        final ids = {for (final f in present) f['id']};
        final manquantes = [
          for (final f in (_jeux[n] ?? const <Fiche>[]))
            if (!ids.contains(f['id'])) {...f}
        ];
        if (manquantes.isNotEmpty) fusionnees[n] = [...present, ...manquantes];
      }
    }
    for (final e in ecrit.entries) {
      _jeux[e.key] = fusionnees[e.key] ?? e.value;
    }
    for (final e in fusionnees.entries) {
      await p.ecrire(e.key, e.value);
    }
    if (meta['jeu'] != empreinte) await p.ecrireMeta({...meta, 'jeu': empreinte});
    jeuxFusionnes = fusionnees.map((k, v) => MapEntry(k, v.length - (ecrit[k]?.length ?? 0)));
    _persistance = p;
  }

  /// Les collections dont des fiches nouvelles du jeu d'origine ont été ajoutées au démarrage, et combien (vide si le jeu n'a pas changé).
  Map<String, int> jeuxFusionnes = const {};

  /// L'empreinte du jeu d'origine : les identifiants des fiches des collections fusionnables (FNV-1a). Elle change quand une version livre de nouvelles fiches.
  String _empreinteJeu(Set<String> noms) {
    var h = 0x811c9dc5;
    for (final n in (noms.toList()..sort())) {
      for (final c in '$n:'.codeUnits) {
        h = ((h ^ c) * 0x01000193) & 0xffffffff;
      }
      for (final f in (_jeux[n] ?? const <Fiche>[])) {
        for (final c in '${f['id']},'.codeUnits) {
          h = ((h ^ c) * 0x01000193) & 0xffffffff;
        }
      }
    }
    return h.toRadixString(16);
  }

  void _marquerSale(String nom) {
    _sales.add(nom);
    _minuterie ??= Timer(_delaiEcriture, () {
      _minuterie = null;
      ecrireMaintenant();
    });
  }

  /// Écrit tout de suite les collections modifiées (fermeture du poste, perte du focus, test). Rend quand c'est écrit.
  Future<void> ecrireMaintenant() {
    final p = _persistance;
    if (p == null) return Future.value();
    _minuterie?.cancel();
    _minuterie = null;
    final noms = _sales.toList();
    _sales.clear();
    _enCours = _enCours.then((_) async {
      var echec = false;
      for (final n in noms) {
        final col = _c[n];
        if (col == null) continue;
        try {
          await p.ecrire(n, col.toutes);
        } catch (e) {
          // Une écriture qui échoue est REPROGRAMMÉE, jamais perdue en silence ; la coque la dit par [erreurPersistance].
          echec = true;
          erreurPersistance.value = 'Écriture de « $n » impossible sur le disque : $e';
          _marquerSale(n);
        }
      }
      if (!echec) erreurPersistance.value = null;
    });
    return _enCours;
  }

  /// Le dernier échec d'écriture sur le disque (`null` : tout va bien). La coque le montre ; un poste qui ne sait plus écrire doit le dire.
  final ValueNotifier<String?> erreurPersistance = ValueNotifier<String?>(null);

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
    'crAnesthesie': 'M3',
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
    'beneficiairesPrimes': 'M10',
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
    'identifiants': 'M14',
    'rbac': 'M14',
    'tentativesConnexion': 'M14',
    'sessionsUtilisateur': 'M14',
    'politiqueSecurite': 'M14',
    'fichiersSauvegarde': 'M14',
    'tachesPlanifiees': 'M14',
    'executionsTaches': 'M14',
    'rolesBase': 'M14',
    'modulesManifeste': 'M14',
    'participations': 'M10',
    'evenements': 'M10',
    'badges': 'M10',
    'modelesBadge': 'M10',
    'pretsEtudes': 'M11',
    'avances': 'M11',
    'heuresSup': 'M11',
    'bulletins': 'M11',
    'exercices': 'M12',
    'objectifsPilotage': 'M12',
    'modulesActifs': 'CFG',
    'reglages': 'CFG',
    'identiteLegale': 'CFG',
    'obligationsFiscales': 'CFG',
    'historiqueObligations': 'CFG',
    'support': 'SUP',
  };

  /// Une collection absente est VIDE, jamais une erreur : l'écran dit « aucun enregistrement » (état vide), comme la maquette.
  CollectionMagasin collection(String nom) {
    final neuve = !_c.containsKey(nom);
    final col = _collection(nom);
    // E724/E725 : le plan du jeu porte deux fiches au même numéro (244100, 631810). Comme la maquette (`assainirPlan`, une fois au premier accès), on garde la
    // fiche du document et on ARCHIVE le doublon (RG-14). Fait APRÈS la création de la collection : l'archivage journalise, donc ouvre `audit`.
    if (neuve && nom == 'comptes') {
      for (final d in cpaDoublonsDuPlan(col.actives)) {
        col.archiver(d.$1);
      }
    }
    return col;
  }

  CollectionMagasin _collection(String nom) => _c.putIfAbsent(nom, () {
        final c = CollectionMagasin(nom, _jeux[nom] ?? const [],
            // `identifiants` (hachés des mots de passe) : le journal inscrit le GESTE et la référence, JAMAIS les valeurs avant / après.
            journal: nom == 'audit'
                ? null
                : (nom == 'identifiants'
                    ? (a, m, e, r, avant, apres) => journaliser(a, m, e, r, null, null)
                    : journaliser),
            module: _modules[nom] ?? '—');
        if (_persistance != null) c.addListener(() => _marquerSale(nom));
        // `S.garder('ecritures', …)` de la maquette : la lecture seule d'un exercice clos est tenue AU MOTEUR, sur la collection — masquer un bouton ne
        // protège rien. La garde relit les exercices À CHAQUE écriture (une clôture validée ferme aussitôt).
        if (nom == 'ecritures') {
          c.garder((op, f) => cpcGardeEcritures(collection('exercices').toutes, f['date'],
              op: op, origineCloture: f['origineCloture'], origine: f['origine'], role: acteur?.role ?? ''));
        }
        // L'archive d'une clôture est IMMUABLE et le registre des clôtures est une piste d'audit (arbitrage du 05/11/2026).
        if (nom == 'archivesExercice') c.garder((op, f) => cpcGardeArchives(collection('archivesExercice').toutes, op, f['reference']));
        if (nom == 'clotures') c.garder((op, f) => cpcGardeClotures(op));
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
      if (acteur != null) ...{'utilisateurId': acteur!.utilisateurId, if (acteur!.matricule.isNotEmpty) 'matricule': acteur!.matricule},
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
    'crAnesthesie',
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
    'evenements',
    'badges',
    'modelesBadge',
    'pretsEtudes',
    'avances',
    'heuresSup',
    'bulletins',
    'exercices',
    'objectifsPilotage',
    'modulesActifs',
    'identiteLegale',
    'obligationsFiscales',
    'historiqueObligations',
    'support'
  ];
}
