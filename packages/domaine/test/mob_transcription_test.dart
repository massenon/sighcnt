// Rejoue les vecteurs de la transcription d'une prescription du mobile, engendrés EN PILOTANT la maquette (`PR.transcrireMobile`, prototype_html/
// build/vecteurs-transcription-mobile.js) : ce que la transcription écrit (ordonnance, facture, tâches, demandes) ou le refus nommé.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

class Memoire implements StockCs {
  Memoire(Map<String, List<Map<String, Object?>>> jeux, this.maintenant)
      : _d = {
          for (final e in jeux.entries) e.key: [for (final f in e.value) _copie(f)]
        };
  final Map<String, List<Map<String, Object?>>> _d;
  final Map<String, List<Map<String, Object?>>> referentiels = {};
  @override
  final DateTime maintenant;
  int _n = 0;

  List<Map<String, Object?>> _c(String c) => _d.putIfAbsent(c, () => []);
  @override
  List<Map<String, Object?>> actives(String c) => [for (final f in _c(c)) if (f['statut'] != 'archive') f];
  @override
  List<Map<String, Object?>> toutes(String c) => List.of(_c(c));
  @override
  Map<String, Object?>? parId(String c, Object? id) => _c(c).where((f) => f['id'] == id).firstOrNull;
  @override
  Map<String, Object?> inserer(String c, Map<String, Object?> f) {
    final n = {'statut': 'actif', ...f};
    n['id'] ??= 'X${c.substring(0, 2)}${_n++}';
    _c(c).insert(0, n);
    return n;
  }

  @override
  void mettreAJour(String c, Object? id, Map<String, Object?> patch) => parId(c, id)?.addAll(patch);
  @override
  void archiver(String c, Object? id) {
    final f = parId(c, id);
    if (f != null) f['statut'] = 'archive';
  }

  @override
  void defaire(String c, Object? id) => _c(c).removeWhere((f) => f['id'] == id);
  @override
  List<Map<String, Object?>> referentiel(String nom) => referentiels[nom] ?? [];

  Map<String, List<Map<String, Object?>>> instantane() => {for (final e in _d.entries) e.key: [for (final f in e.value) _copie(f)]};
}

Map<String, Object?> _copie(Map<String, Object?> f) => (jsonDecode(jsonEncode(f)) as Map).cast<String, Object?>();

const _surveilles = ['ordonnances', 'demandesAnalyses', 'factures', 'taches', 'notifications', 'prescriptions', 'demandesImagerie'];

({Map<String, List<Map<String, Object?>>> inserts, Map<String, List<({Object? id, Map<String, Object?> patch})>> modifs}) ecart(
    Map<String, List<Map<String, Object?>>> avant, Map<String, List<Map<String, Object?>>> apres) {
  final ins = <String, List<Map<String, Object?>>>{};
  final mod = <String, List<({Object? id, Map<String, Object?> patch})>>{};
  for (final n in _surveilles) {
    final a = {for (final f in avant[n] ?? []) f['id']: f};
    for (final f in apres[n] ?? <Map<String, Object?>>[]) {
      if (!a.containsKey(f['id'])) {
        ins.putIfAbsent(n, () => []).add(f);
        continue;
      }
      final b = a[f['id']]!;
      final patch = <String, Object?>{};
      for (final k in f.keys) {
        if (jsonEncode(f[k]) != jsonEncode(b[k])) patch[k] = f[k];
      }
      if (patch.isNotEmpty) mod.putIfAbsent(n, () => []).add((id: f['id'], patch: patch));
    }
  }
  return (inserts: ins, modifs: mod);
}

/// Les clés que la maquette tire du hasard, de l'horloge ou d'un compteur : identifiants, horodatages, références de série (écart E341).
const ignorer = {
  'id', 'factureId', 'ordonnanceId', 'demandeId', 'demandeImagerieId', 'consultationId', 'prescriptionId', 'creeLe', 'reference',
  'statutAvantArchivage', '_motifArchivage', 'dateHeure', 'lue',
};

Object? _neutre(Object? x) {
  if (x is String) return x.replaceAll(RegExp(r'(PRS|ADM|LAB|DOS|IME)-\d{5}'), r'$1-#');
  if (x is List) return [for (final e in x) _neutre(e)];
  if (x is Map) return {for (final e in x.entries) e.key: _neutre(e.value)};
  return x;
}

