import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart' show ErreurFichier, StockageFichiers;

import '../core/service_parametres.dart';
import 'fichiers_poste.dart';
import 'magasin.dart';

/// LA LECTURE OCR DES SCANS AU POSTE, PRÉPARÉE (lot OCR-prep, portage de `modules/fichiers-ocr.js` de la maquette) : AUCUN moteur choisi, AUCUN moteur livré, AUCUNE qualité promise.
///
/// Ce service enchaîne les gestes du domaine (`packages/domaine/lib/src/fichiers/ocr.dart`, vecteurs tirés de la maquette) : il ne décide rien. Par défaut AUCUN moteur n'est branché et
/// l'état de chaque scan dit exactement « aucun moteur d'OCR installé sur ce poste ». Le jour où un moteur est branché ([enregistrer]) et choisi au réglage, les scans sans couche texte
/// entrent dans la file : un fichier à la fois, borné en temps, reprise après arrêt, jamais deux files pour la même empreinte.
///
/// Où vivent les données :
///  - la FILE est une collection LOCALE au poste (`fileOcr`, une ligne par empreinte, jamais synchronisée : un traitement en cours sur un poste n'est pas l'affaire d'un autre) ;
///  - les LECTURES (`lecturesOcr`) sont des MÉTADONNÉES du fichier : une fiche par version, identifiant déterministe, IMMUABLE (garde du magasin), synchronisée par le journal avec le registre
///    `fichiers` (famille B : ajout seul, deux postes qui lisent le même scan avec le même moteur ne font qu'une version), JAMAIS vers un téléphone ;
///  - le RÉGLAGE est celui de la CLINIQUE (lot C) : activation, moteur choisi, langue et délai sont des paramètres `ocr.*` posés à la poste MÈRE (collection `parametres`, famille R, une
///    version par date), reçus des fileuls par le journal, JAMAIS vers un téléphone ; un fileul les lit (cache en lecture seule) et le dit s'ils ne sont pas encore reçus. Chaque poste ne
///    garde en propre que ce qu'il a d'INSTALLÉ : les moteurs que ce poste porte (`enregistrer`) ;
///  - la CORRECTION SIGNÉE du texte lu (lot C) s'AJOUTE comme une version de `lecturesOcr` (`texteSource: 'correction'`), par un agent qui écrit sur l'écran de la pièce, lit la zone du scan ET
///    détient le geste réservé `corriger_texte_ocr` ; la lecture machine reste intacte, une relance ne détruit jamais une correction signée.

/// La file de lecture, collection LOCALE au poste.
const String ocrFile = 'fileOcr';

/// Les lectures (versions de texte lu par machine), collection synchronisée (famille B).
const String ocrLectures = 'lecturesOcr';

class ResultatFileOcr {
  const ResultatFileOcr.ok({this.fait = false, this.sha, this.version, this.nouvelle = false, this.deja = false, this.ecarte, this.conflit = false})
      : refus = null,
        ok = true;
  const ResultatFileOcr.refus(RefusFichier this.refus)
      : ok = false,
        fait = false,
        sha = null,
        version = null,
        nouvelle = false,
        deja = false,
        ecarte = null,
        conflit = false;
  final bool ok;
  final RefusFichier? refus;

  /// Un traitement a été mené à son terme (réussi ou en échec nommé).
  final bool fait;
  final String? sha;
  final String? version;
  final bool nouvelle;

  /// Déjà en file, déjà lu : rien à faire.
  final bool deja;

  /// Le code du refus qui a fait écarter ce fichier pour ce profil (droit, zone) : un autre profil le traitera.
  final String? ecarte;

  /// Une correction a été ajoutée à côté d'une autre correction concurrente (deux postes) : à départager.
  final bool conflit;
}

