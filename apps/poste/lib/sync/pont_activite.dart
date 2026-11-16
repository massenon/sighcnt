import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_domaine/sigh_domaine.dart' show champDepartCompteurs, champEnAttenteMere, champSerieDemande, collectionsGestionSynchronisees, ficheLocaleAuPoste, identiteSyncGestion;

import '../donnees/magasin.dart';
import 'fusion_activite.dart';
import 'reservation_stock.dart';
import 'transcription_mobile.dart' show PieceSync;

/// LE PONT ENTRE LE MAGASIN DU POSTE ET LE JOURNAL D'OPÉRATIONS (PLAN de synchronisation S2 à S4 ; E2130 à E2134).
///
/// Jusqu'ici seule la CONFIGURATION voyageait (mère vers fileuls). Le pont fait voyager, dans les DEUX sens et sans geste de l'agent, l'activité qui peut le faire
/// sans danger, et les mots de passe hachés (un mot de passe changé sur un fileul remonte à la mère, qui le rediffuse). Un geste local arme une minuterie ; une
/// interrogation périodique relit le journal. Rien n'est supprimé en route (RG-14) : un archivage est un champ `statut` qui voyage comme les autres.
///
/// CE QUE LE PONT NE PORTE PAS, ET QU'IL FAUT DIRE : factures, avoirs, écritures (numérotation certifiée), stock, lots et mouvements (RG-03), admissions et lits
/// (un lit, une admission active). Leurs règles de fusion ne sont pas posées : les y faire passer en « dernier geste gagne » les corromprait.
const Set<String> collectionsActivite = {
  // LOT CLO-2 (C5, E3) : le STATUT des exercices voyage comme une donnée métier (fiche descriptive, identité commune `EXO-<année>`) : un fileul sait qu'un exercice est en clôture ou clos.
  'exercices',
  'patients',
  'rendezvous',
  'constantes',
  'releves',
  'observations',
  'visites',
  'appels',
  'consultations',
  'dossiersConsultation',
  'antecedents',
  // Lot L8 : les présences. Un pointage par badge s'écrit au poste (hors ligne comprise) et voyage comme les autres : une fiche par pointage, le départ et la validation
  // sont des correctifs de champs, que la fusion champ à champ garde tous. Deux postes hors ligne peuvent chacun enregistrer une arrivée : les deux lignes restent
  // visibles au registre, le surveillant régularise ou archive (RG-14), rien n'est corrigé en silence.
  'presences',
  // Lot L0 : les USAGES des paramètres par les pièces (une ligne par pièce et par clé, ajout seul). Un fileul note ici qu'une pièce a utilisé une valeur ; la mère,
  // qui seule écrit les versions, refuse ensuite de réécrire ce que cette pièce a utilisé.
  'usagesParametres',
  // Lot T6 : les DEMANDES de prix d'un fileul (proposition, décision, retrait), une fiche par demande. Le fileul la dépose ; la MÈRE l'applique après avoir refait les mêmes
  // contrôles sous le rôle de son auteur, puis écrit le verdict (`etat`, `resultatCode`, `resultatMotif`) sur la même fiche, qui revient au fileul par le même chemin.
  'propositionsTarif',
  // Lot IMP-C : les DEMANDES D'IMPORT d'un fileul (réponse Q5 de la Direction). Un référentiel de configuration importé à un fileul est refusé (réglé sur la mère) : le fileul dépose une demande
  // VÉRIFIÉE, la MÈRE rejoue l'analyse sous le rôle de l'auteur, applique ou refuse en nommant, et écrit le verdict sur la même fiche, qui revient au fileul par ce chemin. Les lignes du fichier
  // sont effacées de la fiche dès le verdict. Jamais vers un téléphone (RG-13).
  'demandesImport',
  // Lot CONT : les DÉCISIONS DE VALIDATION d'un fileul (une fiche par décision : famille, cible, auteur, rôle, date de SIGNATURE, motif). Le fileul la dépose, la MÈRE l'applique MÉCANIQUEMENT (mêmes
  // contrôles sous le rôle de l'auteur) et écrit le verdict (`etat`, `resultatCode`, `resultatMotif`) sur la même fiche, qui revient au fileul par ce chemin. Mère coupée : la décision reste au
  // journal local du fileul, rejouée à la reconnexion (jamais doublée). Jamais vers un téléphone (RG-13).
  'demandesValidation',
  // Lot IDENT : les DEMANDES D'IDENTITÉ d'un fileul habilité (une version datée de l'identité légale et/ou des options d'impression, signées : auteur, rôle, date de SIGNATURE). Le fileul la dépose,
  // la MÈRE revérifie le droit de la fiche RBAC sous le rôle de l'auteur, ajoute la version et la propage par la configuration, puis écrit le verdict sur la même fiche. Jamais vers un téléphone (RG-13).
  'demandesIdentite',
  // Lot D5 (EF-SYNC-18) : les MÉTADONNÉES des fichiers numérisés. La fiche d'un courrier ou d'un document du patient porte `fichier` (empreinte, nom, nom normalisé, type, taille, pages) ;
  // le registre `fichiers` est une fiche par empreinte (AJOUT SEUL, identité commune : deux postes qui déposent le même fichier ne font qu'une fiche). Le BINAIRE ne passe jamais par
  // ici : il voyage à part, par morceaux avec reprise (`service_fichiers.dart`). Jamais vers un téléphone (RG-13).
  'courriers',
  'documentsPatient',
  'fichiers',
  // Lot OCR-prep : les LECTURES OCR des scans (une fiche par version de texte lu par machine) sont une MÉTADONNÉE du fichier : elles voyagent par le journal avec le registre `fichiers`,
  // identité commune (`OCR-<empreinte>-<hash du texte>` : deux postes qui lisent le même scan avec le même moteur ne font qu'une version), ajout seul, jamais vers un téléphone (RG-13).
  // La FILE de lecture (`fileOcr`) reste locale au poste.
  'lecturesOcr',
  // Les pièces et les compteurs, avec leurs règles de fusion propres (`fusion_activite.dart`).
  'factures',
  'avoirs',
  'ecritures',
  'mouvements',
  'lots',
  'produits',
  'admissions',
  // LOT SYNC-CFG (décision 26 de la Direction, 15/11/2026) : les BUDGETS, les IMMOBILISATIONS et les COUVERTURES D'ASSURANCE. Une saisie ou un import chez un fileul ne reste plus local
  // à ce poste. Famille A (champ à champ) à la mère ; identité COMMUNE par le contenu (`identiteSyncGestion`) : deux postes qui écrivent la même chose ne font qu'une fiche. La mère
  // refuse au rejeu le budget d'un exercice clos (refus nommé). Jamais vers un téléphone (RG-13). Elles viennent APRÈS `patients` : l'identité d'une couverture lit celle de l'assuré.
  ...collectionsGestionSynchronisees,
  // LOT SAT (ADR-0009) : les RÉPONSES de satisfaction (ouvertes par la mère, famille B, `REPW-<id>` ; ou recueillies au guichet d'un poste) et les LIENS de collecte (famille A : un lien se révoque) vont
  // aux postes pour l'analyse. Jamais vers un téléphone (RG-13).
  'reponsesEnquetes',
  'jetonsEnquete',
};