void main() {
  final v = lireVecteurs('transcription_mobile');
  final cat = (v['catalogues'] as Map).cast<String, Object?>();
  final jour = DateTime.parse('2026-10-31T12:00:00');

  Memoire memoire() {
    final m = Memoire({
      'patients': liste(cat['patients']),
      'produits': liste(cat['produits']),
      'couverturesAssurance': [],
    }, jour);
    m.referentiels['analyses'] = liste(cat['analyses']);
    return m;
  }

  test('la correspondance des examens du mobile est celle de la maquette', () {
    expect(mobCorrespondanceExamens, (cat['correspondance'] as Map).cast<String, Object?>());
    for (final e in mobExamensAnalyses) {
      expect(mobCorrespondanceExamens.containsKey(e), isTrue, reason: 'chaque examen du mobile a un code du catalogue : $e');
    }
  });

  test('une pièce écrite par le mobile (mobChampsOrdonnance, mobChampsDemandeAnalyses) est transcriptible telle quelle : ordonnance, facture au prix d\'achat, tâches', () {
    final m = memoire();
    final patient = liste(cat['patients']).first;
    final produits = liste(cat['produits']);
    final champs = mobChampsOrdonnance(
        patient: patient, patientId: '${patient['id']}', noteId: 'n1', saisie: {'med': '${produits.first['id']}', 'quantite': '2', 'poso': '1 cp × 3/j', 'duree': '5'},
        acteur: 'Dr YENI', fonction: 'medecin', maintenant: DateTime.parse('2026-10-31T10:00:00'), produits: produits);
    final r = mobTranscrire(m, {...champs, 'id': 'pm1'}, note: {'diagnostic': 'Paludisme simple'});
    expect(r.deja, isFalse);
    expect(r.ordonnance['montant'], (produits.first['prixAchat'] as num) * 2, reason: 'RG-02');
    expect(r.ordonnance['diagnostic'], 'Paludisme simple');
    expect(r.facture!['partPatient'], (produits.first['prixAchat'] as num) * 2);
    expect([for (final t in r.taches) t['type']], containsAll(['encaissement', 'dispensation']));

    final ana = mobChampsDemandeAnalyses(
        patient: patient, patientId: '${patient['id']}', noteId: 'n1', examens: const ['NFS', 'CRP'], urgence: mobUrgencesAnalyses[1], acteur: 'Dr YENI', fonction: 'medecin', maintenant: DateTime.parse('2026-10-31T10:00:00'));
    final r2 = mobTranscrire(m, {...ana, 'id': 'pm2'});
    expect(r2.demandes.length, 2);
    expect(r2.ordonnance['urgent'], isTrue);
  });

  test('la fonction authentifiée (E1600) : affectation du code et fonction de la pièce, refus nommés', () {
    expect(mobRefusAffectation('soignant', 'medecin'), isNull);
    expect(mobRefusAffectation('reception', ''), isNull);
    expect(mobRefusAffectation('', 'medecin')!.code, 'profil_requis');
    expect(mobRefusAffectation('soignant', '')!.code, 'fonction_inconnue');
    expect(mobRefusAffectation('soignant', 'chauffeur')!.motif, contains('chauffeur'));
    expect(mobRefusAffectation('reception', 'medecin')!.code, 'fonction_non_applicable');
    // La pièce : la fonction fixée par la mère prime, une valeur différente du téléphone est une falsification nommée.
    expect(mobRefusFonctionPiece(fixee: 'infirmier', declaree: ''), isNull, reason: 'non déclarée : la mère pose la sienne');
    expect(mobRefusFonctionPiece(fixee: 'infirmier', declaree: 'infirmier'), isNull);
    final faux = mobRefusFonctionPiece(fixee: 'infirmier', declaree: 'medecin')!;
    expect((faux.code, faux.motif), ('fonction_falsifiee', 'Le téléphone déclare « medecin » mais la clinique l’a appairé comme « infirmier » : la fonction est fixée à l’appairage et ne se change pas depuis le téléphone.'));
    expect(faux.geste, contains('nouveau code d’appairage'));
    expect(mobRefusFonctionPiece(fixee: null, declaree: 'medecin')!.code, 'fonction_non_fixee');
    expect(mobRefusFonctionPiece(fixee: '', declaree: '')!.geste, contains('Réappairer'));
  });

  test('ce que devient la prescription au téléphone : en attente, transcrite (numéros), refusée (code, motif, geste) ; le dernier compte rendu fait foi', () {
    expect(mobTranscriptionDe('p1', const []).etat, MobEtatTranscription.attente);
    final t = mobTranscriptionDe('p1', [
      {'prescriptionId': 'p1', 'etat': 'refusee', 'code': 'STOCK_INSUFFISANT', 'motif': 'm', 'geste': 'g', 'date': '2026-10-31T10:00'},
      {'prescriptionId': 'p1', 'etat': 'transcrite', 'ordonnance': 'ORD-1', 'facture': 'FP-1', 'montant': 1000, 'date': '2026-10-31T11:00'},
      {'prescriptionId': 'autre', 'etat': 'refusee', 'date': '2026-10-31T12:00'},
    ]);
    expect(t.etat, MobEtatTranscription.transcrite);
    expect(t.libelle, 'Transcrite par la clinique : ordonnance ORD-1, facture FP-1.');
    expect(mobTranscriptionDe('p2', [{'prescriptionId': 'p2', 'etat': 'refusee', 'code': 'X', 'motif': 'Motif.', 'geste': 'Geste'}]).libelle, 'Refusée par la clinique : Motif.');
  });

  test('la table des textes à valider (docs/architecture/TEXTES-A-VALIDER-MOBILE.md) est exactement la liste du domaine : codes, source, statut', () {
    final md = File('../../docs/architecture/TEXTES-A-VALIDER-MOBILE.md').readAsLinesSync();
    final lignes = <String, List<String>>{
      for (final l in md)
        if (RegExp(r'^\| `[^`]+` \|').hasMatch(l) && l.split('|').length >= 6) RegExp(r'^\| `([^`]+)`').firstMatch(l)!.group(1)!: l.split('|').map((c) => c.trim()).toList()
    };
    final codesTables = {for (final c in lignes.keys) c}..removeWhere((c) => c.startsWith('E1'));
    expect(codesTables, {for (final t in mobTextes) t.code}, reason: 'chaque code du domaine est listé, et rien de plus');
    for (final t in mobTextes) {
      final c = lignes[t.code]!;
      expect(c[4] == 'aucune source', t.source == null, reason: '${t.code} : source');
      expect(c[5] == 'à valider', t.aValider, reason: '${t.code} : statut');
      if (t.source == null) expect(t.aValider, isTrue, reason: '${t.code} : sans source, donc à valider (jamais inventé en silence)');
    }
    // Les refus du téléphone dont le texte n'a pas de source portent la mention à l'écran.
    for (final code in ['PATIENT_HORS_LOT', 'NATURE_NON_PORTEE', 'EXAMEN_INCONNU', 'PRODUIT_INCONNU', 'SANS_NOTE', 'patient_hors_lot', 'fonction_falsifiee']) {
      expect(mobRefusAValider(code), isTrue, reason: code);
    }
    for (final code in ['ECRAN_FERME_AU_PROFIL', 'LOT_EXPIRE', 'STOCK_INSUFFISANT', 'FONCTION_NON_HABILITEE', 'SAISIE_INVALIDE']) {
      expect(mobRefusAValider(code), isFalse, reason: code);
    }
  });

  group('PR.transcrireMobile (piloté dans Chrome)', () {
    for (final c in liste(v['cas'])) {
      test('${c['nom']}', () {
        final m = memoire();
        final params = (c['params'] as Map).cast<String, Object?>();
        final piece = (params['piece'] as Map).cast<String, Object?>();
        final note = params['note'] == null ? null : (params['note'] as Map).cast<String, Object?>();
        if (c['preparation'] != null) mobTranscrire(m, piece, note: note);
        final avant = m.instantane();
        final s = (c['sortie'] as Map).cast<String, Object?>();
        if (s['erreur'] != null) {
          try {
            mobTranscrire(m, piece, note: note);
            fail('un refus était attendu : ${s['code']}');
          } on RefusMobile catch (r) {
            expect(r.code, s['code']);
            expect(r.motif, s['erreur'], reason: 'le motif est celui de la maquette');
            expect(r.geste, s['geste']);
          }
          final e = ecart(avant, m.instantane());
          expect(e.inserts, isEmpty, reason: 'un refus ne laisse rien derrière lui');
          expect(e.modifs, isEmpty);
          return;
        }
        final r = mobTranscrire(m, piece, note: note);
        final retour = (s['retour'] as Map).cast<String, Object?>();
        expect(r.deja, retour['deja']);
        expect(r.ordonnance['numero'], retour['ordonnanceNumero']);
        expect(r.facture?['numero'], retour['factureNumero']);
        expect([for (final t in r.taches) t['type']], retour['taches']);
        expect(r.demandes.length, retour['demandes']);
        final e = ecart(avant, m.instantane());
        final attIns = (s['inserts'] as Map).cast<String, Object?>();
        expect(e.inserts.keys.toSet(), attIns.keys.toSet(), reason: 'collections écrites');
        for (final k in attIns.keys) {
          memes(_neutre(e.inserts[k]), _neutre(attIns[k]), k, ignorer: ignorer);
        }
        expect(e.modifs.keys.toSet(), (s['modifs'] as Map).keys.toSet(), reason: 'collections modifiées');
      });
    }
  });
}
