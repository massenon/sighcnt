// Rejoue les vecteurs des demandes d'analyses (prototype_html/build/vecteurs-demandes.js) : les écrans RÉELS m5-demandes, m5-prelevement et les vues
// par service, pilotés dans Chrome — formulaire rempli, boutons cliqués, ce qui est né au magasin relu.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

num _nombreApres(String texte, String libelle) {
  final m = RegExp('${RegExp.escape(libelle)}\\s+(\\d+)').firstMatch(texte);
  if (m == null) fail('« $libelle » absent de : $texte');
  return num.parse(m.group(1)!);
}

void main() {
  final maintenant = DateTime(2026, 10, 30, 12);

  group('code d\'analyse NNNNN-AAAA (PR.codeAnalyse)', () {
    final doc = lireVecteurs('dem_code_analyse');
    final annee = doc['anneeCourante'] as int;
    for (final c in liste(doc['cas'])) {
      test('${c['nom']}', () {
        final fiches = [
          for (final x in (c['codes'] as List)) {'codeAnalyse': x}
        ];
        final date = c['date'];
        expect(
            demCodeAnalyse(date, fiches, maintenant: DateTime(annee, 10, 30)),
            c['attendu']);
      });
    }
    test('une fiche ARCHIVÉE garde son rang : le registre entier est lu', () {
      final fiches = [
        {'codeAnalyse': '00007-2026', 'statut': 'archive'}
      ];
      expect(demCodeAnalyse('2026-05-05', fiches, maintenant: maintenant),
          '00008-2026');
    });
    test('une date vide retombe sur l\'année de l\'horloge', () {
      expect(demCodeAnalyse(null, [], maintenant: DateTime(2031, 1, 1)),
          '00001-2031');
      expect(demCodeAnalyse('', [], maintenant: DateTime(2031, 1, 1)),
          '00001-2031');
    });
  });

  group('création d\'une demande (m5-demandes › Nouveau › Créer)', () {
    final doc = lireVecteurs('dem_creation');
    final rep = (doc['patientRepertoire'] as Map).cast<String, Object?>();
    final catalogue = liste(doc['catalogue']);
    for (final c in liste(doc['cas'])) {
      final e = (c['entree']! as Map).cast<String, Object?>();
      final saisie = {'urgent': false, ...(e['saisie'] as Map).cast<String, Object?>()};
      test('${e['nom']}', () {
        final refus = demRefusSaisie(saisie);
        final toasts = (c['toasts'] as List);
        final nees = liste(c['demandes']);
        if (nees.isEmpty) {
          expect(refus, (toasts.first as List).first, reason: 'le refus se nomme');
          return;
        }
        expect(refus, isNull);
        final demandes = [
          for (var i = 0; i < (e['refsExistantes'] as List).length; i++)
            {
              'reference': (e['refsExistantes'] as List)[i],
              'codeAnalyse': (e['codesAnalyse'] as List)[i]
            }
        ];
        final patient = '${saisie['patientCode'] ?? ''}' == rep['code']
            ? {...rep, 'code': rep['code']}
            : null;
        final analyse =
            catalogue.firstWhere((a) => a['code'] == saisie['analyseCode']);
        FicheDem? ne;
        final fiche = demPreparerDemande(
            saisie: saisie,
            patient: patient,
            analyse: analyse,
            demandes: demandes,
            creerPatient: (d) => ne = {...d, 'id': 'PAT-TEST', 'statut': 'actif'},
            effectifRepertoire: e['nbPatients'] as int,
            maintenant: maintenant);
        memes(fiche, nees.single, 'demande',
            ignorer: {'id', 'statut', 'patientId'});
        final nouveaux = liste(c['patients']);
        if (nouveaux.isEmpty) {
          expect(ne, isNull, reason: 'le dossier du répertoire l\'emporte');
        } else {
          memes(ne, nouveaux.single, 'patient', ignorer: {'id', 'statut'});
          expect(fiche['patientId'], 'PAT-TEST');
        }
      });
    }
  });

  group('modification d\'une demande (m5-demandes › Modifier › Enregistrer)', () {
    final doc = lireVecteurs('dem_creation');
    final rep = (doc['patientRepertoire'] as Map).cast<String, Object?>();
    final catalogue = liste(doc['catalogue']);
    for (final m in liste(doc['modifications'])) {
      test('${m['nom']}', () {
        final avant = (m['avant'] as Map).cast<String, Object?>();
        final saisie = {
          // Les champs conditionnels masqués (prescripteur extérieur, date de naissance, âge) ne sont pas collectés par le formulaire.
          for (final e in (m['prerempli'] as Map).entries)
            if (!(const ['prescripteurExterne', 'dateNaissance', 'age'].contains(e.key) && e.value == ''))
              e.key as String: e.value,
          ...(m['saisie'] as Map).cast<String, Object?>()
        };
        final fiche = demPreparerDemande(
            saisie: saisie,
            patient: {...rep},
            analyse: catalogue.firstWhere((a) => a['code'] == saisie['analyseCode']),
            demandes: [avant],
            creerPatient: (d) => fail('le dossier existe déjà'),
            effectifRepertoire: 1,
            maintenant: maintenant,
            existante: avant);
        final patch = (m['patch'] as Map).cast<String, Object?>();
        final obtenu = <String, Object?>{
          for (final e in fiche.entries)
            if ('${avant[e.key]}' != '${e.value}') e.key: e.value
        };
        memes(obtenu, patch, 'patch');
        expect(fiche['reference'], avant['reference']);
        expect(fiche['codeAnalyse'], avant['codeAnalyse']);
      });
    }
  });

  group('prélèvement (m5-prelevement)', () {
    final doc = lireVecteurs('dem_prelevement');
    final toutes = liste(doc['fiches']);
    final actives = [
      for (final f in toutes)
        if (f['statut'] != 'archive') f
    ];
    List<String?> refs(List<FicheDem> l) =>
        [for (final r in l) r['reference'] as String?];
    List<String?> vues(String onglet) => [
          for (final l in liste((doc['tabs'] as Map)[onglet])) l['ref'] as String?
        ];

    test('les trois onglets contiennent exactement les mêmes demandes, dans le même ordre', () {
      expect(refs(demAPrelever(actives)), vues('attente'));
      expect(refs(demPreleves(actives)), vues('transmettre'));
      expect(refs(demRecus(actives)), vues('labo'));
    });
    test('les quatre indicateurs', () {
      final k = demKpisPrelevement(actives);
      final t = '${doc['kpiTexte']}';
      expect(k.aPrelever, _nombreApres(t, 'À prélever'));
      expect(k.attenteReglement, _nombreApres(t, 'En attente de règlement'));
      expect(k.aTransmettre, _nombreApres(t, 'Prélevés, à transmettre'));
      expect(k.recus, _nombreApres(t, 'Reçus au laboratoire'));
    });
    test('l\'état « réglée » suit chaque cellule de la colonne État', () {
      for (final l in liste((doc['tabs'] as Map)['attente'])) {
        final r = actives.firstWhere((x) => x['reference'] == l['ref']);
        final cellule = (l['cellules'] as List)[5];
        expect(demReglee(r) ? 'Réglée — à prélever' : 'En attente de caisse',
            cellule, reason: '${l['ref']}');
      }
    });
    test('les demandes en attente de caisse n\'offrent que le verrou', () {
      for (final l in liste((doc['tabs'] as Map)['attente'])) {
        final r = actives.firstWhere((x) => x['reference'] == l['ref']);
        expect((l['actions'] as List).contains('Règlement requis avant prélèvement'),
            !demReglee(r));
        expect((l['actions'] as List).contains('Enregistrer le prélèvement'),
            demReglee(r));
      }
    });

    FicheDem diff(FicheDem avant, FicheDem patch) {
      final out = <String, Object?>{};
      for (final e in patch.entries) {
        if ('${avant[e.key]}' != '${e.value}') out[e.key] = e.value;
      }
      return out;
    }

    for (final a in liste(doc['actions'])) {
      test('${a['nom']}', () {
        final avant = actives.firstWhere((x) => x['reference'] == a['ref']);
        final patch = (a['patch'] as Map).cast<String, Object?>();
        if (a['action'] == 'Enregistrer le prélèvement') {
          final saisie = (a['saisie'] as Map).cast<String, Object?>();
          if ('${saisie['natureEchantillon'] ?? 'x'}'.isEmpty) {
            expect(patch, isEmpty, reason: 'formulaire en erreur : rien n\'est écrit');
            return;
          }
          final obtenu = diff(avant,
              demPatchPrelevement(saisie, demande: avant, maintenant: maintenant));
          expect(obtenu.keys.toSet(), patch.keys.toSet());
          for (final k in patch.keys.where((k) => k != 'preleveLe')) {
            expect(obtenu[k], patch[k], reason: k);
          }
          expect(DateTime.parse('${obtenu['preleveLe']}').isUtc, isTrue);
          expect(obtenu.containsKey('etatAnalyse'), isFalse,
              reason: 'E141 : l\'état ne change pas');
        } else if (a['action'] == 'Transmettre au laboratoire') {
          final obtenu = diff(avant,
              demPatchTransmission(maintenant: maintenant, utilisateur: '${patch['recuPar']}'));
          expect(obtenu.keys.toSet(), patch.keys.toSet());
          expect(obtenu['etatAnalyse'], 'en_cours');
          expect(obtenu['recuPar'], patch['recuPar']);
        } else {
          expect(patch, isEmpty, reason: 'le verrou n\'écrit rien');
          expect(demReglee(avant), isFalse);
        }
      });
    }
  });

  group('vues par service (m5-demandes-maternite / -hospitalisation)', () {
    final doc = lireVecteurs('dem_services');
    final actives = [
      for (final f in liste(doc['fiches']))
        if (f['statut'] != 'archive') f
    ];
    final vues = (doc['vues'] as Map).cast<String, Object?>();
    for (final e in {
      'm5-demandes-maternite': demServiceMaternite,
      'm5-demandes-hospitalisation': demServiceHospitalisation,
    }.entries) {
      test(e.key, () {
        final v = (vues[e.key] as Map).cast<String, Object?>();
        final lignes = actives.where(e.value).toList();
        expect([for (final r in lignes) r['reference']], v['lignes']);
        final k = demKpisService(lignes);
        final t = '${v['kpiTexte']}';
        expect(k.demandes, _nombreApres(t, 'Demandes du service'));
        expect(k.attenteReglement, _nombreApres(t, 'En attente de règlement'));
        expect(k.aPreleverTransmettre, _nombreApres(t, 'À prélever / transmettre'));
        expect(k.rendues, _nombreApres(t, 'Résultats rendus'));
      });
    }
  });

  group('file des prélèvements (m5-demandes › Prendre en charge)', () {
    final doc = lireVecteurs('dem_file');
    for (final c in liste(doc['cas'])) {
      test('${c['nom']}', () {
        if (c['boutonPresent'] != true) {
          expect(c['verrouPresent'], isTrue);
          expect(c['avant'], c['apres']);
          return;
        }
        final etats = (c['avant'] as List).cast<String>();
        final demandes = [
          for (var i = 0; i < etats.length; i++)
            {
              'id': 'F$i',
              'ordonnanceId': i == etats.length - 1 ? 'ORD-AUTRE' : 'ORD-F',
              'etatAnalyse': etats[i]
            }
        ];
        final r = demPriseEnCharge(demandes, 'ORD-F');
        final apres = [
          for (final d in demandes)
            r.aMettreAJour.contains(d['id']) ? 'en_cours' : d['etatAnalyse']
        ];
        expect(apres, c['apres']);
        final toast = ((c['toasts'] as List).first as List).first;
        expect(toast, '${r.annonce} analyse(s) prise(s) en charge.');
      });
    }
  });

  group('divers', () {
    test('référence suivante : le plus grand rang + 1, jamais un compteur de page', () {
      expect(demReferenceSuivante([]), 'LAB-00001');
      expect(
          demReferenceSuivante([
            {'reference': 'LAB-00150'},
            {'reference': 'LAB-00006'},
            {'reference': 'ORD-00999'}
          ]),
          'LAB-00151');
    });
    test('âge : déclaré, daté, ou date de naissance', () {
      expect(demAgeTexte({'dateNaissance': '1990-05-12'}, maintenant: maintenant),
          '36 ans');
      expect(demAgeTexte({'age': 41, 'ageReferenceLe': '2026-10-30'}, maintenant: maintenant),
          '41 ans (âge déclaré)');
      expect(demAgeTexte({'age': 1}, maintenant: maintenant), '1 an (âge déclaré)');
      expect(demAgeTexte({}, maintenant: maintenant), '—');
    });
    test('examen d\'une demande : égalité ou préfixe, accents neutralisés', () {
      final ex = [
        {'code': 'NFS', 'designation': 'NFS complète (hémogramme)'},
        {'code': 'GE', 'designation': 'Goutte épaisse'}
      ];
      expect(demExamenDe({'analyse': 'NFS COMPLETE (HEMOGRAMME)'}, ex)?['code'], 'NFS');
      expect(demExamenDe({'analyse': 'goutte epaisse'}, ex)?['code'], 'GE');
      expect(demExamenDe({'analyse': 'AKOP'}, ex), isNull);
    });
  });
}
