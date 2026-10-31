// Rejoue les vecteurs de M13 (prototype_html/build/vecteurs-administration.js) : les huit écrans RÉELS de l'administration pilotés dans Chrome à l'horloge
// 30/10/2026 10 h. Ici, les RÈGLES : indicateurs, références (série du registre, jamais un compteur de page), délais, ordre des cartes d'appel,
// entretien échu, amorçages.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
List<M> liste(Object? o) => [for (final x in (o as List)) obj(x)];
M lire(String nom) => obj(jsonDecode(File('test/vecteurs/$nom.json').readAsStringSync()));
List<M> jeuDossier(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));

String s(Object? v) => '$v'.replaceAll(RegExp(r'[\s  ]'), '');
final maintenant = DateTime(2026, 10, 30, 10);

List<M> actives(Object? jeu) => [for (final f in liste(jeu)) if (f['statut'] != 'archive') f];

void kpisEgaux(List<AdmKpi> obtenus, Object? attendus, {String contexte = ''}) {
  final a = liste(attendus);
  expect(obtenus.length, a.length, reason: contexte);
  for (var i = 0; i < a.length; i++) {
    expect(obtenus[i].libelle, a[i]['libelle'], reason: contexte);
    expect(s(obtenus[i].valeur), s(a[i]['valeur']), reason: '$contexte ${a[i]['libelle']}');
    expect(obtenus[i].indice, a[i]['indice'], reason: '$contexte indice ${a[i]['libelle']}');
  }
}

