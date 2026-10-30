// M9 — assurances, créances & relances : les règles du domaine REJOUÉES sur ce que les écrans réels de la maquette ont affiché
// (vecteurs engendrés par `prototype_html/build/vecteurs-m9.js`, piloté dans Chrome, horloge au 16/08/2026 midi). Le JEU lu ici est celui du poste.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;

const jeu = '../../apps/poste/assets/donnees/jeu';
List<M> charger(String nom) =>
    liste(jsonDecode(File('$jeu/$nom.json').readAsStringSync()));

M m(Object? x) => (x as Map).cast<String, Object?>();
List<M> lm(Object? x) => liste(x);
/// `texte()` du pilote normalise TOUTE espace (U+202F, U+00A0 comprises) : on compare donc après la même normalisation.
String sp(String s) => s.replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');
String mo(Object? v) => sp(money(v));
String nb(Object? v) => sp(nombre(v));
String pc(Object? v) => sp(pourcent(v));
String f0(num v) => sp(money(v, avecDevise: false));
List<String> cellules(Object? ligne) =>
    [for (final c in (m(ligne)['cellules'] as List)) '$c'];

void main() {
  final v = lireVecteurs('ass_m9');
  final ecrans = m(v['ecrans']);
  final auj = DateTime.parse('${v['aujInstant']}');
  final jour = '${v['auj']}';
  final assureurs = charger('assureurs');
  final patients = charger('patients');
  final factures = charger('factures');
  final couvertures = charger('couverturesAssurance');
  final souscripteurs = charger('souscripteurs');
  final fa = assFacturesAssurance(factures);
  final assures = assAssures(patients);
  bool valide(M p) => carteValide(p, couvertures, jour);

  M ecran(String id) => m(ecrans[id]);
  List<M> lignesTable(M e, [int i = 0]) => lm(m((e['tables'] as List)[i])['lignes']);

  test('l’horloge des vecteurs est celle du banc (16/08/2026 midi)', () {
    expect(jour, '2026-08-16');
    expect(auj.hour, 12);
  });

  group('m9-dashboard', () {
    test('les huit indicateurs = ceux de l’écran réel', () {
      final k = assKpisDashboard(
          assureurs: assureurs,
          patients: patients,
          factures: factures,
          carteValide: valide);
      final lus = [for (final x in lm(ecran('m9-dashboard')['kpis'])) '${x['valeur']}'];
      expect(lus, [
        nb(k.compagnies),
        nb(k.assures),
        nb(k.valides),
        nb(k.expirees),
        nb(k.facturesAssurance),
        mo(k.creances),
        mo(k.creances),
        pc(k.tauxMoyen),
      ]);
    });

    test('le classement des créances par compagnie est décroissant et sans zéro',
        () {
      final texte = '${ecran('m9-dashboard')['texte']}';
      final ordre = [
        for (final a in assureurs)
          (a['code'], assCreance(fa, '${a['code']}'))
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      final attendu = [
        for (final x in ordre)
          if (x.$2 > 0) '${x.$1} ${f0(x.$2)}'
      ];
      var pos = texte.indexOf('Créances par compagnie');
      expect(pos, greaterThan(-1));
      for (final s in attendu) {
        final p = texte.indexOf(s, pos);
        expect(p, greaterThan(-1), reason: s);
        pos = p;
      }
    });
  });

  group('m9-compagnies', () {
    final e = ecran('m9-compagnies');
    test('KPI, assurés et créances par ligne', () {
      expect([for (final x in lm(e['kpis'])) '${x['valeur']}'], [
        nb(assureurs.length),
        nb(assureurs.where((a) => assConvention(a) == 'Signée').length),
        nb(assures.length),
        mo(assureurs.fold<double>(
            0, (a, x) => a + assCreance(fa, '${x['code']}'))),
      ]);
      for (final l in lignesTable(e)) {
        final c = cellules(l);
        final code = c[2];
        expect(c[7], nb(assures.where((p) => p['assureur'] == code).length));
        final cr = assCreance(fa, code);
        expect(c[8], cr > 0 ? f0(cr) : '—', reason: code);
      }
    });

    test('les cinq filtres avancés = les listes de l’écran', () {
      final res = m(e['filtresResultats']);
      expect(res.length, [for (final f in lm(e['filtres'])) (f['options'] as List).length - 1].fold<int>(0, (a, b) => a + b));
      res.forEach((cle, attendu) {
        final p = cle.split('|');
        final nom = switch (p[0]) {
          'Convention' => 'convention',
          'Créances' => 'creanceEtat',
          'Ancienneté de la dette' => 'anciennete',
          'Portefeuille d’assurés' => 'portefeuille',
          _ => 'carte',
        };
        final obtenu = [
          for (final a in assureurs)
            if (assFiltreCompagnie(nom, p[1], a,
                assures: assures,
                facturesAssurance: fa,
                carteValide: valide,
                auj: auj))
              '${a['n']}'
        ];
        expect(obtenu, [for (final x in attendu as List) '$x'], reason: cle);
      });
    });

    test('la création met les champs saisis et rien d’autre', () {
      final c = lm(m(m(e['creation'])['inserts'])['assureurs']).single;
      expect(c['code'], 'TST');
      expect(c['convention'], 'Suspendue');
      expect(c['statut'], 'actif');
      expect(e['formulaire'], [
        'Code *',
        'Raison sociale *',
        'Adresse électronique',
        'État de la convention',
        'Personne de contact',
        'Observations'
      ]);
    });
  });

  group('m9-assures', () {
    final e = ecran('m9-assures');
    test('KPI : assurés, valides, expirées, taux moyen', () {
      final exp = assures.where((p) => !valide(p)).length;
      expect([for (final x in lm(e['kpis'])) '${x['valeur']}'], [
        nb(assures.length),
        nb(assures.length - exp),
        nb(exp),
        pc(assSomme(assures, 'tauxPriseEnCharge') / assures.length),
      ]);
    });

    test('filtres : validité, compagnie, catégorie (première page de 15)', () {
      List<String> codes(Iterable<M> r) => [for (final p in r.take(15)) '${p['code']}'];
      final res = m(e['filtresResultats']);
      List<String> lus(String k) => [for (final x in res[k] as List) '$x'];
      expect(lus('Validité de la carte|valide'), codes(assures.where(valide)));
      expect(lus('Validité de la carte|expiree'), codes(assures.where((p) => !valide(p))));
      expect(lus('Compagnie|NSIA'), codes(assures.where((p) => p['assureur'] == 'NSIA')));
      for (final c in ['entreprise', 'particulier', 'personnel']) {
        expect(lus('Catégorie|$c'),
            codes(assures.where((p) => p['categorieAssurance'] == c)));
      }
    });

    test('la colonne « Validité (RG-09) » : Expirée / Expire dans N j / Valide', () {
      for (final l in lignesTable(e)) {
        final c = cellules(l);
        final p = assures.firstWhere((x) => x['code'] == c[0]);
        expect(c[8], assValidite(p, valide: valide(p), auj: auj), reason: c[0]);
      }
    });

    test('les vérifications citent le bon verdict et la bonne attestation', () {
      final ver = m(e['verifications']);
      for (final k in ['valide', 'expiree']) {
        final x = m(ver[k]);
        final p = assures.firstWhere((q) => q['code'] == x['code']);
        expect(valide(p), k == 'valide');
        final t = '${x['texte']}';
        expect(t, contains(k == 'valide' ? 'Carte valide — prise en charge applicable' : 'Carte expirée — prise en charge refusée'));
        final pc = m(x['piece']);
        final lignes = m((pc['tables'] as List).first)['lignes'] as List;
        expect((lignes.last as List).last, k == 'valide' ? 'CARTE VALIDE' : 'CARTE EXPIRÉE');
      }
    });

    for (final c in lm(v['changements'])) {
      test('couverture datée — ${c['nom']}', () {
        final entree = m(c['entree']);
        final patient = m(entree['patient']);
        final hist = lm(entree['historique']);
        final r = assChangerCouverture(patient, hist, m(entree['v']), auj);
        final sortie = m(c['sortie']);
        expect(r.ok, sortie['ok']);
        expect(r.motif, sortie['motif']);
        if (!r.ok) return;
        final inserts = lm(m(m(c['ecart'])['inserts'])['couverturesAssurance']);
        if (inserts.isNotEmpty) {
          final neuve = inserts.firstWhere((x) => x['motif'] != 'Couverture reprise du dossier à la première mise à jour');
          for (final k in ['assureur', 'numeroPolice', 'tauxPriseEnCharge', 'carteExpiration', 'debut', 'fin', 'motif', 'patientId']) {
            expect(r.nouvelle![k], neuve[k], reason: k);
          }
          final reprises = inserts.where((x) => x['motif'] == 'Couverture reprise du dossier à la première mise à jour');
          expect(r.reprise != null, reprises.isNotEmpty);
          if (r.reprise != null) {
            expect(r.reprise!['fin'], reprises.single['fin']);
            expect(r.reprise!['assureur'], reprises.single['assureur']);
            expect(r.reprise!['debut'], isNull);
          }
        }
        final patch = lm(m(m(c['ecart'])['modifs'])['patients'] ?? const []);
        final apres = c['patientApres'];
        if (apres != null) {
          final maj = {...patient, ...r.majPatient!};
          for (final k in r.majPatient!.keys) {
            final attendu = (apres as Map)[k];
            final a = maj[k];
            expect(a == null || a == 0 ? null : a, attendu == null || attendu == 0 ? null : attendu, reason: k);
          }
          expect(patch.length <= 1, isTrue);
        }
        if (c['historiqueApres'] != null) {
          // bascule datée du mois prochain : la fiche garde la couverture en force AUJOURD'HUI
          expect(r.majPatient!['numeroPolice'], isNot('NSIA/2026/0002'));
        }
      });
    }
  });

  group('m9-conventions', () {
    final e = ecran('m9-conventions');
    test('KPI avant toute saisie : le jeu ne porte aucune grille', () {
      final k = [for (final x in lm(e['kpis'])) '${x['valeur']}'];
      expect(k, ['9', '0', '9', '0']);
      expect(charger('garanties'), isEmpty);
      expect(souscripteurs.length, 9);
    });

    test('filtres des souscripteurs', () {
      final res = m(e['filtresResultats']);
      List<String> noms(Iterable<M> r) => [
            for (final s in r) '${s['nom']} ${s['police']}'
          ]..sort();
      for (final c in ['entreprise', 'particulier', 'personnel']) {
        expect(([for (final x in res['Catégorie|$c'] as List) '$x']..sort()),
            noms(souscripteurs.where((s) => s['categorie'] == c)));
      }
      expect(res['Convention|oui'], isEmpty);
      expect(([for (final x in res['Convention|non'] as List) '$x']..sort()), noms(souscripteurs));
    });

    test('saisie du barème : 20 garanties ajustées, convention marquée saisie', () {
      final s = souscripteurs.firstWhere((x) => x['id'] == 'SOU006');
      final taux = List<Object?>.filled(20, null)..[0] = '75';
      final plafonds = List<Object?>.generate(20, (i) => AssBareme.garanties[i]['plafond'])
        ..[0] = '6000'
        ..[1] = '';
      final g = assGarantiesDepuisBareme(s, taux: taux, plafonds: plafonds);
      final posees = lm(m(m(m(e['saisieBareme'])['ecart'])['inserts'])['garanties']);
      expect(g.length, 20);
      expect(posees.length, 20);
      // la maquette insère en tête : la dernière du barème est lue en premier
      final parCode = {for (final x in posees) x['code']: x};
      for (final x in g) {
        final p = m(parCode[x['code']]);
        for (final k in ['souscripteurId', 'assureur', 'libelle', 'categorie', 'taux', 'plafond', 'unitePlafond', 'zone', 'source']) {
          expect(x[k], p[k], reason: '${x['code']}.$k');
        }
      }
      final patch = lm(m(m(m(e['saisieBareme'])['ecart'])['modifs'])['souscripteurs']).single['patch'] as Map;
      final c = assConventionSaisie();
      for (final k in patch.keys) {
        expect(c[k], patch[k], reason: k);
      }
    });

    test('création d’un souscripteur : nom de la compagnie, listes vides, provenance', () {
      final cr = m(v['souscripteurCreation']);
      final fiche = lm(m(m(cr['ecart'])['inserts'])['souscripteurs']).single;
      final r = assSouscripteurDepuis({
        'nom': 'Employeur de test',
        'assureur': 'NSIA',
        'police': 'NSIA/2026/7777',
        'categorie': 'particulier',
        'effectif': 12,
        'contact': 'Mme Test',
        'dateDebut': '2026-08-01',
        'dateFin': ''
      }, assureurs);
      for (final k in ['assureurNom', 'actesExclus', 'produitsExclus', 'accordPrealable', 'source', 'nom', 'police']) {
        expect(r[k], fiche[k], reason: k);
      }
    });

    test('simulateur : la répartition ligne par ligne = celle de l’écran', () {
      final sous = [for (final s in souscripteurs) s['id'] == 'SOU006' ? {...s, ...m(e['souscripteurApres'])} : s];
      final garanties = lm(e['garantiesPosees']);
      final sims = lm(e['simulations']);
      expect(sims, isNotEmpty);
      for (final s in sims) {
        final p = m(s['patient']);
        final r = repartir(
            patient: p,
            lignes: [for (final l in assLignesSimulateur) {...l}],
            date: jour,
            couvertures: couvertures,
            souscripteurs: sous,
            garanties: garanties);
        final tableau = ((s['tables'] as List).last as List).map((l) => [for (final c in l as List) '$c']).toList();
        expect(tableau.length, 5);
        for (var i = 0; i < 5; i++) {
          final l = r.lignes[i];
          expect(tableau[i][0], l['libelle']);
          expect(tableau[i][1], f0(l['montant'] as num));
          expect(tableau[i][2], f0(l['partAssureur'] as num), reason: '${p['code']} ${l['libelle']}');
          expect(tableau[i][3], f0(l['partPatient'] as num));
          expect(tableau[i][4], sp('${l['motif']}'));
        }
        final t = '${s['texte']}';
        expect(t, contains('Part assureur ${mo(r.partAssureur)}'));
        expect(t, contains('Part patient ${mo(r.partPatient)}'));
        expect(t, contains(r.grilleSaisie ? 'Convention saisie' : 'Convention à collecter'));
      }
    });

    test('libellés : unités de plafond et catégories de garantie', () {
      expect(assLibelleUnite('personne_2ans'), 'par personne, tous les deux ans');
      expect(assLibelleCategorie('maternite'), 'Maternité et accouchements');
      expect(assCategoriesGarantie.length, 16);
    });
  });

  group('m9-prises-en-charge', () {
    final e = ecran('m9-prises-en-charge');
    test('KPI : prises en charge, total, part assureurs, part patients', () {
      expect([for (final x in lm(e['kpis'])) '${x['valeur']}'], [
        nb(fa.length),
        mo(assSomme(fa, 'montantTTC')),
        mo(assSomme(fa, 'partAssurance')),
        mo(assSomme(fa, 'partPatient')),
      ]);
    });

    test('niveau totale / partielle : même tri (date décroissante) et mêmes pièces', () {
      final tri = trierPar<M>(fa, (f) => f['date'], descendant: true);
      final res = m(e['filtresResultats']);
      for (final k in ['totale', 'partielle']) {
        final attendu = tri.where((f) => assNiveau(f, k)).take(3).map((f) => f['numero']).toList();
        final lus = [for (final l in (m(res['Niveau de prise en charge|$k'])['premieres'] as List)) '${(l as List).first}'];
        expect(lus, attendu, reason: k);
      }
    });

    test('la correction d’une prise en charge change les parts et le taux, rien d’autre', () {
      final mod = m(e['modification']);
      final patch = lm(m(m(mod['ecart'])['modifs'])['factures']).single['patch'] as Map;
      expect(patch.keys.toSet(), {'tauxPriseEnCharge', 'partAssurance', 'partPatient', 'observations'});
    });
  });

  group('m9-factures-assureur', () {
    final e = ecran('m9-factures-assureur');
    for (final c in lm(e['cas'])) {
      final code = '${c['assureur']}';
      final mois = c['mois'] as int;
      test('$code / mois ${mois + 1} : relevé par souscripteur, écarts, numéro de facture', () {
        final g = assReleveSouscripteurs(
            facturesAssurance: fa,
            patients: patients,
            souscripteurs: souscripteurs,
            code: code,
            mois: mois,
            annee: 2026);
        final vue = m(c['vue']);
        final k = [for (final x in lm(vue['kpis'])) '${x['valeur']}'];
        expect(k, [
          nb(g.length),
          nb(g.fold<int>(0, (a, x) => a + x.patients.length)),
          mo(g.fold<double>(0, (a, x) => a + x.total)),
          mo(g.fold<double>(0, (a, x) => a + x.assureur)),
        ]);
        if (g.isEmpty) {
          expect('${vue['texte']}', contains('Aucune prestation assurée pour cette compagnie sur le mois choisi.'));
          return;
        }
        // relevé : une ligne par patient, montants lus par NOM de colonne
        final lignes = lignesTable(vue);
        final aplat = [for (final x in g) ...x.patients];
        expect(lignes.length, aplat.length);
        String mt(double x) => x != 0 ? f0(x) : '—';
        for (var i = 0; i < aplat.length; i++) {
          final cel = cellules(lignes[i]);
          final p = aplat[i];
          expect(cel[0], p.patientCode);
          expect(cel[1], '${p.patient}');
          expect(cel[3], mt(p.consultation));
          expect(cel[4], mt(p.analyse));
          expect(cel[5], mt(p.soin));
          expect(cel[6], f0(p.total));
          expect(cel[7], mt(p.assure));
          expect(cel[8], f0(p.assureur));
        }
        final ecarts = assEcartsReleve(g);
        final facture = m(c['facture']);
        expect('${facture['texte']}',
            ecarts.isEmpty ? contains('Relevé et facture se recoupent') : contains('en écart'));
        final pieces = m(c['pieces']);
        expect('${m(pieces['facture'])['sousTitre']}',
            startsWith(assNumeroFactureMensuelle(g.length, mois, 2026)));
        final pied = [for (final x in (m((m(pieces['releve'])['tables'] as List).last)['pied'] as List)) '$x'];
        expect(pied.last, f0(g.fold<double>(0, (a, x) => a + x.assureur)));
      });
    }
  });

  group('m9-facture-mere', () {
    final e = ecran('m9-facture-mere');
    final base = DateTime(auj.year, auj.month, auj.day);
    String depuis(String per) {
      final jours = assPeriodesMere.firstWhere((p) => p.$1 == per).$3;
      return iso(DateTime.fromMillisecondsSinceEpoch(auj.millisecondsSinceEpoch)
          .subtract(Duration(days: jours)));
    }

    test('52 situations (13 compagnies x 4 périodicités) : KPI et rapprochement', () {
      final grille = lm(e['grille']);
      expect(grille.length, 52);
      for (final g in grille) {
        final code = '${g['assureur']}';
        final nom = assNomAssureur(code, assureurs);
        final filles = assFillesMere(factures, code, nom, depuis('${g['periode']}'));
        final rap = assRapprocher(filles);
        final kp = [for (final x in lm(g['kpis'])) '${x['valeur']}'];
        expect(kp, [
          nb(filles.length),
          nb(rap.nbFactures),
          mo(rap.totalFilles),
          rap.vide ? 'Aucune pièce' : (rap.concorde ? 'Concordant' : '${nb(rap.ecarts.length)} écart(s)'),
        ], reason: '$code ${g['periode']}');
        // la commande d'émission n'est offerte que si le rapprochement concorde
        expect((g['boutons'] as List).contains('Émettre la facture mère'), rap.concorde && filles.isNotEmpty, reason: '$code ${g['periode']}');
      }
      expect(base.year, 2026);
    });

    test('émission : la fiche écrite = celle de l’écran (numéros des filles figés, contrôle des trois totaux)', () {
      final em = m(e['emission']);
      final attendu = lm(m(m(em['ecart'])['inserts'])['facturesMere']).single;
      final code = '${em['assureur']}';
      final nom = assNomAssureur(code, assureurs);
      final filles = assFillesMere(factures, code, nom, depuis('${em['periode']}'));
      final rap = assRapprocher(filles);
      final fiche = assEmettreMere(
          code: code,
          nom: nom,
          periode: '${em['periode']}',
          filles: filles,
          rap: rap,
          depuis: depuis('${em['periode']}'),
          auj: DateTime(2026, 8, 16),
          nbExistantes: charger('facturesMere').length,
          emisePar: 'BASSONGUI Chabi Séko');
      for (final k in attendu.keys) {
        if (k == 'id' || k == 'statut') continue;
        expect(fiche[k], attendu[k], reason: k);
      }
    });

    test('règlement : le montant REMPLACE le précédent (non cumulatif) ; réglée seulement si soldée', () {
      final em = lm(m(m(m(e['emission'])['ecart'])['inserts'])['facturesMere']).single;
      final p = m(lm(m(m(m(e['reglementPartiel'])['ecart'])['modifs'])['facturesMere']).single['patch']);
      final r1 = assReglerMere(em, date: '2026-08-20', montant: 1000, reference: 'VIR-001');
      for (final k in p.keys) {
        expect(r1[k], p[k], reason: k);
      }
      final s = m(lm(m(m(m(e['reglementSolde'])['ecart'])['modifs'])['facturesMere']).single['patch']);
      final r2 = assReglerMere({...em, ...r1}, date: '2026-08-20', montant: (em['montantReclame'] as num) - 1000, reference: 'VIR-002');
      for (final k in s.keys) {
        expect(r2[k], s[k], reason: k);
      }
      expect(r2['etat'], 'transmise', reason: 'E501 : la maquette ne solde pas par deux règlements successifs');
      expect(assReglerMere(em, date: '2026-08-20', montant: em['montantReclame'] as num, reference: 'X')['etat'], 'reglee');
    });
  });

  group('m9-historique', () {
    final e = ecran('m9-historique');
    test('plage par défaut : 180 jours jusqu’à aujourd’hui', () {
      final d = [for (final x in e['dates'] as List) '$x'];
      expect(d, [iso(auj.subtract(const Duration(days: 180))), jour]);
    });
    for (final c in lm(e['cas'])) {
      test('${c['assureur'] == '' ? 'toutes' : c['assureur']} du ${c['du']} au ${c['au']}', () {
        final rows = assHistorique(
            facturesAssurance: fa,
            patients: patients,
            souscripteurs: souscripteurs,
            assureurs: assureurs,
            code: '${c['assureur']}',
            du: '${c['du']}',
            au: '${c['au']}');
        final k = [for (final x in lm(c['kpis'])) '${x['valeur']}'];
        expect(k, [
          nb(rows.length),
          nb({for (final r in rows) r['patientId']}.length),
          mo(assSomme(rows, 'montantTTC')),
          mo(assSomme(rows, 'partAssurance')),
        ]);
        final tri = trierPar<M>(rows, (r) => r['date'], descendant: true);
        final prem = (c['premieres'] as List).cast<List>();
        for (var i = 0; i < prem.length; i++) {
          expect(prem[i][1], tri[i]['numero']);
          expect(prem[i][6], f0(_num(tri[i]['montantTTC'])));
          expect(prem[i][7], f0(_num(tri[i]['partAssurance'])));
        }
      });
    }
  });

  group('m9-creances', () {
    final e = ecran('m9-creances');
    for (final c in lm(e['cas'])) {
      test('filtres du ${c['du']} au ${c['au']} / ${c['comp']} / ${c['anc']} / ${c['seuil']}', () {
        final rows = assBalanceAgee(
            assureurs: assureurs,
            facturesAssurance: fa,
            auj: auj,
            du: '${c['du']}',
            au: '${c['au']}',
            compagnie: '${c['comp']}',
            anciennete: '${c['anc']}',
            seuil: c['seuil'] == '' ? 0 : num.parse('${c['seuil']}'));
        expect([for (final x in lm(c['kpis'])) '${x['valeur']}'], [
          mo(rows.fold<double>(0, (a, x) => a + x.total)),
          mo(rows.fold<double>(0, (a, x) => a + x.moins30)),
          mo(rows.fold<double>(0, (a, x) => a + x.de30a90)),
          mo(rows.fold<double>(0, (a, x) => a + x.plus90)),
        ]);
        final tri = trierPar<AssLigneCreance>(rows, (r) => r.total, descendant: true);
        final lus = (c['lignes'] as List).cast<List>();
        expect(lus.length, tri.length);
        for (var i = 0; i < lus.length; i++) {
          expect([for (final x in lus[i]) '$x'], [
            tri[i].code,
            tri[i].nom,
            '${tri[i].nbFactures}',
            f0(tri[i].moins30),
            f0(tri[i].de30a90),
            f0(tri[i].plus90),
            f0(tri[i].total)
          ]);
        }
      });
    }

    test('les tranches : 30 j inclus, jusqu’à 90 j inclus ; une facture datée d’après aujourd’hui est « moins de 30 jours »', () {
      expect(assTrancheDe(-9), 'moins30');
      expect(assTrancheDe(30), 'moins30');
      expect(assTrancheDe(31), '30a90');
      expect(assTrancheDe(90), '30a90');
      expect(assTrancheDe(91), 'plus90');
    });
  });

  group('m9-relances', () {
    final e = ecran('m9-relances');
    test('référence suivante : le plus grand numéro du registre + 1 (E500)', () {
      expect(assReferenceRelance(const []), 'REL-0001');
      expect(assReferenceRelance([{'reference': 'REL-0007'}, {'reference': 'REL-0002'}, {'reference': 'autre'}]), 'REL-0008');
    });

    test('le montant proposé suit la créance de la compagnie choisie', () {
      final cas = lm(e['cas']);
      expect(cas[0]['montantDefaut'], '${assCreance(fa, 'AFR').toInt()}');
      expect(cas[0]['montantApresChoix'], '${assCreance(fa, 'NSIA').toInt()}');
      expect(cas[1]['montantApresChoix'], '${assCreance(fa, 'OLEA').toInt()}');
    });

    test('la lettre : relance ou mise en demeure, observations seulement si saisies', () {
      for (final c in lm(e['cas'])) {
        final fiche = lm(m(m(c['ecart'])['inserts'])['relances']).single;
        final piece = m(c['piece']);
        final lettre = sp(assLettreRelance(fiche).join(''));
        expect(piece['contenu'], lettre);
        expect(piece['titre'], fiche['niveau'] == 'Mise en demeure' ? 'Mise en demeure de payer' : 'Lettre de relance');
      }
      expect(assLettreRelance({'niveau': '1re relance', 'montant': 1, 'periode': 'x', 'observations': ''}).length, 4);
      expect(assLettreRelance({'niveau': '1re relance', 'montant': 1, 'periode': 'x', 'observations': 'note'}).length, 5);
    });

    test('indicateurs vivants après création, correction et archivage (corrigé dans la maquette)', () {
      final k = lm(e['kpisApres']);
      expect([for (final x in k) '${x['valeur']}'], ['3', '3', '0', '280 000 FCFA']);
    });
  });
}

num _num(Object? x) => x is num ? x : num.parse('$x');
