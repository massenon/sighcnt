import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// M10 — RH (premier lot). Les règles rejouent les vecteurs `vecteurs/rh.json`, tirés des écrans RÉELS de la maquette (Chrome, horloge 30/10/2026 10 h,
/// jeu du poste) : indicateurs, graphiques interceptés, classements, échéances, références, montants.
typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
String s(Object? x) => '$x'.replaceAll(RegExp(r'[\s  ]'), '');

final v = obj(jsonDecode(File('test/vecteurs/rh.json').readAsStringSync()));
final auj = DateTime(2026, 10, 30, 10);
final aout = DateTime(2026, 8, 20, 10);

List<M> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));
List<M> actives(String nom) => [
      for (final f in jeu(nom))
        if (f['statut'] != 'archive') f
    ];

void kpisEgaux(List<RhaKpi> obtenus, Object? attendus) {
  final a = liste(attendus);
  expect(obtenus.length, a.length);
  for (var i = 0; i < a.length; i++) {
    expect(obtenus[i].libelle, a[i]['libelle']);
    expect(s(obtenus[i].valeur), s(a[i]['valeur']), reason: '${a[i]['libelle']}');
    expect(obtenus[i].indice, a[i]['indice'], reason: 'indice ${a[i]['libelle']}');
  }
}

