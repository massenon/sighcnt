// Rejoue les vecteurs du MOTEUR D'EXERCICE de M12 (m12-cloture, m12-ouverture) tirés de `SIGH.exercice` et des écrans réels de la maquette
// (prototype_html/build/vecteurs-m12-exercice.js). Le jeu est celui du poste (apps/poste/assets/donnees/jeu), l'horloge celle du 30/10/2026 10 h.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) => ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
F carte(Object? v) => (v as Map).cast<String, Object?>();
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();
List<F> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));

/// Les champs qui ne dépendent ni d'un identifiant tiré au hasard ni de l'horloge d'écriture.
String _v(Object? x) => x is num && x == x.truncate() ? '${x.toInt()}' : '${x ?? ''}';
String cle(F e) => [for (final k in ['numero', 'date', 'journal', 'compte', 'compteLibelle', 'debit', 'credit', 'libelle', 'statut', 'origine', 'origineCloture', 'pieceOrigine']) _v(e[k])].join('|');

void main() {
  final f = File('test/vecteurs/exercice.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-m12-exercice.js`');
  final v = carte(jsonDecode(f.readAsStringSync()));
  final auj = DateTime(2026, 10, 30, 10);
  final ecr = jeu('ecritures');
  final exo = jeu('exercices');
  List<F> valides(List<F> l) => [for (final x in l) {...x, if (x['statut'] == 'brouillon') 'statut': 'validee'}];
  List<F> actives(List<F> l) => [for (final x in l) if (x['statut'] != 'archive') x];

  group('SHA-256 : la maquette et le poste calculent la même empreinte', () {
    test('quatre entrées, accents et longueur comprises', () {
      final s = carte(v['sha']);
      expect(cpcSha256('abc'), s['abc']);
      expect(cpcSha256(''), s['vide']);
      expect(cpcSha256('Résultat net — 12 345,6 €'), s['accents']);
      expect(cpcSha256('a' * 1000), s['long']);
    });
  });

  group('exercices : amorçage, liste, états', () {
    test('l\'amorçage dérive une fiche par année du journal, de l\'horloge et de la liasse (2024-2025 closes d\'office)', () {
      final a = cpcExercicesAAmorcer([], ecr, auj).reversed.toList(); // la maquette insère EN TÊTE
      final att = liste(carte(v['amorcage'])['exercices']);
      expect(a.length, att.length);
      for (var i = 0; i < a.length; i++) {
        for (final k in ['id', 'annee', 'debut', 'fin', 'statut', 'etat', 'source', 'valideLe', 'validePar', 'motif']) {
          expect(a[i][k], att[i][k], reason: '${att[i]['id']}.$k');
        }
      }
    });
    test('une année déjà portée par une fiche n\'est pas recréée ; une fiche ARCHIVÉE non plus', () {
      expect(cpcExercicesAAmorcer(exo, ecr, auj), isEmpty);
      final arch = [for (final x in exo) {...x, if (x['annee'] == 2026) 'statut': 'archive'}];
      expect(cpcExercicesAAmorcer(arch, ecr, auj), isEmpty);
    });
    test('la liste est du plus récent au plus ancien et ignore les archivés', () {
      final att = liste(v['liste']);
      expect([for (final x in cpcListeExercices(exo)) x['annee']], [for (final x in att) x['annee']]);
      expect(cpcListeExercices([for (final x in exo) {...x, if (x['annee'] == 2025) 'statut': 'archive'}]).map((x) => x['annee']), [2026, 2024]);
    });
    test('l\'état de chaque année est celui de la maquette ; une fiche archivée ne ferme rien (RG-14)', () {
      final e = carte(v['etats']);
      for (final k in e.keys) {
        expect(cpcEtatExercice(exo, int.parse(k)), e[k], reason: k);
        expect(cpcEtatExercice([], int.parse(k)), e[k], reason: '$k sans fiche : ce que l\'amorçage donnerait');
      }
      expect(cpcEtatExercice([for (final x in exo) {...x, if (x['annee'] == 2025) 'statut': 'archive'}], 2025), 'ouvert');
    });
  });

  group('la garde de lecture seule, posée sur la collection', () {
    test('les refus ont le motif de la maquette ; 2026 et une date absente passent', () {
      String? motif(String d) => cpcGardeEcritures(exo, d);
      expect(motif('2025-03-01'), allOf(contains('Exercice 2025 clôturé le 15/05/2026'), contains('lecture seule'), contains('réouverture par le comptable')));
      expect(motif('2024-12-31'), contains('Exercice 2024 clôturé'));
      expect(motif('2025-06-01'), contains('Exercice 2025 clôturé'));
      expect(motif('2026-03-01'), isNull);
      expect(cpcGardeEcritures(exo, null), isNull);
      expect(cpcGardeEcritures(exo, ''), isNull);
    });
    test('un exercice clos AU POSTE (deux gestes) refuse à son tour, avec la date de la validation', () {
      final clos = [for (final x in exo) if (x['annee'] == 2026) {...x, 'etat': 'clos', 'valideLe': '2026-10-30T10:00:00.407Z'} else x];
      expect(cpcGardeEcritures(clos, '2026-07-01'), allOf(contains('Exercice 2026 clôturé le 30/10/2026'), contains('lecture seule')));
    });
  });

  group('pré-clôture : six contrôles nommés', () {
    void verifie(String nom, List<F> lignes, int annee) {
      final att = carte(carte(v['preCloture'])[nom]);
      final p = cpcPreCloture(lignes, annee);
      expect([for (final c in p.controles) [c.id, c.bloquant, c.ok, c.libelle, c.ecran, c.detail]],
          [for (final c in liste(att['controles'])) [c['id'], c['bloquant'], c['ok'], c['libelle'], c['ecran'], c['detail']]],
          reason: nom);
      expect(p.bloquants.length, att['nbBloquants'], reason: nom);
      expect(p.resultat, closeTo(att['resultat'] as num, 0.001), reason: nom);
      expect(p.nbEcritures, att['nbEcritures'], reason: nom);
    }

    test('le jeu 2026 : 92 brouillons BLOQUENT, le résultat provisoire est calculé sur les validées', () {
      verifie('jeu2026', actives(ecr), 2026);
      expect(cpcPreCloture(actives(ecr), 2026).bloquants.map((c) => c.id), ['brouillons']);
    });
    test('2025 : aucune écriture, donc le contrôle « écritures » bloque', () => verifie('jeu2025', actives(ecr), 2025));
    test('brouillons validés : plus aucun blocage', () {
      verifie('valide2026', valides(actives(ecr)), 2026);
    });
    test('une ligne validée sans contrepartie : journal ET pièce déséquilibrés (RG-10)', () {
      final l = [
        {'id': 'X-DESEQ', 'numero': 'ODX', 'date': '2026-05-05', 'journal': 'OD', 'compte': '661100', 'debit': 5000, 'credit': 0, 'statut': 'validee'},
        ...valides(actives(ecr))
      ];
      verifie('desequilibre2026', l, 2026);
    });
    test('un à-nouveau déjà écrit sur N+1 BLOQUE : la clôture écrit les définitifs', () {
      final l = [
        {'id': 'X-AN', 'numero': 'AN-2027-00001', 'date': '2027-01-01', 'journal': 'AN', 'compte': '571000', 'debit': 100, 'credit': 0, 'statut': 'validee'},
        ...valides(actives(ecr))
      ];
      verifie('anExistant2026', l, 2026);
    });
    test('un compte d\'attente non soldé INFORME sans bloquer', () {
      final l = [
        {'id': 'X-47A', 'numero': 'OD47', 'date': '2026-05-05', 'journal': 'OD', 'compte': '471000', 'debit': 7000, 'credit': 0, 'statut': 'validee'},
        {'id': 'X-47B', 'numero': 'OD47', 'date': '2026-05-05', 'journal': 'OD', 'compte': '571000', 'debit': 0, 'credit': 7000, 'statut': 'validee'},
        ...valides(actives(ecr))
      ];
      verifie('compte47', l, 2026);
      expect(cpcPreCloture(l, 2026).bloquants, isEmpty);
    });
  });

  group('lectures d\'un exercice : soldes, résultat, à-nouveaux provisoires', () {
    final e26 = cpcEcrituresDe(valides(actives(ecr)), 2026);
    test('les écritures de l\'exercice : validées seulement par défaut', () {
      final n = carte(v['nbEcrituresBrut']);
      expect(cpcEcrituresDe(actives(ecr), 2026).length, n['validees'], reason: 'le jeu brut : 410 validées');
      expect(cpcEcrituresDe(actives(ecr), 2026, brouillons: true).length, n['avecBrouillons']);
      expect(n['validees'] != n['avecBrouillons'], true, reason: 'les brouillons ne sont pas des faits comptables');
      expect(cpcEcrituresDe(valides(actives(ecr)), 2026).length, carte(v['nbEcritures2026'])['validees']);
    });
    test('le résultat suit les classes 6, 7 et 8', () {
      expect(cpcResultatDe(cpcEcrituresDe(actives(ecr), 2026)), closeTo(carte(v['nbEcrituresBrut'])['resultat'] as num, 0.001));
      expect(cpcResultatDe(cpcEcrituresDe(valides(actives(ecr)), 2026)), closeTo(v['resultat2026'] as num, 0.001));
    });
    test('les soldes par compte, triés comme Object.keys().sort()', () {
      final att = liste(v['soldes2026']);
      final s = cpcSoldesParCompte(cpcEcrituresDe(valides(actives(ecr)), 2026));
      expect(s.length, att.length);
      for (var i = 0; i < s.length; i++) {
        expect([s[i]['compte'], s[i]['libelle'], s[i]['debit'], s[i]['credit'], s[i]['solde']], [att[i]['compte'], att[i]['libelle'], att[i]['debit'], att[i]['credit'], att[i]['solde']]);
      }
      expect(e26.isNotEmpty, true);
    });
    test('les à-nouveaux provisoires de 2027 sont calculés, jamais stockés ; 2026 n\'en a pas (2025 vient de la liasse)', () {
      final p = cpcANouveauxProvisoires(exo, valides(actives(ecr)), 2027);
      final att = liste(v['provisoires2027']);
      expect(p.length, att.length);
      for (var i = 0; i < p.length; i++) {
        expect([p[i]['compte'], p[i]['compteLibelle'], p[i]['debit'], p[i]['credit'], p[i]['lettrable'], p[i]['id'], p[i]['libelle']],
            [att[i]['compte'], att[i]['compteLibelle'], att[i]['debit'], att[i]['credit'], att[i]['lettrable'], att[i]['id'], att[i]['libelle']],
            reason: '$i');
      }
      expect(cpcANouveauxProvisoires(exo, actives(ecr), 2026), isEmpty);
      expect(liste(v['provisoires2026']), isEmpty);
    });
    test('un exercice précédent CLOS ne donne plus de provisoires (les définitifs existent)', () {
      final clos = [for (final x in exo) if (x['annee'] == 2026) {...x, 'etat': 'clos'} else x];
      expect(cpcANouveauxProvisoires(clos, actives(ecr), 2027), isEmpty);
    });
  });

  group('lettrage des tiers', () {
    final l = <F>[
      for (final x in [
        ['L1', '411100', 5000, 0],
        ['L2', '411100', 0, 5000],
        ['L3', '411100', 0, 3000],
        ['L4', '421000', 100, 0],
        ['L5', '411200', 0, 5000]
      ])
        {'id': x[0], 'numero': 'LT-${x[0]}', 'date': '2026-06-01', 'journal': 'OD', 'compte': x[1], 'debit': x[2], 'credit': x[3], 'statut': 'validee'}
    ];
    final r = carte(v['lettrage']);
    test('les refus sont nommés, comme à l\'écran', () {
      expect(cpcLettrer(l, '571000', ['L1', 'L2']).motif, carte(r['nonLettrable'])['motif']);
      expect(cpcLettrer(l, '411100', ['L1']).motif, carte(r['uneLigne'])['motif']);
      expect(cpcLettrer(l, '411100', ['L1', 'L5']).motif, carte(r['autreCompte'])['motif']);
      expect(cpcLettrer(l, '411100', ['L1', 'L3']).motif, carte(r['nonNul'])['motif']);
      expect(cpcLettrer(l, '411100', ['L1', 'ZZZ']).motif, carte(r['inconnue'])['motif']);
    });
    test('un ensemble qui s\'annule se lettre ; le code suit le nombre de codes DISTINCTS déjà posés', () {
      final ok = cpcLettrer(l, '411100', ['L1', 'L2']);
      expect([ok.ok, ok.code, ok.ids], [true, carte(r['valide'])['code'], ['L1', 'L2']]);
      final posees = [for (final x in l) if (x['id'] == 'L1' || x['id'] == 'L2') {...x, 'lettrage': 'A'} else x];
      expect(cpcLettrer(posees, '411100', ['L1', 'L2']).motif, carte(r['dejaLettree'])['motif']);
      final avecA = [...posees, {'id': 'L8', 'compte': '411100', 'debit': 50, 'credit': 0}, {'id': 'L9', 'compte': '411100', 'debit': 0, 'credit': 50}];
      expect(cpcLettrer(avecA, '411100', ['L8', 'L9']).code, 'B');
      expect(carte(r['second'])['code'], 'B');
    });
    test('dé-lettrer EXIGE un motif et un code existant', () {
      final posees = [for (final x in l) if (x['id'] == 'L1' || x['id'] == 'L2') {...x, 'lettrage': 'A'} else x];
      expect(cpcDelettrer(posees, '411100', 'A', '').motif, carte(r['delettrerSansMotif'])['motif']);
      expect(cpcDelettrer(posees, '411100', 'A', 'ab').motif, carte(r['delettrerCourt'])['motif']);
      expect(cpcDelettrer(posees, '411100', 'Z', 'Erreur de saisie').motif, carte(r['delettrerInconnu'])['motif']);
      final ok = cpcDelettrer(posees, '411100', 'A', 'Erreur de saisie');
      expect([ok.ok, ok.ids.length], [true, carte(r['delettrer'])['lignes']]);
    });
  });

  group('la clôture rejouée sur le vecteur de la maquette (jeu du poste, 30/10/2026)', () {
    final cl = carte(v['cloture']);
    final tout = valides(actives(ecr));
    final maintenant = auj;
    test('démarrer : mêmes refus nommés, mêmes états', () {
      expect(cpcDemarrerCloture(exo, tout, 2031, acteur: 'KASSA Augustin', role: 'comptable', maintenant: maintenant).motif, carte(cl['inconnue'])['motif']);
      expect(cpcDemarrerCloture(exo, tout, 2025, acteur: 'KASSA Augustin', role: 'comptable', maintenant: maintenant).motif, carte(cl['dejaClos'])['motif']);
      final d = cpcDemarrerCloture(exo, tout, 2026, acteur: 'KASSA Augustin', role: 'comptable', maintenant: maintenant);
      expect(d.ok, carte(cl['demande'])['ok']);
      expect(d.patch!['etat'], 'en_cloture');
    });
    test('clôturer : les refus nommés de la maquette, puis les pièces, le résultat et l\'équilibre', () {
      final enC = [for (final x in exo) if (x['annee'] == 2026) {...x, 'etat': 'en_cloture', 'demandePar': 'KASSA Augustin'} else x];
      CpcValidation val(List<F> e, int a, String motif, String role, String acteur) =>
          cpcValiderCloture(e, tout, a, motif: motif, acteur: acteur, role: role, maintenant: maintenant, toutesEcritures: tout);
      expect(carte(cl['validerRole'])['motif'], val(enC, 2026, 'Conforme', 'comptable', 'KASSA Augustin').motif);
      expect(carte(cl['validerDemandeur'])['motif'], val(enC, 2026, 'Conforme', 'direction', 'KASSA Augustin').motif);
      expect(carte(cl['validerSansMotif'])['motif'], val(enC, 2026, '', 'direction', 'BASSONGUI Chabi Séko').motif);
      expect(carte(cl['validerInconnue'])['motif'], val(enC, 2030, 'Conforme', 'direction', 'BASSONGUI Chabi Séko').motif);
      final r = val(enC, 2026, 'Exercice 2026 conforme', 'direction', 'BASSONGUI Chabi Séko');
      final att = carte(cl['valider']);
      expect(r.ok, true, reason: r.motif);
      expect(r.clNumero, att['clNumero']);
      expect(r.anNumero, att['anNumero']);
      expect(r.lignesCL.length, cl['nbCL']);
      expect(r.lignesAN.length, cl['nbAN']);
      expect(r.resultat, closeTo(att['resultat'] as num, 0.5));
      expect({for (final x in r.lignesAN) '${x['compte']}'[0]}.toList()..sort(), cl['classesAN']);
      expect(r.lignesCL.fold<num>(0, (a, x) => a + (x['debit'] as num) - (x['credit'] as num)).abs() < 1, true);
      expect(cl['equilibreCL'], 0);
      expect(r.patch!['clNumero'], carte(cl['fiche'])['clNumero']);
      expect(r.patch!['motif'], carte(cl['fiche'])['motif']);
      // l'archive a les mêmes quatre fichiers
      final apres = [...tout, ...r.lignesCL, ...r.lignesAN];
      final noms = [for (final x in cpcFichiersArchive(2026, {...enC.first, ...r.patch!}, apres)) x['nom']];
      expect(noms, liste(cl['archive']).first['fichiers']);
    });
  });

  group('les TROIS ÉTATS et la clôture par pièces CL et AN (arbitrage du 05/11/2026, scénarios 73 et 75 de la maquette)', () {
    F l(String num, String date, String compte, num d, num c, {String? centre, String statut = 'validee', String origine = 'Saisie manuelle'}) => {
          'id': '$num-$compte-$d-$c',
          'numero': num,
          'date': date,
          'journal': 'VTE',
          'compte': compte,
          'compteLibelle': 'Compte $compte',
          'libelle': 'Écriture; "test"',
          'debit': d,
          'credit': c,
          'statut': statut,
          'origine': origine,
          'centreCout': centre,
        };
    final journal = <F>[
      l('S30-1', '2030-03-01', '571000', 8000, 0),
      l('S30-1', '2030-03-01', '706000', 0, 8000, centre: 'laboratoire'),
      l('S30-2', '2030-04-01', '604100', 3000, 0, centre: 'pharmacie'),
      l('S30-2', '2030-04-01', '571000', 0, 3000),
    ];
    final ouvert = <F>[
      {'id': 'EXO-2030', 'annee': 2030, 'debut': '2030-01-01', 'fin': '2030-12-31', 'statut': 'actif', 'etat': 'ouvert', 'source': 'journal'}
    ];
    final maintenant = DateTime(2030, 12, 31, 9);
    List<F> enCloture({String par = 'Comptable Sonde'}) => [
          {...ouvert.first, 'etat': 'en_cloture', 'demandePar': par}
        ];

    test('démarrer : le comptable, la DAF et l\'administrateur ; un autre rôle, un exercice déjà en clôture ou de la liasse sont refusés en le nommant', () {
      final ok = cpcDemarrerCloture(ouvert, journal, 2030, acteur: 'Comptable Sonde', role: 'comptable', maintenant: maintenant);
      expect(ok.ok, true);
      expect(ok.patch!['etat'], 'en_cloture');
      expect(ok.patch!['demandePar'], 'Comptable Sonde');
      expect(cpcDemarrerCloture(ouvert, journal, 2030, acteur: 'Caissier', role: 'caissier', maintenant: maintenant).motif, contains('réservé au comptable'));
      expect(cpcDemarrerCloture(enCloture(), journal, 2030, acteur: 'X', role: 'comptable', maintenant: maintenant).motif, contains('déjà en clôture'));
      expect(cpcDemarrerCloture([{...ouvert.first, 'source': 'liasse', 'etat': 'clos'}], journal, 2030, acteur: 'X', role: 'comptable', maintenant: maintenant).motif, contains('liasse'));
    });

    test('reprendre la saisie : seulement depuis « en clôture », par ceux qui peuvent démarrer', () {
      expect(cpcReprendreSaisie(enCloture(), 2030, acteur: 'X', role: 'comptable', maintenant: maintenant).patch!['etat'], 'ouvert');
      expect(cpcReprendreSaisie(ouvert, 2030, acteur: 'X', role: 'comptable', maintenant: maintenant).motif, contains('rien à reprendre'));
      expect(cpcReprendreSaisie(enCloture(), 2030, acteur: 'X', role: 'caissier', maintenant: maintenant).motif, contains('réservé'));
    });

    test('la GARDE : en clôture, un module est refusé et le comptable passe son inventaire ; clôturé, même le comptable est refusé ; les pièces de clôture passent', () {
      final cl = enCloture();
      String? g(List<F> e, {String op = 'inserer', Object? origine, Object? cloture, String role = ''}) =>
          cpcGardeEcritures(e, '2030-05-01', op: op, origine: origine, origineCloture: cloture, role: role);
      expect(g(ouvert, origine: 'Automatique : Caisse'), isNull);
      expect(g(cl, origine: 'Automatique : Caisse', role: 'comptable'), contains('en clôture'));
      expect(g(cl, origine: 'Saisie manuelle', role: 'comptable'), isNull);
      expect(g(cl, origine: 'Saisie manuelle', role: 'da'), contains('en clôture'));
      final clos = [{...ouvert.first, 'etat': 'clos', 'valideLe': '2030-12-31T09:00:00Z'}];
      expect(g(clos, origine: 'Saisie manuelle', role: 'comptable'), contains('clôturé'));
      expect(g(clos, cloture: 'cl', role: ''), isNull, reason: 'une pièce de clôture s\'insère');
      expect(g(clos, op: 'modifier', cloture: 'cl'), contains('clôturé'), reason: 'mais ne se modifie jamais');
      expect(g(clos, op: 'archiver', cloture: 'an'), contains('clôturé'));
    });

    CpcValidation cloturer(List<F> exo, List<F> ecr, {String role = 'da', String acteur = 'Direction Sonde', String motif = 'Clôture de la sonde'}) =>
        cpcValiderCloture(exo, ecr, 2030, motif: motif, acteur: acteur, role: role, maintenant: maintenant, toutesEcritures: ecr);

    test('clôturer : refus nommés (rôle, motif, même personne, exercice pas en clôture, contrôles bloquants)', () {
      expect(cloturer(enCloture(), journal, role: 'comptable').motif, contains('Direction ou la Directrice'));
      expect(cloturer(enCloture(), journal, motif: '').motif, contains('motif'));
      expect(cloturer(enCloture(), journal, acteur: 'Comptable Sonde').motif, contains('autre personne'));
      expect(cloturer(ouvert, journal).motif, contains('n’est pas en clôture'));
      final brouillon = [...journal, l('S30-B', '2030-06-01', '706000', 0, 5, statut: 'brouillon')];
      expect(cloturer(enCloture(), brouillon).motif, contains('Contrôles bloquants en échec'));
    });

    test('clôturer : la pièce CL (31/12, journal CL) est équilibrée CENTRE par centre, contrepartie en 131 ; la pièce AN (01/01) ne reporte que les classes 1 à 5', () {
      final r = cloturer(enCloture(), journal);
      expect(r.ok, true, reason: r.motif);
      expect(r.clNumero, 'CL-2030-00001');
      expect(r.anNumero, 'AN-2031-00001');
      expect(r.lignesCL.every((x) => x['journal'] == 'CL' && x['date'] == '2030-12-31' && x['origineCloture'] == 'cl'), true);
      final parCentre = <String, double>{};
      for (final x in r.lignesCL) {
        parCentre['${x['centreCout'] ?? ''}'] = (parCentre['${x['centreCout'] ?? ''}'] ?? 0) + (x['debit'] as num) - (x['credit'] as num);
      }
      expect(parCentre.keys.length, greaterThanOrEqualTo(2));
      expect(parCentre.values.every((v) => v.abs() < 1), true, reason: 'chaque centre de coûts est équilibré');
      expect(r.lignesCL.any((x) => x['compte'] == '131000' && (x['credit'] as num) > 0), true, reason: 'bénéfice au 131');
      expect(r.lignesAN.isNotEmpty && r.lignesAN.every((x) => x['journal'] == 'AN' && x['date'] == '2031-01-01' && '12345'.contains('${x['compte']}'[0])), true);
      expect(r.lignesAN.fold<num>(0, (a, x) => a + (x['debit'] as num) - (x['credit'] as num)).abs() < 1, true);
      expect(r.patch!['etat'], 'clos');
      expect(r.patch!['clNumero'], 'CL-2030-00001');
      expect(r.exerciceSuivant!['annee'], 2031);
      expect(r.cloture!['type'], 'cloture');
    });

    test('le compte de résultat vient de la TABLE paramétrable, pas du code', () {
      final table = [
        {'sens': 'benefice', 'compte': '131500', 'libelle': 'Bénéfice paramétré', 'statut': 'actif'},
        {'sens': 'perte', 'compte': '139500', 'libelle': 'Perte paramétrée', 'statut': 'actif'}
      ];
      expect(cpcCompteResultatDe(100, table).compte, '131500');
      expect(cpcCompteResultatDe(-1, table).compte, '139500');
      expect(cpcCompteResultatDe(100).compte, '131000');
      final r = cpcValiderCloture(enCloture(), journal, 2030,
          motif: 'ok ok', acteur: 'Direction Sonde', role: 'da', maintenant: maintenant, toutesEcritures: journal, comptesResultat: table);
      expect(r.lignesCL.any((x) => x['compte'] == '131500'), true);
    });

    test('ATOMICITÉ : des à-nouveaux déséquilibrés (une ligne lettrée seule) refusent la clôture et ne laissent rien derrière eux', () {
      final orphelin = [...journal, {...l('S30-O', '2030-06-01', '411000', 100, 0), 'lettrage': 'Z'}, l('S30-O', '2030-06-01', '706000', 0, 100, centre: 'laboratoire')];
      final r = cloturer(enCloture(), orphelin);
      expect(r.ok, false);
      expect(r.motif, contains('déséquilibrés'));
      expect(r.motif, contains('rien n’a été écrit'));
      expect(r.lignesCL, isEmpty);
      expect(r.patch, isNull);
    });

    test('le journal CL est EXCLU des états de N : le résultat de l\'année n\'est pas zéro après la clôture', () {
      final r = cloturer(enCloture(), journal);
      final apres = [...journal, ...r.lignesCL];
      expect(cpcResultatDe(cpcEcrituresDe(apres, 2030)), cpcResultatDe(cpcEcrituresDe(journal, 2030)));
      expect(cpcResultatDe(cpcEcrituresDe(journal, 2030)), 5000);
      expect(cpcResultatDe(cpcEcrituresDe(apres, 2030, avecCL: true)).abs() < 1, true, reason: 'avec CL, les classes 6 à 8 sont soldées');
    });

    test('rouvrir : le comptable seul, motif de dix caractères, jamais la liasse, jamais si N+1 n\'est plus ouvert ; CL et AN sont CONTRE-PASSÉES', () {
      final r = cloturer(enCloture(), journal);
      final apres = [...journal, ...r.lignesCL, ...r.lignesAN];
      final clos = [
        {...ouvert.first, ...r.patch!},
        r.exerciceSuivant!
      ];
      CpcReouverture rouvrir({String role = 'comptable', String motif = 'Erreur de caisse découverte', List<F>? exo}) =>
          cpcRouvrirExercice(exo ?? clos, apres, 2030, motif: motif, acteur: 'Comptable Sonde', role: role, maintenant: maintenant, toutesEcritures: apres);
      expect(rouvrir(role: 'da').motif, contains('réservée au comptable'));
      expect(rouvrir(motif: 'trop bref').motif, contains('dix caractères'));
      expect(rouvrir(motif: 'dix carac.').ok, true, reason: 'dix caractères exactement passent');
      expect(rouvrir(exo: [{...clos.first, 'source': 'liasse'}, clos.last]).motif, contains('liasse'));
      expect(rouvrir(exo: [clos.first, {...clos.last, 'etat': 'en_cloture'}]).motif, contains('2031'));
      expect(cpcRouvrirExercice(ouvert, journal, 2030, motif: 'Erreur de caisse découverte', acteur: 'X', role: 'comptable', maintenant: maintenant).motif, contains('n’est pas clôturé'));
      final ok = rouvrir();
      expect(ok.ok, true, reason: ok.motif);
      expect(ok.pieces, ['CL-2030-C00002', 'AN-2031-C00002']);
      expect(ok.patch!['etat'], 'en_cloture');
      expect(ok.cloture!['type'], 'reouverture');
      // contre-passation : somme (pièce d'origine + contre-passation) nulle, compte par compte et centre par centre ; rien n'est effacé
      final net = <String, double>{};
      for (final x in [...r.lignesCL, ...ok.lignes.where((z) => z['journal'] == 'CL')]) {
        final k = '${x['compte']}|${x['centreCout'] ?? ''}';
        net[k] = (net[k] ?? 0) + (x['debit'] as num) - (x['credit'] as num);
      }
      expect(net.isNotEmpty && net.values.every((v) => v.abs() < 1), true);
      expect(ok.lignes.every((x) => x['contrePasseDe'] != null), true);
      // une seconde clôture est possible sous de NOUVEAUX numéros (les à-nouveaux contre-passés ne comptent plus comme « déjà écrits »)
      final reOuvert = [...apres, ...ok.lignes];
      final enC = [
        {...clos.first, ...ok.patch!, 'demandePar': 'Comptable Sonde'},
        clos.last
      ];
      final second = cpcValiderCloture(enC, reOuvert, 2030,
          motif: 'Seconde clôture', acteur: 'Direction Sonde', role: 'da', maintenant: maintenant, toutesEcritures: reOuvert);
      expect(second.ok, true, reason: second.motif);
      expect(second.clNumero, 'CL-2030-00003');
      expect(second.anNumero, 'AN-2031-00003');
    });

    test('l\'ARCHIVE : quatre fichiers, CSV SYSCOHADA (BOM, onze colonnes, JJ/MM/AAAA), manifeste, empreintes ; un fichier altéré est refusé au téléchargement', () {
      final r = cloturer(enCloture(), journal);
      final apres = [...journal, ...r.lignesCL];
      final fichiers = cpcFichiersArchive(2030, {...ouvert.first, ...r.patch!}, apres);
      expect(fichiers.map((f) => f['nom']), ['ecritures-2030.csv', 'balance-2030.csv', 'etats-2030.html', 'manifeste-2030.txt']);
      final csv = '${fichiers.first['contenu']}';
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv.substring(1).split('\r\n').first, cpcEnteteEcritures.join(';'));
      expect(cpcEnteteEcritures.length, 11);
      expect(csv.split('\r\n')[1].split(';')[1], matches(RegExp(r'^\d{2}/\d{2}/2030$')));
      expect(csv, contains('"Écriture; ""test"""'), reason: 'séparateur et guillemets échappés');
      expect(fichiers.every((f) => f['empreinte'] == cpcSha256('${f['contenu']}')), true);
      final man = '${fichiers.last['contenu']}';
      expect(fichiers.take(3).every((f) => man.contains('${f['empreinte']}  ${f['nom']}')), true);
      final archive = {'reference': 'ARC-2030-01', 'annee': 2030, 'fichiers': fichiers};
      expect(cpcLireArchive([archive], 'ARC-2030-01', 'ecritures-2030.csv').ok, true);
      expect(cpcLireArchive([archive], 'ARC-2030-01', 'absent.csv').motif, contains('ne figure pas'));
      expect(cpcLireArchive([], 'ARC-2030-01', 'x').motif, contains('introuvable'));
      final alteree = {
        ...archive,
        'fichiers': [
          {...fichiers.first, 'contenu': '${fichiers.first['contenu']}x'},
          ...fichiers.skip(1)
        ]
      };
      final refus = cpcLireArchive([alteree], 'ARC-2030-01', 'ecritures-2030.csv');
      expect([refus.ok, refus.altere], [false, true]);
      expect(refus.motif, contains('altéré'));
    });

    test('l\'archive et le registre des clôtures sont IMMUABLES : modifier, archiver, redéposer sont refusés', () {
      expect(cpcGardeArchives([{'reference': 'ARC-2030-01'}], 'inserer', 'ARC-2030-01'), contains('jamais régénérée'));
      expect(cpcGardeArchives([{'reference': 'ARC-2030-01'}], 'inserer', 'ARC-2030-02'), isNull);
      expect(cpcGardeArchives([], 'modifier', 'x'), contains('immuable'));
      expect(cpcGardeArchives([], 'archiver', 'x'), contains('immuable'));
      expect(cpcGardeClotures('inserer'), isNull);
      expect(cpcGardeClotures('modifier'), contains('piste d’audit'));
      expect(cpcVersionCloture([{'annee': 2030, 'type': 'cloture'}, {'annee': 2030, 'type': 'reouverture'}, {'annee': 2030, 'type': 'cloture'}], 2030), 2);
      expect(cpcReferenceArchive(2030, 2), 'ARC-2030-02');
    });

    test('le choix d\'exercice : défaut = ouvert le plus récent ; voisins absents aux bornes ; dates relatives depuis le dernier jour de l\'exercice consulté', () {
      final exos = [
        {'annee': 2025, 'etat': 'clos', 'statut': 'actif', 'source': 'liasse'},
        {'annee': 2026, 'etat': 'ouvert', 'statut': 'actif'},
        {'annee': 2027, 'etat': 'ouvert', 'statut': 'actif'}
      ];
      final auj = DateTime(2026, 8, 16);
      expect(cpcExerciceParDefaut(exos, auj), 2027);
      expect(cpcExerciceParDefaut([exos.first], auj), 2025, reason: 'aucun ouvert : le plus récent tout court');
      expect(cpcExerciceChoisi(exos, 2025, auj), 2025);
      expect(cpcExerciceChoisi(exos, 1999, auj), 2027, reason: 'un choix inconnu retombe sur le défaut');
      expect(cpcExerciceVoisin(exos, 2025, -1), isNull);
      expect(cpcExerciceVoisin(exos, 2025, 1), 2026);
      expect(cpcExerciceVoisin(exos, 2027, 1), isNull);
      expect(cpcDateReference(2025, auj), DateTime(2025, 12, 31));
      expect(cpcDateReference(2026, auj), auj);
    });
  });

  group('bilan d\'ouverture : seules les classes 1 à 5 se reportent', () {
    final o = carte(v['ecranOuverture']);
    final actif = actives(ecr);
    test('les comptes reportés, leurs soldes et le résultat qui équilibre — comme l\'écran', () {
      final s = cpcSoldesDeCloture(actif, 2026);
      final t = carte(liste(carte(o['initial'])['tables']).first);
      final lignes = liste(t['lignes']);
      final res = cpcLignesOuverture(s, 2026);
      expect(res.length, lignes.length);
      for (var i = 0; i < res.length; i++) {
        final cel = (lignes[i]['cellules'] as List).cast<String>();
        final solde = res[i]['solde'] as double;
        expect([res[i]['compte'], res[i]['libelle'], solde > 0 ? nt(money(solde, avecDevise: false)) : '', solde < 0 ? nt(money(-solde, avecDevise: false)) : ''], cel.map(nt).toList());
      }
      expect(s.comptes.length, 8);
      expect(s.equilibre, true);
      expect(nt(money(s.totalDebiteurs)), nt(carte(liste(carte(o['initial'])['kpis'])[1])['valeur']));
      expect(nt(money(s.totalCrediteurs)), nt(carte(liste(carte(o['initial'])['kpis'])[2])['valeur']));
      expect(nt(money(s.resultat)), nt(carte(liste(carte(o['initial'])['kpis'])[3])['valeur']));
    });
    test('le report écrit une pièce en BROUILLON, au journal AN, avec le résultat au compte 131000 (bénéfice) ou 139000 (perte), un seul compte de résultat (E813)', () {
      final s = cpcSoldesDeCloture(actif, 2026);
      final r = cpcReporterANouveaux(s, 2026, dejaEcrits: 0);
      expect(r.ok, true);
      expect(r.numero, 'AN-2027-00001');
      final ins = liste(carte(carte(o['ecart'])['inserts'])['ecritures']);
      expect(r.lignes.map(cle).toList()..sort(), ins.map(cle).toList()..sort());
      expect(r.lignes.every((l) => l['statut'] == 'brouillon' && l['journal'] == 'AN'), true);
      expect(r.lignes.last['compte'], s.resultat >= 0 ? '131000' : '139000');
      expect(cpcCompteResultat(-1), '139000');
      expect(cpcCompteResultat(0), '131000');
    });
    test('REFUSÉ s\'il ne s\'équilibre pas (RG-10), REFUSÉ une seconde fois (double report) — avec les mots de l\'écran', () {
      final deseq = [
        {'id': 'X-DESEQ', 'numero': 'ODX', 'date': '2026-05-05', 'journal': 'OD', 'compte': '571000', 'compteLibelle': 'Caisse', 'debit': 5000, 'credit': 0, 'statut': 'validee'},
        ...actif
      ];
      final s = cpcSoldesDeCloture(deseq, 2026);
      expect(s.equilibre, false);
      final r = cpcReporterANouveaux(s, 2026, dejaEcrits: 0);
      expect(r.ok, false);
      final att = liste(o['deseqRefus']).first;
      expect([r.message, r.detail], [att['message'], att['detail']]);
      final dbl = cpcReporterANouveaux(cpcSoldesDeCloture(actif, 2026), 2026, dejaEcrits: 9);
      expect(dbl.ok, false);
      expect([dbl.message, dbl.detail], [liste(o['secondReport']).first['message'], liste(o['secondReport']).first['detail']]);
    });
  });

  test('les écrans « à année » : M12 et la liste nommée ; jamais les écrans du jour ni les tableaux de bord (miroir de N.aExercice)', () {
    expect(cpcAExercice('m12-balance', 'M12'), true);
    expect(cpcAExercice('m12-cloture', 'M12'), true);
    expect(cpcAExercice('m12-ouverture', 'M12'), false);
    expect(cpcAExercice('m12-dashboard', 'M12'), false);
    expect(cpcAExercice('mecef-factures', 'MECEF'), true);
    expect(cpcAExercice('m8-caisse', 'M8'), false);
    expect(cpcAExercice('m8-factures', 'M8'), true);
    expect(cpcAExercice('dash-da', 'DASH'), false);
    expect(cpcAExercice('hub-m12', 'M12'), false);
    expect(cpcAExercice('m6-point-ventes', 'M6'), false);
    expect(cpcAExercice('', 'M12'), false);
  });

  test('la table des comptes de résultat : refus nommés, miroir du scénario 76 de la maquette', () {
    final ben = {'sens': 'benefice'}, per = {'sens': 'perte'};
    expect(cpcControleCompteResultat(ben, compte: '13100', libelle: 'Bénéfice'), contains('six chiffres'));
    expect(cpcControleCompteResultat(ben, compte: '139000', libelle: 'Bénéfice'), contains('131'));
    expect(cpcControleCompteResultat(per, compte: '131000', libelle: 'Perte'), contains('139'));
    expect(cpcControleCompteResultat(ben, compte: '131000', libelle: ' '), contains('libellé'));
    expect(cpcControleCompteResultat(ben, compte: '131500', libelle: 'Bénéfice paramétré'), isNull);
    expect(cpcControleCompteResultat(per, compte: '139000', libelle: 'Résultat net : perte'), isNull);
  });
}
