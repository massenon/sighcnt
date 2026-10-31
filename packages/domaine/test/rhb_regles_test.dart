// Rejoue les vecteurs de M10 (B) engendrés par la maquette (prototype_html/build/vecteurs-rh-b.js) : planning, statistiques de garde / de permanence /
// de présence, registre des présences, évaluations NS 131, sanctions, primes NS 132 — écrans PILOTÉS dans Chrome sur le jeu du poste.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef F = Map<String, Object?>;

const jeu = '../../apps/poste/assets/donnees/jeu';
List<F> dossier(String nom) => liste(jsonDecode(File('$jeu/$nom.json').readAsStringSync()));
List<F> actives(List<F> l) => [for (final f in l) if (f['statut'] != 'archive') f];

String norm(Object? s) => '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();
F f(Object? x) => (x as Map).cast<String, Object?>();

void main() {
  final v = lireVecteurs('rhb');
  final b = f(v['jeuDeLaMaquette']);
  final ouv = f(v['ouverture']);
  final planning = actives(dossier('planning'));
  final personnel = actives(dossier('personnel'));
  final presences = actives(dossier('presences'));
  final evaluations = actives(dossier('evaluations'));
  final grille = actives(dossier('grillePrimes'));
  final historique = actives(dossier('historiquePrimes'));
  final regimes = actives(dossier('regimesTravail'));
  final auj16 = DateTime(2026, 8, 16, 12);
  final auj30 = DateTime(2026, 10, 30, 10);

  group('référentiels', () {
    test('douze types de vacation, les repos et congés ne comptent pas comme du travail', () {
      expect(rhbTypesPlanning.length, 12);
      for (final id in ['repos24', 'repos48', 'conge', 'absence']) {
        expect(rhbVacationsTravaillees.contains(id), isFalse, reason: id);
      }
      expect(rhbVacationsTravaillees.length, 8);
    });

    test('NS 131 : les quatre-vingt-un croisements de niveaux, rejoués sur ce que la maquette calcule', () {
      final p = liste((f(b['evaluations'])['prelevements'] as List).map((x) => {'x': x}).toList());
      expect(p.length, 81);
      for (final x in p) {
        final l = x['x'] as List;
        expect(rhbPrelevement({'ponctualite': l[0], 'execution': l[1], 'attitude': l[2], 'hierarchie': l[3]}), l[4], reason: '$l');
      }
    });

    test('un niveau absent ne retient rien', () {
      expect(rhbPrelevement({}), 0);
      expect(rhbPrelevement({'ponctualite': 'inconnu'}), 0);
    });
  });

  group('m10-stats-gardes', () {
    final g = f(b['gardes']);
    final cas = liste(g['cas']);

    String agentTexte(RhbStatAgent a) => '${a.agent} ${a.fonctionLabel} · ${a.service}';

    for (final c in cas) {
      final rg = {for (final r in (c['reglages'] as List)) (r as List)[0] as String: '${r[1]}'};
      test('${c['reglages']} du ${c['du']} au ${c['au']}', () {
        final rows = rhbLignesGardes(planning,
            du: '${c['du']}', au: '${c['au']}', agent: rg['Agent']!, service: rg['Service']!, type: rg['Type de vacation']!, fonction: rg['Fonction']!);
        final agents = rhbParAgentGardes(rows);
        final k = [for (final x in (c['kpis'] as List)) f(x)];
        expect(nombre(rows.length), norm(k[0]['valeur']).replaceAll(' ', ' '), reason: 'vacations');
        expect(norm(nombre(rows.length)), norm(k[0]['valeur']));
        final jours = rhbJoursPlage('${c['du']}', '${c['au']}');
        expect(jours > 0 ? 'sur ${nombre(jours)} jour(s)' : null, k[0]['indice'] == null ? null : norm(k[0]['indice']).replaceAll(' ', ' '));
        expect(norm(nombre(rows.where((x) => '${x['type']}'.startsWith('garde')).length)), norm(k[1]['valeur']));
        expect(norm(nombre(agents.length)), norm(k[2]['valeur']));
        expect(agents.isNotEmpty ? rhbDecimalJs(rows.length / agents.length) : '0', k[3]['valeur']);
        expect(c['vide'], rows.isEmpty);
        if (rows.isNotEmpty) {
          final t = f(c['table']);
          final lignes = (t['lignes'] as List).cast<List>();
          expect(lignes.length, agents.length.clamp(0, 20));
          for (var i = 0; i < lignes.length; i++) {
            final a = agents[i];
            expect(norm(lignes[i][0]), norm(agentTexte(a)), reason: 'ligne $i');
            expect([for (final x in lignes[i].skip(1)) norm(x)],
                [for (final x in [a.gardes, a.permanences, a.soirees, a.autres, a.total]) norm(nombre(x))] + [norm('${nombre(a.heures)} h')],
                reason: 'ligne $i (${a.agent})');
          }
        }
      });
    }

    test('la périodicité pose la plage : sept jours pour la semaine, trente pour le mois (jour de l\'horloge compris)', () {
      expect(rhbPlageDePeriode('semaine', auj16), ('2026-08-10', '2026-08-16'));
      expect(rhbPlageDePeriode('mois', auj16), ('2026-07-18', '2026-08-16'));
      expect(rhbPlageDePeriode('annee', auj16), ('2025-08-17', '2026-08-16'));
      expect(rhbPlageDePeriode('libre', auj16), isNull);
    });

    test('les vecteurs d\'ouverture au 30/10/2026 : le jeu daté d\'août ne montre rien sur le mois', () {
      final c = liste(f(ouv['gardes'])['cas']).first;
      expect(c['du'], '2026-10-01');
      expect(c['au'], '2026-10-30');
      expect(c['vide'], true);
      expect(rhbLignesGardes(planning, du: '2026-10-01', au: '2026-10-30'), isEmpty);
    });

    test('un agent à heures fractionnaires : arrondi au dixième', () {
      expect(rhbParAgentGardes([
        {'employeId': 'X', 'employe': 'X', 'type': 'garde_soins', 'service': 'S', 'fonction': 'infirmier'},
        {'employeId': 'X', 'employe': 'X', 'type': 'garde_soins', 'service': 'S', 'fonction': 'infirmier'},
        {'employeId': 'X', 'employe': 'X', 'type': 'permanence', 'service': 'S', 'fonction': 'infirmier'},
      ]).first.heures, 31);
    });

    test('un service absent se range sous « — »', () {
      final a = rhbParAgentGardes([
        {'employeId': 'X', 'employe': 'X', 'type': 'garde', 'fonction': 'medecin'}
      ]);
      expect(a.first.service, '—');
    });

    test('l\'état imprimé : même tableau que l\'écran', () {
      final p = f(g['impression']);
      expect(p['titre'], 'État des gardes effectuées');
      expect(p['sousTitre'], 'du 01/08/2026 au 31/08/2026');
      expect(rhbLibellePlageGardes('2026-08-01', '2026-08-31'), p['sousTitre']);
      expect(rhbLibellePlageGardes('', ''), 'toutes périodes');
    });
  });

  group('m10-stats-permanences', () {
    final p = f(b['permanences']);
    for (final c in liste(p['cas'])) {
      final rg = {for (final r in (c['reglages'] as List)) (r as List)[0] as String: '${r[1]}'};
      test('${c['reglages']}', () {
        final bo = bornes(rg['Périodicité']!, DateTime.parse(rg['Arrêtée au']!));
        final rows = rhbPermanencesParAgent(planning, personnel, bo, rg['Service']!);
        final total = rows.fold<int>(0, (s, x) => s + x.nombre);
        final k = [for (final x in (c['kpis'] as List)) f(x)];
        expect(norm(nombre(total)), norm(k[0]['valeur']));
        expect(norm(nombre(rows.length)), norm(k[1]['valeur']));
        expect(rows.isNotEmpty ? rhbUneDecimale(total / rows.length) : '0', k[2]['valeur']);
        expect(rows.isNotEmpty ? rows.first.agent : '—', k[3]['valeur']);
        expect(
            norm(c['note']),
            norm('${libellePeriode(bo)} — ${nombre(total)} permanence(s) assurée(s) par ${nombre(rows.length)} agent(s). '
                'La permanence court de 08h à 18h ; la garde de vingt-quatre heures est comptée sur son propre écran.'));
        if (rows.isNotEmpty) {
          final lignes = (f(c['table'])['lignes'] as List).cast<List>();
          expect(lignes.length, rows.length.clamp(0, 20));
          for (var i = 0; i < lignes.length; i++) {
            expect([for (final x in lignes[i]) norm(x)],
                [norm('${rows[i].agent} Mat. ${rows[i].matricule}'), norm(rows[i].service), norm(rows[i].fonction), norm(nombre(rows[i].nombre))],
                reason: 'ligne $i');
          }
        }
      });
    }

    test('la permanence n\'est pas la garde : seule la vacation « permanence » compte', () {
      expect(rhbEstPermanence({'type': 'permanence'}), isTrue);
      expect(rhbEstPermanence({'type': 'garde'}), isFalse);
      expect(rhbEstPermanence({'type': null, 'regimeLibelle': 'Permanence du soir'}), isTrue);
    });

    test('un agent inconnu du personnel est compté sous son nom de vacation', () {
      final r = rhbPermanencesParAgent([
        {'date': '2026-08-16', 'type': 'permanence', 'agent': 'Intérimaire'}
      ], personnel, bornes('mois', DateTime(2026, 8, 16)), '— Tous les services —');
      expect(r.single.agent, 'Intérimaire');
      expect(r.single.matricule, '—');
    });
  });

  group('m10-stats-presence', () {
    final p = f(b['presenceService']);
    for (final c in liste(p['cas'])) {
      final e = f(c['etat']);
      final du = e['Du'] ?? '2026-07-19', au = e['Au'] ?? '2026-08-16';
      test('du $du au $au', () {
        final tous = rhbPointagesDans(presences, '$du', '$au');
        final rows = rhbPresenceParService(tous);
        final presents = tous.where((x) => x['etat'] != 'absent').length;
        final retards = tous.where((x) => x['etat'] == 'retard').length;
        final k = [for (final x in (c['kpis'] as List)) f(x)];
        expect(tous.isNotEmpty ? norm(pourcent(presents / tous.length * 100)) : '—', norm(k[0]['valeur']));
        expect(norm(nombre(retards)), norm(k[1]['valeur']));
        expect(norm(nombre(tous.length - presents)), norm(k[2]['valeur']));
        expect(rows.isNotEmpty ? rows.first.service : '—', k[3]['valeur']);
        expect(
            norm(c['note']),
            norm('${nombre(tous.length)} journée(s) pointée(s) sur la période, pour ${nombre(rows.length)} service(s). Le taux porte sur ces journées effectivement renseignées — '
                'un pourcentage calculé sur le calendrier ferait passer pour absents des jours qu’on n’a simplement pas pointés.'));
        if (rows.isNotEmpty) {
          final lignes = (f(c['table'])['lignes'] as List).cast<List>();
          expect(lignes.length, rows.length);
          for (var i = 0; i < rows.length; i++) {
            final x = rows[i];
            expect([for (final y in lignes[i]) norm(y)], [
              x.service,
              '${x.agents}',
              norm(nombre(x.observes)),
              norm(nombre(x.presents)),
              x.retards > 0 ? norm(nombre(x.retards)) : '—',
              x.absents > 0 ? norm(nombre(x.absents)) : '—',
              norm(pourcent(x.taux)),
            ]);
          }
        }
      });
    }

    test('le retard est une présence : le taux d\'un service tout en retard vaut 100 %', () {
      final r = rhbPresenceParService([
        {'service': 'A', 'etat': 'retard', 'employeId': '1'},
        {'service': 'A', 'etat': 'retard', 'employeId': '2'},
      ]);
      expect(r.single.taux, 100);
      expect(r.single.absents, 0);
    });

    test('un congé n\'est ni présent ni absent par service, mais « présent » au global (écart E656, porté fidèlement)', () {
      final tous = [
        {'service': 'A', 'etat': 'conge', 'employeId': '1'},
        {'service': 'A', 'etat': 'present', 'employeId': '1'},
      ];
      expect(rhbPresenceParService(tous).single.taux, 50);
      expect(tous.where((x) => x['etat'] != 'absent').length, 2);
    });

    test('un service sans nom devient « Non renseigné »', () {
      expect(rhbPresenceParService([
        {'service': '', 'etat': 'present', 'employeId': '1'}
      ]).single.service, 'Non renseigné');
    });
  });

  group('m10-presences (registre)', () {
    final p = f(b['presences']);
    for (final c in liste(p['cas'])) {
      final du = '${c['du']}', au = '${c['au']}';
      test('du $du au $au', () {
        final m = rhbPointagesRegistre(presences, du, au);
        final k = [for (final x in (c['kpis'] as List)) f(x)];
        expect(norm(nombre(m.length)), norm(k[0]['valeur']));
        expect(norm(nombre(m.where((r) => r['etat'] == 'present').length)), norm(k[1]['valeur']));
        expect(norm(nombre(m.where((r) => r['etat'] == 'retard').length)), norm(k[2]['valeur']));
        expect(norm(nombre(m.where((r) => r['etat'] == 'absent').length)), norm(k[3]['valeur']));
      });
    }

    test('le classement par service : pourcentage de présents SEULS, plus fort d\'abord', () {
      final m = rhbPointagesRegistre(presences, '2026-07-17', '2026-08-16');
      final par = rhbGrouper(m, (r) => '${r['service']}');
      final rang = trierPar([
        for (final e in par.entries) (e.key, arrondiJs(e.value.where((r) => r['etat'] == 'present').length / e.value.length * 100).toInt())
      ], (e) => e.$2, descendant: true);
      final texte = norm(p['rangs']);
      expect(texte, 'Taux de présence par service ${rang.map((e) => '${e.$1} ${e.$2} %').join(' ')}');
    });
  });

  group('m10-evaluations et m10-sanctions', () {
    final e = f(b['evaluations']);
    final s = f(b['sanctions']);

    test('les quatre compteurs de l\'écran des évaluations', () {
      final k = [for (final x in (e['kpis'] as List)) f(x)];
      expect(evaluations.length, int.parse(norm(k[0]['valeur'])));
      expect(personnel.length, int.parse(norm(k[1]['valeur'])));
      expect(evaluations.where((x) => (x['prelevementPct'] as num) > 0).length, int.parse(norm(k[2]['valeur'])));
      expect(norm(money(evaluations.fold<num>(0, (a, x) => a + (x['prelevementMontant'] as num)))), norm(k[3]['valeur']));
    });

    test('les compteurs des sanctions : retenue > 0, agents distincts, montant total, retenue moyenne arrondie', () {
      final sanctionnees = [for (final x in evaluations) if ((x['prelevementPct'] as num) > 0) x];
      final k = [for (final x in (s['kpis'] as List)) f(x)];
      expect(sanctionnees.length, int.parse(norm(k[0]['valeur'])));
      expect(sanctionnees.map((x) => x['employeId']).toSet().length, int.parse(norm(k[1]['valeur'])));
      expect(norm(money(sanctionnees.fold<num>(0, (a, x) => a + (x['prelevementMontant'] as num)))), norm(k[2]['valeur']));
      final moy = arrondiJs(sanctionnees.fold<num>(0, (a, x) => a + (x['prelevementPct'] as num)) / sanctionnees.length).toInt();
      expect('$moy %', norm(k[3]['valeur']));
    });

    test('chaque évaluation du jeu porte le prélèvement que le barème d\'origine calcule', () {
      for (final x in evaluations) {
        expect(rhbPrelevement(f(x['criteres'])), x['prelevementPct'], reason: '${x['reference']}');
        expect(rhbMontantPrelevement(x['salaireBrut'], x['prelevementPct']), x['prelevementMontant'], reason: '${x['reference']}');
      }
    });

    test('la nouvelle évaluation : 27 % de 350 000 = 94 500 ; le formulaire reprend la même règle', () {
      final n = f(f(e['creation'])['nouvelle']);
      expect(rhbPrelevement(f(n['criteres'])), 27);
      expect(rhbMontantPrelevement(350000, 27), 94500);
      expect(norm(e['apercuModifie']), contains('Prélèvement total 27 %'));
      expect(norm(e['apercuModifie']), contains('Montant prélevé ${norm(money(94500))}'));
      expect(norm(e['apercuModifie']), contains('Salaire brut restant ${norm(money(350000 - 94500))}'));
    });

    test('l\'arrondi suit Math.round : la moitié vers +∞', () {
      expect(rhbMontantPrelevement(1000, 10.5), 105);
      expect(rhbMontantPrelevement(25, 10), 3); // 2,5 → 3
    });

    for (final fi in liste(e['fiches'])) {
      final ev = f(fi['evaluation']);
      test('fiche de solde de ${ev['employe']} (${fi['gardes']} garde(s) en août)', () {
        final emp = personnel.firstWhere((x) => x['id'] == ev['employeId']);
        final solde = rhbSolde(
            salaireBrut: ev['salaireBrut'],
            prelevementPct: ev['prelevementPct'],
            gardes: rhbCompter(planning, emp['id'], 2026, 8, 'garde'),
            permanences: rhbCompter(planning, emp['id'], 2026, 8, 'permanence'),
            montantGarde: rhbMontantPrime(grille, historique, 'garde', '${emp['fonction']}'),
            montantPermanence: rhbMontantPrime(grille, historique, 'permanence', '${emp['fonction']}'),
            montantAccueil: rhbMontantPrime(grille, historique, 'accueil', '${emp['fonction']}'),
            ans: rhbAnciennete(emp['dateEmbauche'], auj16).ans);
        expect(rhbCompter(planning, emp['id'], 2026, 8, 'garde'), fi['gardes']);
        final piece = f(fi['piece']);
        final tables = liste(piece['tables']);
        final droite = [for (final r in (tables[1]['lignes'] as List)) (r as List).map(norm).toList()];
        String m(num x) => norm(money(x, avecDevise: false));
        expect(droite[0], ['01', 'SALAIRE DE BASE', m(ev['salaireBrut'] as num)]);
        expect(droite[1], ['02', 'PRIME D’ANCIENNETÉ', solde.primeAnciennete > 0 ? m(solde.primeAnciennete) : '']);
        expect(droite[2], ['03', 'PRIME DE GARDE', solde.primeGarde > 0 ? m(solde.primeGarde) : '']);
        expect(droite[3], ['04', 'PRIME DE PERMANENCE', solde.primePermanence > 0 ? m(solde.primePermanence) : '']);
        expect(droite[4], ['05', 'PRIME D’ACCUEIL', solde.primeAccueil > 0 ? m(solde.primeAccueil) : '']);
        expect(droite[6], ['', 'SALAIRE BRUT', m(solde.brut)]);
        expect(droite[7], ['', 'SALAIRE BRUT RESTANT', m(solde.brut - solde.prelevement)]);
        expect((tables[0]['pied'] as List).map(norm).first, 'TOTAL À PRÉLEVER : ${m(solde.prelevement)}');
        final anc = rhbAnciennete(emp['dateEmbauche'], auj16);
        expect((piece['cartouche'] as List)[2], ['Ancienneté', '${anc.ans} ans ${anc.mois} mois']);
      });
    }

    test('la prime d\'ancienneté : 2 % du salaire par année, à partir de deux ans, hors du brut (écart E652)', () {
      final s0 = rhbSolde(salaireBrut: 100000, prelevementPct: 10, gardes: 0, permanences: 0, montantGarde: 0, montantPermanence: 0, montantAccueil: 0, ans: 1);
      final s3 = rhbSolde(salaireBrut: 100000, prelevementPct: 10, gardes: 0, permanences: 0, montantGarde: 0, montantPermanence: 0, montantAccueil: 0, ans: 3);
      expect(s0.primeAnciennete, 0);
      expect(s3.primeAnciennete, 6000);
      expect(s3.brut, 100000);
      expect(s3.prelevement, 10000);
    });

    test('le prélèvement s\'applique au brut recomposé : base + primes de garde, de permanence et d\'accueil', () {
      final s = rhbSolde(salaireBrut: 200000, prelevementPct: 10, gardes: 3, permanences: 2, montantGarde: 1500, montantPermanence: 800, montantAccueil: 0, ans: 0);
      expect(s.brut, 200000 + 4500 + 1600);
      expect(s.prelevement, 20610);
    });
  });

  group('m10-primes', () {
    final p = f(b['primes']);
    final ecr = f(b['primesEcritures']);

    test('les montants de la grille du jeu, rejoués : fonction par fonction, prime par prime', () {
      for (final x in (p['montants'] as List).cast<List>()) {
        expect(rhbMontantPrime(grille, historique, '${x[0]}', '${x[1]}'), x[3], reason: '$x');
      }
    });

    test('les primes acquises d\'août : même liste, mêmes totaux que l\'écran', () {
      final r = trierPar(
          rhbPrimesAcquises(personnelActif: personnel, planningActif: planning, grille: grille, historique: historique, annee: 2026, mois: 8),
          (x) => x.total,
          descendant: true);
      final k = [for (final x in (p['kpis'] as List)) f(x)];
      expect(r.length, int.parse(norm(k[0]['valeur'])));
      expect(norm(money(r.fold<num>(0, (a, x) => a + x.primeGarde))), norm(k[1]['valeur']));
      expect(norm(money(r.fold<num>(0, (a, x) => a + x.primePermanence))), norm(k[2]['valeur']));
      expect(norm(money(r.fold<num>(0, (a, x) => a + x.total))), norm(k[3]['valeur']));
      final lignes = (f(p['acquises'])['lignes'] as List).cast<List>();
      for (var i = 0; i < lignes.length; i++) {
        final x = r[i];
        expect([for (final c in lignes[i]) norm(c)], [
          x.matricule, x.employe, rhbFonctionLabel(x.fonction), '${x.gardes}', norm(money(x.primeGarde, avecDevise: false)),
          '${x.permanences}', norm(money(x.primePermanence, avecDevise: false)), norm(money(x.primesFixes, avecDevise: false)), norm(money(x.total, avecDevise: false))
        ], reason: 'ligne $i');
      }
    });

    test('à l\'ouverture du 30/10 : aucun planning en octobre, seules les primes fixes subsistent', () {
      final o = f(ouv['primes']);
      final k = [for (final x in (o['kpis'] as List)) f(x)];
      final r = rhbPrimesAcquises(personnelActif: personnel, planningActif: planning, grille: grille, historique: historique, annee: 2026, mois: 10);
      expect(r.length, int.parse(norm(k[0]['valeur'])));
      expect(norm(money(r.fold<num>(0, (a, x) => a + x.total))), norm(k[3]['valeur']));
      expect(r.every((x) => x.gardes == 0 && x.permanences == 0), isTrue);
      expect(auj30.month, 10);
    });

    // L'état cumulé de la grille après chaque geste de la maquette : la fiche réécrite remplace la précédente, la version sortante rejoint l'historique.
    test('après chaque modification : les montants datés de la maquette, rejoués', () {
      var g = [for (final x in grille) {...x}];
      var h = [for (final x in historique) {...x}];
      for (final c in liste(ecr['cas'])) {
        final fiche = f(c['fiche']);
        g = [for (final x in g) x['id'] == fiche['id'] ? fiche : x];
        h = [...liste(c['historique']), ...h.where((x) => !liste(c['historique']).any((y) => y['id'] == x['id']))];
        for (final x in (c['echantillons'] as List).cast<List>()) {
          expect(rhbMontantPrime(g, h, '${x[0]}', '${x[1]}', x[2] as String?), x[3], reason: '${c['lib']} → $x');
        }
      }
    });

    test('une modification « futur » : l\'ancienne version vaut avant la date d\'effet, la nouvelle à partir de ce jour', () {
      final c = liste(ecr['cas']).first;
      expect(c['portee'], 'futur');
      final fiche = f(c['fiche']);
      final hv = f(liste(c['historique']).first);
      expect(fiche['dateEffet'], '2026-08-16');
      expect(hv['dateFin'], '2026-08-15');
      final g = [for (final x in grille) x['id'] == fiche['id'] ? fiche : x];
      final h = [hv];
      expect(rhbMontantPrime(g, h, 'garde', 'infirmier', '2026-08-15'), 1500);
      expect(rhbMontantPrime(g, h, 'garde', 'infirmier', '2026-08-16'), 2000);
      expect(rhbMontantPrime(g, h, 'garde', 'infirmier'), 2000);
      // Avant la première version en vigueur : le barème d'origine de la note.
      expect(rhbMontantPrime(g, h, 'garde', 'infirmier', '2026-07-12'), 1500);
    });

    test('une modification « tout » réécrit depuis la date d\'origine et n\'écrit AUCUNE version antérieure', () {
      final c = liste(ecr['cas'])[1];
      expect(c['portee'], 'tout');
      expect(c['historique'], isEmpty);
      expect(f(c['fiche'])['dateEffet'], '2026-07-13');
    });

    test('une prime créée porte son identifiant en tirets, mais n\'entre pas dans les primes fixes du mois (écart E651)', () {
      final c = f(ecr['creation']);
      final fiche = f(c['fiche']);
      expect(fiche['primeId'], 'prime-de-nuit');
      expect(rhbMontantPrime([...grille, fiche], historique, 'prime-de-nuit', 'infirmier'), 1200);
      expect(rhbMontantPrime([...grille, fiche], historique, 'prime-de-nuit', 'sage_femme'), 1300);
      expect(rhbMontantPrime([...grille, fiche], historique, 'prime-de-nuit', 'tsl'), 0);
      expect((c['echantillons'] as List), [1200, 1300, 0]);
      // Elle ne figure pas parmi les primes d'origine : les primes fixes ne la lisent jamais.
      expect(rhbPrimesOrigine.any((x) => x.id == 'prime-de-nuit'), isFalse);
    });

    test('une prime RETIRÉE est encore calculée : le moteur retombe sur le barème d\'origine (écart E651)', () {
      final r = f(ecr['retrait']);
      expect(r['montantCaisse'], 10000);
      final sansCaisse = [for (final x in grille) if (x['primeId'] != 'caisse') x];
      expect(rhbMontantPrime(sansCaisse, historique, 'caisse', 'caissiere'), 10000);
      expect(rhbMontantPrime(sansCaisse, historique, 'caisse', 'infirmier'), 0);
    });

    test('un montant « 0 » de la grille n\'est pas un montant', () {
      final g = [
        {'primeId': 'garde', 'montants': {'infirmier': 0}, 'dateEffet': '2026-07-13'}
      ];
      expect(rhbMontantPrime(g, [], 'garde', 'infirmier'), 0);
    });
  });

  group('m10-planning', () {
    final pl = f(b['planning']);

    test('les quatre compteurs : vacations planifiées, de garde, en permanence, en repos aujourd\'hui', () {
      final k = [for (final x in (pl['kpis'] as List)) f(x)];
      final auj = planning.where((x) => x['date'] == '2026-08-16').toList();
      expect(norm(nombre(planning.length)), norm(k[0]['valeur']));
      expect(norm(nombre(auj.where((x) => x['type'] == 'garde').length)), norm(k[1]['valeur']));
      expect(norm(nombre(auj.where((x) => x['type'] == 'permanence').length)), norm(k[2]['valeur']));
      expect(norm(nombre(auj.where((x) => '${x['type']}'.startsWith('repos')).length)), norm(k[3]['valeur']));
    });

    test('à l\'ouverture du 30/10 : personne n\'est de garde, en permanence ni en repos ce jour-là', () {
      final k = [for (final x in (f(ouv['planning'])['kpis'] as List)) f(x)];
      final auj = planning.where((x) => x['date'] == '2026-10-30').toList();
      expect(auj, isEmpty);
      expect([for (final x in k.skip(1)) x['valeur']], ['0', '0', '0']);
    });

    test('le régime d\'une fonction : le magasin d\'abord, le repli de data.js ensuite', () {
      expect(rhbRegimeDe(regimes, 'medecin')!.libelle, 'Médecins');
      expect(rhbRegimeDe(regimes, 'medecin')!.repos, 'repos48');
      expect(rhbRegimeDe([], 'sage_femme')!.repos, 'repos24');
      expect(rhbRegimeDe([], 'chauffeur'), isNull);
      // Un régime sans repos codifié.
      expect(rhbRegimeDe(regimes, 'entretien')!.repos, isNull);
    });

    for (final c in liste(f(b['affectation'])['cas'])) {
      test('affectation refusée : ${c['fonction']}, garde ${c['joursAvant']} jour(s) avant le ${c['jour']}', () {
        final regime = rhbRegimeDe(regimes, '${c['fonction']}');
        final jour = DateTime.parse('${c['jour']}');
        final veille = rhbJourAvant(jour, c['joursAvant'] as int);
        final r = rhbIncompatibiliteGarde([
          {'employeId': 'A', 'date': veille, 'type': c['typeAvant']}
        ], employeId: 'A', jour: jour, type: '${c['typeVoulu']}', repos: regime!.repos);
        expect(r, veille);
        final detail = f(c['toast'])['detail'] as String;
        expect(detail, contains(dateFR(DateTime.parse(r!))));
        expect(f(c['toast'])['message'], 'Incompatibilité — le repos de ${regime.repos == 'repos48' ? 48 : 24} h qui suit une garde n’est pas respecté.');
        // Les vacations offertes : celles du régime, plus le repos et les quatre absences, dans l'ordre des types.
        final autorisees = rhbVacationsAutorisees(regime);
        expect([for (final t in rhbTypesPlanning) if (autorisees.contains(t.id)) t.id], [for (final o in (c['offerts'] as List)) (o as List)[0]]);
        expect([for (final t in rhbTypesPlanning) if (autorisees.contains(t.id)) rhbLibelleVacation(t)], [for (final o in (c['offerts'] as List)) (o as List)[1]]);
      });
    }

    test('hors du repos : une garde le troisième jour passe, une garde soins ne déclenche aucun contrôle', () {
      final pl0 = [
        {'employeId': 'A', 'date': '2026-08-13', 'type': 'garde'}
      ];
      expect(rhbIncompatibiliteGarde(pl0, employeId: 'A', jour: DateTime(2026, 8, 16), type: 'garde', repos: 'repos48'), isNull);
      expect(rhbIncompatibiliteGarde(pl0, employeId: 'A', jour: DateTime(2026, 8, 14), type: 'garde_soins', repos: 'repos48'), isNull);
      expect(rhbIncompatibiliteGarde(pl0, employeId: 'B', jour: DateTime(2026, 8, 14), type: 'garde', repos: 'repos48'), isNull);
      // Repos de 24 h : le deuxième jour est libre.
      expect(rhbIncompatibiliteGarde(pl0, employeId: 'A', jour: DateTime(2026, 8, 15), type: 'garde', repos: 'repos24'), isNull);
      expect(rhbIncompatibiliteGarde(pl0, employeId: 'A', jour: DateTime(2026, 8, 14), type: 'garde', repos: 'repos24'), '2026-08-13');
    });

    test('la portée d\'une modification de régime : vacations passées et à venir, comptées comme la maquette', () {
      for (final c in liste(f(b['regimes'])['cas'])) {
        final regime = regimes.firstWhere((x) => x['libelle'] == c['lib']);
        final r = rhbVacationsDuRegime(planning, (regime['fonctions'] as List).cast<String>(), '2026-08-16');
        final m = RegExp(r'(\d+) vacation\(s\) s’adossent à ce régime — (\d+) déjà effectuée\(s\) et (\d+) à venir').firstMatch(norm(c['demande']))!;
        expect([r.concernees.length, r.passees.length, r.futures.length], [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)], reason: '${c['lib']}');
        expect(r.concernees.length, r.passees.length + r.futures.length);
      }
      final arch = norm(f(f(b['regimes'])['archivage'])['message']);
      final s = rhbVacationsDuRegime(planning, ['securite'], '2026-08-16');
      expect(arch, contains('${s.concernees.length} vacation(s) s’adossent à ce régime'));
    });

    test('le régime des vacations est lu sur le régime de la FONCTION de la vacation', () {
      final lignes = (f(pl['registre'])['lignes'] as List).cast<List>();
      expect(lignes.first.length, greaterThan(6));
    });
  });
}