class OcrPoste extends ChangeNotifier {
  OcrPoste(this.fp, {required this.roleCourant, required this.droitDe, bool Function(String role, String geste)? gesteDe, bool Function()? estFileul, RendeurPages? rendeur})
      : _rendeur = rendeur,
        gesteDe = gesteDe ?? ((_, __) => false),
        estFileul = estFileul ?? (() => false) {
    fp.ocr = this;
    magasin.collection(ocrLectures).garder((op, f) {
      final existantes = magasin.collection(ocrLectures).toutes;
      if (op == 'modifier') return 'Une lecture OCR est IMMUABLE : une relance AJOUTE une version datée, elle ne réécrit pas l’ancienne.';
      if (op == 'archiver') return 'Une lecture OCR ne s’archive pas : elle reste lisible (RG-14), une nouvelle lecture devient la version courante.';
      if (op == 'inserer') {
        final nonSignee = ocrMotifCorrectionNonSignee(f);
        if (nonSignee != null) return nonSignee;
      }
      if (op == 'inserer' && existantes.any((x) => x['id'] == f['id'])) return 'La lecture « ${f['id']} » existe déjà : une version ne se réécrit pas.';
      return null;
    });
  }

  final FichiersPoste fp;
  Magasin get magasin => fp.magasin;
  StockageFichiers get stockage => fp.stockage;

  /// Le rôle de l'agent connecté (`null` : aucune session), et le droit d'un rôle sur un écran (la matrice RBAC, corrections à chaud comprises).
  final String? Function() roleCourant;
  final Droit Function(String role, String ecran) droitDe;

  /// Le droit d'un GESTE réservé pour un rôle (la matrice RBAC, corrections à chaud comprises). Par défaut FERMÉ : un geste réservé ne s'ouvre jamais sans la fiche.
  final bool Function(String role, String geste) gesteDe;

  /// Ce poste est-il un FILEUL rattaché à une mère ? Il lit le réglage de la clinique et ne le pose pas.
  final bool Function() estFileul;
  RendeurPages? _rendeur;
  final Map<String, MoteurOcr> _moteurs = {};
  /// Les fichiers que le PROFIL COURANT ne lit pas (droit, zone) : écartés pour lui, pas pour un autre. Changer de session les remet à zéro.
  final Set<String> _ecartes = {};
  String? _roleDesEcartes;
  bool _occupe = false;
  Timer? _minuterie;

  /// La file tourne d'elle-même (une minuterie, un fichier par passe) : vrai en exploitation. Un test la coupe pour mener la file à la main ([traiterSuivant], [vider]).
  bool automatique = true;

  static final Expando<OcrPoste> _installes = Expando<OcrPoste>('OcrPoste');

  /// Le service installé pour ce magasin (posé par `main`, ou par un test), ou `null` : les écrans ne plantent jamais sans lui.
  static OcrPoste? de(Magasin m) => _installes[m];
  void installer() => _installes[magasin] = this;
  void rafraichir() => notifyListeners();

  // --- moteurs : injectables, AUCUN par défaut ---------------------------------------------------------------------------------------------

  void enregistrer(MoteurOcr m) {
    _moteurs[m.id] = m;
    notifyListeners();
  }

  void retirer([String? id]) {
    if (id == null) {
      _moteurs.clear();
    } else {
      _moteurs.remove(id);
    }
    notifyListeners();
  }

  void poserRendeur(RendeurPages? r) => _rendeur = r;
  Map<String, MoteurOcr> get moteurs => Map.unmodifiable(_moteurs);
  bool get moteurInstalle => _moteurs.isNotEmpty;

  // --- réglage de clinique ----------------------------------------------------------------------------------------------------------------------

  ServiceParametres get _parametres => serviceParametres(magasin, auteur: () => magasin.utilisateur, horloge: () => magasin.horloge());
  String get _aujourdhui => parametreDateIso(magasin.horloge());

  /// Le réglage de clinique est-il REÇU ? La fiche d'activation de la mère (même son semis) est arrivée : sinon on ne lit pas un défaut qui peut différer de ce que la mère a posé.
  bool get reglageRecu => _parametres.versions(ocrCleActif).isNotEmpty;

  /// Le réglage de clinique, lu de la base (jamais du code). Non reçu : les valeurs du défaut, `regle` faux, et l'état des pièces le DIT (jamais « désactivé » en silence).
  ReglageOcr get reglage {
    if (!reglageRecu) return const ReglageOcr();
    final p = _parametres, d = _aujourdhui;
    final moteur = '${p.valeur(ocrCleMoteur, d) ?? ''}';
    final delai = p.valeur(ocrCleDelai, d);
    final dernier = [for (final v in p.versions()) if (v.cle.startsWith('ocr.') && v.version > 0) v]..sort((a, b) => '${a.creeLe}'.compareTo('${b.creeLe}'));
    return ReglageOcr(
        actif: p.valeur(ocrCleActif, d) == true,
        moteur: moteur.isEmpty ? null : moteur,
        langue: '${p.valeur(ocrCleLangue, d) ?? ocrLangueDefaut}',
        delaiMs: delai is num && delai > 0 ? delai.toInt() : ocrDelaiDefautMs,
        regleLe: dernier.isEmpty ? null : dernier.last.creeLe,
        reglePar: dernier.isEmpty ? null : dernier.last.auteur,
        regle: dernier.isNotEmpty);
  }

