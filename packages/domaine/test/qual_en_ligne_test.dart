// LOT SAT (ADR-0009) : la satisfaction en ligne au domaine. Les vecteurs sont tirés de l'écran RÉEL de la maquette (`prototype_html/build/vecteurs-sat.js`) ; les 15 refus et la charge
// publiée sont testés ici contre des cas construits.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> fl(Object? v) => [for (final x in (v as List)) obj(x)];
String sp(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();

final v = lireVecteurs('satisfaction_en_ligne');

void main() {
  group('points de collecte : paramètre de clinique, défaut semé', () {
    test('les sept points de la décision S2, comme à l’écran de la maquette', () {
      final attendus = [for (final p in fl(v['points'])) (code: p['code'], libelle: p['libelle'])];
      expect([for (final p in qualPointsCollecteDefaut) (code: p.code, libelle: p.libelle)], attendus);
      expect(attendus.length, 7);
    });
    test('le texte du paramètre se lit et se réécrit ; un texte illisible retombe sur les sept points', () {
      final pts = qualPointsDepuisParametre('accueil=Accueil;urgences=Urgences');
      expect(pts.map((p) => p.code), ['accueil', 'urgences']);
      expect(qualPointsDepuisParametre(qualPointsVersParametre(pts)).length, 2);
      expect(qualPointsDepuisParametre('n importe quoi'), qualPointsCollecteDefaut);
      expect(qualPointsDepuisParametre(qualDefinitionsEnLigne[1].defaut), qualPointsCollecteDefaut);
      expect(qualDefinitionsEnLigne[0].defaut, 'non', reason: 'la collecte en ligne est désactivée par défaut');
    });
  });

  group('analyse : rejouée sur la carte « Analyse » de l’écran réel', () {
    final a = obj(v['analyse']);
    final e = obj(obj(a['entrees'])['enquete']);
    final reps = fl(obj(a['entrees'])['reponses']);
    for (final c in fl(a['cas'])) {
      test(c['nom'] as String, () {
        final f = obj(c['filtres']);
        final r = qualAnalyse(e, reps, du: '${f['du'] ?? ''}', au: '${f['au'] ?? ''}', point: '${f['point'] ?? ''}', version: '${f['version'] ?? ''}', canal: '${f['canal'] ?? ''}');
        final k = fl(c['kpis']);
        expect(nombre(r.reponses), sp(k[0]['valeur']));
        expect(sp(qualPctOuNC(r.satisfaction)), sp(k[1]['valeur']));
        expect(sp(qualPctOuNC(r.recommandation)), sp(k[2]['valeur']));
        expect(sp(qualPctOuNC(r.tauxReponse)), 'Non calculable', reason: 'passages non comptés');
        expect(sp(k[3]['valeur']), 'Non calculable');
        final t = fl(c['tables']);
        expect([
          for (final q in r.parQuestion) [q.libelle, nombre(q.n), q.moyenne == null ? 'Non calculable' : nombre(q.moyenne, 1), sp(qualPctOuNC(q.satisfaction))]
        ], [
          for (final l in (t[0]['lignes'] as List)) [(l as List)[1], l[2], l[3], sp(l[4])]
        ]);
        if (t.length > 1) {
          expect([for (final m in r.parMois) [m.mois, nombre(m.n), sp(qualPctOuNC(m.satisfaction))]], [
            for (final l in (t[1]['lignes'] as List)) [(l as List)[1], l[2], sp(l[3])]
          ]);
          expect([for (final p in r.parPoint) [p.libelle, nombre(p.n), sp(qualPctOuNC(p.satisfaction))]], [
            for (final l in (t[2]['lignes'] as List)) [(l as List)[1], l[2], sp(l[3])]
          ]);
        } else {
          expect(r.parMois, isEmpty);
          expect(r.parPoint, isEmpty);
        }
      });
    }
    test('un recompte à la main : 13 notes valides, 8 de 4 ou 5 = 61,5 %', () {
      final r = qualAnalyse(e, reps);
      expect(r.notes, 13);
      expect(r.satisfaction, 61.5);
      expect(r.recommandation, 60.0);
    });
    test('les listes déroulantes de la carte proposent les points et les versions', () {
      final c = fl(a['cas']).first;
      expect(obj(c['options'])['points'], ['', ...qualPointsCollecteDefaut.map((p) => p.code)]);
      expect(obj(c['options'])['versions'], ['', 'V1', 'V2']);
    });
  });

  group('versions datées : modifier le questionnaire en ajoute une, la réponse garde la sienne', () {
    final c = obj(v['versions']);
    test('l’écran réel : sans changement aucune version ; un changement ajoute V2 à la date du jour', () {
      final avant = obj(c['avant']);
      final enq = {'id': 'ENQ0001', 'creeLe': '2026-08-01', 'questions': avant['questions'], 'versions': avant['versions']};
      final qs = fl(avant['questions']);
      final rien = qualAjouterVersion(enq, qs, '2026-08-16');
      expect(rien.versions, isNull);
      expect(rien.refus, isNull);
      expect((obj(c['sansChangement'])['versions'] as List), ['V1']);
      final neuf = qualAjouterVersion(enq, qs.sublist(1), '2026-08-16');
      expect([for (final x in neuf.versions!) '${x['version']}|${x['effetLe']}|${[for (final q in fl(x['questions'])) q['code']]}'],
          [for (final x in fl(obj(c['apresModification'])['versions'])) '${x['version']}|${x['effetLe']}|${x['codes']}']);
      expect(qualVersionALaDate({...enq, 'versions': neuf.versions}, '2026-08-10')['version'], 'V1');
      expect(qualVersionALaDate({...enq, 'versions': neuf.versions}, '2026-08-16')['version'], 'V2');
      expect(qualVersionALaDate({...enq, 'versions': neuf.versions}, '2026-07-01')['version'], 'V1', reason: 'avant la première : la première');
    });
    test('une date d’effet antérieure à la dernière version est refusée (VERSION_ANTERIEURE)', () {
      final enq = {'id': 'E', 'versions': [{'version': 'V1', 'effetLe': '2026-08-01', 'questions': []}, {'version': 'V2', 'effetLe': '2026-08-10', 'questions': [{'code': 'A'}]}]};
      final r = qualAjouterVersion(enq, [{'code': 'B'}], '2026-08-05');
      expect(r.refus?.code, 'VERSION_ANTERIEURE');
      expect(r.versions, isNull);
    });
    test('la réponse recueillie porte la version en vigueur (V2) et celles d’avant gardent V1', () {
      expect(obj(c['reponseNee'])['version'], 'V2');
      expect(c['anciennesReponses'], ['V1']);
    });
  });

  group('partage en ligne : un jeton, un point, une adresse publique', () {
    final p = obj(v['partageEnLigne']);
    test('le lien porte enLigne, le point et la version ; l’adresse ne porte pas l’enquête', () {
      final j = obj(p['jeton']);
      expect(j['enLigne'], true);
      expect(j['point'], 'laboratoire');
      expect(j['version'], 'V1');
      expect(p['lienGabarit'], 'https://sighcnt.nassieratoo.com/s/<jeton>');
      expect(p['formatJeton'], true);
      expect(obj((p['form'] as Map))['champs'].toString(), contains('en_ligne'));
    });
    test('la charge publiée : version en vigueur, point nommé, aucune donnée de santé', () {
      final enq = {'id': 'ENQ0001', 'titre': 'Satisfaction des patients', 'creeLe': '2026-08-01', 'questions': [{'code': 'Q1', 'type': 'note', 'libelle': 'Accueil'}, {'code': 'Q2', 'type': 'texte', 'libelle': 'Avis'}, {'code': 'Q3', 'type': 'choix', 'libelle': 'Reco', 'options': ['Oui', 'Non']}]};
      final ch = qualCharge(enq, {'point': 'laboratoire'}, aLaDate: '2026-08-16');
      expect(ch['version'], 'V1');
      expect(obj(ch['point'])['libelle'], 'Laboratoire');
      expect([for (final q in fl(ch['questions'])) q['obligatoire']], [true, false, true]);
      expect(ch.keys.toSet(), {'enquete', 'version', 'point', 'titre', 'intro', 'questions'});
    });
    test('les liens à publier : ouverts et « en ligne » seulement, empreinte SHA-256, jamais le jeton, 200 au plus', () {
      final enq = {'id': 'ENQ0001', 'titre': 'S', 'creeLe': '2026-08-01', 'statut': 'actif', 'questions': [{'code': 'Q1', 'type': 'note', 'libelle': 'A'}]};
      M j(String id, String jeton, {bool ligne = true, String? revoque, String expire = '2026-12-31', String cree = '2026-08-10'}) =>
          {'id': id, 'jeton': jeton, 'enqueteId': 'ENQ0001', 'enLigne': ligne, 'point': 'accueil', 'creeLe': cree, 'expireLe': expire, 'revoqueLe': revoque};
      final r = qualLiensAPublier(jetons: [j('1', 'aaaaaaaaaaaaaaaaaaaaaaaa'), j('2', 'bbbbbbbbbbbbbbbbbbbbbbbb', ligne: false), j('3', 'cccccccccccccccccccccccc', revoque: '2026-08-12'), j('4', 'dddddddddddddddddddddddd', expire: '2026-08-01')], enquetes: [enq], aLaDate: '2026-08-16');
      expect(r.liens.length, 1);
      expect(r.liens.first['empreinte'], qualEmpreinteJeton('aaaaaaaaaaaaaaaaaaaaaaaa'));
      expect('${r.liens}', isNot(contains('aaaaaaaaaaaaaaaaaaaaaaaa')));
      final beaucoup = qualLiensAPublier(jetons: [for (var i = 0; i < 230; i++) j('$i', 'jeton${i.toString().padLeft(19, '0')}', cree: '2026-08-${(1 + i % 15).toString().padLeft(2, '0')}')], enquetes: [enq], aLaDate: '2026-08-16');
      expect(beaucoup.liens.length, qualLiensMax);
      expect(beaucoup.ignores, 30, reason: 'les liens au-delà de 200 sont comptés, jamais perdus en silence');
    });
  });

  group('jugement d’une réponse ouverte : 15 refus nommés', () {
    const jeton = 'jetonessai0123456789abcd';
    final enq = {
      'id': 'ENQ0001',
      'statut': 'actif',
      'creeLe': '2026-08-01',
      'versions': [
        {'version': 'V1', 'effetLe': '2026-08-01', 'questions': [{'code': 'Q_A', 'type': 'note', 'libelle': 'Accueil'}, {'code': 'Q_R', 'type': 'choix', 'libelle': 'Reco', 'options': ['Oui', 'Non']}, {'code': 'Q_T', 'type': 'texte', 'libelle': 'Avis'}, {'code': 'Q_N', 'type': 'nps', 'libelle': 'NPS', 'obligatoire': false}]},
        {'version': 'V2', 'effetLe': '2026-09-01', 'questions': [{'code': 'Q_A', 'type': 'note', 'libelle': 'Accueil'}]},
      ],
    };
    M lien([M plus = const {}]) => {'id': 'JET1', 'jeton': jeton, 'enqueteId': 'ENQ0001', 'point': 'accueil', 'creeLe': '2026-08-02', 'expireLe': '2026-08-31', 'revoqueLe': null, ...plus};
    const id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
    final recu = DateTime.utc(2026, 8, 16, 10).millisecondsSinceEpoch;
    M clair([M plus = const {}]) => {'id': id, 'enquete': 'ENQ0001', 'version': 'V1', 'point': 'accueil', 'langue': 'fr', 'reponses': {'Q_A': 5, 'Q_R': 'Oui', 'Q_T': '  Merci  '}, ...plus};
    ({QualFiche? reponse, QualRefus? refus}) juger(Object? c, {List<M>? jetons, List<M>? enquetes, String? emp, String? idr, int? ms}) => qualJugerReponseEnLigne(
        clair: c, idRelais: idr ?? id, empreinteLien: emp ?? qualEmpreinteJeton(jeton), recuMs: ms ?? recu, jetons: jetons ?? [lien()], enquetes: enquetes ?? [enq]);

    test('une réponse valide devient la fiche REPW-<id> : canal « Lien public », anonyme, version et point gardés, texte rogné', () {
      final r = juger(clair());
      expect(r.refus, isNull);
      final f = r.reponse!;
      expect(f['id'], 'REPW-$id');
      expect(f['canal'], 'Lien public');
      expect(f['version'], 'V1');
      expect(f['point'], 'accueil');
      expect(f['saisiPar'], contains('anonyme'));
      expect(f['date'], '2026-08-16');
      expect(obj(f['reponses']), {'Q_A': 5, 'Q_R': 'Oui', 'Q_T': 'Merci'});
    });

    final cas = <String, ({({QualFiche? reponse, QualRefus? refus}) Function() f})>{
      'format_inconnu': (f: () => juger('texte')),
      'identifiant_invalide': (f: () => juger(clair({'id': 'pas-un-id'}), idr: 'pas-un-id')),
      'champ_identite': (f: () => juger(clair({'nom': 'Awa'}))),
      'lien_inconnu': (f: () => juger(clair(), emp: qualEmpreinteJeton('autre'))),
      'lien_revoque': (f: () => juger(clair(), jetons: [lien({'revoqueLe': '2026-08-10'})])),
      'lien_expire': (f: () => juger(clair(), jetons: [lien({'expireLe': '2026-08-10'})])),
      'enquete_introuvable': (f: () => juger(clair(), enquetes: [{...enq, 'statut': 'archive'}])),
      'version_incoherente': (f: () => juger(clair({'version': 'V2'}))),
      'point_inconnu': (f: () => juger(clair({'point': 'cuisine'}))),
      'question_inconnue': (f: () => juger(clair({'reponses': {'Q_A': 5, 'Q_R': 'Oui', 'Q_Z': 1}}))),
      'reponse_obligatoire_manquante': (f: () => juger(clair({'reponses': {'Q_A': 5}}))),
      'note_hors_bornes': (f: () => juger(clair({'reponses': {'Q_A': 6, 'Q_R': 'Oui'}}))),
      'choix_hors_liste': (f: () => juger(clair({'reponses': {'Q_A': 5, 'Q_R': 'Peut-être'}}))),
      'texte_trop_long': (f: () => juger(clair({'reponses': {'Q_A': 5, 'Q_R': 'Oui', 'Q_T': 'x' * 1001}}))),
      'reponses_vides': (f: () => juger(clair({'reponses': <String, Object?>{}}))),
    };
    test('la liste des refus est exactement celle du domaine', () => expect(cas.keys.toSet(), qualRefusEnLigne.toSet()));
    for (final e in cas.entries) {
      test('refus ${e.key} : code, motif et geste nommés, rien n’est écrit', () {
        final r = e.value.f();
        expect(r.reponse, isNull);
        expect(r.refus?.code, e.key);
        expect(r.refus!.motif, isNotEmpty);
        expect(r.refus!.geste, isNotEmpty);
      });
    }
    test('tout champ d’identité est refusé, au premier niveau comme parmi les réponses', () {
      for (final cle in ['nom', 'prenom', 'telephone', 'email', 'dossier', 'patient', 'numero_dossier', 'adresse']) {
        expect(juger(clair({cle: 'x'})).refus?.code, 'champ_identite', reason: cle);
        expect(juger(clair({'reponses': {'Q_A': 5, 'Q_R': 'Oui', cle: 'x'}})).refus?.code, 'champ_identite', reason: 'dans les réponses : $cle');
      }
      expect(juger(clair({'inconnu': 1})).refus?.code, 'format_inconnu');
    });
    test('l’attribution vient du relais : un identifiant que le relais n’a pas vu est refusé', () {
      expect(juger(clair(), idr: 'ffffffffffffffffffffffffffffffff').refus?.code, 'identifiant_invalide');
    });
    test('la version de la réponse reste celle sous laquelle elle a été donnée (V1 lue après l’arrivée de V2), pas V2 (question en moins)', () {
      final r = juger(clair(), ms: DateTime.utc(2026, 9, 2).millisecondsSinceEpoch, jetons: [lien({'expireLe': '2026-12-31'})]);
      expect(r.refus, isNull);
      expect(r.reponse!['version'], 'V1');
    });
    test('un lien révoqué le jour même accepte ce que le relais a reçu avant (il a refusé les suivants)', () {
      expect(juger(clair(), jetons: [lien({'revoqueLe': '2026-08-16'})]).refus, isNull);
    });
    test('la note facultative (NPS) vide est ignorée, une note entière hors bornes est refusée', () {
      expect(juger(clair({'reponses': {'Q_A': 5, 'Q_R': 'Oui', 'Q_N': ''}})).reponse!['reponses'], isNot(contains('Q_N')));
      expect(juger(clair({'reponses': {'Q_A': 4.5, 'Q_R': 'Oui'}})).refus?.code, 'note_hors_bornes');
    });
  });
}
