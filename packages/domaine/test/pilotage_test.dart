// Rejoue les vecteurs du PILOTAGE (PIL), tirés des écrans réels de la maquette pilotés dans Chrome (prototype_html/build/vecteurs-pilotage.js) :
// dash-direction, dash-da, dash-croise, dash-admin, m4-stats-maternite, m2-stats-echographie, m5-stats-examens, m2-stats-consultations, m3-stats-bloc,
// m3-stats-hospitalisations, m10-cout-agent, m12-rentabilite-groupes, m12-tableau-decisionnel. Le jeu est celui du poste, l'horloge celle du 30/10/2026 10 h.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) => ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
F carte(Object? v) => (v as Map).cast<String, Object?>();
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();
String sans(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), '');
List<F> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));
List<F> actives(List<F> l) => [for (final x in l) if (x['statut'] != 'archive') x];

String libelleMode(String id) =>
    const {'especes': 'Espèces', 'tpe': 'TPE (carte bancaire)', 'mtn': 'MTN Mobile Money', 'moov': 'Moov Money', 'assurance': 'Prise en charge assurance'}[id] ?? id;

void main() {
  final f = File('test/vecteurs/pilotage.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-pilotage.js`');
  final v = carte(jsonDecode(f.readAsStringSync()));
  final auj = DateTime(2026, 10, 30, 10);
  final aout = DateTime(2026, 8, 1); // E20 : K.parMois est ancré en dur au 1er août 2026
  final inj = carte(v['injections']);
  final tout = <String, List<F>>{};
  List<F> col(String n) => actives(tout[n] ??= jeu(n));
  List<F> colInj(String n) => actives(liste(inj[n]));

  // ---------------------------------------------------------------------------------------------------------------------------------------
  void kpis(PilVue vue, Object? attendu, String ou) {
    final e = (attendu as List).map((x) => (x as List).cast<Object?>()).toList();
    expect(vue.kpis.length, e.length, reason: '$ou : nombre d’indicateurs');
    for (var i = 0; i < e.length; i++) {
      expect(vue.kpis[i].libelle, e[i][0], reason: '$ou : libellé n°$i');
      expect(nt(vue.kpis[i].valeur), nt(e[i][1]), reason: '$ou : ${e[i][0]}');
      expect(vue.kpis[i].indice == null ? null : nt(vue.kpis[i].indice), e[i][2] == null ? null : nt(e[i][2]), reason: '$ou : indice de ${e[i][0]}');
    }
  }

  void graphiques(PilVue vue, Object? attendu, String ou) {
    final e = liste(attendu);
    expect(vue.graphiques.length, e.length, reason: '$ou : nombre de graphiques');
    for (var i = 0; i < e.length; i++) {
      final g = vue.graphiques[i];
      expect(g.type, e[i]['type'], reason: '$ou : type du graphique $i');
      expect(g.etiquettes, (e[i]['etiquettes'] as List).cast<String>(), reason: '$ou : étiquettes du graphique $i');
      if (g.type == 'anneau') {
        expect(g.series.first.donnees, (e[i]['series'] as List).cast<num>(), reason: '$ou : valeurs de l’anneau $i');
      } else {
        final s = liste(e[i]['series']);
        expect(g.series.length, s.length, reason: '$ou : séries du graphique $i');
        for (var j = 0; j < s.length; j++) {
          expect(g.series[j].libelle, s[j]['label'], reason: '$ou : série $j');
          expect(g.series[j].donnees, (s[j]['data'] as List).cast<num>(), reason: '$ou : données de la série $j du graphique $i');
        }
      }
    }
  }

  void classements(PilVue vue, Object? attendu, String ou) {
    final e = liste(attendu);
    expect(vue.classements.length, e.length, reason: '$ou : classements');
    for (var i = 0; i < e.length; i++) {
      final items = liste(e[i]['items']);
      expect([for (final x in vue.classements[i].items) x.$1], [for (final x in items) x['label']], reason: '$ou : libellés du classement $i');
      expect([for (final x in vue.classements[i].items) x.$2], [for (final x in items) x['value']], reason: '$ou : valeurs du classement $i');
    }
  }

  /// Compare les tableaux de la vue à ceux de l'écran : les tableaux paginés ne montrent que leur première page (préfixe).
  void tables(PilVue vue0, Object? attendu, String ou, {List<int> pagines = const []}) {
    final e = liste(attendu);
    // Un tableau sans ligne n'est pas un <table> : la maquette dessine alors un message « aucune donnée ».
    final vt = [for (final t in vue0.tables) if (t.lignes.isNotEmpty) t];
    expect(vt.length, e.length, reason: '$ou : nombre de tableaux');
    for (var i = 0; i < e.length; i++) {
      final t = vt[i];
      expect(t.titre, e[i]['titre'], reason: '$ou : titre du tableau $i');
      expect([for (final h in t.entetes) h.toUpperCase()], [for (final h in (e[i]['entetes'] as List)) '$h'.toUpperCase()], reason: '$ou : en-têtes $i');
      final lignes = (e[i]['lignes'] as List).map((l) => (l as List).map(nt).toList()).toList();
      if (pagines.contains(i)) {
        expect(t.lignes.length, greaterThanOrEqualTo(lignes.length), reason: '$ou : lignes du tableau $i');
      } else {
        expect(t.lignes.length, lignes.length, reason: '$ou : lignes du tableau $i');
      }
      for (var k = 0; k < lignes.length; k++) {
        expect(t.lignes[k].map(nt).toList(), lignes[k], reason: '$ou : ligne $k du tableau $i');
      }
    }
  }

  void tout_(PilVue vue, F a, String ou, {bool tablesVerif = true, List<int> pagines = const []}) {
    kpis(vue, a['kpis'], ou);
    graphiques(vue, a['graphiques'], ou);
    classements(vue, a['classements'], ou);
    if (tablesVerif) tables(vue, a['tables'], ou, pagines: pagines);
  }

  // =====================================================================================================================================
  group('m5-stats-examens : chaque axe est un FILTRE', () {
    final e = carte(v['examens']);
    final dem = col('demandesAnalyses'), pat = col('patients');
    test('les services proposés au filtre sont ceux que portent les demandes, triés', () {
      final attendus = [for (final o in (carte(e['options'])['service'] as List)) (o as List)[0] as String].where((x) => x.isNotEmpty).toList();
      expect(pilServicesExamens(dem), attendus);
    });
    PilFiltreExamens filtre(F x) {
      final fl = carte(x['filtres']);
      return PilFiltreExamens(du: '${fl['du']}', au: '${fl['au']}', service: '${fl['service']}', sexe: '${fl['sexe']}', age: '${fl['age']}', origine: '${fl['origine']}');
    }

    test('sans filtre : population entière', () {
      final d = carte(e['defaut']);
      tout_(pilStatsExamens(dem, pat, const PilFiltreExamens(), auj), d, 'défaut', pagines: [0]);
    });
    final sc = carte(e['scenarios']);
    for (final nom in sc.keys) {
      test('filtre « $nom »', () {
        final a = carte(sc[nom]);
        tout_(pilStatsExamens(dem, pat, filtre(a), auj), a, nom, pagines: [0]);
      });
    }
    test('un axe qui ne retient rien se compte à zéro : le tableau est vide', () {
      final vue = pilStatsExamens(dem, pat, const PilFiltreExamens(du: '2030-01-01', au: '2030-02-01'), auj);
      expect(vue.kpis.first.valeur, '0');
      expect(vue.tables.first.lignes, isEmpty);
    });
  });

  // =====================================================================================================================================
  group('m2-stats-echographie : calculées, jamais fournies', () {
    final im = carte(v['imagerie']);
    test('le jeu : comptes rendus, rendus, part obstétricale, délai tracé', () {
      final vue = pilStatsImagerie(col('demandesImagerie'), col('resultatsImagerie'));
      tout_(vue, carte(im['defaut']), 'défaut');
    });
    test('aucun registre : « — », jamais un zéro qui ferait croire à un délai nul', () {
      final vue = pilStatsImagerie(const [], const []);
      tout_(vue, carte(im['vide']), 'vide');
    });
  });

  // =====================================================================================================================================
  void parPlage(String nom, Object? Function(String du, String au) calcul, {bool tablesVerif = true, List<int> pagines = const []}) {
    final b = carte(v[nom]);
    test('$nom : toute la période', () {
      tout_(calcul('', '') as PilVue, carte(b['defaut']), 'défaut', tablesVerif: tablesVerif, pagines: pagines);
      tout_(calcul('', '') as PilVue, carte(b['toutePeriode']), 'toute la période', tablesVerif: tablesVerif, pagines: pagines);
    });
    final sc = carte(b['scenarios']);
    for (final k in sc.keys) {
      test('$nom : plage « $k »', () {
        final a = carte(sc[k]);
        final fl = carte(a['filtres']);
        tout_(calcul('${fl['du']}', '${fl['au']}') as PilVue, a, k, tablesVerif: tablesVerif, pagines: pagines);
      });
    }
  }

  group('m2-stats-consultations : plage de dates', () {
    parPlage('consultations', (du, au) => pilStatsConsultations(col('consultations'), col('personnel'), du, au, auj));
  });

  group('m3-stats-bloc : les interventions sans CPA sont signalées, jamais bloquées', () {
    parPlage('bloc', (du, au) => pilStatsBloc(col('crOperatoires'), colInj('crAnesthesie'), colInj('cpa'), du, au));
    test('« aucun incident » s’écrit et ne compte pas ; un incident compte dès qu’il est NOMMÉ', () {
      final vue = pilStatsBloc(const [], [
        {'incidents': 'Aucun incident'},
        {'incidents': ' aucun'},
        {'incidents': 'Hypotension'},
        {'incidents': ''},
        {}
      ], const [], '', '');
      expect(vue.kpis.firstWhere((k) => k.libelle.startsWith('Incidents')).valeur, '1');
    });
  });

  group('m3-stats-hospitalisations : durée moyenne sur les séjours TERMINÉS seulement', () {
    parPlage('hospitalisations', (du, au) => pilStatsHospitalisations(col('admissions'), du, au, auj, refMois: aout).vue, pagines: []);
    test('un séjour en cours n’abaisse pas la durée moyenne', () {
      final base = pilStatsHospitalisations([
        {'dateEntree': '2026-10-01', 'dateSortie': '2026-10-11', 'typeChambre': 'standard'},
      ], '', '', auj, refMois: aout);
      final avec = pilStatsHospitalisations([
        {'dateEntree': '2026-10-01', 'dateSortie': '2026-10-11', 'typeChambre': 'standard'},
        {'dateEntree': '2026-10-28', 'typeChambre': 'standard'},
      ], '', '', auj, refMois: aout);
      expect(base.dms, 10);
      expect(avec.dms, 10, reason: 'le séjour en cours est exclu de la moyenne');
      expect(avec.enCours, 1);
      expect(avec.terminees, 1);
    });
    test('l’état imprimé : cartouche et tableau avec TOTAL', () {
      final h = pilStatsHospitalisations(col('admissions'), '', '', auj, refMois: aout);
      final p = carte(carte(v['hospitalisations'])['piece']);
      expect([for (final c in pilCartoucheHospitalisations(h, '', '')) [c.$1, nt(c.$2)]], [for (final c in (p['cartouche'] as List)) [(c as List)[0], nt(c[1])]]);
      expect(h.parType.fold<int>(0, (a, r) => a + r.sejours), 91);
    });
  });

  group('m12-rentabilite-groupes : deux registres, un rapprochement ARRÊTÉ, des charges transverses non ventilées', () {
    final actes = col('actes');
    PilRentabilite calc(String du, String au, {List<F>? ecritures}) => pilRentabilite(
        factures: col('factures'),
        ecritures: ecritures ?? col('ecritures'),
        centresCouts: jeu('centresCouts'),
        secteurParCode: secteursDesActes(actes),
        du: du,
        au: au);
    parPlage('rentabilite', (du, au) => calc(du, au).vue);
    test('la note des charges transverses reprend la somme des centres non rattachés', () {
      final r = calc('', '');
      expect(nt(r.vue.notes.first), nt(carte(v['rentabilite'])['defaut'] == null ? '' : ((carte(v['rentabilite'])['defaut'] as Map)['notes'] as List).first));
    });
    test('une écriture sans centre est « Non imputé », un brouillon est écarté et compté, un crédit réduit la charge', () {
      final ecr = [
        ...col('ecritures'),
        {'id': 'ECR-T1', 'numero': 'OD-T-1', 'date': '2026-10-10', 'compte': '601000', 'statut': 'validee', 'debit': 12345, 'credit': 0},
        {'id': 'ECR-T2', 'numero': 'OD-T-2', 'date': '2026-10-11', 'compte': '604000', 'statut': 'brouillon', 'debit': 999, 'credit': 0, 'centreCout': 'laboratoire'},
        {'id': 'ECR-T3', 'numero': 'OD-T-3', 'date': '2026-10-12', 'compte': '641000', 'statut': 'validee', 'debit': 0, 'credit': 2000, 'centreCout': 'maternite'},
      ];
      final r = calc('', '', ecritures: ecr);
      final a = carte(carte(v['rentabilite'])['synthetique']);
      kpis(r.vue, a['kpis'], 'synthétique');
      tables(r.vue, a['tables'], 'synthétique');
      expect(r.brouillons, 1);
    });
  });

  group('m10-cout-agent : DEUX colonnes à ne jamais additionner', () {
    final c = carte(v['coutAgent']);
    final personnel = col('personnel');
    final bull = colInj('bulletins');
    final avances = col('avances');
    F agent(String id) => personnel.firstWhere((p) => p['id'] == id);
    final sc = carte(c['scenarios']);
    for (final k in sc.keys) {
      test('« $k »', () {
        final a = carte(sc[k]);
        final id = k.startsWith('agent:') ? k.substring(6) : carte(v['agents'])['haut'] as String;
        var du = '', au = '';
        if (k == 'plage') {
          du = '2026-09-01';
          au = '2026-10-31';
        } else if (k == 'octobre' || k == 'avecAvances') {
          du = '2026-10-01';
          au = '2026-10-31';
        }
        final ag = agent(id);
        final r = pilCoutAgent(ag, bull, du, au);
        kpis(r.vue, a['kpis'], k);
        tables(r.vue, a['tables'], k);
        final note = pilNoteAvances(k == 'avecAvances' ? [...avances, {'id': 'AV-T', 'personnelId': id}] : avances, ag);
        expect([for (final n in (a['notes'] as List)) nt(n)].where((n) => n.contains('avance(s)')).toList(), note == null ? isEmpty : [nt(note)], reason: k);
      });
    }
    test('le coût employeur et les retenues de l’agent restent deux colonnes : jamais de total qui les additionne', () {
      final r = pilCoutAgent(agent(carte(v['agents'])['haut'] as String), bull, '', '');
      expect(r.coutMensuel, r.brut + r.patronale + r.vps);
      expect(r.coutMensuel, isNot(r.coutMensuel + r.ouvriere));
      final composition = r.vue.tables.first.lignes;
      expect(composition.map((l) => l[0]), contains('COÛT EMPLOYEUR'));
      expect(composition.last[1], 'Retenue à l’agent');
    });
    test('ORTB : la radio pour tous, la télé AU-DELÀ de 60 000 — elles se cumulent', () {
      expect(pilCoutAgent({'salaireBase': 60000}, const [], '', '').ortbAnnuel, 1000);
      expect(pilCoutAgent({'salaireBase': 60001}, const [], '', '').ortbAnnuel, 4000);
    });
  });

  group('m4-stats-maternite : indicateurs DHIS2 calculés depuis les registres', () {
    final m = carte(v['maternite']);
    PilVue calc({String? vide}) => pilStatsMaternite(
        grossesses: vide == 'grossesses' ? const [] : col('grossesses'),
        accouchements: vide == 'accouchements' ? const [] : col('accouchements'),
        naissances: vide == 'naissances' ? const [] : col('naissances'),
        planification: vide == 'planificationFamiliale' ? const [] : col('planificationFamiliale'),
        sonu: vide == 'registreSONU' ? const [] : col('registreSONU'),
        curatifs: vide == 'soinsCuratifsMaternite' ? const [] : col('soinsCuratifsMaternite'));
    test('le jeu', () => tout_(calc(), carte(m['defaut']), 'défaut'));
    for (final k in carte(m['sans']).keys) {
      test('registre « $k » vide : 0 % et non une division par zéro', () => tout_(calc(vide: k), carte(carte(m['sans'])[k]), 'sans $k'));
    }
  });

  // =====================================================================================================================================
  group('m12-tableau-decisionnel : objectif fixé / réel atteint', () {
    final d = carte(v['decisionnel']);
    final mo = carte(d['moteur']);
    List<PilIndicateur> calc({Object? fin, int? jours, List<F>? objectifs, List<F>? factures, List<F>? admissions}) => pilIndicateurs(
        factures: factures ?? col('factures'),
        produits: col('produits'),
        facturesFournisseurs: col('facturesFournisseurs'),
        mouvements: col('mouvements'),
        admissions: admissions ?? col('admissions'),
        facturesMere: col('facturesMere'),
        objectifs: objectifs ?? jeu('objectifsPilotage'),
        auj: auj,
        fin: fin,
        jours: jours);
    void compare(String nom, List<PilIndicateur> got) {
      final e = liste(mo[nom]);
      expect(got.length, e.length, reason: nom);
      for (var i = 0; i < e.length; i++) {
        expect(got[i].id, e[i]['id'], reason: '$nom #$i');
        expect(got[i].reel, e[i]['reel'], reason: '$nom : réel de ${e[i]['id']}');
        expect(got[i].etat, e[i]['etat'], reason: '$nom : état de ${e[i]['id']}');
        expect(got[i].ecart, e[i]['ecart'], reason: '$nom : écart de ${e[i]['id']}');
        expect(got[i].cible, e[i]['cible'], reason: nom);
        expect(got[i].alerte, e[i]['alerte'], reason: nom);
        expect(got[i].aValider, e[i]['aValider'] == true, reason: nom);
        expect(got[i].axe, e[i]['axe'], reason: nom);
        expect(got[i].label, e[i]['label'], reason: nom);
      }
    }

    test('la fenêtre par défaut (90 jours glissants)', () => compare('defaut', calc()));
    test('30 jours : le chiffre d’affaires est nul, les indicateurs qui en dépendent sont « non calculables »', () {
      compare('j30', calc(fin: '2026-10-30', jours: 30));
      expect(calc(fin: '2026-10-30', jours: 30).firstWhere((x) => x.id == 'dso').etat, 'indisponible');
    });
    test('180 jours', () => compare('j180', calc(fin: '2026-10-30', jours: 180)));
    test('arrêté au 16/08/2026', () => compare('aout', calc(fin: '2026-08-16', jours: 90)));
    test('dans le futur et sans chiffre d’affaires', () {
      compare('futur', calc(fin: '2027-03-01', jours: 90));
      compare('sansCA', calc(fin: '2024-01-01', jours: 30));
    });
    test('collection des objectifs vidée : repli sur la semence, sans cible arrêtée', () {
      compare('semence', calc(objectifs: const []));
      expect(calc(objectifs: const []).every((x) => x.aValider), isTrue);
    });
    test('corriger une cible l’ARRÊTE ; un sens « bas » dépassé franchit le seuil', () {
      final objs = jeu('objectifsPilotage');
      final o = objs.firstWhere((x) => x['id'] == 'dso');
      final arrete = pilArreterObjectif({...o, 'cible': 300, 'alerte': 500}, auj: auj, par: 'DAF');
      expect(arrete['aValider'], false);
      expect(arrete['arreteLe'], '2026-10-30');
      expect(arrete['arretePar'], 'DAF');
      compare('dsoArrete', calc(objectifs: [for (final x in objs) x['id'] == 'dso' ? pilArreterObjectif({...x, 'cible': 300, 'alerte': 500}, auj: auj, par: 'DAF') : x]));
      compare('dsoAlerte', calc(objectifs: [for (final x in objs) x['id'] == 'dso' ? {...x, 'cible': 1, 'alerte': 2, 'aValider': false} : x]));
    });
    test('sans factures, sans admissions : « non calculable » n’est pas zéro', () {
      compare('sansFactures', calc(factures: const []));
      compare('sansAdmissions', calc(admissions: const []));
      expect(calc(admissions: const []).firstWhere((x) => x.id == 'occupation_lits').reel, 0, reason: 'zéro admission en cours sur 19 lits : 0 %, pas indisponible');
    });
    test('les sorties valorisées et le délai de transmission', () {
      final s = carte(mo['sorties']);
      final f90 = cpcFenetre(auj: auj), f30 = cpcFenetre(auj: auj, jours: 30);
      expect(pilSortiesValorisees(mouvements: col('mouvements'), produits: col('produits'), fenetre: f90), s['j90']);
      expect(pilSortiesValorisees(mouvements: col('mouvements'), produits: col('produits'), fenetre: f30), s['j30']);
      expect(pilDelaiTransmission(col('facturesMere')), mo['delaiTransmission']);
    });
    test('la grille à l’écran : les quatre compteurs, les lignes par axe', () {
      final g = carte(d['grille']);
      final ind = calc();
      final c = pilCompteGrille(ind);
      expect([c.atteints, c.vigilance, c.alertes, c.indisponibles].map((x) => '$x'), [for (final k in (g['kpis'] as List)) (k as List)[1]]);
      final tabs = liste(g['tables']);
      var t = 0;
      for (final axe in pilAxesPilotage) {
        final l = ind.where((x) => x.axe == axe.$1).toList();
        if (l.isEmpty) continue;
        final e = tabs[t++];
        expect(e['titre'], axe.$2);
        final rows = (e['lignes'] as List).map((r) => (r as List).map((c) => nt(c).toUpperCase()).toList()).toList();
        expect(rows.length, l.length);
        for (var i = 0; i < l.length; i++) {
          expect(rows[i], [
            nt('${l[i].label} ${l[i].aide ?? ''}').toUpperCase(),
            nt('${pilObjectifTexte(l[i])}${l[i].aValider ? 'À VALIDER' : ''}').toUpperCase(),
            nt(pilValeurIndicateur(l[i])).toUpperCase(),
            nt(pilEcartTexte(l[i])).toUpperCase(),
            nt(pilLibelleEtat(l[i].etat)).toUpperCase(),
          ]);
        }
      }
    });
    test('l’état imprimé reprend les mêmes lignes', () {
      final p = carte(d['piece']);
      final ind = calc();
      final texte = sans(p['contenu']);
      for (final x in ind) {
        expect(texte, contains(sans(pilValeurIndicateur(x))), reason: x.id);
        expect(texte, contains(sans(pilLibelleEtat(x.etat))), reason: x.id);
      }
    });
  });

  // =====================================================================================================================================
  group('dash-admin : supervision technique', () {
    final a = carte(v['admin']);
    PilVue calc() {
      final k = carte(a['constantes']);
      return pilAdmin(
          personnel: col('personnel'),
          audit: col('audit'),
          patients: col('patients').length,
          produits: col('produits').length,
          analyses: k['analyses'] as int,
          assureurs: k['assureurs'] as int,
          comptes: k['plan'] as int);
    }

    test('indicateurs, intégrité des référentiels et répartition des actions par module', () {
      final d = carte(a['defaut']);
      final vue = calc();
      kpis(vue, d['kpis'], 'admin');
      graphiques(vue, d['graphiques'], 'admin');
      classements(vue, d['classements'], 'admin');
    });
  });

  // =====================================================================================================================================
  group('dash-direction : pilotage stratégique', () {
    final d = carte(v['direction']);
    PilDirection calc({List<F>? echeances, List<F>? produits, List<F>? lots}) => pilDirection(
        factures: col('factures'),
        consultations: col('consultations'),
        produits: produits ?? col('produits'),
        patients: col('patients'),
        admissions: col('admissions'),
        personnel: col('personnel'),
        lots: lots ?? col('lots'),
        echeances: echeances ?? col('echeancesFiscales'),
        facturesFournisseurs: col('facturesFournisseurs'),
        mouvements: col('mouvements'),
        facturesMere: col('facturesMere'),
        objectifs: jeu('objectifsPilotage'),
        auj: auj,
        libelleMode: libelleMode,
        refMois: aout);
    test('les douze indicateurs, les quatre graphiques et le classement par service', () {
      final a = carte(d['defaut']);
      final r = calc();
      kpis(r.vue, a['kpis'], 'direction');
      graphiques(r.vue, a['graphiques'], 'direction');
      classements(r.vue, a['classements'], 'direction');
    });
    test('le bandeau d’alertes, le premier regard (échéances dépassées) et les indicateurs au-delà du seuil', () {
      final texte = nt(carte(d['defaut'])['texte']);
      final r = calc();
      expect(texte, contains('${r.ruptures} produit(s) sous le seuil d’alerte'));
      expect(texte, contains('${r.perimes} lot(s) périmé(s) à retourner'));
      expect(texte, contains('${r.peremptionProche} lot(s) à péremption proche (FEFO)'));
      expect(texte, contains('${r.echeancesDepassees} échéance(s) fiscale(s) dépassée(s)'));
      expect(texte, contains('${r.enAlerte.length} indicateur(s) au-delà du seuil d’alerte : ${r.enAlerte.join(' · ')}.'));
    });
    test('aucune échéance en retard : le premier regard le dit', () {
      final r = calc(echeances: [for (final e in col('echeancesFiscales')) {...e, 'paye': true}]);
      expect(r.echeancesDepassees, 0);
      expect(nt(carte(d['sansEcheance'])['texte']), contains('Aucune échéance fiscale en retard.'));
    });
    test('rien sous le seuil, rien de périmé : le bandeau disparaît', () {
      final r = calc(produits: [for (final p in col('produits')) {...p, 'stock': pilN(p['seuilAlerte']) + 5}], lots: [for (final l in col('lots')) {...l, 'statut': 'valide'}]);
      expect(r.ruptures, 0);
      expect(r.perimes, 0);
      expect(nt(carte(d['sansAlerte'])['texte']), isNot(contains('sous le seuil d’alerte')));
    });
    test('le rapport d’activité imprimé', () {
      final r = calc();
      final contenu = sans(carte(d['piece'])['contenu']);
      expect(contenu, sans('IndicateurValeur${[for (final l in r.lignesRapport) '${l.$1}${l.$2}'].join()}'));
    });
  });

  // =====================================================================================================================================
  group('dash-da : la caisse du jour et les cumuls par périodicité', () {
    final da = carte(v['da']);
    final fs = col('factures'), dem = col('demandesAnalyses'), cons = col('consultations');
    test('la caisse du jour : l’encaissé n’est pas le facturé', () {
      final jour = iso(auj);
      final m = pilMesuresDa(factures: fs, demandesAnalyses: dem, consultations: cons, filtre: (d) => pilJour(d) == jour);
      final ks = pilKpisCaisseDuJour(m);
      final e = ((carte(da['defaut'])['kpis'] as List).sublist(4)).cast<List>();
      expect([for (final k in ks) [k.libelle, nt(k.valeur), k.indice]], [for (final k in e) [k[0], nt(k[1]), k[2]]]);
    });
    test('la plage libre : pièces émises, facturé, encaissé, dépenses', () {
      final p = carte(da['plage']);
      for (final (nom, du, au) in [('sept', '2026-09-01', '2026-09-30'), ('tout', '2026-01-01', '2026-12-31'), ('vide', '2030-01-01', '2030-02-01')]) {
        final ks = pilKpisPlageDa(fs, col('depenses'), du, au);
        final e = (carte(p[nom])['kpis'] as List).sublist(0, 4).cast<List>();
        expect([for (final k in ks) [k.libelle, nt(k.valeur)]], [for (final k in e) [k[0], nt(k[1])]], reason: nom);
      }
    });
    final onglets = carte(da['onglets']);
    DateTime ancre(String code, String a) {
      if (code == 'jour' || code == 'semaine') return DateTime.parse(a);
      if (code == 'annee') return DateTime(int.parse(a), 1, 15);
      return DateTime(2026, int.parse(a) + 1, 15);
    }

    for (final code in pilPeriodicitesDa.map((p) => p.$1)) {
      final o = carte(onglets[code]);
      final unites = carte(o['unites']);
      for (final a in unites.keys) {
        test('$code, ancre $a : bornes calendaires, comparaison à la période de même nature qui précède', () {
          final u = carte(unites[a]);
          final p = pilPanneauDa(code: code, ancre: ancre(code, a), factures: fs, demandesAnalyses: dem, consultations: cons);
          expect(nt(p.note), nt(u['note']));
          graphiques(PilVue(graphiques: [p.repartition]), u['graphiques'], '$code/$a');
          final tabs = liste(u['tables']);
          if (tabs.isNotEmpty) {
            final rows = (tabs.first['lignes'] as List).map((l) => (l as List).map(nt).toList()).toList();
            for (var i = 0; i < rows.length; i++) {
              expect([p.lignes[i].grandeur, nt(p.lignes[i].texteCourant), nt(p.lignes[i].textePrecedent), p.lignes[i].texteVariation], rows[i], reason: '$code/$a ligne $i');
            }
          }
        });
      }
    }
    test('la semaine commence le lundi ; le trimestre et le semestre sont calendaires', () {
      final s = pilBornesDa('semaine', DateTime(2026, 10, 30));
      expect([dateFR(s.debut), dateFR(s.fin)], ['26/10/2026', '01/11/2026']);
      expect(dateFR(pilBornesDa('trimestre', DateTime(2026, 8, 14)).debut), '01/07/2026');
      expect(dateFR(pilBornesDa('trimestre', DateTime(2026, 8, 14)).fin), '30/09/2026');
      expect(dateFR(pilBornesDa('semestre', DateTime(2026, 3, 3)).fin), '30/06/2026');
      expect(dateFR(pilBornesPrecedenteDa('mois', DateTime(2026, 3, 3)).fin), '28/02/2026');
    });
    test('une période précédente nulle n’a pas de variation : « pas de base de comparaison »', () {
      expect(pilVariation(10, 0), isNull);
      expect(pilVariation(15, 10), 50);
      expect(pilVariation(5, 10), -50);
    });
  });

  // =====================================================================================================================================
  group('dash-croise : une source, deux axes, une mesure, une période', () {
    final cr = carte(v['croise']);
    final d = PilDonneesCroise(
        auj: auj,
        consultations: col('consultations'),
        prescriptions: col('prescriptions'),
        demandesAnalyses: col('demandesAnalyses'),
        mouvements: col('mouvements'),
        produits: col('produits'),
        factures: col('factures'),
        patients: col('patients'),
        personnel: col('personnel'),
        actes: col('actes'),
        administrations: col('administrations'),
        planning: col('planning'));
    test('les dix sources, dans l’ordre', () {
      expect([for (final s in pilSourcesCroise) [s.code, s.libelle]], [for (final o in (cr['sourcesOptions'] as List)) (o as List).cast<String>()]);
    });
    void verifie(PilSource s, String l, String? c, String mesure, String periode, F a, String ou) {
      final r = pilCroiser(source: s, donnees: d, lignes: l, colonnes: c, mesure: mesure, periode: periode);
      final k = (a['kpis'] as List).map((x) => (x as List).cast<Object?>()).toList();
      expect(nt(s.libelle), nt(k[0][1]), reason: '$ou : source');
      expect(nombre(r.effectif), nt(k[1][1]), reason: '$ou : enregistrements');
      expect(nt(pilTexteMesure(r.mesure, r.total)), nt(k[2][1]), reason: '$ou : ${r.mesure.libelle}');
      expect(k[2][0], r.mesure.libelle, reason: ou);
      expect('${nombre(r.lignes.length)} × ${nombre(r.colonnes.length)}', nt(k[3][1]), reason: '$ou : croisement');
      final t = a['table'] as Map?;
      if (r.lignes.isEmpty) {
        expect(t, isNull, reason: '$ou : aucune donnée, aucun tableau');
        return;
      }
      final fmt = (num x) => r.mesure.unite == 'FCFA' ? money(x) : nombre(x);
      expect(t!['titre'], '${r.mesure.libelle} — ${s.axes[l]!.libelle}${c != null && c.isNotEmpty ? ' × ${s.axes[c]!.libelle}' : ''}', reason: ou);
      expect([for (final h in (t['entetes'] as List)) '$h'.toUpperCase()], [s.axes[l]!.libelle.toUpperCase(), ...r.colonnes.map((x) => x.toUpperCase()), 'TOTAL'], reason: '$ou : en-têtes');
      final lignes = [
        for (final ln in pilCroiseOrdre(r))
          [ln, for (final col in r.colonnes) (r.table[ln]![col] ?? 0) != 0 ? fmt(r.table[ln]![col]!) : '—', fmt(r.totalLigne(ln))],
        ['TOTAL', for (final col in r.colonnes) (r.totauxColonnes[col] ?? 0) != 0 ? fmt(r.totauxColonnes[col]!) : '—', fmt(r.total)],
      ];
      final e = (t['lignes'] as List).map((x) => (x as List).map(nt).toList()).toList();
      for (var i = 0; i < e.length; i++) {
        expect(lignes[i].map(nt).toList(), e[i], reason: '$ou : ligne $i');
      }
      final g = liste(a['graphiques']);
      final top = pilCroiseTop(r);
      expect([for (final x in top) x.$1], (g.first['etiquettes'] as List).cast<String>(), reason: '$ou : top 12');
      expect([for (final x in top) x.$2], ((g.first['series'] as List).first as Map)['data'], reason: '$ou : valeurs du top 12');
    }

    final srcs = carte(cr['sources']);
    for (final s in pilSourcesCroise) {
      final e = carte(srcs[s.code]);
      test('${s.code} : axes, mesures et périodes proposés', () {
        expect([for (final a in s.axes.entries) [a.key, a.value.libelle]], [for (final o in (e['axes'] as List)) (o as List).cast<String>()]);
        expect([for (final m in s.mesures.entries) [m.key, m.value.libelle]], [for (final o in (e['mesures'] as List)) (o as List).cast<String>()]);
        expect([for (final p in pilPeriodesCroise) [p.$1, p.$2]], [for (final o in (e['periodes'] as List)) (o as List).cast<String>()]);
      });
      final axes = s.axes.keys.toList(), mes = s.mesures.keys.toList();
      test('${s.code} : le choix par défaut sur 30 jours, puis sur tout l’historique', () {
        verifie(s, axes[0], axes.length > 1 ? axes[1] : null, mes[0], 'mois', carte(e['defaut']), '${s.code}/défaut');
        verifie(s, axes[0], axes.length > 1 ? axes[1] : null, mes[0], 'tout', carte(e['toutDefaut']), '${s.code}/tout');
      });
      test('${s.code} : les croisements deux à deux', () {
        final combos = carte(e['combos']);
        for (final k in combos.keys) {
          final p = k.split('|');
          verifie(s, p[0], p[1].isEmpty ? null : p[1], mes[0], 'tout', carte(combos[k]), '${s.code}/$k');
        }
      });
      test('${s.code} : chaque mesure, chaque période', () {
        final ml = carte(e['mesuresLues']);
        for (final k in ml.keys) {
          verifie(s, axes[0], axes.length > 1 ? axes[1] : null, k, 'tout', carte(ml[k]), '${s.code}/mesure $k');
        }
        final pl = carte(e['periodesLues']);
        for (final k in pl.keys) {
          verifie(s, axes[0], axes.length > 1 ? axes[1] : null, mes[0], k, carte(pl[k]), '${s.code}/période $k');
        }
      });
    }
  });
}
