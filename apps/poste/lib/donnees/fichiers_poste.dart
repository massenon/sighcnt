import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart' show EtatLocalFichier, ErreurFichier, StockageFichiers;

import 'magasin.dart';

/// LES FICHIERS NUMÉRISÉS AU POSTE (lot D5, portage de `modules/fichiers.js` de la maquette) : dépôt d'un scan sur la fiche d'un courrier (M13) ou d'un document du patient
/// (M1), lecture avec empreinte VÉRIFIÉE, téléchargement sous le nom normalisé, retrait annulable (RG-14), taille maximale réglée en base, recherche dans le texte indexé.
///
/// Le fichier vit sur le disque du poste, hors du magasin ([StockageFichiers] : `<aa>/<sha256>.<ext>`, chiffré au repos avec la clé du poste, empreinte recalculée à chaque
/// lecture) ; la fiche ne garde que ses métadonnées. TOUTES les règles sont celles du domaine (`packages/domaine/lib/src/fichiers`, vecteurs tirés de la maquette) : ce service ne
/// décide rien, il enchaîne les gestes, journalise (RG-12) et range. Aucun appel réseau : un poste autonome, sans mère, dépose, lit et télécharge sans erreur.

/// Ce que rend un geste : réussi (avec ce qu'il a produit et de quoi l'annuler), ou REFUSÉ en nommant (code, motif, geste).
class ResultatFichier {
  const ResultatFichier.ok({this.fichier, this.annuler, this.octets, this.nom, this.avertissementDoublon})
      : ok = true,
        refus = null;
  const ResultatFichier.refus(RefusFichier this.refus)
      : ok = false,
        fichier = null,
        annuler = null,
        octets = null,
        nom = null,
        avertissementDoublon = null;
  final bool ok;
  final RefusFichier? refus;

  /// L'objet `fichier` posé sur la fiche (dépôt), ou le fichier lu.
  final Map<String, Object?>? fichier;

  /// Défait le geste (dépôt : la fiche redevient « sans pièce » ; retrait : la pièce revient).
  final VoidCallback? annuler;
  final Uint8List? octets;
  final String? nom;

  /// Le fichier est déjà la pièce d'une AUTRE fiche : le geste a été confirmé par l'agent.
  final FicheDoc? avertissementDoublon;
}

/// L'état d'un transfert de fichiers vers CE poste : branché par la synchronisation (étape 5), absent sur un poste autonome.
abstract class EtatTransfertFichiers {
  /// Un transfert de cette empreinte est commencé ou en attente.
  bool enCours(String sha);

  /// Ce poste joint sa mère (ou l'est).
  bool get mereJoignable;
}

/// La file d'envoi des fichiers vers la mère : collection LOCALE au poste.
const String fichiersFileEnvoi = 'transfertsFichiers';

/// Les noms des collections et le module du journal de chaque famille.
String fichiersCollectionDe(String famille) => famille == 'patient' ? 'documentsPatient' : 'courriers';
String _module(String famille) => famille == 'patient' ? 'M1' : 'M13';
String _entite(String famille) => famille == 'patient' ? 'document' : 'courrier';

String _dateFr(Object? iso) {
  final s = '${iso ?? ''}';
  if (s.length < 10) return '';
  return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
}

/// La décompression Flate de `dart:io`, pour l'extracteur de texte (zlib, puis DEUXIÈME tentative en DEFLATE brut : les mêmes essais que le serveur de la maquette).
List<int>? inflaterIo(List<int> flux) {
  try {
    return ZLibCodec().decode(flux);
  } catch (_) {}
  try {
    return ZLibCodec(raw: true).decode(flux.sublist(2));
  } catch (_) {}
  try {
    return ZLibCodec(raw: true).decode(flux);
  } catch (_) {}
  return null;
}

class FichiersPoste extends ChangeNotifier {
  FichiersPoste(this.magasin, this.stockage, {PdfInflater inflater = inflaterIo, this.transfert}) : _inflater = inflater;

