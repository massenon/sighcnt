// Rejoue les vecteurs M1 (prototype_html/build/vecteurs-m1.js) : écrans RÉELS pilotés dans Chrome.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

String nn(Object? x) => '$x'.replaceAll(RegExp('[\u00A0\u202F]'), ' ');

void main() {
  final maintenant = DateTime(2026, 10, 30, 12);

  group('RG-01 — prochain code patient', () {
    final doc = lireVecteurs('pat_patients');
    for (final c in liste((doc['prochainCode'] as Map)['cas'])) {
      test('${c['nom']}', () {
        final patients = [
          for (final x in (c['codes'] as List))
            {'code': (x as List)[0], 'statut': x[1]}
        ];
        expect(patProchainCode(patients, maintenant), c['attendu']);
      });
    }
    test('un code déjà pris est refusé en le nommant', () {
      expect(patRefusCode([{'code': 'CNT/5/26'}], 'CNT/5/26'), contains('déjà attribué'));
      expect(patRefusCode([{'code': 'CNT/5/26'}], 'CNT/6/26'), isNull);
    });
  });

  group('création : ce que le dossier déduit de la saisie', () {
    final doc = lireVecteurs('pat_patients');
    for (final c in liste((doc['creation'] as Map)['cas'])) {
      final crees = liste(c['crees']);
      if (crees.isEmpty) continue;
      test('${c['nom']}', () {
        final saisie = {...(c['saisie'] as Map).cast<String, Object?>()};
        final v = patTransformerPatient(saisie, null, maintenant);
        final attendu = crees.first;
        for (final k in ['assureurNom', 'dateNaissance', 'age', 'ageReferenceLe']) {
          final a = attendu[k];
          final o = v[k];
          if (a == null || a == '') {
            expect(o == null || o == '', isTrue, reason: k);
          } else {
            expect('$o', '$a', reason: k);
          }
        }
        expect(v.containsKey('naissanceConnue'), isFalse);
      });
    }
    test('l\'âge déjà déclaré ne se re-date pas', () {
      final v = patTransformerPatient({'naissanceConnue': 'age', 'age': '41'},
          {'age': 41, 'ageReferenceLe': '2020-01-01'}, maintenant);
      expect(v['ageReferenceLe'], '2020-01-01');
    });
  });

  group('répertoire', () {
    final r = (lireVecteurs('pat_patients')['repertoire'] as Map).cast<String, Object?>();
    final jeu = liste(r['jeu']);
    final actifs = jeu.where((p) => p['statut'] != 'archive').toList();
    test('indicateurs', () {
      final k = patKpisRepertoire(actifs, const [], maintenant);
      final v = (r['kpis'] as List).map((e) => (e as List)[1]).toList();
      expect([k.actifs, k.crees2026, k.assures, k.expirees].map((e) => '$e').toList(), v);
      expect(nn('${k.partAssures} du répertoire'), ((r['kpis'] as List)[2] as List)[2]);
    });
    test('filtres de couverture', () {
      for (final f in liste(r['filtres'])) {
        if (f['filtre'] != 'Couverture') continue;
        final cle = {'Assurés': 'assure', 'Non assurés': 'non', 'Carte expirée': 'expiree'}[f['valeur']]!;
        final codes = [
          for (final p in actifs)
            if (patFiltreCouverture(p, cle, const [], maintenant)) p['code']
        ]..sort();
        expect(codes, (f['codes'] as List).cast<String>().toList()..sort(), reason: '${f['valeur']}');
      }
    });
    test('âge déclaré vieilli', () {
      final p = actifs.firstWhere((x) => x['code'] == 'CNT/8/26');
      expect(patAge(p, maintenant), 36);
    });
  });

  group('antécédents & allergies', () {
    final d = lireVecteurs('pat_antecedents');
    final actifs = liste(d['jeu']).where((p) => p['statut'] != 'archive').toList();
    test('indicateurs', () {
      final k = patKpisAntecedents(actifs);
      expect([k.renseignes, k.allergies, k.risque, k.sansAntecedent].map((e) => '$e').toList(),
          (d['kpis'] as List).map((e) => (e as List)[1]).toList());
    });
    test('filtres : la valeur se cherche DANS la liste (E305)', () {
      for (final f in liste(d['filtres'])) {
        final allergie = f['filtre'] == 'Allergie';
        final codes = [
          for (final p in actifs)
            if (allergie
                ? patFiltreAllergie(p, '${f['valeur']}')
                : patFiltreAntecedent(p, '${f['valeur']}'))
              p['code']
        ];
        expect(codes, f['codes'], reason: '${f['filtre']} ${f['valeur']}');
      }
    });
    test('risque par ligne', () {
      final l = List.generate((d['lignes'] as List).length, (_) => <String, Object?>{});
      for (final (i, p) in actifs.indexed) {
        expect(patRisque(p) ? 'Élevé' : 'Standard', (l[i].isEmpty ? '' : '') + ((d['lignes'] as List)[i] as List)[6]);
      }
    });
  });

  group('constantes', () {
    final d = lireVecteurs('pat_constantes');
    final jeu = liste(d['jeu']);
    test('bornes : le contrôle de chaque ligne (multiensemble)', () {
      final actifs = jeu.where((r) => r['statut'] != 'archive').toList();
      final attendu = [for (final l in d['lignes'] as List) (l as List)[8] as String]..sort();
      final obtenu = [
        for (final r in actifs)
          patAnormale(r).isEmpty ? 'normales' : 'hors bornes : ${patAnormale(r).join(', ')}'
      ]..sort();
      expect(obtenu, attendu);
    });
    test('indicateurs', () {
      final k = patKpisConstantes(jeu.where((r) => r['statut'] != 'archive').toList(), maintenant);
      expect([k.releves, k.aujourdhui, k.patients, k.horsBornes].map((e) => '$e').toList(),
          (d['kpis'] as List).map((e) => (e as List)[1]).toList());
    });
    for (final c in liste(d['creations'])) {
      final crees = liste(c['crees']);
      if (crees.isEmpty) continue;
      test('${c['nom']}', () {
        final pats = [
          for (final n in [1, 2, 3]) {'id': 'K$n', 'code': 'CNT/$n/26', 'nom': 'Nom$n', 'prenom': 'Pre$n'}
        ];
        final v = patValeursReleve({'patientCode': 'CNT/1/26', ...(c['saisie'] as Map).cast<String, Object?>()}, pats);
        for (final k in ['patientId', 'patient', 'tension', 'imc']) {
          expect(v[k], crees.first[k], reason: k);
        }
      });
    }
    test('la correction recalcule (E303)', () {
      final m = (d['modification'] as Map).cast<String, Object?>();
      final avant = (m['avant'] as Map).cast<String, Object?>();
      final patch = (m['patch'] as Map).cast<String, Object?>();
      final v = patValeursReleve({...avant, 'poids': 80, 'tensionSys': 15, 'tensionDia': 9}, [
        {'id': 'K1', 'code': 'CNT/1/26', 'nom': 'Nom1', 'prenom': 'Pre1'}
      ]);
      expect(v['tension'], patch['tension']);
      expect(v['imc'], patch['imc']);
    });
    test('référence suivante : archivés compris', () {
      expect(patReferenceSuivante('CST-', 5, ['CST-00012', 'CST-00003', 'X']), 'CST-00013');
    });
  });

  group('références', () {
    final d = lireVecteurs('pat_reference');
    final refs = liste(d['jeuRefs']);
    final crfs = liste(d['jeuContre']);
    test('indicateurs et vues', () {
      final actives = refs.where((r) => r['statut'] != 'archive').toList();
      final k = patKpisReference(actives, crfs);
      final v = ((d['reference'] as Map)['kpis'] as List).map((e) => (e as List)[1]).toList();
      expect([k.fiches, k.sortantes, k.entrantes, k.sansRetour].map((e) => '$e').toList(), v);
      expect([for (final r in patSansContreReference(actives, crfs)) r['numero']],
          ((d['reference'] as Map)['parOnglet'] as Map)['Contre-référence attendue']);
    });
    test('création : numéro, âge, sexe, adresse', () {
      final pats = [
        {'id': 'K2', 'code': 'CNT/2/26', 'nom': 'Nom2', 'prenom': 'Pre2', 'sexe': 'M', 'dateNaissance': '1990-01-01', 'quartier': 'Perma'}
      ];
      final c = liste((d['reference'] as Map)['creations']).first;
      final v = patDeduitReference((c['saisie'] as Map).cast<String, Object?>(), pats, refs, maintenant);
      final a = liste(c['crees']).first;
      for (final k in ['numero', 'patientId', 'patient', 'age', 'sexe', 'adresse']) {
        expect(v[k], a[k], reason: k);
      }
    });
    test('contre-référence : le patient vient de la fiche', () {
      final c = liste((d['contre'] as Map)['creations']).first;
      final v = patDeduitContreReference((c['saisie'] as Map).cast<String, Object?>(), refs, crfs);
      final a = liste(c['crees']).first;
      for (final k in ['reference', 'patientId', 'patient', 'patientCode']) {
        expect(v[k], a[k], reason: k);
      }
    });
    test('pourcentages (E306)', () {
      final k = patKpisContreReference([
        {'concordance': true, 'justifiee': true},
        {'concordance': false, 'justifiee': false, 'evolution': 'Décédé(e)'}
      ]);
      expect([k.recues, k.concordantes, k.justifiees, k.deces], [2, 1, 1, 1]);
      expect(nn(k.partConcordance), '50.0 % des retours');
    });
  });

  group('certificats', () {
    final d = lireVecteurs('pat_pieces');
    final posees = liste(d['jeu']);
    test('statut de règlement lu sur la pièce de caisse', () {
      final factures = [
        {'id': 'F1', 'lignes': [{'statutPaiement': 'paye'}], 'numero': 'FC-2026-00001', 'reliquat': 0, 'partPatient': 5000},
        {'id': 'F2', 'lignes': [{'statutPaiement': 'du'}], 'numero': 'FC-2026-00002', 'reliquat': 7000, 'partPatient': 7000},
      ];
      for (final s in liste(d['statuts'])) {
        final p = posees.firstWhere((x) => x['numero'] == s['numero']);
        final st = patStatutPiece(p, factures);
        expect([st.code, st.label, st.ton, st.detail], [s['code'], s['label'], s['ton'], s['detail']]);
      }
    });
    test('indicateurs', () {
      final pats = [
        {'id': 'K1', 'code': 'CNT/1/26'},
        {'id': 'K4', 'code': 'CNT/4/26', 'externe': true}
      ];
      final factures = [
        {'id': 'F1', 'lignes': [{'statutPaiement': 'paye'}]},
        {'id': 'F2', 'lignes': [{'statutPaiement': 'du'}], 'numero': 'x', 'reliquat': 7000},
      ];
      final actives = posees.where((p) => p['statut'] != 'archive').toList();
      final k = patKpisPieces(actives, pats, factures, 2026);
      final v = (d['registre'] as Map)['kpis'] as List;
      expect([k.delivrees, k.exercice].map((e) => '$e').toList(), [(v[0] as List)[1], (v[1] as List)[1]]);
      expect('${k.externes}', ((v[0] as List)[2] as String).split('·')[1].trim().split(' ')[0]);
      expect(nn(money(k.encaisse)), (v[2] as List)[1]);
      expect(nn(money(k.aEncaisser)), (v[3] as List)[1]);
      expect(k.sansPiece, 3);
    });
    final types = {for (final t in patTypesPiece) t.id: t};
    var n = 0;
    for (final c in liste(d['delivrances'])) {
      final pieces = liste(c['pieces']);
      if (pieces.isEmpty) continue;
      final nom = '${c['nom']}';
      final idx = n;
      test(nom, () {
        final saisie = (c['saisie'] as Map).cast<String, Object?>();
        final t = types[saisie['typeId']]!;
        final p = pieces.first;
        // la série : les pièces posées + celles des délivrances précédentes
        final avant = [
          ...posees,
          for (final prec in liste(d['delivrances']).take(idx)) ...liste(prec['pieces'])
        ];
        final nu = patNumeroter(t, avant, 2026);
        expect(nu.numero, p['numero']);
        expect(nu.reference, p['reference']);
        expect(patCouverturePiece(null), isNotEmpty);
        final f = liste(c['factures']);
        if (f.isNotEmpty) {
          final pat = {
            'id': p['patientId'],
            'code': p['patientCode'],
            'nom': '${p['patient']}'.split(' ').first,
            'prenom': '${p['patient']}'.split(' ').last,
            if (p['patientCode'] == 'CNT/2/26') ...{'assureur': 'SOS', 'tauxPriseEnCharge': 80, 'carteExpiration': '2027-12-31'},
            if (p['patientCode'] == 'CNT/3/26') ...{'assureur': 'NSIA', 'tauxPriseEnCharge': 80, 'carteExpiration': '2027-12-31'},
          };
          final r = patFacturerPiece(
              patient: pat,
              montant: p['montant'] as num,
              libelle: t.libelle,
              reference: nu.reference,
              acteCode: t.tarifCode,
              assurable: 'sos',
              couvertures: const [],
              nbFactures: int.parse('${f.first['numero']}'.split('-').last) - 1,
              nouvelId: (x) => '$x-1',
              date: DateTime(2026, 10, 30, 12))!;
          for (final k in ['numero', 'montantTTC', 'partAssurance', 'partPatient', 'reliquat', 'tauxPriseEnCharge', 'motifCouverture', 'type', 'pieceRef']) {
            expect(r.facture[k], f.first[k], reason: k);
          }
        } else {
          expect(p['montant'], isNull);
        }
      });
      n++;
    }
  });

  group('patient externe', () {
    final d = lireVecteurs('pat_externe');
    final catalogue = liste(d['analysesCatalogue']);
    test('états et verrous du registre', () {
      final posees = {
        'LAB-00001': {'bloqueParPaiement': true, 'etatAnalyse': 'en_attente'},
        'LAB-00002': {'etatAnalyse': 'attente_prelevement'},
        'LAB-00004': {'etatAnalyse': 'en_cours', 'recuLaboLe': 'x'},
        'LAB-00005': {'etatAnalyse': 'valide', 'recuLaboLe': 'x'},
      };
      final att = {
        'LAB-00001': 'En attente de caisse',
        'LAB-00002': 'Échantillon non parvenu',
        'LAB-00004': 'À saisir',
        'LAB-00005': 'Résultat rendu'
      };
      posees.forEach((ref, f) => expect(patEtatLigne(f).$1, att[ref], reason: ref));
      final reg = ((d['registre'] as Map)['lignes'] as List);
      for (final l in reg) {
        final ref = (l as List)[0];
        if (att.containsKey(ref)) expect(l[6], att[ref], reason: '$ref');
      }
    });
    test('verrou : examen d\'imagerie non réglé', () {
      expect(patBlocageResultat({'examenCode': 'X', 'statut': 'demandee'})!.motif, 'Examen non réglé.');
      expect(patBlocageResultat({'examenCode': 'X', 'statut': 'payee'}), isNull);
    });
    var i = 0;
    for (final c in liste(d['creations'])) {
      final dem = liste(c['demandes']);
      final nom = '${c['nom']}';
      final k = i++;
      if (dem.isEmpty) continue;
      test(nom, () {
        final saisie = {...(c['saisie'] as Map).cast<String, Object?>()};
        var seq = 0;
        final base = liste(d['creations']).take(k).fold<int>(0, (a, x) => a + liste(x['demandes']).length);
        final fact = liste(c['factures']).first;
        final r = patOuvrirDemandeExterne(
            saisie: {...saisie, 'age': saisie['age'], 'dateNaissance': null, 'taux': saisie['taux']},
            codesAnalyses: (saisie['analyses'] as List).cast<String>(),
            catalogue: catalogue.isEmpty ? const [] : [...catalogue, ...catalogueComplet],
            patients: List.generate(198 + liste(d['creations']).take(k).where((x) => liste(x['patients']).isNotEmpty).length, (j) => {'id': 'x$j'}),
            demandesExistantes: List.generate(base, (j) => {
                  'reference': 'LAB-${(j + 1).toString().padLeft(5, '0')}',
                  'codeAnalyse': '${(j + 1).toString().padLeft(5, '0')}-2026'
                }),
            nbFactures: int.parse('${fact['numero']}'.split('-').last) - 1,
            nouvelId: (p) => '$p${seq++}',
            date: DateTime(2026, 10, 30, 12));
        expect(r.patient['code'], liste(c['patients']).first['code']);
        expect(r.facture['numero'], fact['numero']);
        for (final key in ['montantTTC', 'partAssurance', 'partPatient', 'reliquat', 'assureur', 'tauxPriseEnCharge', 'type']) {
          expect(r.facture[key], fact[key], reason: key);
        }
        expect(r.demandes.map((x) => x['reference']).toList().reversed.toList(), dem.map((x) => x['reference']).toList());
        expect(r.demandes.map((x) => x['codeAnalyse']).toList().reversed.toList(), dem.map((x) => x['codeAnalyse']).toList());
        expect(r.demandes.first['urgent'], dem.reversed.first['urgent']);
        expect(r.taches.map((x) => x['statut']).toList(), ['en_attente', 'bloque']);
        expect(r.patient['origineDossier'], liste(c['patients']).first['origineDossier']);
      });
    }
    test('refus nommés', () {
      expect(() => patOuvrirDemandeExterne(saisie: {'nom': 'A', 'prenom': 'B'}, codesAnalyses: [], catalogue: [], patients: [], demandesExistantes: [], nbFactures: 0, nouvelId: (p) => p, date: maintenant),
          throwsA(isA<PatRefus>().having((e) => e.message, 'message', 'Cocher au moins un examen au catalogue.')));
      expect(() => patOuvrirDemandeExterne(saisie: {}, codesAnalyses: ['L01'], catalogue: [], patients: [], demandesExistantes: [], nbFactures: 0, nouvelId: (p) => p, date: maintenant),
          throwsA(isA<PatRefus>()));
    });
  });

  group('fiche', () {
    test('synthèse IPPOA : elle reçoit les examens (E316)', () {
      final s = patSyntheseExamen({
        'cardio_vasculaire': {'inspection': 'RAS', 'palpation': 'RAS'},
        'pleuro_pulmonaire': {'inspection': 'RAS', 'auscultation': 'Sibilants bilatéraux'},
        'orl': {}
      });
      expect(s.map((x) => x.texte).toList(), ['RAS — examen normal', 'Inspection : RAS · Auscultation : Sibilants bilatéraux']);
      expect(s.first.normal, isTrue);
    });
    test('saisie antérieure : examen global', () {
      expect(patExamensPhysiquesDe({'exam_inspection': 'x'}).keys, ['global']);
    });
    test('documents : poids', () {
      expect(patPoidsDoc(null), '—');
      expect(patPoidsDoc(500), '0 Ko');
      expect(patPoidsDoc(3 * 1024 * 1024), '3.0 Mo');
      expect(patPoidsDoc(2048), '2 Ko');
    });
  });
}

/// Le catalogue complet des analyses utilisées par les vecteurs (L01..L04).
final catalogueComplet = <Map<String, Object?>>[];