/// Les référentiels d'ACTIVITÉ que la mère seule écrit (famille R de la mère) : un fileul les reçoit, il ne les envoie pas.
const Set<String> collectionsDeLaMereSeule = {'produits'};

/// Le registre des VARIATIONS de compteur dans le journal (stock des produits, quantité restante des lots).
const String collectionDeltas = 'deltasCompteurs';

/// Les marqueurs que chaque poste DÉDUIT lui-même des mêmes données : ils ne voyagent pas (un marqueur synchronisé ferait des allers-retours sans fin).
const Set<String> marqueursLocaux = {'codeEnDoublon', 'numeroEnDoublon', 'litEnConflit', 'stockNegatifDetecte', 'encaissementEnDoublon'};

/// Les fiches qui voyagent EN UN BLOC : un haché et son sel ne se mélangent jamais champ à champ entre deux postes.
const Set<String> collectionsAtomiques = {'identifiants'};

/// Les champs d'un haché qui restent PROPRES au poste : le compteur d'échecs et le verrou changent à chaque tentative ratée, ils ne voyagent pas (sinon chaque
/// mauvaise frappe réécrirait le haché partout et le ferait entrer en conflit avec un vrai changement de mot de passe).
const Set<String> champsLocauxDuHache = {'echecs', 'verrouJusqua', 'dernierEchecLe', 'dernierSuccesLe'};

/// Ce que le pont lit et écrit du côté du journal : le moteur du fileul, ou le service de la mère.
abstract class TransportPont {
  Future<List<PieceSync>> liste(String collection);
  Future<void> ecrire(String collection, String fiche, {required bool existe, required Map<String, Object?> champs});
}

/// Le transport du FILEUL : sa base de synchronisation locale.
class TransportFileul implements TransportPont {
  TransportFileul({required this.lire, required this.ecrireFiche});
  final Future<List<PieceSync>> Function(String) lire;
  final void Function(String collection, String fiche, {required bool existe, required Map<String, Object?> champs}) ecrireFiche;
  @override
  Future<List<PieceSync>> liste(String collection) => lire(collection);
  @override
  Future<void> ecrire(String collection, String fiche, {required bool existe, required Map<String, Object?> champs}) async =>
      ecrireFiche(collection, fiche, existe: existe, champs: champs);
}