  final Magasin magasin;
  final StockageFichiers stockage;
  final PdfInflater _inflater;

  /// Branché par la synchronisation ; `null` : poste sans mère.
  EtatTransfertFichiers? transfert;

  static final Expando<FichiersPoste> _installes = Expando<FichiersPoste>('FichiersPoste');

  /// Le service installé pour ce magasin (posé par `main`, ou par un test), ou `null` : les écrans ne plantent jamais sans lui, ils le disent.
  static FichiersPoste? de(Magasin m) => _installes[m];
  void installer() => _installes[magasin] = this;

  // --- taille maximale (réglage en base : collection `reglages`, fiche `documentsBornes`) --------------------------------------------------

  Map<String, Object?>? get _reglage {
    final f = magasin.collection('reglages').parId('documentsBornes');
    final v = f?['valeur'];
    return v is Map ? v.cast<String, Object?>() : null;
  }

  int tailleMax() => fichierTailleMax(_reglage);
  bool get tailleMaxReglee => fichierTailleMaxReglee(_reglage);
  bool peutRegler(String role) => fichierPeutRegler(role);

  /// Règle la taille maximale : réservé à l'administrateur et à la DAF, motivé, borné ; l'écriture est en base, le geste journalisé.
  ResultatFichier definirTailleMax({required String role, required Object? octets, required String? motif}) {
    final r = fichierDefinirTailleMax(role: role, octets: octets, motif: motif, reglage: _reglage);
    if (!r.ok) return ResultatFichier.refus(r.refus!);
    final col = magasin.collection('reglages');
    final valeur = {'tailleMax': r.tailleMax, 'regleLe': magasin.horloge().toIso8601String(), 'reglePar': magasin.utilisateur};
    if (col.parId('documentsBornes') == null) {
      col.inserer({'id': 'documentsBornes', 'valeur': valeur});
    } else {
      col.mettreAJour('documentsBornes', {'valeur': valeur}, journaliser: false);
    }
    final m = (motif ?? '').trim();
    magasin.journaliser('Taille maximale d’un fichier numérisé', 'M14', 'reglage', 'documentsBornes', {'tailleMax': r.avant}, {'tailleMax': r.tailleMax, 'motif': m.length > 60 ? m.substring(0, 60) : m});
    notifyListeners();
    return ResultatFichier.ok(fichier: {'tailleMax': r.tailleMax, 'avant': r.avant});
  }

  // --- le registre par empreinte (collection `fichiers`) ----------------------------------------------------------------------------------

  CollectionMagasin get _registre => magasin.collection('fichiers');

  /// Une fiche par empreinte, AJOUT SEUL : un second dépôt du même fichier (chez ce poste ou un autre) ne crée jamais une seconde fiche. Pas de compteur de références
  /// (il se déduit des fiches : un compteur synchronisé entre postes serait compté deux fois).
  void _noter(Map<String, Object?> depot) {
    final id = fichierIdRegistre('${depot['sha256']}');
    if (_registre.parId(id) != null) return;
    _registre.inserer(fichierEntreeRegistre(depot: depot, premiereDate: magasin.horloge().toIso8601String()), prefixe: 'FIC');
  }

  /// Le texte indexé d'une empreinte (mots normalisés), ou `''`.
  String texteDe(Object? sha) {
    if (sha == null) return '';
    final f = _registre.parId(fichierIdRegistre('$sha'));
    return '${f?['texte'] ?? ''}';
  }

  /// Le texte que la recherche d'un registre lit en plus des colonnes (observations, date lisible, nom du fichier, texte extrait).
  String texteRecherche(FicheDoc fiche) {
    final x = fichierDe(fiche);
    return fichierTexteRecherche(fiche, dateFr: _dateFr(fiche['date']), texteIndexe: x == null ? '' : texteDe(x['sha256']), observations: '${fiche['observations'] ?? ''}');
  }