  MoteurOcr? get moteurActif {
    final id = reglage.moteur;
    return id != null ? _moteurs[id] : null;
  }

  bool get pret => ocrPret(actif: reglage.actif, moteurActif: moteurActif != null);
  bool peutRegler(String role) => ocrPeutRegler(role);

  /// Pose le réglage de la clinique : réservé à l'administrateur et à la DAF, motivé ; activer sans moteur installé SUR CE POSTE est REFUSÉ en le nommant. N'écrit que ce qui change, comme
  /// NOUVELLE VERSION datée du jour (jamais une réécriture), journalisé (RG-12). Un FILEUL ne peut pas régler : la collection des paramètres est tenue par la mère, le refus est nommé. Une
  /// activation rattrape les scans déjà déposés.
  ResultatFileOcr definirReglage({required String role, required bool actif, required String? moteur, required String langue, required String? motif, int? delaiMs}) {
    final avant = reglage;
    if (estFileul()) {
      return ResultatFileOcr.refus(ocrRefus('FILEUL_LECTURE_SEULE', 'la lecture des scans est un réglage de la clinique, posé à la poste mère : ce poste le reçoit par le journal',
          'Régler la lecture des scans sur le poste mère : ce poste reçoit ce réglage par le journal.'));
    }
    final r = ocrDefinirReglage(
        role: role,
        actif: actif,
        moteur: moteur,
        langue: langue,
        motif: motif,
        moteurs: _moteurs,
        avant: avant,
        delaiMs: delaiMs,
        regleLe: magasin.horloge().toUtc().toIso8601String(),
        reglePar: magasin.utilisateur);
    if (!r.ok) return ResultatFileOcr.refus(r.refus!);
    final p = _parametres;
    final voulu = <String, Object?>{ocrCleActif: actif, ocrCleMoteur: moteur ?? '', ocrCleLangue: r.reglage!.langue, ocrCleDelai: r.reglage!.delaiMs};
    final m = (motif ?? '').trim();
    try {
      // Un poste qui n'a pas encore le semis (poste autonome, jamais rattaché) le sème : version 0 identique partout. Un fileul ne le peut pas : la garde le refuse.
      if (!reglageRecu) p.semerDefauts();
      final dejaLa = reglage;
      final courant = <String, Object?>{ocrCleActif: dejaLa.actif, ocrCleMoteur: dejaLa.moteur ?? '', ocrCleLangue: dejaLa.langue, ocrCleDelai: dejaLa.delaiMs};
      for (final e in voulu.entries) {
        if (courant[e.key] == e.value) continue;
        final w = p.regler(e.key, e.value, _aujourdhui, motif: m);
        if (!w.ok) return ResultatFileOcr.refus(ocrRefus('REGLAGE_REFUSE', '${w.refus!.code} : ${w.refus!.motif}', w.refus!.geste));
      }
    } on EcritureRefusee catch (e) {
      return ResultatFileOcr.refus(ocrRefus('FILEUL_LECTURE_SEULE', e.motif, 'Régler la lecture des scans sur le poste mère : ce poste reçoit ce réglage par le journal.'));
    }
    magasin.journaliser('Réglage de la lecture OCR des scans', 'M14', 'reglage', 'ocr', {'actif': avant.actif, 'moteur': avant.moteur, 'langue': avant.langue, 'delaiMs': avant.delaiMs},
        {'actif': actif, 'moteur': moteur, 'langue': r.reglage!.langue, 'delaiMs': r.reglage!.delaiMs, 'motif': m.length > 40 ? m.substring(0, 40) : m});
    if (actif) {
      balayer();
      demarrer();
    }
    notifyListeners();
    return const ResultatFileOcr.ok();
  }

  // --- données ----------------------------------------------------------------------------------------------------------------------------------

