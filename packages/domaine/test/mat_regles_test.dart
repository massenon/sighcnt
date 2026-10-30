// Rejoue les vecteurs de la maternité (prototype_html/build/vecteurs-maternite.js) : les écrans RÉELS de M4 pilotés dans Chrome. Ici, les RÈGLES :
// alertes du nouveau-né, partogramme (alerte 4 cm + 1 cm/h, action décalée de 4 h), numéro et risque du dossier obstétrical, références, refus nommés.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
M lire(String nom) => obj(jsonDecode(File('test/vecteurs/$nom.json').readAsStringSync()));

void main() {
  final regles = lire('mat_regles');
  final saisies = lire('mat_saisies');

  group('référentiels tracés au rapport du 27/08/2026', () {
    test('10 fonctions SONU : 7 SONUB puis 3 SONUC', () {
      final f = matFonctionsSonu;
      expect(f.length, 10);
      expect([for (final x in f.take(7)) x['type']].toSet(), {'SONUB'});
      expect([for (final x in f.skip(7)) x['type']].toSet(), {'SONUC'});
      expect(matFonctionSonu(7)!['label'], 'Réanimation du nouveau-né');
      expect(matFonctionSonu('10')!['label'], 'Césarienne d’urgence');
      expect(matFonctionSonu(11), isNull);
    });
    test('15 méthodes PF, codification A/N reprise telle quelle', () {
      expect(matMethodesPf.length, 15);
      expect(matMethodePf('jadelle')!['label'], 'Jadelle (2 bâtonnets)');
      expect([for (final s in matStatutsAcceptante) s['code']], ['A', 'N']);
      expect(matStatutsAcceptante.first['label'], 'A — Nouvelle acceptante');
    });
    test('bornes écrites du nouveau-né et âges CPN', () {
      final b = matBornesNouveauNe;
      expect([b.pcMin, b.pcMax, b.ptMin, b.ptMax, b.apgarSeuil5min], [32, 38, 30, 36, 7]);
      expect(matCarte('AGES_RISQUE_CPN'), {'min': 18, 'max': 35});
      expect(matTypesCpon.length, 3);
      expect(matFacteursSurveillance.length, 12);
      expect(matComptesRendus.map((c) => c['code']), ['accouchement', 'planning_familial', 'amiu']);
    });
    test('modèle de partographie : alerte 4 cm + 1 cm/h, action décalée de 4 h', () {
      final p = matModelePartogramme;
      expect([p.alerteDepart, p.alerteParHeure, p.actionDecalageHeures], [4, 1, 4]);
    });
  });

  group('nouveau-né : PC 32–38, PT 30–36, alerte Apgar 5 min < 7', () {
    final n = obj(regles['nouveauNe']);
    final fiches = liste(n['fiches']);
    final rendu = liste(obj(n['registre'])['rendu']);
    final bebe = liste(n['rendu']);
    for (var i = 0; i < 12; i++) {
      test('${(n['cas'] as List)[i]}', () {
        final f = fiches[i];
        expect(matPcHorsBornes(f), bebe[i]['pcAlerte'], reason: 'PC dans le dossier bébé');
        expect(matPtHorsBornes(f), bebe[i]['ptAlerte'], reason: 'PT dans le dossier bébé');
        expect(matApgarAlerte(f), rendu[i]['apgarAlerte'], reason: 'Apgar dans le registre');
        expect(matAlertesNouveauNe(f).isNotEmpty, rendu[i]['horsBornes'], reason: 'PC / PT (cm) du registre');
        expect(matApgarTexte(f), rendu[i]['apgar']);
      });
    }
    test('le KPI « Mesures hors bornes » compte les fiches signalées', () {
      final k = liste(n['kpis']).firstWhere((x) => x['label'] == 'Mesures hors bornes');
      expect('${fiches.where((f) => matAlertesNouveauNe(f).isNotEmpty).length}', k['valeur']);
    });
    test('motifs et ordre : PC, PT, Apgar', () {
      expect(matAlertesNouveauNe(fiches.last), ['PC', 'PT', 'Apgar']);
    });
    test('l\'ancien score unique s\'écrit n/10 ; un temps non relevé, un tiret', () {
      expect(matApgarTexte({'apgar': 8}), '8/10');
      expect(matApgarTexte({'apgar5': 7}), '— / 7 / —');
      expect(matApgarTexte({'apgar1': 8, 'apgar5': 9, 'apgar10': 10}), '8 / 9 / 10');
    });
  });

  group('partogramme', () {
    final p = obj(regles['partogramme']);
    final fiches = liste(p['fiches']);
    final cas = liste(p['cas']);
    for (var i = 0; i < fiches.length; i++) {
      test('${fiches[i]['reference']} : ligne d\'action ${cas[i]['note'] == true ? 'franchie' : 'non franchie'}', () {
        expect(matFranchitAction(fiches[i]), cas[i]['note']);
      });
    }
    test('indicateurs : franchies et travaux en cours', () {
      final k = {for (final x in liste(p['kpis'])) x['label']: x['valeur']};
      expect('${fiches.where(matFranchitAction).length}', k['Ligne d’action franchie']);
      expect('${fiches.where((f) => f['clos'] != true).length}', k['Travaux en cours']);
      expect('${fiches.where((f) => f['clos'] == true).length}', k['Dilatations complètes']);
    });
    test('lignes d\'alerte et d\'action', () {
      final s = matSeriesPartogramme(fiches[0]);
      expect(s.etiquettes.length, 13);
      expect(s.alerte.take(8), [4, 5, 6, 7, 8, 9, 10, 10]);
      expect(s.action.take(6), [null, null, null, null, 4, 5]);
      expect(s.action.last, 10);
      expect(s.dilatation.take(4), [4, 5, 6, null]);
    });
    test('la fenêtre s\'étend à la dernière heure relevée (au-delà de 12 h)', () {
      final s = matSeriesPartogramme({'mesures': [{'heure': 15, 'dilatation': 9}]});
      expect(s.etiquettes.length, 16);
      expect(s.dilatation.last, 9);
    });
    final ajouts = liste(p['ajouts']);
    test('mesures triées par heure ; clôture à 10 cm', () {
      var cur = <String, Object?>{'mesures': <Object?>[], 'clos': false};
      for (final a in ajouts) {
        final r = matAjouterMesure(cur, obj(a['saisie']));
        cur = {'mesures': r.mesures, 'clos': r.clos, 'resume': r.resume};
        expect([for (final m in r.mesures) m['heure']], [for (final m in liste(a['mesures'])) m['heure']]);
        expect(r.clos, a['clos']);
        expect(r.resume, a['resume']);
      }
    });
  });

  group('dossier obstétrical', () {
    final d = obj(regles['dossier']);
    test('numéro de dossier : série annuelle, archivés compris, cinq chiffres', () {
      List<M> fiches(List n) => [for (final x in n) {'numeroDossier': (x as List)[0]}];
      for (final s in liste(d['series'])) {
        expect(matNumeroDossier(fiches(s['numeros'] as List), DateTime(2026, 8, 16)), s['propose'], reason: '${s['nom']}');
      }
    });
    test('le risque se déduit du CUMUL des facteurs cochés', () {
      for (final g in (d['gar'] as List)) {
        expect(g, isA<List>());
      }
      expect(matFacteursSurveillance.map((f) => f['code']).first, 'age_min');
      expect(matEstGar({'facteurs': {}}), isFalse);
      expect(matEstGar({'facteurs': {'hta': true}}), isTrue);
      expect(matEstGar({'facteurs': {'hta': false}}), isFalse);
      expect([for (final f in matFacteursCoches({'facteurs': {'diabete': true, 'age_max': true}})) f['code']], ['age_max', 'diabete']);
    });
    test('la date probable se DÉDUIT de la DDR : 280 jours', () {
      for (final c in liste(d['creations'])) {
        for (final x in liste(c['nouvelles'])) {
          expect(matDpaDepuisDdr(x['ddr']), x['dpa'], reason: '${c['nom']}');
        }
      }
      expect(matDpaDepuisDdr('2026-05-10'), '2027-02-14');
      expect(matDpaDepuisDdr(''), isNull);
    });
    test('les cases facteur_* se rangent dans UNE carte', () {
      for (final c in liste(d['creations'])) {
        for (final x in liste(c['nouvelles'])) {
          final r = matRanger({...obj(c['saisie']), 'ddr': x['ddr']});
          expect(r['facteurs'], x['facteurs'], reason: '${c['nom']}');
        }
      }
    });
    test('modification : le diabète coché s\'ajoute, la DDR corrigée déplace la DPA', () {
      final m = obj(d['modification']);
      final apres = obj(m['apres']);
      expect(apres['facteurs'], {'age_max': true, 'diabete': true});
      expect(matDpaDepuisDdr(apres['ddr']), apres['dpa']);
    });
  });

  group('références : le registre fait foi (écart E400), jamais un compteur de page', () {
    test('plus grand rang + 1, archivées comprises, préfixe respecté', () {
      final f = [
        {'reference': 'ACC-0007'},
        {'reference': 'ACC-0003', 'statut': 'archive'},
        {'reference': 'ACCX-0099'},
        {'reference': 'NAI-0050'}
      ];
      expect(matReferenceSuivante('ACC-', f), 'ACC-0008');
      expect(matReferenceSuivante('DEC-', f), 'DEC-0001');
      expect(matReferenceSuivante('NAI-', f), 'NAI-0051');
    });
  });

  group('refus nommés', () {
    test('verrou d\'admission (Module A) : nomme le dossier à corriger', () {
      final refus = liste(saisies['saisies']).firstWhere((s) => '${s['nom']}'.startsWith('suivi : dossier sans date'));
      final msg = matRefusAdmission(
          patientCode: obj(saisies['contexte'])['femmeSansNaissance'] as String, dateNaissanceConnue: false, poids: 55);
      expect(msg, ((refus['toasts'] as List).single as List).single);
      expect(matRefusAdmission(patientCode: 'X', dateNaissanceConnue: true, poids: null), 'Le poids est obligatoire à l’admission (rapport du 27/08/2026).');
      expect(matRefusAdmission(patientCode: 'X', dateNaissanceConnue: true, poids: 0), isNull, reason: 'un poids à 0 est écrit : seul l\'absent est refusé');
    });
    test('hémorragie ante-partum : l\'étiologie est exigée', () {
      final refus = liste(saisies['saisies']).firstWhere((s) => '${s['nom']}'.contains('SANS étiologie'));
      expect(matRefusCpon(hemorragieAntePartum: true, etiologie: ''), ((refus['toasts'] as List).single as List).single);
      expect(matRefusCpon(hemorragieAntePartum: true, etiologie: 'Placenta praevia'), isNull);
      expect(matRefusCpon(hemorragieAntePartum: false, etiologie: ''), isNull);
    });
    test('Case 27 : jours exigés si hospitalisée, refusés sinon', () {
      final a = liste(saisies['saisies']).firstWhere((s) => '${s['nom']}'.contains('hospitalisée sans jours'));
      final b = liste(saisies['saisies']).firstWhere((s) => '${s['nom']}'.contains('jours sans hospitalisation'));
      expect(matRefusCase27(hospitalisee: true, jours: null), ((a['toasts'] as List).single as List).single);
      expect(matRefusCase27(hospitalisee: false, jours: 3), ((b['toasts'] as List).single as List).single);
      expect(matRefusCase27(hospitalisee: true, jours: 3), isNull);
      expect(matRefusCase27(hospitalisee: false, jours: null), isNull);
    });
    test('âge hors fenêtre CPN : signalé sauf si GAR est déjà coché', () {
      final auj = DateTime(2026, 8, 16);
      expect(matAgeHorsFenetreCpn('1989-01-01', false, auj), isTrue);
      expect(matAgeHorsFenetreCpn('1989-01-01', true, auj), isFalse);
      expect(matAgeHorsFenetreCpn('1990-06-01', false, auj), isTrue, reason: '36 ans : > 35 signale');
      expect(matAgeHorsFenetreCpn('2000-01-01', false, auj), isFalse);
      expect(matAgeHorsFenetreCpn('2010-01-01', false, auj), isTrue);
      expect(matAgeHorsFenetreCpn(null, false, auj), isFalse);
    });
  });

  group('nombres à la façon de JavaScript', () {
    test('String(3) et String(3.1)', () {
      expect(matTexteNombre(3), '3');
      expect(matTexteNombre(3.0), '3');
      expect(matTexteNombre(3.1), '3.1');
      expect(matTexteNombre('2,5'), '2.5');
      expect(matTexteNombre(null), '');
      expect(matNombreSaisi('3'), 3);
      expect(matNombreSaisi('3.50'), 3.5);
      expect(matNombreSaisi(''), isNull);
    });
  });
}