  /// Ce que la recherche ne lit pas, dit sous « Aucun résultat » : le nombre de pièces sans texte indexé parmi [fiches].
  String? indiceNonIndexe(Iterable<FicheDoc> fiches) =>
      fichierIndiceNonIndexe(fiches.where((f) => f['statut'] != 'archive' && fichierDe(f) != null && fichierDe(f)!['texteIndexe'] != true).length);

  // --- dépôt, remplacement ---------------------------------------------------------------------------------------------------------------------

  ResultatFichier _refus(String code, String motif, String geste) => ResultatFichier.refus(RefusFichier(code, motif, geste));

  /// Les étapes COMMUNES d'un dépôt (sur une fiche existante ou à la création d'une fiche) : format lu sur les octets, taille, doublon, confirmation, indexation du texte, rangement
  /// sur le disque (empreinte recalculée), registre par empreinte. Rend le refus nommé, ou le dépôt et le doublon confirmé.
  Future<({ResultatFichier? refus, Map<String, Object?>? depot, FicheDoc? autre})> _ranger(
      {required String famille,
      required String nom,
      required String mime,
      required Uint8List octets,
      required String? type,
      required Iterable<FicheDoc> fiches,
      FicheDoc? ficheCourante,
      bool Function(FicheDoc)? portee,
      Future<bool> Function(FicheDoc autre)? confirmerAutre}) async {
    final prep = fichierPreparerDepot(nom: nom, mime: mime, octets: octets, famille: famille, tailleMax: tailleMax(), fiches: fiches, ficheCourante: ficheCourante, portee: portee);
    if (prep.refus != null) return (refus: ResultatFichier.refus(prep.refus!), depot: null, autre: null);
    if (prep.autre != null) {
      final ok = confirmerAutre == null ? false : await confirmerAutre(prep.autre!);
      if (!ok) return (refus: _refus('DEPOT_ANNULE', 'dépôt annulé après l’avertissement de doublon', 'Choisir un autre fichier si besoin.'), depot: null, autre: null);
    }
    final idx = indexerFichier(octets, prep.format!.id, _inflater);
    try {
      final r = await stockage.ranger(octets,
          famille: famille, zone: famille == 'patient' ? docZoneDe(type) : 0, deposePar: magasin.utilisateur, shaAnnonce: prep.sha256, tailleMax: tailleMax());
      if (r.sha256 != prep.sha256) return (refus: _refus('EMPREINTE_DIVERGENTE', 'le poste a rangé un fichier d’une autre empreinte', 'Déposer de nouveau le fichier.'), depot: null, autre: null);
      final depot = <String, Object?>{
        'sha256': r.sha256,
        'ext': r.ext,
        'mime': r.mime,
        'taille': r.taille,
        'pages': idx.pages,
        'texteIndexe': idx.texteIndexe,
        'mots': idx.mots,
        'motsTronques': idx.motsTronques,
      };
      _noter(depot);
      return (refus: null, depot: depot, autre: prep.autre);
    } on ErreurFichier catch (e) {
      return (refus: ResultatFichier.refus(e.refus), depot: null, autre: null);
    }
  }