  CollectionMagasin get _registre => magasin.collection('fichiers');
  CollectionMagasin get _lectures => magasin.collection(ocrLectures);
  CollectionMagasin get _file => magasin.collection(ocrFile);

  String _idFile(String sha) => 'OCQ-${sha.substring(0, 16)}';
  FicheDoc? _entreeFile(String sha) => _file.parId(_idFile(sha));
  FicheDoc? _registreDe(String sha) => _registre.parId(fichierIdRegistre(sha));
  bool _natif(String sha, [FicheDoc? fichier]) => fichier?['texteIndexe'] == true || _registreDe(sha)?['texteIndexe'] == true;

  /// Les lectures d'une empreinte, de la plus ancienne à la plus récente.
  List<FicheDoc> versionsDe(String sha) => ocrVersionsOrdonnees([
        for (final v in _lectures.actives)
          if (v['sha256'] == sha) v
      ]);
  FicheDoc? versionCourante(String sha) => ocrVersionCourante(versionsDe(sha));

  /// L'état d'indexation d'un fichier (l'objet `fichier` d'une fiche) : couche texte, lu par machine (à vérifier), en attente, en cours, en échec, non indexé.
  EtatIndexationOcr etatDe(Map<String, Object?> fichier) {
    final sha = '${fichier['sha256']}';
    final r = reglage;
    return ocrEtatIndexation(
        natif: _natif(sha, fichier),
        versions: versionsDe(sha),
        file: _entreeFile(sha),
        moteurInstalle: moteurInstalle,
        actif: r.actif,
        moteurActif: moteurActif != null,
        reglageRecu: reglageRecu);
  }

  // --- correction signée ----------------------------------------------------------------------------------------------------------------------------

  bool _zoneLue(String famille, String? type, String role) => famille != 'patient' || docPeutVoir(type, role).autorise;

  /// La commande « Corriger le texte lu » est-elle OFFERTE ? ABSENTE sinon, jamais grisée : écrire sur l'écran de la pièce, lire la zone du scan, détenir le geste réservé, pas de couche texte.
  bool correctionPossible(Map<String, Object?> fichier, {required bool peutDeposer, required String famille, String? type}) {
    final role = roleCourant();
    if (role == null) return false;
    return ocrCorrectionPossible(
        peutDeposer: peutDeposer,
        zoneLue: _zoneLue(famille, type, role),
        gesteAccorde: gesteDe(role, ocrGesteCorriger),
        etat: etatDe(fichier).etat,
        versions: versionsDe('${fichier['sha256']}'));
  }

  /// Corrige le texte lu d'un scan : AJOUTE une version signée (jamais une réécriture), journalisée sans le texte. Le moteur refuse aussi : masquer la commande ne protège rien.
  /// [corrigeDe] : la version dont le texte sert de départ (par défaut la courante).
  ResultatFileOcr corriger(Map<String, Object?> fichier, String texte, {required bool peutDeposer, required String famille, String? type, String? corrigeDe}) {
    final role = roleCourant();
    final sha = '${fichier['sha256']}';
    if (fichier['sha256'] == null) return ResultatFileOcr.refus(ocrRefus(CodeOcr.sansPiece, 'cette fiche ne porte aucun fichier', 'Déposer d’abord le scan.'));
    final vs = versionsDe(sha);
    final c = ocrCorriger(
        sha: sha,
        texte: texte,
        natif: _natif(sha, fichier),
        versions: vs,
        corrigeDe: corrigeDe,
        par: magasin.utilisateur,
        le: magasin.horloge().toUtc().toIso8601String(),
        peutDeposer: peutDeposer && role != null,
        zoneLue: role != null && _zoneLue(famille, type, role),
        gesteAccorde: role != null && gesteDe(role, ocrGesteCorriger));
    if (c.refus != null) return ResultatFileOcr.refus(c.refus!);
    if (c.deja) return ResultatFileOcr.ok(deja: true, nouvelle: false, version: null, conflit: c.conflit);
    final f = c.fiche!;
    final avant = vs.where((x) => x['id'] == f['corrigeDe']).firstOrNull;
    try {
      _lectures.inserer(f, prefixe: 'OCC');
    } on EcritureRefusee catch (e) {
      return ResultatFileOcr.refus(ocrRefus('CORRECTION_REFUSEE', e.motif, 'Vérifier la signature et le texte, puis recommencer.'));
    }
    magasin.journaliser('Correction signée du texte lu d’un scan', 'M13', 'lecture OCR', '${f['id']}', {'version': f['corrigeDe'], 'mots': avant?['nbMots'] ?? 0},
        {'version': f['id'], 'mots': f['nbMots'], 'remplace': (f['remplace'] as List).length});
    notifyListeners();
    return ResultatFileOcr.ok(version: '${f['id']}', nouvelle: true, conflit: ocrConflit(versionsDe(sha)).length > 1);
  }

