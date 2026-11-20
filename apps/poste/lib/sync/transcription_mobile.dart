import 'dart:async';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import '../modules/m2/cs_commun.dart' show StockMagasin;

/// Une fiche telle que la base de synchronisation du poste la livre (`id`, champs, archivée ou non).
class PieceSync {
  const PieceSync(this.id, this.data, {this.archive = false});
  final String id;
  final Map<String, Object?> data;
  final bool archive;
}

/// Ce que le service lit et écrit dans la base de synchronisation du poste (fileul) : en production `MoteurFileul`, en test une mémoire.
abstract class SourcePiecesMobile {
  Future<List<PieceSync>> liste(String collection);

  /// Écrit une opération `creer` ; rend l'identifiant de la fiche.
  Future<String> creer(String collection, Map<String, Object?> champs);
}

/// Le bilan d'un passage.
class ResumeTranscription {
  const ResumeTranscription({this.transcrites = 0, this.refusees = 0});
  final int transcrites, refusees;
  bool get vide => transcrites == 0 && refusees == 0;
}

/// TRANSCRIPTION AU POSTE DES PRESCRIPTIONS DU MOBILE (E1559, E1561).
///
/// Le téléphone d'un soignant écrit une pièce `prescriptions` (émise, immuable) que la mère accepte et distribue aux postes. Ce service la LIT dans la base de
/// synchronisation du poste et la transcrit, par le moteur du domaine ([mobTranscrire], port de `PR.transcrireMobile` : le même `csPrescrire` que la fiche de
/// consultation du poste, rien n'est dupliqué), en ORDONNANCE + FACTURE DE LA CAISSE + files d'aval (pharmacie, laboratoire) dans le magasin du poste, où les
/// écrans des ordonnances, des prescriptions et de la caisse les affichent déjà.
///
/// Une pièce NON TRANSCRIPTIBLE (patient inconnu de la clinique, médicament hors catalogue, stock insuffisant, examen sans correspondance...) est REFUSÉE EN LE
/// DISANT : un compte rendu `transcriptions` (code, motif, geste) est écrit à la mère, qui le rend au SEUL téléphone émetteur, et le refus est rangé dans le
/// registre `piecesMobile` du magasin, que l'écran des ordonnances montre. Rien n'est perdu en silence ; rien n'est transcrit à moitié.
///
/// Idempotent : une pièce qui a déjà un compte rendu n'est pas reprise.
class ServiceTranscriptionMobile {
  ServiceTranscriptionMobile({required this.magasin, required this.source, DateTime Function()? maintenant}) : _maintenant = maintenant ?? DateTime.now;

  final Magasin magasin;
  final SourcePiecesMobile source;
  final DateTime Function() _maintenant;
  bool _enCours = false;

  /// Le registre des pièces reçues du mobile au poste (transcrites et refusées), lu par l'écran des ordonnances.
  static const registre = 'piecesMobile';

  Timer? _minuterie;

  /// Passe toutes les [intervalle] ; `arreter` la libère.
  void demarrer({Duration intervalle = const Duration(seconds: 5)}) {
    _minuterie?.cancel();
    _minuterie = Timer.periodic(intervalle, (_) => unawaited(traiter().then((_) {}, onError: (Object _) {/* la base de sync n'est pas prête : au prochain passage */})));
  }

  void arreter() => _minuterie?.cancel();

  /// Un passage : transcrit les prescriptions du mobile qui n'ont pas encore de compte rendu.
  Future<ResumeTranscription> traiter() async {
    if (_enCours) return const ResumeTranscription();
    _enCours = true;
    try {
      final pieces = [for (final p in await source.liste('prescriptions')) if (!p.archive) p];
      if (pieces.isEmpty) return const ResumeTranscription();
      final comptesRendus = {for (final t in await source.liste('transcriptions')) '${t.data['prescriptionId']}'};
      final aFaire = [for (final p in pieces) if (!comptesRendus.contains(p.id) && p.data['origine'] == 'mobile') p];
      if (aFaire.isEmpty) return const ResumeTranscription();
      final patients = {for (final p in await source.liste('patients')) p.id: p};
      final notes = {for (final n in await source.liste('notes')) n.id: n};
      var ok = 0, ko = 0;
      for (final p in aFaire) {
        if (await _transcrire(p, patients, notes)) {
          ok++;
        } else {
          ko++;
        }
      }
      return ResumeTranscription(transcrites: ok, refusees: ko);
    } finally {
      _enCours = false;
    }
  }

  /// Le dossier du patient vient de la synchronisation : s'il manque au magasin du poste, il y entre (RG-01 : son code n'est jamais modifié).
  void _assurerPatient(PieceSync? p) {
    if (p == null) return;
    final code = p.data['code'];
    if (code == null || '$code'.isEmpty || '$code'.startsWith('PROV-')) return;
    final col = magasin.collection('patients');
    if (col.actives.any((x) => x['code'] == code)) return;
    col.inserer({...p.data, 'statut': 'actif', 'origineSync': p.id}, prefixe: 'PAT');
  }

  Future<bool> _transcrire(PieceSync p, Map<String, PieceSync> patients, Map<String, PieceSync> notes) async {
    final piece = {...p.data, 'id': p.id};
    final patient = patients['${p.data['patientId']}'];
    final note = notes['${p.data['noteId']}'];
    _assurerPatient(patient);
    RefusMobile? refus;
    TranscriptionMobile? t;
    try {
      t = mobTranscrire(StockMagasin(magasin, _maintenant), piece, note: note?.data);
    } on RefusMobile catch (r) {
      refus = r;
    } on RefusCs catch (r) {
      refus = RefusMobile(r.code ?? 'TRANSCRIPTION_IMPOSSIBLE', r.message, 'Faire la prescription depuis un poste de la clinique');
    }
    final quand = _maintenant().toIso8601String();
    final base = <String, Object?>{
      'prescriptionId': p.id,
      'patientId': p.data['patientId'],
      'patientCode': p.data['patientCode'],
      'date': quand,
    };
    if (refus != null) {
      magasin.collection(registre).inserer({
        'pieceId': p.id,
        'etat': 'refusee',
        'code': refus.code,
        'motif': refus.motif,
        'geste': refus.geste,
        'nature': p.data['nature'],
        'patient': p.data['patient'],
        'patientCode': p.data['patientCode'],
        'prescripteur': p.data['prescripteur'],
        'fonction': p.data['fonction'],
        'date': quand,
        'statut': 'actif',
      }, prefixe: 'PMO');
      await source.creer('transcriptions', {...base, 'etat': 'refusee', 'code': refus.code, 'motif': refus.motif, 'geste': refus.geste});
      return false;
    }
    final o = t!.ordonnance;
    final facture = t.facture;
    if (!t.deja) {
      magasin.collection(registre).inserer({
        'pieceId': p.id,
        'etat': 'transcrite',
        'ordonnance': o['numero'],
        'facture': facture?['numero'],
        'nature': p.data['nature'],
        'patient': p.data['patient'],
        'patientCode': p.data['patientCode'],
        'prescripteur': p.data['prescripteur'],
        'fonction': p.data['fonction'],
        'date': quand,
        'statut': 'actif',
      }, prefixe: 'PMO');
    }
    await source.creer('transcriptions', {...base, 'etat': 'transcrite', 'ordonnance': o['numero'], 'facture': facture?['numero'], 'montant': o['montant']});
    return true;
  }
}