  /// LE GESTE DE DÉPÔT, le même pour les deux familles. Droits, format lu sur les octets, taille, doublon, rangement, journal : dans cet ordre. [remplacer] : la pièce déjà
  /// rattachée est RETIRÉE de la fiche (jamais supprimée) quand la nouvelle est rangée. [confirmerAutre] : l'agent confirme un fichier déjà rattaché à une AUTRE fiche.
  Future<ResultatFichier> deposer(
      {required String famille,
      required Object ficheId,
      required String nom,
      String mime = '',
      required Uint8List octets,
      required String role,
      required Droit droit,
      bool Function(FicheDoc)? portee,
      Future<bool> Function(FicheDoc autre)? confirmerAutre,
      bool remplacer = false}) async {
    final col = magasin.collection(fichiersCollectionDe(famille));
    final fiche = col.parId(ficheId);
    if (fiche == null) return _refus('FICHE_INTROUVABLE', 'la fiche n’existe pas', 'Rouvrir la fiche depuis le registre.');
    final type = famille == 'patient' ? '${fiche['type']}' : null;
    final refusDroit = fichierRefusDroit(role: role, famille: famille, geste: 'editer', type: type, droitEcran: droit);
    if (refusDroit != null) return ResultatFichier.refus(refusDroit);
    if (fiche['statut'] == 'archive') return _refus('FICHE_ARCHIVEE', 'la fiche est archivée', 'Restaurer la fiche avant d’y déposer une pièce.');
    final r = await _ranger(famille: famille, nom: nom, mime: mime, octets: octets, type: type, fiches: col.toutes, ficheCourante: fiche, portee: portee, confirmerAutre: confirmerAutre);
    if (r.refus != null) return r.refus!;
    final depot = r.depot!;
    VoidCallback? undoRetrait;
    if (remplacer) {
      final ret = retirer(famille: famille, ficheId: ficheId, motif: 'Remplacée par un autre fichier', role: role, droit: droit);
      if (!ret.ok) return ret;
      undoRetrait = ret.annuler;
    }
    final courante = col.parId(ficheId)!;
    final f = fichierConstruire(
        famille: famille, fiche: courante, depot: depot, nomOrigine: nom, deposePar: magasin.utilisateur, deposeLe: magasin.horloge().toIso8601String());
    final VoidCallback undo;
    try {
      undo = col.mettreAJour(ficheId, {'fichier': f}, journaliser: false);
    } on EcritureRefusee catch (e) {
      undoRetrait?.call();
      return _refus('ECRITURE_REFUSEE', e.motif, 'Vérifier les droits sur cet écran.');
    }
    magasin.journaliser('Dépôt d’un fichier numérisé', _module(famille), _entite(famille), '${courante['reference'] ?? courante['id']}', {'fichier': null},
        {'empreinte': docAbrege('${depot['sha256']}'), 'nom': f['nomNormalise'], 'taille': depot['taille']});
    _enfiler('${depot['sha256']}', famille, type, role);
    notifyListeners();
    return ResultatFichier.ok(fichier: f, avertissementDoublon: r.autre, annuler: () {
      undo();
      // L'ANNULATION DOIT SE PROPAGER : retirer la clé ne se propage pas (la fusion par champ ne sait pas dire « retiré »), on pose `fichier: null` comme la maquette.
      col.mettreAJour(ficheId, {'fichier': null}, journaliser: false);
      undoRetrait?.call();
      notifyListeners();
    });
  }

  /// LA CRÉATION D'UN DOCUMENT DU PATIENT AVEC SON FICHIER (`deposer()` de `m1-documents`) : le fichier est contrôlé et rangé D'ABORD, la fiche n'est créée que s'il l'est (un refus ne
  /// laisse aucune fiche vide). [fiche] porte référence, dossier, type, date, état, déposé par. Rend la fiche créée dans `fichier`… et de quoi ARCHIVER la création (RG-14).
  Future<ResultatFichier> creerDocumentPatient(
      {required FicheDoc fiche, required String nom, String mime = '', required Uint8List octets, required String role, required Droit droit, Future<bool> Function(FicheDoc autre)? confirmerAutre}) async {
    final col = magasin.collection('documentsPatient');
    final type = '${fiche['type']}';
    final refusDroit = fichierRefusDroit(role: role, famille: 'patient', geste: 'editer', type: type, droitEcran: droit);
    if (refusDroit != null) return ResultatFichier.refus(refusDroit);
    final r = await _ranger(
        famille: 'patient',
        nom: nom,
        mime: mime,
        octets: octets,
        type: type,
        fiches: col.toutes,
        portee: (f) => f['patientId'] == fiche['patientId'],
        confirmerAutre: confirmerAutre);
    if (r.refus != null) return r.refus!;
    final depot = r.depot!;
    final f = fichierConstruire(famille: 'patient', fiche: fiche, depot: depot, nomOrigine: nom, deposePar: magasin.utilisateur, deposeLe: magasin.horloge().toIso8601String());
    final ({FicheDoc fiche, VoidCallback annuler}) ins;
    try {
      ins = col.inserer({'statut': 'actif', ...fiche, 'fichier': f}, prefixe: 'DOC');
    } on EcritureRefusee catch (e) {
      return _refus('ECRITURE_REFUSEE', e.motif, 'Vérifier les droits sur cet écran.');
    }
    magasin.journaliser('Création d’un document numérisé', 'M1', 'document', '${fiche['reference']}', null,
        {'reference': fiche['reference'], 'type': type, 'empreinte': docAbrege('${depot['sha256']}'), 'nom': f['nomNormalise']});
    _enfiler('${depot['sha256']}', 'patient', type, role);
    notifyListeners();
    return ResultatFichier.ok(fichier: f, avertissementDoublon: r.autre, annuler: () {
      ins.annuler();
      notifyListeners();
    });
  }