  /// Les corrections concurrentes (deux postes ont corrigé la même version) : vide, ou les têtes à départager.
  List<FicheDoc> conflitDe(String sha) => ocrConflit(versionsDe(sha));

  /// Le texte (mots normalisés) que la recherche lit : la couche native PRIME, sinon la lecture courante, seulement si [role] lit la zone du document.
  String texteOcr(String sha, {required String famille, String? type, required String role}) {
    final reg = _registreDe(sha);
    return ocrTexteRecherche(
        natifIndexe: reg?['texteIndexe'] == true, natifTexte: '${reg?['texte'] ?? ''}', versions: versionsDe(sha), famille: famille, type: type, role: role);
  }

  // --- la file ------------------------------------------------------------------------------------------------------------------------------------

  /// Un scan entre dans la file (idempotent : une seule ligne par empreinte). Rend le refus nommé, ou `deja` s'il n'y a rien à faire.
  ResultatFileOcr demander(String sha, {String? famille, String? type, bool relance = false}) {
    final reg = _registreDe(sha);
    final f = _entreeFile(sha);
    final r = reglage;
    final d = ocrDemander(
        registre: reg == null ? null : {...reg, if (f != null) 'ocr': f},
        versions: versionsDe(sha),
        moteurInstalle: moteurInstalle,
        actif: r.actif,
        moteurActif: moteurActif != null,
        relance: relance,
        famille: famille,
        type: type,
        maintenant: magasin.horloge().toUtc().toIso8601String(),
        par: magasin.utilisateur);
    if (d.refus != null) return ResultatFileOcr.refus(d.refus!);
    if (d.deja) return const ResultatFileOcr.ok(deja: true);
    final role = roleCourant();
    final ligne = {'id': _idFile(sha), 'sha256': sha, ...d.etat!, 'role': role};
    if (f == null) {
      _file.inserer(ligne, prefixe: 'OCQ');
    } else {
      _file.mettreAJour(_idFile(sha), ligne, journaliser: false);
    }
    magasin.journaliser(relance ? 'Relance de la lecture OCR' : 'Lecture OCR demandée', 'M13', 'lecture OCR', docAbrege(sha), {'empreinte': docAbrege(sha)}, {'etat': 'en_attente'});
    _ecartes.remove(sha);
    notifyListeners();
    return const ResultatFileOcr.ok();
  }

  /// Après un dépôt : le scan sans couche texte entre dans la file SI une lecture est possible ; sinon rien ne se met en file et l'état dit pourquoi.
  void apresDepot(Map<String, Object?> fichier, {required String famille, String? type}) {
    final sha = '${fichier['sha256']}';
    if (_natif(sha, fichier)) return;
    final r = demander(sha, famille: famille, type: type);
    if (r.ok && !r.deja) demarrer();
  }

  /// Les scans sans texte, sans lecture et hors file qu'une activation du réglage doit rattraper. Rend le nombre mis en file.
  int balayer() {
    if (!pret) return 0;
    var n = 0;
    for (final famille in fichierFamilles) {
      for (final f in magasin.collection(fichiersCollectionDe(famille)).actives) {
        final x = fichierDe(f);
        if (x == null) continue;
        final sha = '${x['sha256']}';
        if (_natif(sha, x) || _entreeFile(sha) != null || versionCourante(sha) != null) continue;
        final r = demander(sha, famille: famille, type: famille == 'patient' ? '${f['type']}' : null);
        if (r.ok && !r.deja) n++;
      }
    }
    return n;
  }