void main() {
  final v = lire('administration');

  group('notes de service (NS 131 / NS 132)', () {
    final n = obj(v['notes']);
    test('référentiels engendrés = D.NS131 / D.NS132 de la maquette', () {
      expect(admNs131.reference, obj(n['ns131'])['reference']);
      expect(admNs131.dateEffet, obj(n['ns131'])['dateEffet']);
      expect(admNs132.reference, obj(n['ns132'])['reference']);
      expect(admCriteresNs131.length, liste(obj(n['ns131'])['criteres']).length);
      expect(admPrimesNs132.length, liste(obj(n['ns132'])['primes']).length);
      expect(admFonctions.length, liste(n['fonctions']).length);
    });
    test('indicateurs de l’écran', () {
      kpisEgaux(admKpisNotesService(n['agents'] as int), obj(n['ecran'])['kpis']);
    });
    test('tableau NS 131 : sanctions en %, tableau NS 132 : mode et premier mot des fonctions', () {
      final t = liste(obj(n['ecran'])['tableaux']);
      for (var i = 0; i < admCriteresNs131.length; i++) {
        final c = admCriteresNs131[i];
        final ligne = (t[0]['lignes'] as List)[i] as List;
        expect(c.numero, ligne[0]);
        expect(c.libelle, ligne[1]);
        expect(s('− ${c.moyenne} %'), s(ligne[2]));
        expect(s('− ${c.faible} %'), s(ligne[3]));
      }
      for (var i = 0; i < admPrimesNs132.length; i++) {
        final p = admPrimesNs132[i];
        final ligne = (t[1]['lignes'] as List)[i] as List;
        expect(p.libelle, ligne[0]);
        expect(admModePrime(p.mode), ligne[1]);
        expect(p.montants.keys.map(admLibelleCourtFonction).join(' '), ligne[2]);
      }
    });
  });

  group('courriers', () {
    final c = obj(v['courriers']);
    final jeu = c['jeu'];
    test('indicateurs sur les courriers ACTIFS', () {
      kpisEgaux(admKpisCourriers(actives(jeu)), obj(c['ecran'])['kpis']);
    });
    test('référence : série annuelle ARR/DEP-AAAA-NNNN, millésime = année de la date, rang par sens et par année (E538 levé)', () {
      final arr = obj(obj(c['creation'])['arrivee'])['fiche'] as M, dep = obj(obj(c['creation'])['depart'])['fiche'] as M;
      expect(admReferenceCourrier('arrivee', arr['date'], liste(jeu)), arr['reference']);
      expect(admReferenceCourrier('depart', dep['date'], liste(jeu)), dep['reference']);
      final serie = [
        {'reference': 'ARR-2026-0007', 'statut': 'archive'},
        {'reference': 'ARR-2027-0002'},
        {'reference': 'DEP-2026-0003'}
      ];
      expect(admReferenceCourrier('arrivee', '2026-12-31', serie), 'ARR-2026-0008');
      expect(admReferenceCourrier('arrivee', '2027-01-02', serie), 'ARR-2027-0003');
      expect(admReferenceCourrier('depart', '2026-05-05', serie), 'DEP-2026-0004');
      expect(admReferenceCourrier('depart', '2028-01-01', serie), 'DEP-2028-0001');
      expect(admExercicesCourriers(serie.map((x) => {...x, 'date': '2026-01-01'}), 2030), '2026');
      expect(admExercicesCourriers(const [], 2030), '2030');
    });
    test('traitements : libellé et ton', () {
      expect(admTraitementCourrier('traite'), ('Traité', 'success'));
      expect(admTraitementCourrier('en_cours'), ('En cours', 'info'));
      expect(admTraitementCourrier('en_attente'), ('En attente', 'warning'));
      expect(admTraitementCourrier('autre'), ('—', 'neutral'));
    });
    test('filtre Service : cinq services (liste du formulaire : sept)', () {
      final f = (c['filtres'] as List).cast<List>().firstWhere((x) => x[0] == 'Service');
      expect([for (final o in (f[1] as List).skip(1)) (o as List)[0]], admServicesFiltreCourrier);
      expect(admServicesFiltreCourrier.length, 5);
      expect(admServicesCourrier.length, 7);
    });
  });

  group('réunions', () {
    final r = obj(v['reunions']);
    test('statut À venir / Tenue : la date du jour est « Tenue » (AUJ porte l’heure)', () {
      final lignes = ((((r['ecran'] as Map)['tableaux'] as List)[0] as Map)['lignes'] as List).cast<List>();
      for (final f in actives(r['jeu'])) {
        final ligne = lignes.firstWhere((l) => l[0] == f['reference']);
        expect(admReunionAVenir(f, maintenant) ? 'À venir' : 'Tenue', ligne[7], reason: '${f['reference']}');
      }
    });
    test('indicateurs', () {
      kpisEgaux(admKpisReunions(actives(r['jeu']), maintenant), obj(r['ecran'])['kpis']);
    });
    test('référence : série du registre (E531), archivés compris — plus RU-2026-001 en doublon', () {
      expect(admReferenceSuivante('RU-2026-', 3, liste(r['jeu'])), (obj(obj(r['creation'])['creee'])['fiche'] as M)['reference']);
      expect(admReferenceSuivante('RU-2026-', 3, liste(r['jeu'])), 'RU-2026-009');
    });
  });

  group('événements', () {
    final e = obj(v['evenements']);
    final rows = actives(e['jeu']);
    test('indicateurs', () => kpisEgaux(admKpisEvenements(rows, maintenant), obj(e['ecran'])['kpis']));
    test('prochains événements : six au plus, du plus proche au plus lointain, délai et urgence', () {
      final p = admProchainsEvenements(rows, maintenant);
      final brut = (e['prochainsBrut'] as List).cast<String>();
      final rouges = (e['prochainsRouges'] as List).cast<bool>();
      expect(p.length, 6);
      for (var i = 0; i < p.length; i++) {
        final j = admJoursAvant(maintenant, p[i]['date']);
        expect(brut[i], contains(admDelaiEvenement(j)), reason: '${p[i]['libelle']}');
        expect(brut[i], contains('${p[i]['libelle']}'));
        expect(admDelaiUrgent(j), rouges[i], reason: '${p[i]['libelle']}');
        expect(brut[i], contains(dateJour(admDate(p[i]['date'])!)));
      }
    });
    test('catégories du filtre : triées, une fois chacune', () {
      final f = (e['filtres'] as List)[0] as List;
      final opts = [for (final o in (f[1] as List).skip(1)) (o as List)[0]];
      expect(admCategoriesPresentes(rows), opts);
    });
    test('référence de création : EVT- + effectif + 1', () {
      expect(admReferenceEvenement(10), (obj(obj(e['creation'])['avecNotif'])['fiche'] as M)['reference']);
      expect(admReferenceEvenement(11), (obj(obj(e['creation'])['sansNotif'])['fiche'] as M)['reference']);
    });
    test('canaux à la modification (E532) : cocher pose « In-app », décocher les retire', () {
      expect(admCanauxEvenement(true, <Object?>[]), ['In-app']);
      expect(admCanauxEvenement(true, ['SMS']), ['SMS']);
      expect(admCanauxEvenement(false, ['SMS']), isEmpty);
      expect((obj(obj(e['modification'])['enregistre'])['fiche'] as M)['canaux'], ['In-app']);
    });
    test('notifications système : dix lignes, canaux', () {
      final t = obj(e['notifications'])['lignes'] as List;
      expect(admNotificationsSysteme.length, t.length);
      for (var i = 0; i < t.length; i++) {
        final l = t[i] as List;
        expect(admNotificationsSysteme[i].$1, l[0]);
        expect(admNotificationsSysteme[i].$2, l[1]);
        expect(admNotificationsSysteme[i].$3.join(' '), l[2]);
      }
    });
    test('amorçage à froid = jeu exporté de la maquette (graine 2713)', () {
      final jeuDossier0 = jeuDossier('evenementsEtablissement');
      final personnel = [for (final p in jeuDossier('personnel')) if (p['statut'] != 'archive') '${p['nomComplet']}'];
      final a = admAmorcerEvenements(maintenant, personnel);
      expect(a.length, jeuDossier0.length);
      for (var i = 0; i < a.length; i++) {
        final att = jeuDossier0[i];
        for (final k in ['id', 'reference', 'libelle', 'categorie', 'date', 'heure', 'lieu', 'responsable', 'notifier', 'canaux']) {
          expect(a[i][k], att[k], reason: '${att['reference']} $k');
        }
      }
    });
  });

  group('plan annuel', () {
    final p = obj(v['planAnnuel']);
    final rows = actives(p['jeu']);
    test('indicateurs', () => kpisEgaux(admKpisPlan(rows), obj(p['ecran'])['kpis']));
    test('diagramme : ordre par trimestre de début, barres et ton par état', () {
      final gantt = (p['gantt'] as List).cast<List>();
      final tri = admTrierPlan(rows);
      expect(tri.length, gantt.length);
      for (var i = 0; i < tri.length; i++) {
        expect('${tri[i]['action']}', gantt[i][0]);
        for (var q = 1; q <= 4; q++) {
          final attendu = admTrimestreActif(tri[i], q) ? 'bg-${admTonAvancement(tri[i]['avancement'])}-400' : 'bg-slate-100';
          expect(attendu, gantt[i][1 + q], reason: '${tri[i]['action']} T$q');
        }
      }
    });
    test('amorçage = jeu exporté', () {
      final jeu = jeuDossier('planAnnuel');
      final a = admAmorcerPlan();
      expect(a.length, jeu.length);
      for (var i = 0; i < a.length; i++) {
        for (final k in ['id', 'reference', 'action', 'axe', 'trimestreDebut', 'trimestreFin', 'avancement', 'responsable']) {
          expect(a[i][k], jeu[i][k], reason: '${jeu[i]['reference']} $k');
        }
      }
    });
    test('modifier une action garde son ÉTAT (E533) : le pourcentage est un autre champ', () {
      final f = obj(obj(p['modification'])['enregistre'])['fiche'] as M;
      expect(f['avancement'], 'En cours');
      expect(obj(p['avancementNumerique'])['fiche'], containsPair('tauxAvancement', 60));
    });
  });

  group('interventions d’ambulance', () {
    final a = obj(v['ambulance']);
    final rows = actives(a['jeu']);
    test('indicateurs (mois en cours, kilométrage, recettes des interventions facturées)', () {
      kpisEgaux(admKpisInterventions(rows, maintenant), obj(a['ecran'])['kpis']);
    });
    test('montant par défaut : 5 000 F + 500 F par km quand aucun tarif n’est saisi', () {
      expect(admTarifAmbulance('', '20'), 15000);
      expect(admTarifAmbulance(null, 20), 15000);
      expect(admTarifAmbulance('9000', 5), 9000);
      expect(admTarifAmbulance('', 'abc'), 5000);
      expect((obj(obj(a['creation'])['tarifCalcule'])['fiche'] as M)['tarif'], 15000);
      expect((obj(obj(a['creation'])['tarifSaisi'])['fiche'] as M)['tarif'], 9000);
    });
    test('référence : série du registre (E534) — plus AM-2026-0001 en doublon', () {
      expect(admReferenceSuivante('AM-2026-', 4, liste(a['jeu'])), (obj(obj(a['creation'])['tarifCalcule'])['fiche'] as M)['reference']);
      expect(admReferenceSuivante('AM-2026-', 4, liste(a['jeu'])), 'AM-2026-0008');
    });
    test('états de l’intervention', () {
      expect(admEtatsIntervention['demandee'], ('Demandée', 'warning'));
      expect(admEtatsIntervention['terminee'], ('Terminée', 'success'));
    });
  });

  group('répertoire des ambulances', () {
    final r = obj(v['repertoire']);
    final rows = actives(r['jeu']);
    test('indicateurs : disponibles joignables, numéros à renseigner, non vérifiés depuis 90 j (jamais vérifié compris)', () {
      kpisEgaux(admKpisRepertoire(rows, maintenant), obj(r['ecran'])['kpis']);
    });
    test('cartes d’appel : disponibles d’abord, clinique avant l’extérieur, puis libellé', () {
      final cartes = liste(r['cartes']);
      final ordre = admOrdreAppelRapide(rows);
      expect(ordre.length, cartes.length);
      for (var i = 0; i < ordre.length; i++) {
        expect(cartes[i]['texte'], startsWith('${ordre[i]['libelle']}'));
        expect(cartes[i]['classe'] == 'vert', ordre[i]['disponibilite'] == 'disponible' && admVrai(ordre[i]['telephone']));
      }
    });
    test('numéro cliquable : tel: sans espaces ; vérification : 90 j exactement n’est PAS périmé, 91 j l’est ; jamais vérifié l’est', () {
      final cartes = liste(r['cartes']);
      final ordre = admOrdreAppelRapide(rows);
      for (var i = 0; i < ordre.length; i++) {
        final liens = (cartes[i]['liens'] as List).cast<List>();
        if (!admVrai(ordre[i]['telephone'])) {
          expect(liens, isEmpty);
          continue;
        }
        expect(admHrefTel(ordre[i]['telephone']), liens[0][1]);
        final alerte = admAlerteVerification(ordre[i], maintenant);
        final texte = '${cartes[i]['texte']}';
        if (alerte == null) {
          expect(texte, isNot(contains('vérifié')));
        } else {
          expect(texte, contains(alerte));
        }
      }
      expect(admAlerteVerification({'telephone': '1', 'verifieLe': '2026-08-01'}, maintenant), isNull);
      expect(admAlerteVerification({'telephone': '1', 'verifieLe': '2026-07-31'}, maintenant), 'Non vérifié depuis 91 jours');
      expect(admAlerteVerification({'telephone': '1'}, maintenant), 'Jamais vérifié');
      expect(admAlerteVerification({'verifieLe': '2020-01-01'}, maintenant), isNull);
    });
    test('note « fiche(s) sans numéro » : jamais de numéro inventé', () {
      final n = (obj(r['ecran'])['notes'] as List).cast<String>();
      expect(admNoteSansNumero(rows), n[0]);
      expect(admNoteAppelRapide, n[1]);
      expect(admNoteSansNumero([for (final x in rows) if (admVrai(x['telephone'])) x]), isNull);
    });
    test('tableau trié par désignation, jours depuis la vérification', () {
      final t = (obj(r['tableau'])['lignes'] as List).cast<List>();
      final tri = admTrierRepertoire(rows);
      for (var i = 0; i < tri.length; i++) {
        expect(tri[i]['libelle'], t[i][0]);
        final j = admJoursDepuis(tri[i]['verifieLe'], maintenant);
        expect(j == null ? 'jamais' : '${admDateFR(tri[i]['verifieLe'])} ($j j)', t[i][6]);
      }
    });
    test('fiche créée à l’accueil : date du jour, à compléter sans numéro (E535 : le numéro n’est plus obligatoire)', () {
      final f = obj(obj(obj(r['creation'])['sansNumero'])['derniere']);
      final att = admFicheAmbulance({'libelle': 'Sapeurs-pompiers', 'telephone': ''}, maintenant);
      expect(att['verifieLe'], f['verifieLe']);
      expect(att['aCompleter'], true);
      expect(att['source'], f['source']);
      expect(admFicheAmbulance({'telephone': '+229 90 00 00 09'}, maintenant)['aCompleter'], false);
    });
    test('amorçage à froid = ce que la maquette sème (ordre d’insertion, numéros de l’en-tête officiel, aucun numéro inventé)', () {
      final a = admAmorcerRepertoire(maintenant, [for (final t in (r['brand'] as List)) '$t'], 'TCHANE Nourou');
      // la maquette insère en TÊTE : sa collection est l'ordre inverse.
      final att = liste(obj(r['amorcage'])['fiches']);
      expect(a.length, att.length);
      for (final (i, f) in a.reversed.indexed) {
        for (final k in ['libelle', 'type', 'contact', 'base', 'disponibilite', 'aCompleter', 'source']) {
          expect(f[k], att[i][k], reason: '${att[i]['libelle']} $k');
        }
        expect(f['telephone'], att[i]['telephone'], reason: '${att[i]['libelle']} téléphone');
        expect(f['verifieLe'], att[i]['verifieLe'], reason: '${att[i]['libelle']} vérifié');
      }
    });
  });

  group('l’après-midi (15 h) : tout se compte PAR JOUR et par DÉBUT (E540)', () {
    final am = obj(v['apresMidi']);
    final quinzeHeures = DateTime(2026, 10, 30, 15);
    test('événements : demain se lit « Dans 1 j » (jamais « Aujourd’hui »), ceux du jour restent à venir et en tête', () {
      final e = obj(am['evenements']);
      final rows = actives(e['jeu']);
      kpisEgaux(admKpisEvenements(rows, quinzeHeures), e['kpis']);
      final p = admProchainsEvenements(rows, quinzeHeures);
      final brut = (e['prochainsBrut'] as List).cast<String>();
      final rouges = (e['prochainsRouges'] as List).cast<bool>();
      expect(p.length, brut.length);
      for (var i = 0; i < p.length; i++) {
        final j = admJoursAvant(quinzeHeures, p[i]['date']);
        expect(brut[i], contains(admDelaiEvenement(j)), reason: '${p[i]['libelle']}');
        expect(admDelaiUrgent(j), rouges[i]);
      }
      expect(admJoursAvant(quinzeHeures, '2026-10-31'), 1);
      expect(admJoursAvant(quinzeHeures, '2026-10-30'), 0);
      expect(admJoursAvant(DateTime(2026, 10, 30, 23, 59), '2026-10-31'), 1);
    });
    test('réunions : une réunion du jour est « À venir » jusqu’à son heure de début, « Tenue » une minute après', () {
      final r = obj(am['reunions']);
      kpisEgaux(admKpisReunions(actives(r['jeu']), quinzeHeures), r['kpis']);
      final lignes = (obj(r['tableau'])['lignes'] as List).cast<List>();
      for (final f in actives(r['jeu'])) {
        final ligne = lignes.firstWhere((l) => l[0] == f['reference']);
        expect(admReunionAVenir(f, quinzeHeures) ? 'À venir' : 'Tenue', ligne[7], reason: '${f['reference']}');
      }
      final seize = {'date': '2026-10-30', 'heure': '16:00'};
      expect(admReunionAVenir(seize, quinzeHeures), isTrue);
      expect(admReunionAVenir(seize, DateTime(2026, 10, 30, 16)), isTrue, reason: 'à l’heure dite, elle commence');
      expect(admReunionAVenir(seize, DateTime(2026, 10, 30, 16, 1)), isFalse);
      expect(admHeure('9:05'), '09:05');
    });
    test('répertoire : vérifié ce matin = « 0 j » même l’après-midi', () {
      final r = obj(am['repertoire']);
      kpisEgaux(admKpisRepertoire(actives(r['jeu']), quinzeHeures), r['kpis']);
      final t = (obj(r['tableau'])['lignes'] as List).cast<List>();
      for (final f in admTrierRepertoire(actives(r['jeu']))) {
        final ligne = t.firstWhere((l) => l[0] == f['libelle']);
        final j = admJoursDepuis(f['verifieLe'], quinzeHeures);
        expect(j == null ? 'jamais' : '${admDateFR(f['verifieLe'])} ($j j)', ligne[6], reason: '${f['libelle']}');
      }
    });
  });

  group('parc technique & maintenance', () {
    final m = obj(v['maintenance']);
    final rows = actives(m['jeu']);
    test('indicateurs', () => kpisEgaux(admKpisMateriel(rows, maintenant), obj(m['ecran'])['kpis']));
    test('filtre Suivi : panne / entretien échu / fiche à compléter', () {
      for (final cas in liste(m['filtreCas'])) {
        final refs = [for (final r in rows) if (admSuiviMateriel(r, '${cas['valeur']}', maintenant)) '${r['reference']}'];
        final att = (cas['lignes'] as List).cast<String>();
        expect(refs.toSet(), att.toSet(), reason: '${cas['valeur']}');
      }
    });
    test('un équipement RÉFORMÉ n’est jamais « échu » (E536) ; sans périodicité ni date, jamais échu', () {
      final reforme = rows.firstWhere((r) => r['etat'] == 'reforme');
      expect(admEntretienEchu(reforme, maintenant), isFalse);
      final sansPeriode = rows.firstWhere((r) => r['reference'] == 'EQ-007');
      expect(admEntretienEchu(sansPeriode, maintenant), isFalse);
      expect(admEntretienEchu(rows.firstWhere((r) => r['reference'] == 'EQ-006'), maintenant), isFalse);
    });
    test('« à compléter » disparaît par la SAISIE de marque, n° de série et mise en service', () {
      expect(admMaterielACompleter({'marque': 'APC', 'numeroSerie': 'X', 'miseEnService': '2023-01-01'}), isFalse);
      expect(admMaterielACompleter({'marque': 'APC', 'numeroSerie': 'X', 'miseEnService': ''}), isTrue);
      expect(admMaterielACompleter({}), isTrue);
    });
    test('référence : série du registre (E536) — plus EQ-001 en doublon', () {
      expect(admReferenceSuivante('EQ-', 3, liste(m['jeu'])), (obj(obj(m['creation'])['aCompleter'])['fiche'] as M)['reference']);
      expect(admReferenceSuivante('EQ-', 3, liste(m['jeu'])), 'EQ-009');
    });
    test('amorçage à froid = ce que la maquette sème (graine 1348), dates relatives à l’horloge', () {
      final a = admAmorcerMateriel(maintenant);
      final att = liste(obj(m['amorcage'])['fiches']);
      expect(a.length, 18);
      for (var i = 0; i < a.length; i++) {
        for (final k in ['id', 'reference', 'libelle', 'categorie', 'localisation', 'etat', 'periodiciteMois', 'dernierEntretien', 'aCompleter']) {
          expect(a[i][k], att[i][k], reason: '${att[i]['reference']} $k');
        }
        expect(a[i]['observation'], att[i]['observation']);
        expect(a[i].containsKey('marque'), isFalse, reason: 'jamais de marque inventée');
      }
    });
  });
}