  // --- la file d'envoi vers la mère (collection LOCALE `transfertsFichiers`, jamais synchronisée) ----------------------------------------------

  /// Une ligne par (empreinte, famille, zone) : ce qu'il reste à envoyer à la mère, avec le RÔLE de l'agent qui a déposé (le droit et la zone se vérifient à la mère sous ce rôle).
  /// Écrite au dépôt même, sur un poste autonome aussi : le jour où le poste rejoint une mère, ses fichiers partent.
  void _enfiler(String sha, String famille, String? type, String role) {
    final zone = famille == 'patient' ? docZoneDe(type) : 0;
    final id = 'ENV-${sha.substring(0, 16)}-$famille-$zone';
    final col = magasin.collection(fichiersFileEnvoi);
    if (col.parId(id) != null) return;
    col.inserer({'id': id, 'sha256': sha, 'sens': 'envoi', 'famille': famille, 'type': type, 'zone': zone, 'role': role, 'etat': 'attente', 'essais': 0}, prefixe: 'ENV');
  }

  // --- retrait (RG-14) ----------------------------------------------------------------------------------------------------------------------

  /// RETIRE la pièce de la fiche : jamais une suppression. Le fichier reste sur le disque, l'empreinte reste au journal et à l'historique de la fiche (`fichiersRetires`). Le droit
  /// est celui d'ANNULER l'écran. Annulable.
  ResultatFichier retirer({required String famille, required Object ficheId, required String motif, required String role, required Droit droit}) {
    final col = magasin.collection(fichiersCollectionDe(famille));
    final fiche = col.parId(ficheId);
    if (fiche == null) return _refus('FICHE_INTROUVABLE', 'la fiche n’existe pas', 'Rouvrir la fiche depuis le registre.');
    final type = famille == 'patient' ? '${fiche['type']}' : null;
    final refusDroit = fichierRefusDroit(role: role, famille: famille, geste: 'annuler', type: type, droitEcran: droit);
    if (refusDroit != null) {
      return ResultatFichier.refus(RefusFichier(refusDroit.code, refusDroit.motif.replaceFirst('déposer', 'retirer une pièce'), refusDroit.geste));
    }
    final x = fichierDe(fiche);
    final r = fichierRetirer(fiche: fiche, motif: motif, retirePar: magasin.utilisateur, retireLe: magasin.horloge().toIso8601String());
    if (r == null || x == null) return _refus('SANS_PIECE', 'cette fiche ne porte aucun fichier', 'Déposer d’abord le scan.');
    final VoidCallback undo;
    try {
      undo = col.mettreAJour(ficheId, r.patch, journaliser: false);
    } on EcritureRefusee catch (e) {
      return _refus('ECRITURE_REFUSEE', e.motif, 'Vérifier les droits sur cet écran.');
    }
    final m = motif.length > 60 ? motif.substring(0, 60) : motif;
    magasin.journaliser('Pièce numérisée retirée de la fiche', _module(famille), _entite(famille), '${fiche['reference'] ?? fiche['id']}',
        {'empreinte': docAbrege(x['sha256']), 'nom': x['nomNormalise']}, {'fichier': null, 'motif': m});
    notifyListeners();
    return ResultatFichier.ok(annuler: () {
      // L'ANNULATION remet la pièce ET l'historique d'avant : une clé ajoutée par le retrait ne se retire pas d'elle-même.
      undo();
      col.mettreAJour(ficheId, {'fichier': r.annulation['fichier'], 'fichiersRetires': r.annulation['fichiersRetires']}, journaliser: false);
      notifyListeners();
    });
  }