/// Le transport de la MÈRE : le service de son propre processus (`GET /admin/liste`, `POST /admin/referentiel`).
class TransportMereLocale implements TransportPont {
  TransportMereLocale({required this.port, required this.admin, http.Client? client}) : _c = client ?? http.Client();
  final int port;
  final String admin;
  final http.Client _c;

  @override
  Future<List<PieceSync>> liste(String collection) async {
    final r = await _c
        .get(Uri.parse('http://127.0.0.1:$port/admin/liste?collection=${Uri.encodeQueryComponent(collection)}'), headers: {'x-admin': admin})
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw StateError('la mère a répondu ${r.statusCode}');
    return [
      for (final x in (jsonDecode(r.body) as List))
        PieceSync('${(x as Map)['id']}', (x['data'] as Map).cast<String, Object?>(), archive: x['archive'] == true)
    ];
  }

  /// Une plage de numéros de dossier pour la mère elle-même (`POST /admin/plage`) : le même carnet que celui des fileuls.
  Future<(int, int)> plage(int taille, int minimum) async {
    final r = await _c
        .post(Uri.parse('http://127.0.0.1:$port/admin/plage'),
            headers: {'content-type': 'application/json', 'x-admin': admin}, body: jsonEncode({'nom': 'patients', 'taille': taille, 'minimum': minimum}))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw StateError('la mère a répondu ${r.statusCode}');
    final c = jsonDecode(r.body) as Map;
    return ((c['debut'] as num).toInt(), (c['fin'] as num).toInt());
  }

  @override
  Future<void> ecrire(String collection, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    final r = await _c
        .post(Uri.parse('http://127.0.0.1:$port/admin/referentiel'),
            headers: {'content-type': 'application/json', 'x-admin': admin}, body: jsonEncode({'collection': collection, 'fiche': fiche, 'champs': champs}))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw StateError('la mère a répondu ${r.statusCode} : ${r.body}');
    final corps = jsonDecode(r.body);
    if (corps is Map && corps['statut'] == 'refusee') throw StateError('${corps['motif'] ?? corps['code']}');
  }
}

String _j(Object? o) => jsonEncode(o);

class PontActivite {
  PontActivite(this.magasin, this.transport,
      {required this.etiquette,
      Set<String>? collections,
      this.enLectureSeule = const {},
      this.liaison,
      this.surveillerLesAutres = false,
      this.delai = const Duration(seconds: 1)})
      : collections = collections ?? {...collectionsActivite, ...collectionsAtomiques};
  final Magasin magasin;
  final TransportPont transport;

  /// Le préfixe propre à ce poste : un identifiant local `ID00042` qui existe sur deux postes à la fois devient `<étiquette>-ID00042`, unique dans la clinique.
  final String etiquette;
  final Set<String> collections;

  /// Les collections que ce poste REÇOIT sans jamais les envoyer : les référentiels que la mère seule écrit (le catalogue des produits, famille R). Un fileul
  /// qui en enverrait une fiche s'attirerait un refus sans objet à chaque tour.
  final Set<String> enLectureSeule;

  /// Ce poste atteint-il VRAIMENT sa mère ? Le transport d'un fileul est sa base locale : il répond toujours, même mère injoignable. Cette fonction dit la
  /// vérité (`MoteurFileul.instantane`). Absente : le tour réussi suffit (la mère, qui parle à son propre service).
  final Future<bool> Function()? liaison;

  /// La MÈRE ne se sait pas coupée d'un fileul : elle le déduit de son battement. Vrai : elle n'est « en liaison » que si TOUS les postes connus ont battu récemment.
  final bool surveillerLesAutres;
  final Duration delai;

  /// La dernière version SYNCHRONISÉE de chaque fiche (clé `collection/idSync`) : sert de base à la fusion champ à champ.
  final Map<String, Map<String, Object?>> _base = {};
  final Map<String, VoidCallback> _ecouteurs = {};
  Timer? _minuterie, _periode;
  bool _enCours = false;

  final ValueNotifier<String?> erreur = ValueNotifier<String?>(null);
  /// Les fiches que la mère a REFUSÉES (clé `collection/identifiant` → motif) : jamais perdues en silence, comptées ici et lisibles.
  final Map<String, String> motifsRefus = {};
  final Map<String, String> _refusees = {};
  final ValueNotifier<int> refus = ValueNotifier<int>(0);
  final ValueNotifier<int> envoyees = ValueNotifier<int>(0);
  final ValueNotifier<int> recues = ValueNotifier<int>(0);