  /// Reprise après arrêt : un traitement « en cours » depuis plus de deux délais est remis en attente, ou en échec après trois essais. Rend le nombre repris.
  int reprendre() {
    var n = 0;
    final maintenant = magasin.horloge();
    for (final f in _file.toutes) {
      final r = ocrReprendre(f, maintenant: maintenant, delaiMs: reglage.delaiMs);
      if (r == null) continue;
      _file.mettreAJour(f['id'], r, journaliser: false);
      magasin.journaliser('Lecture OCR reprise après arrêt', 'M13', 'lecture OCR', docAbrege(f['sha256']), {'etat': 'en_cours'}, {'etat': r['etat']});
      n++;
    }
    if (n > 0) notifyListeners();
    return n;
  }

  /// La commande « Relancer la lecture » est-elle OFFERTE ? Absente sinon, jamais grisée.
  bool relancePossible(Map<String, Object?> fichier, {required bool peutDeposer}) =>
      ocrRelancePossible(peutDeposer: peutDeposer, pret: pret, etat: etatDe(fichier).etat);

  /// La relance : le moteur la refuse aussi sans le droit (masquer un bouton ne protège rien).
  ResultatFileOcr relancer(Map<String, Object?> fichier, {required bool peutDeposer, required String famille, String? type}) {
    final refus = ocrRefusRelance(peutDeposer: peutDeposer, moteurInstalle: moteurInstalle, actif: reglage.actif, moteurActif: moteurActif != null, sansPiece: fichier['sha256'] == null);
    if (refus != null) return ResultatFileOcr.refus(refus);
    final r = demander('${fichier['sha256']}', famille: famille, type: type, relance: true);
    if (r.ok && !r.deja) demarrer();
    return r;
  }

  /// Traite UN fichier de la file, sous le rôle de l'agent connecté. Jamais deux traitements à la fois. Un refus de droit ou de zone n'est pas un échec du fichier : ce profil ne le
  /// lit pas, un autre le traitera.
  Future<ResultatFileOcr> traiterSuivant() async {
    if (_occupe) return const ResultatFileOcr.ok();
    if (!pret) {
      return ResultatFileOcr.refus(ocrRefus(!moteurInstalle ? CodeOcr.moteurAbsent : CodeOcr.desactive, !moteurInstalle ? ocrRaisonSansMoteur : 'la lecture OCR est désactivée au réglage'));
    }
    final role = roleCourant();
    if (_roleDesEcartes != role) {
      _ecartes.clear();
      _roleDesEcartes = role;
    }
    // La file du poste est PLATE (une ligne par empreinte, `etat` en tête) ; le domaine lit un registre qui porte son état de lecture sous `ocr` : on la lui présente ainsi.
    final choisi = ocrChoisirSuivant([for (final f in _file.toutes) {'sha256': f['sha256'], 'ocr': f}], ecartes: _ecartes);
    if (choisi == null) return const ResultatFileOcr.ok();
    final suivant = (choisi['ocr']! as Map).cast<String, Object?>();
    final sha = '${suivant['sha256']}';
    final famille = '${suivant['famille'] ?? 'courrier'}';
    final type = suivant['type'] as String?;
    if (role == null) {
      _ecartes.add(sha);
      return const ResultatFileOcr.ok(ecarte: 'SESSION_REQUISE');
    }
    final refusDroit = fichierRefusDroit(role: role, famille: famille, geste: 'voir', type: type, droitEcran: droitDe(role, fichierEcranDeFamille(famille)));
    if (refusDroit != null) {
      _ecartes.add(sha);
      return ResultatFileOcr.ok(ecarte: refusDroit.code);
    }
    _occupe = true;
    try {
      final Uint8List octets;
      try {
        octets = await stockage.lire(sha);
      } on ErreurFichier {
        _ecartes.add(sha); // absent ou altéré : rien à lire pour l'instant, la synchronisation le ramènera
        return const ResultatFileOcr.ok(ecarte: 'FICHIER_ABSENT');
      }
      final essais = ((suivant['essais'] as num?) ?? 0).toInt() + 1;
      _file.mettreAJour(suivant['id'], {'etat': 'en_cours', 'debutLe': magasin.horloge().toUtc().toIso8601String(), 'essais': essais}, journaliser: false);
      magasin.journaliser('Lecture OCR commencée', 'M13', 'lecture OCR', docAbrege(sha), {'empreinte': docAbrege(sha)}, {'etat': 'en_cours'});
      final r = reglage;
      final lu = await ocrLireFichier(
          moteur: moteurActif,
          octets: octets,
          formatId: fichierFormatDesOctets(octets) ?? 'inconnu',
          mime: null,
          langue: r.langue,
          delaiMs: r.delaiMs,
          rendeur: _rendeur);
      if (!lu.ok) {
        _file.mettreAJour(suivant['id'], {'etat': 'echec', 'code': lu.refus!.code, 'raison': lu.refus!.motif, 'geste': lu.refus!.geste, 'finLe': magasin.horloge().toUtc().toIso8601String()}, journaliser: false);
        magasin.journaliser('Lecture OCR en échec', 'M13', 'lecture OCR', docAbrege(sha), {'empreinte': docAbrege(sha)}, {'etat': 'echec', 'code': lu.refus!.code});
        notifyListeners();
        return ResultatFileOcr.ok(fait: true, sha: sha);
      }
      final m = moteurActif!;
      final fiche = ocrNouvelleLecture(
          sha: sha,
          texte: lu.texte,
          moteur: m.id,
          moteurVersion: m.version,
          langue: r.langue,
          ocrLe: magasin.horloge().toUtc().toIso8601String(),
          ocrPar: magasin.utilisateur,
          declencheur: '${suivant['declencheur'] ?? 'automatique'}',
          pages: lu.pages,
          dureeMs: lu.dureeMs,
          confiance: lu.confiance);
      final nouvelle = _lectures.parId(fiche['id']) == null;
      if (nouvelle) {
        _lectures.inserer(fiche, prefixe: 'OCR');
        magasin.journaliser('Lecture OCR d’un scan', 'M13', 'lecture OCR', '${fiche['id']}', null, {'empreinte': docAbrege(sha), 'moteur': m.id, 'mots': fiche['nbMots'], 'pages': lu.pages});
      }
      // La ligne de file est terminée : elle ne se supprime pas (RG-14), elle est marquée faite, et ne compte plus comme file.
      _file.mettreAJour(suivant['id'], {'etat': 'termine', 'finLe': magasin.horloge().toUtc().toIso8601String()}, journaliser: false);
      magasin.journaliser('Lecture OCR terminée', 'M13', 'lecture OCR', docAbrege(sha), {'etat': 'en_cours'}, {'etat': 'ocr_indexe', 'version': fiche['id']});
      notifyListeners();
      return ResultatFileOcr.ok(fait: true, sha: sha, version: '${fiche['id']}', nouvelle: nouvelle);
    } finally {
      _occupe = false;
    }
  }