  // --- lecture, téléchargement ----------------------------------------------------------------------------------------------------------------

  /// Lit la pièce de la fiche : droit de lire l'écran ET la zone du type (RG-13), puis le fichier avec son empreinte VÉRIFIÉE (un fichier altéré n'est jamais servi : le refus
  /// nomme l'empreinte). Absent : le refus dit que le fichier n'est pas encore arrivé sur ce poste. La lecture est journalisée (RG-12).
  Future<ResultatFichier> lire({required String famille, required FicheDoc fiche, required String role, required Droit droit, String usage = 'apercu'}) async {
    final x = fichierDe(fiche);
    if (x == null) return _refus('SANS_PIECE', 'cette fiche ne porte aucun fichier', 'Déposer d’abord le scan.');
    final type = famille == 'patient' ? '${fiche['type']}' : null;
    final refusDroit = fichierRefusDroit(role: role, famille: famille, geste: 'voir', type: type, droitEcran: droit);
    if (refusDroit != null) return ResultatFichier.refus(refusDroit);
    final sha = '${x['sha256']}';
    final Uint8List octets;
    try {
      octets = await stockage.lire(sha);
    } on ErreurFichier catch (e) {
      return ResultatFichier.refus(e.refus);
    }
    final nom = docNomNormalise(famille, fiche, fichierExtDeMime('${x['mime']}'));
    magasin.journaliser(usage == 'telechargement' ? 'Téléchargement d’un document numérisé' : 'Consultation d’un document numérisé', _module(famille), _entite(famille),
        '${fiche['reference'] ?? fiche['id']}', null, {'cible': 'empreinte ${docAbrege(sha)} (${x['nomNormalise'] ?? x['nom']})', if (famille == 'patient') 'patientId': fiche['patientId']});
    return ResultatFichier.ok(octets: octets, nom: nom, fichier: x);
  }

  /// Le chemin du fichier sur CE poste (`null` : pas encore arrivé).
  Future<String?> chemin(FicheDoc fiche) async {
    final x = fichierDe(fiche);
    if (x == null) return null;
    return stockage.cheminDe('${x['sha256']}');
  }

  /// Ce que le poste dit du fichier de la fiche (présent, en cours de transfert, non disponible hors ligne, altéré, zone refusée).
  Future<EtatFichierPoste> etat({required String famille, required FicheDoc fiche, required String role}) async {
    final x = fichierDe(fiche);
    if (x == null) return EtatFichierPoste.sansFichier;
    final type = famille == 'patient' ? '${fiche['type']}' : null;
    final zoneOk = famille != 'patient' || docPeutVoir(type, role).autorise;
    final e = await stockage.etat('${x['sha256']}');
    final bool? copie = switch (e) { EtatLocalFichier.present => true, EtatLocalFichier.altere => false, EtatLocalFichier.absent => null };
    return fichierEtatPoste(referenceParFiche: true, copieLocale: copie, mereJoignable: transfert?.mereJoignable ?? false, zoneAutorisee: zoneOk);
  }
}

/// Ce que `stockage.ranger` a rendu, sans dépendre du type de la couche de synchronisation.
class FichierRangeLocal {
  const FichierRangeLocal(this.sha256, this.ext, this.mime, this.taille);
  final String sha256;
  final String ext;
  final String mime;
  final int taille;
}