  /// Les patients dont le code CNT existe en double (RG-01) : jamais corrigés en silence, comptés et marqués `codeEnDoublon`.
  final ValueNotifier<int> doublonsDeCode = ValueNotifier<int>(0);

  void demarrer({Duration intervalle = const Duration(seconds: 3)}) {
    for (final n in collections) {
      if (_ecouteurs.containsKey(n)) continue;
      void ecoute() => _armer();
      _ecouteurs[n] = ecoute;
      magasin.collection(n).addListener(ecoute);
    }
    _periode?.cancel();
    _periode = Timer.periodic(intervalle, (_) => unawaited(cycle()));
    unawaited(cycle());
  }

  void arreter() {
    _minuterie?.cancel();
    _periode?.cancel();
    _minuterie = _periode = null;
    _ecouteurs.forEach((n, e) => magasin.collection(n).removeListener(e));
    _ecouteurs.clear();
  }

  void _armer() => _minuterie ??= Timer(delai, () {
        _minuterie = null;
        unawaited(cycle());
      });

  /// Un tour complet : d'abord ce que l'agent a fait (envoi), puis ce que les autres postes ont fait (réception).
  Future<void> cycle() async {
    if (_enCours) return;
    _enCours = true;
    try {
      await pousser();
      await _pousserCompteurs();
      await tirer();
      await _tirerCompteurs();
      _deduireMarqueurs();
      await _battement();
      var joint = liaison == null ? true : await liaison!();
      if (joint && surveillerLesAutres) joint = _tousFrais;
      if (joint) ReservationStock.de(magasin).synchronise(magasin, collections, postes: _nbPostes);
      erreur.value = null;
    } catch (e) {
      erreur.value = 'Synchronisation de l’activité impossible : $e';
    } finally {
      _enCours = false;
    }
  }

  static bool _atomique(String c) => collectionsAtomiques.contains(c);

  /// La forme d'une fiche dans le journal. Une fiche atomique devient un champ unique.
  Map<String, Object?> _versJournal(String c, Fiche f) {
    if (_atomique(c)) return {'atome': _j({...f}..removeWhere((k, _) => champsLocauxDuHache.contains(k)))};
    final champs = {...f}..remove('id');
    for (final k in marqueursLocaux) {
      champs.remove(k);
    }
    // Un compteur ne voyage JAMAIS comme un champ : il voyage par ses variations (une sortie de stock d'un poste ne remplace pas celle d'un autre).
    for (final k in champsCompteurs[c] ?? const <String>{}) {
      champs.remove(k);
    }
    return champs;
  }

  Map<String, Object?> _sansLocaux(String c, Map<String, Object?> d) => d;

  String _cleSync(String c, Fiche f) => _atomique(c) ? '${f['id']}' : '${f['idSync']}';

  /// Donne à chaque fiche son identité de synchronisation (y compris dans les collections que ce poste ne fait que recevoir : sans elle, la fiche reçue
  /// remplacerait la fiche locale au lieu de la rejoindre). Une fiche du jeu d'ORIGINE existe à l'identique sur tous les postes : son identité est son
  /// identifiant ; toute autre fiche porte l'étiquette de son poste.
  void _identifier() {
    for (final c in collections) {
      if (_atomique(c)) continue;
      for (final f in magasin.collection(c).toutes) {
        if ('${f['id'] ?? ''}'.isEmpty || '${f['idSync'] ?? ''}'.isNotEmpty) continue;
        // LOT IMP-E : une fiche née d'une DEMANDE D'IMPORT porte la même identité sur tous les postes (son identifiant, déterministe : `<COL>-<demande>-<rang>`), comme une fiche du jeu
        // d'origine. Préfixée de l'étiquette du poste, la fiche du fileul et celle que la mère réécrit seraient DEUX fiches (mesuré : lots, mouvements et articles comptés deux fois).
        // Même règle pour un référentiel d'activité que la mère seule écrit (le catalogue des produits) : la configuration le publie sous son identifiant, le pont sous son identité de synchronisation ;
        // préfixée, elle faisait de chaque article créé après le jeu d'origine DEUX fiches chez un fileul (mesuré avec un import de la mère).
        // Lot D5 : une fiche du registre `fichiers` a pour identifiant `FIC-<empreinte>` : déterministe, elle est la MÊME sur tous les postes (préfixée, deux postes qui déposent le même fichier
        // feraient deux fiches et le texte indexé deux fois).
        final identiteCommune = magasin.idsOrigine(c).contains('${f['id']}') || '${f[champSerieDemande] ?? ''}'.isNotEmpty || collectionsDeLaMereSeule.contains(c) || c == 'fichiers' || c == 'lecturesOcr' || c == 'exercices';
        // LOT SYNC-CFG : budget, bien, couverture créés sur un poste prennent une identité COMMUNE tirée de leur contenu (jamais préfixée du poste) : le même budget saisi à deux postes,
        // le même fichier importé deux fois mère coupée, ne font qu'une fiche partout.
        final parContenu = identiteCommune || !collectionsGestionSynchronisees.contains(c)
            ? null
            : identiteSyncGestion(c, f, patientSync: '${magasin.collection('patients').parId(f['patientId'])?['idSync'] ?? ''}');
        f['idSync'] = identiteCommune ? '${f['id']}' : (parContenu ?? '$etiquette-${f['id']}');
      }
    }
  }