  /// Vide la file jusqu'à ce qu'il n'y ait plus rien à lire (tests, reprise à l'ouverture d'un écran).
  Future<int> vider([int max = 50]) async {
    reprendre();
    var faits = 0;
    while (faits < max) {
      final r = await traiterSuivant();
      if (!r.fait) break;
      faits++;
    }
    return faits;
  }

  /// Fait tourner la file sans bloquer la saisie : un fichier par passe, la main rendue entre deux. Le poste de bureau l'appelle une fois ; il s'arrête de lui-même quand la file est vide.
  void demarrer() {
    if (!automatique || _minuterie != null || !pret) return;
    _minuterie = Timer(const Duration(milliseconds: 50), () async {
      _minuterie = null;
      reprendre();
      final r = await traiterSuivant();
      if (r.fait) demarrer();
    });
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
  }

  /// Ce que la recherche ne lit pas, dit sous « Aucun résultat » : le BON nombre de pièces, la raison (aucun moteur installé...), les pièces lues par machine.
  String? indice(Iterable<FicheDoc> fiches) =>
      ocrIndiceVide([
        for (final f in fiches)
          if (f['statut'] != 'archive' && fichierDe(f) != null) etatDe(fichierDe(f)!)
      ]);

  /// Au-dessus des résultats : combien ont été trouvés par un texte lu par machine.
  String? noteRecherche(String q, Iterable<FicheDoc> lignes, {required String famille, required String role}) {
    if (q.trim().isEmpty) return null;
    var n = 0;
    for (final f in lignes) {
      final x = fichierDe(f);
      if (x == null) continue;
      if (etatDe(x).etat != EtatIndexation.ocrIndexe) continue;
      final t = texteOcr('${x['sha256']}', famille: famille, type: famille == 'patient' ? '${f['type']}' : null, role: role);
      if (fichierCorrespond(t, q)) n++;
    }
    return ocrNoteRecherche(n);
  }
}