void main() {
  group('tableau de bord', () {
    test('indicateurs à 30/10 (aucune vacation ce jour) et à 20/08 (gardes et repos), identiques à la maquette', () {
      final p = actives('personnel'), pl = actives('planning');
      kpisEgaux(rhaKpisDashboard(p, rhaPlanningDuJour(pl, auj), auj), obj(obj(v['dashboard'])['ecran'])['kpis']);
      final aoutKpis = rhaKpisDashboard(p, rhaPlanningDuJour(pl, aout), aout);
      kpisEgaux(aoutKpis, obj(obj(v['dashboardAout'])['ecran'])['kpis']);
      expect(int.parse(aoutKpis[4].valeur), greaterThan(0), reason: 'le 20/08 il y a des gardes : la sonde ne mesure pas un zéro');
    });

    test('graphiques : services, masse par service, répartition du planning du jour', () {
      final p = actives('personnel');
      final g = liste(obj(v['dashboardAout'])['graphes']);
      final srv = rhaParService(p);
      expect([for (final x in srv) x.service], (g[0]['etiquettes'] as List).cast<String>());
      expect([for (final x in srv) x.effectif], (g[0]['donnees'] as List).cast<num>());
      expect([for (final x in srv) x.masse], (obj((g[1]['donnees'] as List).first)['data'] as List).cast<num>());
      final jour = rhaRepartitionPlanning(rhaPlanningDuJour(actives('planning'), aout));
      expect([for (final x in jour) x.libelle], (g[2]['etiquettes'] as List).cast<String>());
      expect([for (final x in jour) x.nombre], (g[2]['donnees'] as List).cast<num>());
    });

    test('effectif par fonction : décroissant, ex æquo dans l’ordre d’apparition', () {
      final texte = (obj(v['dashboard'])['cartes'] as List)[1] as String;
      final l = rhaEffectifParFonction(actives('personnel'));
      expect(s(texte), s('Effectif par fonction ${[for (final x in l) '${x.libelle} ${x.valeur}'].join(' ')}'));
    });

    test('ancienneté : jours ÷ 30,44, arrondie à la décimale — « 5 » et non « 5.0 »', () {
      expect(rhaNombreJs(5.0), '5');
      expect(rhaNombreJs(5.1), '5.1');
      expect(rhaAncienneteCourte('2018-06-27', auj), '8 a. 4 m.');
      expect(rhaAncienneteLongue('2018-06-27', auj), '8 an(s) 4 mois');
      expect(rhaAncienneteCourte('2026-10-30', auj), '0 a. 0 m.');
    });
  });

  group('personnel', () {
    test('indicateurs avant et après la création, puis après l’archivage', () {
      final p = actives('personnel');
      final e = obj(v['personnel']);
      kpisEgaux(rhaKpisPersonnel(p), obj(e['ecran'])['kpis']);
      final nouveau = rhaAgentEnregistrable({'nom': 'AGBO', 'prenom': 'Rosine', 'sexe': 'F', 'salaireBase': 120000});
      expect(nouveau['nomComplet'], 'AGBO Rosine');
      kpisEgaux(rhaKpisPersonnel([nouveau, ...p]), obj(obj(e['creation'])['apres'])['kpis']);
      kpisEgaux(rhaKpisPersonnel(p), obj(e['archivage'])['kpis']);
    });

    test('ancienneté de chaque ligne de la première page = celle de la maquette', () {
      final p = {for (final x in actives('personnel')) x['matricule']: x};
      final lignes = (obj((obj(obj(v['personnel'])['ecran'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      for (final l in lignes) {
        final agent = p['${l[0]}']!;
        expect(l.contains(rhaAncienneteCourte(agent['dateEmbauche'], auj)), isTrue, reason: 'matricule ${l[0]}');
      }
    });

    test('initiales : les deux premiers mots, en majuscules', () {
      expect(rhaInitiales('BASSONGUI Chabi Séko'), 'BC');
      expect(rhaInitiales('GBEDJI Hervé'), 'GH');
      expect(rhaInitiales('YENI M’PO Florent'), 'YM');
    });
  });

  group('fiche employé : planning du mois, primes NS 132', () {
    for (final id in ['EMP01', 'EMP10', 'EMP18', 'EMP29', 'EMP21', 'EMP44']) {
      test('$id : gardes, permanences et lignes de primes identiques à la maquette (20/08/2026)', () {
        final agent = actives('personnel').firstWhere((x) => x['id'] == id);
        final planning = actives('planning');
        final vac = rhaVacations(planning, id, aout.year, aout.month);
        final onglets = obj(obj(obj(obj(v['profil'])['aout'])['agents'])[id])['parOnglet'];
        final plan = obj(obj(onglets)['Planning du mois']);
        final gardes = rhaCompter(vac, 'garde'), perm = rhaCompter(vac, 'permanence');
        if (vac.isEmpty) {
          expect(plan['texte'], contains('Aucune vacation programmée ce mois-ci.'));
        } else {
          kpisEgaux([RhaKpi('Gardes', '$gardes'), RhaKpi('Permanences', '$perm')], plan['kpis']);
          expect((obj((plan['tableaux'] as List).first)['lignes'] as List).length, vac.length);
        }
        final primes = rhaPrimesAgent(actives('grillePrimes'), agent['fonction'], gardes, perm);
        final t = obj(onglets)['Primes (NS 132)'];
        final tab = obj(t)['tableaux'] as List;
        if (primes.isEmpty) {
          expect(obj(t)['texte'], contains('Aucune prime prévue pour cette fonction par la note NS 132.'));
          expect(tab, isEmpty);
        } else {
          final lignes = (obj(tab.first)['lignes'] as List).cast<List>();
          expect(lignes.length, primes.length);
          for (var i = 0; i < primes.length; i++) {
            expect(lignes[i][0], primes[i].prime);
            expect(lignes[i][1], primes[i].mode);
            expect(s(lignes[i][2]), s(money(primes[i].montant, avecDevise: false)));
            expect(s(lignes[i][3]), s(primes[i].nb));
            expect(s(lignes[i][4]), s(money(primes[i].total, avecDevise: false)));
          }
        }
      });
    }

    test('la grille DATÉE prime sur le barème d’origine ; sans fiche, c’est le barème de la NS 132', () {
      expect(rhaMontantPrime([], 'garde', 'infirmier'), 1500);
      expect(rhaMontantPrime([], 'garde', 'medecin'), 0, reason: 'aucune prime de garde pour un médecin : ce n’est pas un zéro inventé');
      expect(
          rhaMontantPrime([
            {'primeId': 'garde', 'montants': {'infirmier': 1800}}
          ], 'garde', 'infirmier'),
          1800);
    });

    test('un badge inconnu s’affiche tel quel (« present »), un code connu est traduit', () {
      expect(rhaStatutBadge('present').$1, 'present');
      expect(rhaStatutBadge('en_attente').$1, 'En attente');
      expect(rhaStatutBadge(null).$1, '—');
    });
  });

  group('contrats', () {
    test('indicateurs identiques ; échéance de chaque ligne (Indéterminée, Échu, Dans N j, date)', () {
      final c = actives('contrats');
      final e = obj(v['contrats']);
      kpisEgaux(rhaKpisContrats(c, auj), obj(e['ecran'])['kpis']);
      final parRef = {for (final x in c) x['reference']: x};
      final lignes = (obj((obj(e['ecran'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      final vus = <String>{};
      for (final l in lignes) {
        final ech = rhaEcheanceContrat(parRef['${l[0]}']!, auj);
        expect(l[6], ech.texte, reason: '${l[0]}');
        vus.add(ech.texte.startsWith('Dans') ? 'dans' : ech.texte);
      }
      expect(vus, containsAll(['Indéterminée', 'Échu', 'dans']));
    });

    test('référence : la suivante de la SÉRIE (CT-0045), gardée à la modification (E620)', () {
      final c = jeu('contrats');
      final e = obj(v['contrats']);
      expect(admReferenceSuivante('CT-', 4, c), obj(obj(obj(e['creation'])['creee'])['fiche'])['reference']);
      final f = rhaContratEnregistrable({'employeId': 'EMP10'}, jeu('personnel').firstWhere((x) => x['id'] == 'EMP10'), reference: 'CT-0045');
      expect(f['employe'], obj(obj(obj(e['creation'])['creee'])['fiche'])['employe']);
      expect(f['poste'], obj(obj(obj(e['creation'])['creee'])['fiche'])['poste']);
      expect(f['statutContrat'], 'en_vigueur');
      expect(obj(obj(e['modification'])['enregistre'])['nbSansRef'], 1, reason: 'un seul CT-0001 après la modification : la référence n’est pas réécrite');
    });

    test('articles du contrat imprimé : CDD (échéance) et CDI', () {
      final e = obj(v['contrats']);
      final cdd = jeu('contrats').firstWhere((x) => x['reference'] == e['refCDD']);
      final lignes = (obj((obj(e['etatCDD'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      final art = rhaArticlesContrat(cdd);
      expect([for (final a in art) a.$1], [for (final l in lignes) l[0]]);
      expect([for (final a in art) s(a.$2)], [for (final l in lignes) s(l[1])]);
      final cdi = jeu('contrats').firstWhere((x) => x['reference'] == e['refCDI']);
      final l2 = (obj((obj(e['etatCDI'])['tableaux'] as List).first)['lignes'] as List).cast<List>();
      expect([for (final a in rhaArticlesContrat(cdi)) s(a.$2)], [for (final l in l2) s(l[1])]);
    });
  });

  group('congés', () {
    test('indicateurs identiques ; « en congé aujourd’hui » ignore un congé qui finit AUJOURD’HUI (fin lue à minuit)', () {
      final c = actives('conges');
      kpisEgaux(rhaKpisConges(c, auj), obj(obj(v['conges'])['ecran'])['kpis']);
      final finAujourdhui = {'statutConge': 'valide', 'dateDebut': '2026-10-26', 'dateFin': '2026-10-30'};
      expect(rhaCongeEnCours(finAujourdhui, auj), isFalse);
      expect(rhaCongeEnCours({...finAujourdhui, 'dateFin': '2026-10-31'}, auj), isTrue);
      expect(rhaCongeEnCours({...finAujourdhui, 'dateFin': '2026-10-31', 'statutConge': 'en_attente'}, auj), isFalse);
    });

    test('lecture graphique : par service, par nature, décisions, jours accordés par mois', () {
      final st = rhaStatsConges(actives('conges'));
      final g = liste(obj(v['conges'])['graphes']);
      expect([for (final x in st.parService) x.$1], (g[0]['etiquettes'] as List).cast<String>());
      expect([for (final x in st.parService) x.$2], (obj((g[0]['donnees'] as List).first)['data'] as List).cast<num>());
      expect([for (final x in st.parNature) x.$1], (g[1]['etiquettes'] as List).cast<String>());
      expect([for (final x in st.parNature) x.$2], (g[1]['donnees'] as List).cast<num>());
      expect([for (final x in st.parDecision) x.$1], (g[2]['etiquettes'] as List).cast<String>());
      expect([for (final x in st.parDecision) x.$2], (g[2]['donnees'] as List).cast<num>());
      expect(st.moisLibelles, (g[3]['etiquettes'] as List).cast<String>());
      expect(st.moisJours, (obj((g[3]['donnees'] as List).first)['data'] as List).cast<num>());
    });

    test('durée = max(1, jours) ; refus nommé si la fin précède le début ; référence CG-0023', () {
      final e = obj(v['conges']);
      expect(rhaDureeConge('2026-11-10', '2026-11-16'), 6);
      expect(rhaDureeConge('2026-11-10', '2026-11-10'), 1);
      expect(rhaRefuserConge('2026-11-10', '2026-11-05'), (((obj(obj(e['creation'])['refusDates'])['toasts'] as List).first) as List).first);
      expect(rhaRefuserConge('2026-11-10', '2026-11-16'), isNull);
      expect(admReferenceSuivante('CG-', 4, jeu('conges')), 'CG-0023');
      final f = rhaCongeEnregistrable({'dateDebut': '2026-11-10', 'dateFin': '2026-11-16'}, jeu('personnel').firstWhere((x) => x['id'] == 'EMP10'), reference: 'CG-0023');
      expect(f['duree'], obj(obj(obj(e['creation'])['creee'])['fiche'])['duree']);
      expect(f['service'], 'Soins infirmiers');
    });

    test('décision imprimée : accordée, refusée, en cours d’instruction — avec remplaçant', () {
      final e = obj(v['conges']);
      for (final d in ['valide', 'refuse', 'en_attente']) {
        final x = obj(obj(e['etats'])[d]);
        final c = jeu('conges').firstWhere((f) => f['reference'] == x['reference']);
        expect(s(rhaTexteDecisionConge(c).join()), s(obj(x['etat'])['texte']), reason: d);
      }
    });
  });

  group('ordres de mission', () {
    test('indicateurs avant et après la validation de OM-2026-0004', () {
      final m = actives('missions');
      final e = obj(v['missions']);
      kpisEgaux(rhaKpisMissions(m), obj(e['ecran'])['kpis']);
      final apres = [
        for (final x in m)
          if (x['reference'] == 'OM-2026-0004') {...x, ...rhaCorrectifValidationMission(auj)} else x
      ];
      kpisEgaux(rhaKpisMissions(apres), obj(obj(e['validation'])['ecran'])['kpis']);
      final fiche = obj(obj(obj(e['validation'])['apres'])['fiche']);
      expect(fiche['valideePar'], 'TAKI Alimatou');
      expect(fiche['valideeLe'], '2026-10-30');
    });

    test('gestes de la ligne selon l’état ; état inconnu = « En projet »', () {
      expect(rhaGestesMission('a_valider').valider, isTrue);
      expect(rhaGestesMission('a_valider').terminerReporter, isFalse);
      expect(rhaGestesMission('validee').terminerReporter, isTrue);
      expect(rhaGestesMission('en_cours').terminerReporter, isTrue);
      expect(rhaGestesMission('terminee').terminerReporter, isFalse);
      expect(rhaStatutMission('???').$2, 'En projet');
      expect(rhaStatutMission('a_valider').$2, 'En attente de validation DA');
    });

    test('création : référence OM-AAAA-NNNN (année de la date de départ, rang par année), agent et poste repris du dossier', () {
      final e = obj(v['missions']);
      final nouv = obj(obj(obj(e['creation'])['creee'])['fiche']);
      expect(rhaReferenceMission(nouv['dateDepart'], jeu('missions')), nouv['reference']);
      expect(rhaReferenceMission('2027-02-01', [...jeu('missions'), {'reference': 'OM-2027-0004', 'statut': 'archive'}]), 'OM-2027-0005');
      expect(rhaReferenceMission('2031-02-01', jeu('missions')), 'OM-2031-0001');
      final f = rhaMissionEnregistrable({'dateDepart': nouv['dateDepart']}, jeu('personnel').firstWhere((x) => x['id'] == 'EMP37'), toutes: jeu('missions'));
      expect(f['agent'], nouv['agent']);
      expect(f['fonction'], nouv['fonction']);
      expect(rhaMissionEnregistrable({}, null, toutes: const [])['agent'], '—');
    });
  });

  group('prestataires externes', () {
    test('indicateurs avant/après la création ; montant dû = tarif × actes', () {
      final p = actives('prestataires');
      final e = obj(v['prestataires']);
      kpisEgaux(rhaKpisPrestataires(p), obj(e['ecran'])['kpis']);
      final nouv = obj(obj(obj(e['creation'])['creee'])['fiche']);
      kpisEgaux(rhaKpisPrestataires([nouv, ...p]), obj(obj(e['creation'])['apres'])['kpis']);
      expect(rhaMontantDuPrestataire({'tarifActe': 15000, 'actesRealises': 4}), 60000);
      expect(admReferenceSuivante('PE-', 4, jeu('prestataires')), nouv['reference']);
    });

    test('lecture graphique et classement des huit mieux rémunérés (tri croissant stable puis inversé)', () {
      final st = rhaStatsPrestataires(actives('prestataires'));
      final e = obj(v['prestataires']);
      final g = liste(e['graphes']);
      expect(st.specialites, (g[0]['etiquettes'] as List).cast<String>());
      expect(st.montants, (obj((g[0]['donnees'] as List).first)['data'] as List).cast<num>());
      expect(st.actes, (g[1]['donnees'] as List).cast<num>());
      expect([st.facturesFournies, st.facturesManquantes], (g[2]['donnees'] as List).cast<num>());
      final carte = (e['cartes'] as List)[4] as String;
      expect(s(carte), s('Les huit prestataires les plus rémunérés ${[for (final x in st.classement) '${x.libelle} ${money(x.valeur, avecDevise: false)}'].join(' ')}'));
      expect(st.classement.length, 8);
    });
  });

  group('fiches de poste', () {
    test('indicateurs avant, après la création d’une fiche rédigée, puis après son archivage', () {
      final f = actives('fichesPoste');
      final e = obj(v['fichesPoste']);
      kpisEgaux(rhaKpisFichesPoste(f), obj(e['ecran'])['kpis']);
      final nouvelle = rhaFicheDePosteEnregistrable({'intitule': 'Responsable qualité', 'statut': ''});
      expect(nouvelle['redigee'], isTrue);
      expect(nouvelle['source'], 'Rédigée dans l’application');
      expect(nouvelle['missions'], isEmpty);
      kpisEgaux(rhaKpisFichesPoste([...f, nouvelle]), obj(obj(e['creation'])['apres'])['kpis']);
      kpisEgaux(rhaKpisFichesPoste(f), obj(e['archivage'])['kpis']);
    });

    test('seules deux fiches sont rédigées : 8 missions, 17 indicateurs', () {
      final f = actives('fichesPoste');
      expect(f.where((x) => rhaVrai(x['redigee'])).length, 2);
      expect(rhaKpisFichesPoste(f)[2].valeur, '8');
      expect(rhaKpisFichesPoste(f)[3].valeur, '17');
    });
  });
}