  Future<int> pousser() async {
    _identifier();
    var n = 0;
    for (final c in collections) {
      if (enLectureSeule.contains(c)) continue;
      final col = magasin.collection(c);
      List<PieceSync>? distant;
      for (final f in List<Fiche>.of(col.toutes)) {
        if ('${f['id'] ?? ''}'.isEmpty) continue;
        // LOT IMP-E : une fiche que la mère n'a pas confirmée (ou a refusée) est PROPRE À CE POSTE, et un mouvement qui s'appuie sur un article propre à ce poste aussi : aucun autre poste
        // ne voit un stock que la mère n'a pas accepté.
        if (_proprePoste(c, f)) continue;

        final cle = _cleSync(c, f);
        final champs = _versJournal(c, f);
        var base = _base['$c/$cle'];
        if (base != null && _j(base) == _j(champs)) continue;
        if (base == null) {
          // Une fiche que le journal porte déjà À L'IDENTIQUE n'est pas réécrite : un écho inutile entrerait en conflit avec le vrai changement qui suit.
          distant ??= await transport.liste(c);
          final deja = distant.where((p) => p.id == cle).firstOrNull;
          if (deja != null && _j(_sansLocaux(c, deja.data)) == _j(champs)) {
            _base['$c/$cle'] = champs;
            continue;
          }
        }
        // Seuls les champs qui ont changé partent : deux postes qui touchent des champs différents ne s'écrasent pas.
        final diff = base == null || _atomique(c)
            ? champs
            : <String, Object?>{for (final e in champs.entries) if (_j(base[e.key]) != _j(e.value)) e.key: e.value};
        distant ??= await transport.liste(c);
        final existe = distant.any((p) => p.id == cle);
        if (_atomique(c) && existe) {
          // Un haché plus ANCIEN que celui du journal ne l'écrase jamais (poste resté en retard) : il sera remplacé à la réception.
          final brut = distant.firstWhere((p) => p.id == cle).data['atome'];
          final d = brut is String ? DateTime.tryParse('${(jsonDecode(brut) as Map)['definiLe'] ?? ''}') : null;
          final i = DateTime.tryParse('${f['definiLe'] ?? ''}');
          if (d != null && (i == null || d.isAfter(i))) continue;
        }
        final empreinteRefus = _j(champs);
        if (_refusees['$c/$cle'] == empreinteRefus) continue;
        try {
          await transport.ecrire(c, cle, existe: existe, champs: diff);
        } on StateError catch (e) {
          // Un refus NOMMÉ de la mère ne bloque pas le reste : la fiche est mise de côté, dite, et réessayée dès qu'elle change.
          _refusees['$c/$cle'] = empreinteRefus;
          motifsRefus['$c/$cle'] = '$e';
          refus.value = motifsRefus.length;
          continue;
        }
        _refusees.remove('$c/$cle');
        motifsRefus.remove('$c/$cle');
        refus.value = motifsRefus.length;
        _base['$c/$cle'] = champs;
        n++;
      }
    }
    envoyees.value += n;
    return n;
  }

