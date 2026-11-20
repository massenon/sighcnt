// LOT 8B, groupe GARANTIES ET COUVERTURES : le geste d'ÉCRIRE et d'ANNULER, rejoué sur les vecteurs tirés de l'écran réel de la maquette (`prototype_html/build/vecteurs-import.js`, section
// `assurances`). Une version datée ne réécrit jamais une pièce émise : une garantie ne s'annule plus sous une facture émise ou sous une version plus récente de sa série ; une couverture
// de même (la précédente reprend sa fin, le dossier retrouve son état). Les fichiers `ga-*` et `cv-*` sont analysés par `import_test.dart`.
import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';
import 'import_test.dart' show MagasinMemoire;

void main() {
  final V = lireVecteurs('import');
  final A = (V['assurances'] as Map).cast<String, Object?>();
  final initial = (V['magasin'] as Map).cast<String, Object?>();

  List<List<Object?>> lignesDe(String id) {
    final c = liste(V['cas']).firstWhere((x) => x['id'] == id);
    return [
      for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
    ];
  }

  JeuImport jeuDe(String id) => id.startsWith('ga-') ? jeuGaranties : jeuCouverturesAssurance;
  AnalyseImport analyser(MagasinMemoire port, String id) => analyserLignes(jeuDe(id), lignesDe(id), '$id.xlsx', port);
  FicheImport poser(MagasinMemoire port, String id) {
    final r = appliquer(jeuDe(id), analyser(port, id), port);
    expect(r.ok, isTrue, reason: '$id : ${r.motif}');
    return r.lot!;
  }

  Map<String, Object?> resume(AnalyseImport a) => {
        'accepte': a.accepte,
        'compte': a.compte.versJson(),
        'problemes': [
          for (final p in a.problemes) {'n': p.n, 'colonne': p.colonne, 'code': p.code, 'niveau': p.niveau}
        ],
        'details': [
          for (final l in a.lignes) [l.n, l.etat, l.detail ?? '']
        ],
      };
  Map<String, Object?> refusDe(ResultatImport r) => {'ok': r.ok, 'code': r.code, 'motif': r.motif, 'geste': r.geste};

  /// Les références de lot se disent {A}, {B}… (dans l'ordre où le test les pose) ; les identifiants tirés au hasard par la maquette se disent par ce que la fiche porte.
  Object? mask(Object? o, List<String> refs) {
    var t = jsonEncode(o);
    for (var i = 0; i < refs.length; i++) {
      t = t.replaceAll(refs[i], '{${'ABCD'[i]}}');
    }
    return jsonDecode(t);
  }

  List<Map<String, Object?>> fiches(MagasinMemoire port, FicheImport lot) => [
        for (final e in (lot['ecrits'] as List).cast<Map>())
          () {
            final f = {...port.parId('${e['collection']}', e['id'])!};
            for (final k in ['_creePar', '_creeLe', '_modifiePar', '_modifieLe', 'statutAvantArchivage', '_archivePar', '_archiveLe', '_motifArchivage']) {
              f.remove(k);
            }
            if ('${e['collection']}' == 'couverturesAssurance' && '${f['id']}' != 'COU1') f['id'] = 'COU:${f['patientId']}@${f['debut'] ?? 'reprise'}';
            if ('${e['collection']}' == 'garanties') f['id'] = 'GAR:${f['souscripteurId']}@${f['libelle']}@${f['dateEffet'] ?? 'origine'}';
            return {'collection': e['collection'], 'avant': e['avant'], 'fiche': f};
          }()
      ];

  group('garanties : une version datée ne réécrit jamais une pièce émise', () {
    test('la vérification dit l\'ancien, le nouveau, la variation et la décision ; la pose écrit des versions (version 2 d\'une série, version 1 d\'une autre) ; le rejeu est « inchangé »', () {
      final port = MagasinMemoire(initial);
      final G = (A['garanties'] as Map).cast<String, Object?>();
      memes(resume(analyser(port, 'ga-valide')), G['analyse'], 'analyse');
      final refs = <String>[];
      final lot = poser(port, 'ga-valide');
      refs.add('${lot['reference']}');
      final pose = (G['pose'] as Map).cast<String, Object?>();
      expect(lot['etat'], pose['etat']);
      expect(lot['nbLignes'], pose['nbLignes']);
      memes(mask(fiches(port, lot), refs), pose['fiches'], 'fiches');
      // La version remplacée RESTE écrite (une pièce émise garde son taux) : deux lignes pour la série, la première sans date.
      expect(port.toutes('garanties').where((g) => g['libelle'] == 'Consultation généraliste').length, 2);
      memes(resume(analyser(port, 'ga-valide')), G['rejeu'], 'rejeu');
    });

    test('annulation REFUSÉE sous une facture émise (GARANTIE_UTILISEE), puis sous une version plus récente (VERSION_POSTERIEURE) ; ensuite les deux s\'annulent, la dernière d\'abord, par archivage (RG-14)', () {
      final port = MagasinMemoire(initial);
      final G = (A['garanties'] as Map).cast<String, Object?>();
      final g1 = poser(port, 'ga-valide');
      final fac = port.inserer('factures', {'numero': 'F-2027-0002', 'patientId': 'PAT0003', 'assureur': 'AFR', 'date': '2027-02-01', 'statut': 'emise'});
      memes(refusDe(annulerLot(jeuImportParId, g1['id'], 'essai', port)), G['annulationFactureEmise'], 'annulationFactureEmise');
      expect(port.parId(collectionLots, g1['id'])!['etat'], 'applique', reason: 'rien ne bouge');
      port.archiver('factures', fac['id'], 'essai');
      final g3 = poser(port, 'ga-suivante');
      memes(refusDe(annulerLot(jeuImportParId, g1['id'], 'essai', port)), G['annulationVersionPosterieure'], 'annulationVersionPosterieure');
      final r3 = annulerLot(jeuImportParId, g3['id'], 'essai', port), r1 = annulerLot(jeuImportParId, g1['id'], 'essai', port);
      final ann = (G['annulations'] as Map).cast<String, Object?>();
      expect({'ok': r3.ok, 'archives': r3.archives}, ann['suivante']);
      expect({'ok': r1.ok, 'archives': r1.archives}, ann['premiere']);
      expect([for (final e in (g1['ecrits'] as List).cast<Map>()) port.parId('${e['collection']}', e['id'])!['statut']], ann['statuts']);
    });
  });

  group('couvertures : la précédente reprend sa fin, le dossier retrouve son état', () {
    test('la pose : couverture neuve (trace du lot), précédente close la veille, couverture du dossier REPRISE au premier changement, fiche du dossier au pas (souscripteur compris)', () {
      final port = MagasinMemoire(initial);
      final C = (A['couvertures'] as Map).cast<String, Object?>();
      memes(resume(analyser(port, 'cv-valide')), C['analyse'], 'analyse');
      final refs = <String>[];
      final lot = poser(port, 'cv-valide');
      refs.add('${lot['reference']}');
      final pose = (C['pose'] as Map).cast<String, Object?>();
      expect(lot['etat'], pose['etat']);
      memes(mask(fiches(port, lot), refs), pose['fiches'], 'fiches');
      Map<String, Object?> etatPatient(String id) {
        final p = port.parId('patients', id)!;
        return {'id': id, for (final k in ['assureur', 'numeroPolice', 'tauxPriseEnCharge', 'carteExpiration', 'souscripteurId']) k: p[k]};
      }

      final att = {for (final p in liste(pose['patients'])) p['id'] as String: p};
      for (final id in ['PAT0003', 'PAT0004']) {
        memes(etatPatient(id), att[id], 'patient $id');
      }
      // RG-09 : la couverture du dossier ne bascule pas avant la date d'effet (2030) : la fiche suit la couverture en force AUJOURD'HUI.
      expect(port.parId('patients', 'PAT0003')!['assureur'], 'AFR');
    });

    test('annulation REFUSÉE sous une facture émise après le lot (FACTURE_SOUS_COUVERTURE), puis sous une couverture plus récente (COUVERTURE_POSTERIEURE) ; ensuite tout se restitue : fins reprises, dossier retrouvé', () {
      final port = MagasinMemoire(initial);
      final C = (A['couvertures'] as Map).cast<String, Object?>();
      final avant = {for (final id in ['PAT0003', 'PAT0004']) id: {...port.parId('patients', id)!}};
      final c1 = poser(port, 'cv-valide');
      final fac = port.inserer('factures', {'numero': 'F-2030-0003', 'patientId': 'PAT0003', 'assureur': 'NSIA', 'date': '2030-02-01', 'statut': 'emise'});
      memes(refusDe(annulerLot(jeuImportParId, c1['id'], 'essai', port)), C['annulationFactureEmise'], 'annulationFactureEmise');
      port.archiver('factures', fac['id'], 'essai');
      final c3 = poser(port, 'cv-suivante');
      memes(refusDe(annulerLot(jeuImportParId, c1['id'], 'essai', port)), C['annulationPosterieure'], 'annulationPosterieure');
      final r3 = annulerLot(jeuImportParId, c3['id'], 'essai', port), r1 = annulerLot(jeuImportParId, c1['id'], 'essai', port);
      final ann = (C['annulations'] as Map).cast<String, Object?>();
      expect({'ok': r3.ok, 'archives': r3.archives}, ann['suivante']);
      expect({'ok': r1.ok, 'archives': r1.archives}, ann['premiere']);
      expect(port.parId('couverturesAssurance', 'COU1')!['fin'], isNull, reason: 'la couverture précédente reprend sa fin');
      for (final id in ['PAT0003', 'PAT0004']) {
        for (final k in ['assureur', 'numeroPolice', 'tauxPriseEnCharge', 'carteExpiration', 'souscripteurId']) {
          expect(port.parId('patients', id)![k], avant[id]![k], reason: '$id.$k retrouvé');
        }
      }
      memes(
          [for (final c in port.toutes('couverturesAssurance')) {'patientId': c['patientId'], 'debut': c['debut'], 'fin': c['fin'], 'statut': c['statut'], 'assureur': c['assureur']}]
            ..sort((a, b) => '${a['patientId']}${a['debut']}${a['statut']}'.compareTo('${b['patientId']}${b['debut']}${b['statut']}')),
          ((C['apresAnnulation'] as Map)['couvertures'] as List).cast<Map>(),
          'couvertures après annulation');
    });
  });
}