  Future<int> tirer() async {
    var n = 0;
    for (final c in collections) {
      final col = magasin.collection(c);
      for (final p in await transport.liste(c)) {
        final cle = p.id;
        final distant = p.data;
        if (_atomique(c)) {
          final brut = distant['atome'];
          if (brut is! String) continue;
          final f = (jsonDecode(brut) as Map).cast<String, Object?>();
          final local = col.parId(f['id']);
          if (local != null) {
            // Le plus RÉCENT gagne, jamais l'inverse : un mot de passe changé ici ne revient pas à l'ancien.
            final d = DateTime.tryParse('${f['definiLe'] ?? ''}');
            final i = DateTime.tryParse('${local['definiLe'] ?? ''}');
            if (d == null || (i != null && !d.isAfter(i))) {
              if (i != null && d != null && i.isAfter(d)) continue;
              _base['$c/$cle'] = distant;
              continue;
            }
          }
          if (local != null) {
            for (final k in champsLocauxDuHache) {
              if (local.containsKey(k)) f[k] = local[k];
            }
          }
          if (col.appliquerDistante(f)) n++;
          _base['$c/$cle'] = distant;
          continue;
        }
        final local = _parSync(col, cle);
        final recu = <String, Object?>{...distant, 'idSync': cle, if (p.archive) 'statut': 'archive'};
        if (local == null) {
          // LOT IMP-E : une fiche née d'une demande d'import arrive avec sa valeur de DÉPART : c'est son compteur tant qu'aucune variation n'est venue s'y ajouter.
          final nouvelle = <String, Object?>{...recu, 'id': cle};
          for (final k in champsCompteurs[c] ?? const <String>{}) {
            // La valeur d'un compteur publiée par un autre poste n'est jamais adoptée : son départ (demande d'import), sinon rien (les variations qu'il a publiées s'y additionnent à partir de zéro).
            final d = _depart(recu, k);
            if (d != null) {
              nouvelle[k] = d;
            } else {
              nouvelle.remove(k);
            }
          }
          if (col.appliquerDistante(nouvelle)) n++;
          _base['$c/$cle'] = recu;
          continue;
        }
        final base = _base['$c/$cle'];
        final fusion = <String, Object?>{};
        final compteursDeC = champsCompteurs[c] ?? const <String>{};
        for (final k in {...recu.keys, ...local.keys}) {
          if (k == 'id') continue;
          // LOT IMP-E : un compteur ne se remplace JAMAIS par la valeur d'un autre poste (la fiche de configuration que la mère publie porte le stock du jour, comme avant, pour les
          // téléphones) : il bouge par ses variations. Ce poste garde le sien ; remplacer sa valeur effacerait ses sorties que la mère n'a pas encore reçues.
          if (compteursDeC.contains(k)) {
            if (local.containsKey(k)) {
              fusion[k] = local[k];
            } else {
              final d = _depart(recu, k);
              if (d != null) fusion[k] = d;
            }
            continue;
          }
          // Fusion à trois voies : ce que l'agent a changé ici est gardé, le reste suit le journal.
          final changeIci = base != null && _j(local[k]) != _j(base[k]);
          final v = changeIci ? local[k] : (recu.containsKey(k) ? recu[k] : local[k]);
          if (v != null) fusion[k] = v;
        }
        fusion['id'] = local['id'];
        // LOT IMP-E : la fiche de la MÈRE est arrivée : c'est la confirmation du stock que ce poste tenait « en attente ». Le marquage tombe, la fiche suit désormais le chemin ordinaire.
        if ('${local[champEnAttenteMere] ?? ''}'.isNotEmpty) fusion.remove(champEnAttenteMere);
        // Les règles propres à la famille : un règlement ne se perd pas.
        if (c == 'factures') {
          final regle = fusionnerFacture(fusion, local, recu);
          fusion
            ..clear()
            ..addAll(regle);
        }
        if (_j(fusion) != _j(local)) {
          col.appliquerDistante(fusion);
          n++;
        }
        _base['$c/$cle'] = recu;
      }
    }
    recues.value += n;
    return n;
  }

  /// LOT IMP-E : cette fiche ne part pas au journal (voir [ficheLocaleAuPoste]). Un mouvement ou un lot qui s'appuie sur un article propre à ce poste l'est aussi.
  bool _proprePoste(String c, Fiche f) {
    if (ficheLocaleAuPoste(f)) return true;
    if ((c == 'mouvements' || c == 'lots') && '${f['produitId'] ?? ''}'.isNotEmpty) {
      final p = magasin.collection('produits').parId(f['produitId']);
      if (p != null && ficheLocaleAuPoste(p)) return true;
    }
    return false;
  }

  /// LOT IMP-E : le point de départ d'un compteur d'une fiche née d'une demande d'import (la valeur d'écriture, commune à tous les postes), ou `null`.
  static num? _depart(Map<String, Object?> f, String champ) {
    final d = f[champDepartCompteurs];
    final v = d is Map ? d[champ] : null;
    return v is num ? v : null;
  }

  Fiche? _parSync(CollectionMagasin col, String cle) {
    for (final f in col.toutes) {
      if (f['idSync'] == cle) return f;
    }
    return null;
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // LE BATTEMENT : combien de postes dans la clinique ?
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  DateTime? _dernierBattement;
  int? _nbPostes;
  static const String collectionBattements = 'postesClinique';

  /// Chaque poste publie un battement (au plus un toutes les 10 secondes) ; les postes qui ont battu dans les sept derniers jours forment la clinique. Le nombre sert à
  /// partager le stock entre postes quand l'un d'eux est hors ligne (`ReservationStock`).
  Future<void> _battement() async {
    final now = DateTime.now();
    final liste = await transport.liste(collectionBattements);
    if (_dernierBattement == null || now.difference(_dernierBattement!) > const Duration(seconds: 10)) {
      final existe = liste.any((p) => p.id == etiquette);
      try {
        await transport.ecrire(collectionBattements, etiquette, existe: existe, champs: {'vuLe': now.toIso8601String()});
        _dernierBattement = now;
      } on StateError {
        // refus : on garde ce qu'on sait
      }
    }
    final actifs = {
      etiquette,
      for (final p in liste)
        if ((DateTime.tryParse('${p.data['vuLe'] ?? ''}') ?? DateTime(2000)).isAfter(now.subtract(const Duration(days: 7)))) p.id,
    };
    _nbPostes = actifs.length;
    // Les AUTRES postes ont-ils battu il y a moins de 30 s ? (la mère n'a pas d'autre moyen de savoir qu'un fileul est coupé)
    _tousFrais = [
      for (final p in liste)
        if (p.id != etiquette) DateTime.tryParse('${p.data['vuLe'] ?? ''}') ?? DateTime(2000)
    ].every((d) => now.difference(d) <= const Duration(seconds: 30));
  }

  bool _tousFrais = true;

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // LES COMPTEURS (stock des produits, quantité restante des lots)
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  /// Le total que le journal porte, tel que CE poste le connaît (clé `collection/idSync/champ`), et les variations déjà prises en compte. Ils vivent au magasin
  /// (collection locale `pontEtat`) : un redémarrage ne doit pas faire compter une variation deux fois.
  final Map<String, num> _totaux = {};
  final Set<String> _appliques = {};
  bool _etatCharge = false;
  int _serie = 0;

  /// Le nombre de produits ou de lots dont le compteur est NÉGATIF après fusion (RG-03) : détecté, marqué `stockNegatifDetecte`, jamais corrigé en silence.
  final ValueNotifier<int> stocksNegatifs = ValueNotifier<int>(0);

  static num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

  void _chargerEtat() {
    if (_etatCharge) return;
    _etatCharge = true;
    final f = magasin.collection('pontEtat').parId('compteurs');
    if (f == null) return;
    for (final e in ((f['totaux'] as Map?) ?? const {}).entries) {
      _totaux['${e.key}'] = _n(e.value);
    }
    _appliques.addAll([for (final i in (f['appliques'] as List? ?? const [])) '$i']);
  }

  void _sauverEtat() {
    final col = magasin.collection('pontEtat');
    final fiche = <String, Object?>{'id': 'compteurs', 'totaux': {..._totaux}, 'appliques': [..._appliques]};
    if (col.parId('compteurs') == null) {
      col.ajouterSansJournal(fiche);
    } else {
      col.appliquerDistante(fiche);
    }
  }

  static ({String collection, String cle, String champ})? _decouper(String cleC) {
    final i = cleC.indexOf('/'), j = cleC.lastIndexOf('/');
    if (i < 0 || j <= i) return null;
    return (collection: cleC.substring(0, i), cle: cleC.substring(i + 1, j), champ: cleC.substring(j + 1));
  }

  /// Envoie les variations de ce poste. Le POINT DE DÉPART d'un compteur est le même partout : la valeur du jeu d'origine pour une fiche livrée avec le poste,
  /// zéro pour une fiche créée depuis. Tout ce qui s'en écarte localement part comme une variation, et rien d'autre : un poste qui rejoint la clinique avec ses
  /// propres sorties les publie, et reçoit celles des autres.
  Future<int> _pousserCompteurs() async {
    _chargerEtat();
    var n = 0, change = false;
    for (final e in champsCompteurs.entries) {
      if (!collections.contains(e.key)) continue;
      final col = magasin.collection(e.key);
      for (final f in List<Fiche>.of(col.toutes)) {
        final idSync = '${f['idSync'] ?? ''}';
        if (idSync.isEmpty) continue;
        // LOT IMP-E : un compteur propre à ce poste (stock non confirmé) ne publie rien : ses variations partiront, comptées depuis son départ, quand la mère aura confirmé.
        if (_proprePoste(e.key, f)) continue;
        final origine = idSync == '${f['id']}' ? magasin.ficheOrigine(e.key, idSync) : null;
        for (final k in e.value) {
          final cleC = '${e.key}/$idSync/$k';
          if (!_totaux.containsKey(cleC)) {
            // Le point de départ commun : la valeur du jeu d'origine, ou celle d'écriture d'une demande d'import (lot IMP-E), sinon zéro.
            _totaux[cleC] = origine != null && origine.containsKey(k) ? _n(origine[k]) : (_depart(f, k) ?? 0);
            change = true;
          }
          if (!f.containsKey(k)) continue;
          final diff = _n(f[k]) - _totaux[cleC]!;
          if (diff == 0) continue;
          final id = '$etiquette~${DateTime.now().microsecondsSinceEpoch}~${_serie++}';
          try {
            await transport.ecrire(collectionDeltas, id, existe: false, champs: {'cle': cleC, 'delta': diff, 'poste': etiquette});
          } on StateError {
            continue;
          }
          _totaux[cleC] = _totaux[cleC]! + diff;
          _appliques.add(id);
          change = true;
          n++;
        }
      }
    }
    if (change) _sauverEtat();
    return n;
  }

  /// Additionne les variations des AUTRES postes aux compteurs locaux (celles que ce poste a lui-même publiées sont déjà comptées).
  Future<int> _tirerCompteurs() async {
    _chargerEtat();
    final deltas = await transport.liste(collectionDeltas);
    var n = 0, change = false;
    for (final d in deltas) {
      if (_appliques.contains(d.id)) continue;
      final cleC = '${d.data['cle']}';
      final cible = _decouper(cleC);
      if (cible == null || !collections.contains(cible.collection)) continue;
      final col = magasin.collection(cible.collection);
      final f = _parSync(col, cible.cle);
      if (f == null) continue;
      if (!_totaux.containsKey(cleC)) {
        final origine = cible.cle == '${f['id']}' ? magasin.ficheOrigine(cible.collection, cible.cle) : null;
        _totaux[cleC] = origine != null && origine.containsKey(cible.champ) ? _n(origine[cible.champ]) : (_depart(f, cible.champ) ?? 0);
      }
      final delta = _n(d.data['delta']);
      f[cible.champ] = _n(f[cible.champ]) + delta;
      col.appliquerDistante({...f});
      _totaux[cleC] = _totaux[cleC]! + delta;
      _appliques.add(d.id);
      change = true;
      n++;
    }
    if (change) _sauverEtat();
    recues.value += n;
    return n;
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // LES MARQUEURS QUE CHAQUE POSTE DÉDUIT DES MÊMES DONNÉES
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  /// Les pièces au même numéro (par collection) : le nombre de fiches concernées.
  final Map<String, int> doublonsDeNumero = {};

  void _marquer(CollectionMagasin col, Iterable<Fiche> toutes, Set<Fiche> concernees, String marqueur) {
    for (final f in toutes) {
      final doit = concernees.any((x) => identical(x, f));
      if ((f[marqueur] == true) != doit) {
        if (doit) {
          f[marqueur] = true;
        } else {
          f.remove(marqueur);
        }
        col.appliquerDistante({...f});
      }
    }
  }

  String _identitePiece(String c, Fiche f) {
    if (c == 'ecritures') return '${f['pieceId'] ?? '${f['_creePar']}|${f['date']}|${f['libelle']}'}';
    return '${f['idSync'] ?? f['id']}';
  }

  void _deduireMarqueurs() {
    for (final e in champsNumero.entries) {
      if (!collections.contains(e.key)) continue;
      final col = magasin.collection(e.key);
      final groupes = numerosEnDoublon(col.toutes, e.value.champ, (f) => _identitePiece(e.key, f));
      final concernees = {for (final g in groupes) ...g};
      _marquer(col, col.toutes, concernees, e.value.marqueur);
      if (e.key == 'patients') {
        doublonsDeCode.value = concernees.length;
      } else {
        doublonsDeNumero[e.key] = concernees.length;
      }
    }
    if (collections.contains('admissions')) {
      final col = magasin.collection('admissions');
      final conflits = {for (final g in litsEnConflit(col.toutes)) ...g};
      _marquer(col, col.toutes, conflits, 'litEnConflit');
      litsEnConflitCompte.value = conflits.length;
    }
    var neg = 0;
    for (final e in champsCompteurs.entries) {
      if (!collections.contains(e.key)) continue;
      final col = magasin.collection(e.key);
      final negatives = <Fiche>{
        for (final f in col.toutes)
          if (e.value.any((k) => f[k] is num && (f[k] as num) < 0)) f
      };
      neg += negatives.length;
      _marquer(col, col.toutes, negatives, 'stockNegatifDetecte');
    }
    stocksNegatifs.value = neg;
    if (collections.contains('factures')) {
      final col = magasin.collection('factures');
      for (final f in List<Fiche>.of(col.toutes)) {
        final voulu = statutPaiementDepuis(f);
        if (voulu != null) col.appliquerDistante({...f, 'statutPaiement': voulu});
      }
    }
  }

  /// Les admissions actives dont le lit est aussi pris par une autre admission active (un lit, une admission active).
  final ValueNotifier<int> litsEnConflitCompte = ValueNotifier<int>(0);
}
