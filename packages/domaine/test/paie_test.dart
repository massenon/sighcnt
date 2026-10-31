// M11 — paie & primes : le moteur de calcul REJOUÉ sur ce que les écrans réels de la maquette ont affiché (vecteurs engendrés par
// `prototype_html/build/vecteurs-paie.js`, piloté dans Chrome, horloge au 30/10/2026 10 h). Deux scénarios : S0 = le jeu du poste tel quel ; S1 = le jeu
// auquel on ajoute ce qu'il ne contient pas (sanctions NS 131, participations imputées sur salaire, grille de primes DATÉE avec son historique).
// Douze mois, quarante-quatre agents, toutes les fonctions : mars et juin portent l'ORTB, juillet-septembre les gardes du planning.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;

M m(Object? x) => (x as Map).cast<String, Object?>();

/// `texte()` du pilote normalise TOUTE espace (U+202F, U+00A0 comprises) : on compare après la même normalisation.
String sp(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');
String mo(num v) => sp(money(v));
String mf(num v) => sp(money(v, avecDevise: false));

/// Les entiers d'une cellule (« − 25 000 reste 25 000 » → [25000, 25000]).
List<int> entiers(String s) => [for (final x in RegExp(r'\d+(?: \d{3})*').allMatches(s)) int.parse(x.group(0)!.replaceAll(' ', ''))];
int premier(String s) => s == '—' ? 0 : entiers(s).first;

PaiEntrees entreesDe(M e) => PaiEntrees(
    planning: liste(e['planning']),
    evaluations: liste(e['evaluations']),
    avances: liste(e['avances']),
    participations: liste(e['participations']),
    grille: liste(e['grillePrimes']),
    historique: liste(e['historiquePrimes']));

void main() {
  final v = lireVecteurs('paie');
  final auj = DateTime.parse('${v['aujInstant']}');
  final scenarios = m(v['scenarios']);

  group('les paramètres sont ceux de la maquette (aucun taux inventé)', () {
    final p = m(v['param']);
    test('CNSS, VPS et barème ITS', () {
      expect(m(p['cnss'])['ouvriere'], paiCnssOuvriere);
      expect(m(p['cnss'])['patronale'], paiCnssPatronale);
      expect(m(p['vps'])['taux'], paiVpsTaux);
      final bareme = liste(m(p['its'])['bareme']);
      expect(bareme.length, paiBaremeIts.length);
      for (var i = 0; i < bareme.length; i++) {
        expect(bareme[i]['de'], paiBaremeIts[i].de, reason: 'tranche $i');
        expect(bareme[i]['a'], paiBaremeIts[i].a, reason: 'tranche $i');
        expect(bareme[i]['taux'], paiBaremeIts[i].taux, reason: 'tranche $i');
      }
    });
    test('les deux redevances ORTB : montant, mois, seuils, cumul', () {
      final o = m(p['ortb']);
      expect(o['seuilTele'], paiSeuilTele);
      expect(o['cumulMaximum'], paiCumulMaximum);
      final rs = liste(o['redevances']);
      expect(rs.length, paiRedevances.length);
      for (var i = 0; i < rs.length; i++) {
        final r = paiRedevances[i];
        expect([rs[i]['id'], rs[i]['code'], rs[i]['categorie'], rs[i]['libelle'], rs[i]['montant'], rs[i]['mois'], rs[i]['moisLabel'], rs[i]['seuilMin'], rs[i]['seuilMax'], rs[i]['assiette']],
            [r.id, r.code, r.categorie, r.libelle, r.montant, r.mois, r.moisLabel, r.seuilMin, r.seuilMax, r.assiette]);
      }
      expect(paiRedevances.fold<num>(0, (a, r) => a + r.montant), paiCumulMaximum, reason: 'Radio 1 000 + Télé 3 000 = 4 000 sur l’exercice');
    });
    test('les primes NS 132 et les fonctions', () {
      final primes = liste(v['ns132']);
      expect(primes.length, paiPrimesNs132.length);
      for (var i = 0; i < primes.length; i++) {
        expect([primes[i]['id'], primes[i]['label'], primes[i]['mode']], [paiPrimesNs132[i].id, paiPrimesNs132[i].libelle, paiPrimesNs132[i].mode]);
        expect(m(primes[i]['montants']).map((k, x) => MapEntry(k, x as num)), paiPrimesNs132[i].montants);
      }
      final f = liste(v['fonctions']);
      expect({for (final x in f) '${x['id']}': '${x['label']}'}, paiFonctions);
      expect((v['services'] as List).cast<String>(), paiServices);
    });
  });

  group('ITS : barème progressif, arrondi au franc', () {
    test('bornes de tranches', () {
      expect(paiCalculIts(0), 0);
      expect(paiCalculIts(60000), 0);
      expect(paiCalculIts(60001), 0); // `+ 1` : la tranche 10 % commence à 60 001, un franc imposable vaut 0,1 → 0
      expect(paiCalculIts(70000), 1000);
      expect(paiCalculIts(150000), 9000);
      expect(paiCalculIts(250000), 9000 + 15000);
      expect(paiCalculIts(500000), 9000 + 15000 + 47500);
      expect(paiCalculIts(600000), 9000 + 15000 + 47500 + 30000, reason: 'au-delà de 500 000 : 30 %');
    });
  });

  group('ORTB : deux redevances qui SE CUMULENT, chacune au seul mois de son prélèvement', () {
    test('Radio pour tous en mars, Télé au-delà de 60 000 en juin, en sus', () {
      for (final brut in [40000, 60000, 60001, 100000, 522000]) {
        var annee = 0.0;
        for (var mois = 0; mois < 12; mois++) {
          final d = paiCalculOrtb(brut, mois);
          annee += d.montant;
          expect(d.radio != null, true, reason: 'la radio vise tous les salariés, $brut F compris');
          expect(d.tele != null, brut >= 60001, reason: 'la télé exige plus de 60 000 F ($brut)');
          expect(d.radio!.montant, mois == 2 ? 1000 : 0);
          if (d.tele != null) expect(d.tele!.montant, mois == 5 ? 3000 : 0);
          expect(d.radio!.montantAnnuel, 1000);
        }
        expect(annee, brut >= 60001 ? 4000 : 1000, reason: '$brut F : 4 000 F au-dessus du seuil (cumul), 1 000 F en dessous');
      }
    });
    test('les lignes d’un bulletin : une par catégorie, un tiret hors du mois de prélèvement', () {
      final mars = paiLignesOrtb(paiCalculOrtb(100000, 2));
      expect([for (final l in mars) (l.libelle, l.base, l.montant)], [
        ('Redevance ORTB / Radio', 'Annuelle, prélevée ce mois', '1 000'),
        ('Redevance ORTB / Télé', 'Annuelle, prélevée en juin', '—'),
      ]);
      final bas = paiLignesOrtb(paiCalculOrtb(50000, 9));
      expect([for (final l in bas) (l.libelle, l.base, l.montant)], [('Redevance ORTB / Radio', 'Annuelle, prélevée en mars', '—')]);
      expect(paiLignesOrtb(null).single.base, 'Non applicable');
    });
  });

  for (final nom in ['S0', 'S1']) {
    final s = m(scenarios[nom]);
    final e = m(s['entrees']);
    final entrees = entreesDe(e);
    final personnel = liste(e['personnel']);
    final mois = m(s['mois']);

    group('scénario $nom — le calcul de la paie, mois par mois', () {
      for (var mo = 0; mo < 12; mo++) {
        test('${paiMois[mo]} : calcul, cotisations et ORTB = écrans réels', () {
          final calc = paiCalculerTous(personnel, 2026, mo, entrees, auj);
          final parMat = {for (final c in calc) c.matricule: c};
          final lu = m(mois['$mo']);

          // m11-calcul : le tableau complet et ses KPI
          final lignes = [for (final l in m(m(lu['calcul'])['table'])['lignes'] as List) [for (final c in (l as List)) '$c']];
          expect(lignes.length, calc.length, reason: 'une ligne par agent actif');
          for (final cel in lignes) {
            final c = parMat[cel[0]]!;
            final ctx = '${paiMois[mo]} · ${c.matricule} ${c.nomComplet}';
            expect(cel[1], '${c.nomComplet} ${paiFonctionLibelle(c.employe['fonction'])}', reason: ctx);
            expect(premier(cel[2]), c.salaireBase, reason: '$ctx : base');
            expect(premier(cel[3]), c.gardes, reason: '$ctx : gardes');
            expect(premier(cel[4]), c.permanences, reason: '$ctx : permanences');
            expect(premier(cel[5]), c.totalPrimes, reason: '$ctx : primes');
            expect(premier(cel[6]), c.brut, reason: '$ctx : brut');
            expect(premier(cel[7]), c.sanction, reason: '$ctx : sanction');
            expect(premier(cel[8]), c.cnssOuvriere, reason: '$ctx : CNSS ouvrière');
            expect(premier(cel[9]), c.its, reason: '$ctx : ITS');
            expect(premier(cel[10]), c.avances, reason: '$ctx : avances');
            if (c.avances != 0) {
              expect(entiers(cel[10])[1], paiResteAvances(c.avancesDetail), reason: '$ctx : reste dû');
              expect(cel[10].contains('avances ·'), c.avancesDetail.length > 1, reason: '$ctx : « N avances · reste »');
            }
            expect(premier(cel[11]), c.participations, reason: '$ctx : participations');
            expect(premier(cel[12]), c.net, reason: '$ctx : net à payer');
          }
          final kc = {for (final k in liste(m(lu['calcul'])['kpis'])) '${k['label']}': sp('${k['valeur']}')};
          expect(kc['Agents concernés'], '${calc.length}');
          expect(kc['Masse salariale brute'], mo2(paiSomme(calc, (c) => c.brut)));
          expect(kc['Total des retenues'], mo2(paiSomme(calc, (c) => c.totalRetenues)));
          expect(kc['Net à payer'], mo2(paiSomme(calc, (c) => c.net)));

          // m11-cotisations
          final cot = m(lu['cotisations']);
          for (final l in m(cot['table'])['lignes'] as List) {
            final cel = [for (final c in (l as List)) '$c'];
            final c = parMat[cel[0]]!;
            expect(cel[2], '${c.employe['cnss']}');
            expect(premier(cel[3]), c.brut);
            expect(premier(cel[4]), c.cnssOuvriere);
            expect(premier(cel[5]), c.cnssPatronale);
            expect(premier(cel[6]), c.vps);
            expect(premier(cel[7]), c.its);
            expect(premier(cel[8]), c.ortbRadio);
            expect(premier(cel[9]), c.ortbTele);
            expect(premier(cel[10]), c.ortb);
            expect(cel[8] == '—', c.ortbRadio == 0);
          }
          final kt = {for (final k in liste(cot['kpis'])) '${k['label']}': sp('${k['valeur']}')};
          expect(kt['CNSS part ouvrière'], mo2(paiSomme(calc, (c) => c.cnssOuvriere)));
          expect(kt['CNSS part patronale'], mo2(paiSomme(calc, (c) => c.cnssPatronale)));
          expect(kt['CNSS totale à verser'], mo2(paiSomme(calc, (c) => c.cnssOuvriere) + paiSomme(calc, (c) => c.cnssPatronale)));
          expect(kt['ITS retenu'], mo2(paiSomme(calc, (c) => c.its)));
          expect(kt['VPS'], mo2(paiSomme(calc, (c) => c.vps)));
          expect(kt['ORTB Radio'], mo2(paiSomme(calc, (c) => c.ortbRadio)));
          expect(kt['ORTB Télé'], mo2(paiSomme(calc, (c) => c.ortbTele)));
          expect(kt['Coût employeur'], mo2(paiSomme(calc, (c) => c.coutEmployeur)));

          // m11-ortb : par agent
          final ortb = m(lu['ortb']);
          final par = {for (final r in paiLignesOrtbAgents(personnel, 2026, mo, entrees, auj)) r.matricule: r};
          for (final l in m(ortb['table'])['lignes'] as List) {
            final cel = [for (final c in (l as List)) '$c'];
            final r = par[cel[0]]!;
            expect(cel[1], '${r.agent} ${r.poste}');
            expect(premier(cel[2]), r.brut);
            expect(cel[3], r.radio == 0 ? '—' : mf(r.radio));
            expect(cel[4], r.tele == 0 ? 'non redevable' : mf(r.tele));
            expect(cel[5], r.categorie == 'aucune' ? 'Non redevable' : r.categorieLabel);
            expect(premier(cel[6]), r.totalAnnuel);
            final attendu = r.duCeMois != 0
                ? '${mf(r.duCeMois)} ${r.libelleDuCeMois}'
                : r.aPrelever != 0
                    ? 'à prélever · ${sp(r.resume)}'
                    : r.prelevee != 0
                        ? 'Déjà prélevée'
                        : '—';
            expect(cel[7], attendu, reason: '${r.agent} en ${paiMois[mo]}');
          }
          final ko = {for (final k in liste(ortb['kpis'])) '${k['label']}': k};
          final rows = par.values.toList();
          expect(sp('${ko['Dû sur ${paiMois[mo]}']!['valeur']}'), mo2(rows.fold<num>(0, (a, r) => a + r.duCeMois)));
          expect(sp('${ko['ORTB Radio — tous les salariés']!['valeur']}'), '${rows.length}');
          expect(sp('${ko['ORTB Télé — au-delà de 60 000']!['valeur']}'), '${rows.where((r) => r.tele > 0).length}');
        });
      }
    });
  }

  group('la grille des primes est lue À LA DATE du bulletin (S1)', () {
    final s = m(scenarios['S1']);
    final e = entreesDe(m(s['entrees']));
    test('avant la date d’effet de la version courante, l’historique répond ; sinon le barème d’origine', () {
      // garde d’un infirmier : version courante dès le 15/10 (1 600), historique 13/07→14/10 (1 500), plus ancienne 01/01→12/07 (750)
      expect(paiMontantPrime('garde', 'infirmier', '2026-10-28', e.grille, e.historique), 1600);
      expect(paiMontantPrime('garde', 'infirmier', '2026-10-15', e.grille, e.historique), 1600);
      expect(paiMontantPrime('garde', 'infirmier', '2026-10-14', e.grille, e.historique), 1500);
      expect(paiMontantPrime('garde', 'infirmier', '2026-07-28', e.grille, e.historique), 1500);
      expect(paiMontantPrime('garde', 'infirmier', '2026-03-28', e.grille, e.historique), 750);
      expect(paiMontantPrime('garde', 'infirmier', '2025-12-28', e.grille, e.historique), 1500, reason: 'aucune version en vigueur : repli sur le barème d’origine');
      expect(paiMontantPrime('garde', 'medecin', '2026-10-28', e.grille, e.historique), 0, reason: 'une fonction absente de la grille ne perçoit rien (la hausse ne vise que les fonctions déjà servies)');
      expect(paiMontantPrime('inconnue', 'infirmier', '2026-10-28', e.grille, e.historique), 0);
    });
    test('sans grille au magasin, le barème d’origine de la note répond', () {
      expect(paiMontantPrime('caisse', 'caissiere', '2026-08-28', const [], const []), 10000);
      expect(paiMontantPrime('caisse', 'infirmier', '2026-08-28', const [], const []), 0);
    });
  });

  group('refus et exclusions du moteur (S1)', () {
    final s = m(scenarios['S1']);
    final e = m(s['entrees']);
    final entrees = entreesDe(e);
    final personnel = liste(e['personnel']);
    PaiCalcul calc(String mat, int mo) => paiCalculer(personnel.firstWhere((p) => p['matricule'] == mat), 2026, mo, entrees, auj);
    final agents = (s['agents'] as List).cast<String>();
    test('une sanction NS 131 diminue le BRUT et n’entre pas dans les retenues ; une évaluation archivée ne compte pas', () {
      final c = calc(agents[0], 9);
      expect(c.pctSanction, 10);
      expect(c.sanction, arrondiJs(c.brut * 10 / 100));
      expect(c.brutApresSanction, c.brut - c.sanction);
      expect(c.totalRetenues, c.cnssOuvriere + c.its + c.ortb + c.avances + c.participations, reason: 'la sanction n’est pas une retenue');
      expect(calc(agents[3], 9).sanction, 0, reason: 'l’évaluation archivée (50 %) est ignorée');
      expect(calc(agents[2], 9).sanction, 0);
    });
    test('une participation n’est retenue qu’au SEUL mois de retenue, jamais au comptant, jamais archivée', () {
      expect(calc(agents[0], 9).participations, 3500);
      expect(calc(agents[0], 8).participations, 0);
      expect(calc(agents[1], 2).participations, 1000);
      expect(calc(agents[1], 9).participations, 0);
      expect(calc(agents[2], 9).participations, 0, reason: 'règlement au comptant : jamais sur le salaire');
      expect(calc(agents[5], 9).participations, 0, reason: 'participation archivée');
    });
    test('une avance soldée ou archivée ne se retient pas ; deux avances en cours se cumulent', () {
      final c = calc(agents[5], 9);
      expect(c.avances, 25000 + 10000 * 0, reason: 'en cours (25 000) seule : la soldée (20 000) et l’archivée (10 000) sont écartées');
      expect(c.avancesDetail.length, 1);
    });
  });

  group('les gestes d’écriture rejoués contre la fiche écrite par la maquette', () {
    final g = m(v['gestes']);
    final s0 = m(scenarios['S0']);
    final e0 = m(s0['entrees']);
    final entrees = entreesDe(e0);
    final personnel = liste(e0['personnel']);
    M agent(String mat) => personnel.firstWhere((p) => p['matricule'] == mat);

    test('« Générer les bulletins » : un bulletin par agent, la série suit le registre, le détail ORTB et les participations voyagent avec la pièce', () {
      final paie = m(g['paie']);
      final existants = <M>[];
      for (final cle in ['generation9', 'generation4']) {
        final mo = cle == 'generation9' ? 9 : 4;
        final attendus = liste(m(m(m(paie[cle])['ecart'])['inserts'])['bulletins']);
        expect(attendus.length, personnel.length);
        final produits = <M>[];
        for (final p in personnel) {
          final c = paiCalculer(p, 2026, mo, entrees, auj);
          final b = paiBulletinDe(c, paiReferenceSuivante('BP-', 5, existants));
          existants.add(b);
          produits.add(b);
        }
        final parEmploye = {for (final b in produits) b['employeId']: b};
        for (final a in attendus) {
          memes(parEmploye[a['employeId']], a, 'bulletin ${a['reference']}', ignorer: {'id', 'statut'});
        }
        expect({for (final a in attendus) a['reference']}, {for (final b in produits) b['reference']});
      }
      expect(existants.first['reference'], 'BP-00001');
      expect(existants.last['reference'], 'BP-00088');
      expect(m(paie['generationAnnulee'])['ecart'], {'inserts': {}, 'modifs': {}}, reason: 'une génération annulée ne crée rien');
    });

    test('les lots de la validation : une période = un lot, l’ordre est celui de la première apparition dans le registre', () {
      final paie = m(g['paie']);
      final collection = [
        ...liste(m(m(m(paie['generation4'])['ecart'])['inserts'])['bulletins']),
        ...liste(m(m(m(paie['generation9'])['ecart'])['inserts'])['bulletins']),
      ];
      final lots = paiLots(collection);
      final tbl = [for (final l in m(m(paie['validation'])['table'])['lignes'] as List) [for (final c in (l as List)) '$c']];
      expect(tbl.length, lots.length);
      for (var i = 0; i < lots.length; i++) {
        expect(tbl[i][0], lots[i].periode);
        expect(premier(tbl[i][1]), lots[i].nb);
        expect(premier(tbl[i][2]), lots[i].brut);
        expect(premier(tbl[i][3]), lots[i].cnss);
        expect(premier(tbl[i][4]), lots[i].net);
        expect(tbl[i][5], '${lots[i].aValider} à valider');
      }
      final kpis = {for (final k in liste(m(paie['validation'])['kpis'])) '${k['label']}': sp('${k['valeur']}')};
      expect(kpis['Périodes traitées'], '${lots.length}');
      expect(kpis['Bulletins à valider'], '${lots.fold<int>(0, (a, l) => a + l.aValider)}');
      expect(kpis['Net à payer cumulé'], mo(lots.fold<num>(0, (a, l) => a + l.net)));
    });

    test('heures supplémentaires : taux horaire majoré, montant = heures × taux, majoration 0 → 25 %, la modification garde son numéro', () {
      final hs = m(g['heuresSup']);
      final c1 = m(hs['creation']);
      final a = agent('${m(c1['agent'])['matricule']}');
      final att = liste(m(m(c1['ecart'])['inserts'])['heuresSup']).single;
      final r = paiHeuresSupTransform({'employeId': a['id'], 'periode': 'Octobre 2026', 'heures': 10, 'majoration': 50, 'motif': 'Urgence', 'valide': true}, a, reference: () => 'HS-0021');
      memes(r, att, 'heures sup', ignorer: {'id', 'statut'});
      expect(paiTauxHoraire(95000, 50), 822);
      final z = liste(m(m(m(hs['creationMajorationZero'])['ecart'])['inserts'])['heuresSup']).single;
      memes(paiHeuresSupTransform({'employeId': agent('4')['id'], 'periode': 'Mars 2026', 'heures': 4, 'majoration': 0, 'motif': 'Remplacement', 'valide': false}, agent('4'), reference: () => 'HS-0022'), z, 'majoration 0', ignorer: {'id', 'statut'});
      expect(z['majoration'], 0);
      expect(z['tauxHoraire'], paiTauxHoraire(110000, 25), reason: '0 vaut 25 : `Number(v.majoration) || 25`');
      final edit = liste(m(m(m(hs['modification'])['ecart'])['modifs'])['heuresSup']).single;
      expect(edit['patch'], {'heures': 7, 'montant': 22715}, reason: 'ni numéro ni taux ne bougent');
      expect(paiReferenceSuivante('HS-', 4, [{'reference': 'HS-0020'}, {'reference': 'HS-0001', 'statut': 'archive'}, {'reference': 'XX-0099'}]), 'HS-0021');
    });

    test('avances : trois mois de salaire au plus (pile au plafond accepté), mensualité arrondie, remboursé à 0, la modification garde remboursé et numéro', () {
      final av = m(g['avances']);
      final refus = m(av['refusPlafond']);
      final a = agent('11');
      expect(sp(paiAvanceRefus(285001, a)!), (refus['toasts'] as List).single);
      expect(paiAvanceRefus(285000, a), isNull, reason: 'pile au plafond');
      expect(paiAvanceRefus(1000000, null), isNull, reason: 'agent inconnu : aucun plafond à comparer');
      expect(m(refus['ecart']), {'inserts': {}, 'modifs': {}});
      final pl = liste(m(m(m(av['creationPlafond'])['ecart'])['inserts'])['avances']).single;
      memes(paiAvanceTransform({'employeId': a['id'], 'date': '2026-10-30', 'montant': 285000, 'nbMensualites': 7, 'motif': 'Frais de santé', 'statutAvance': 'en_cours'}, a, reference: () => 'AVS-0013'), pl, 'plafond', ignorer: {'id', 'statut'});
      expect(pl['mensualite'], 40714);
      final cr = liste(m(m(m(av['creation'])['ecart'])['inserts'])['avances']).single;
      memes(paiAvanceTransform({'employeId': agent('21')['id'], 'date': '2026-10-30', 'montant': 50000, 'nbMensualites': 3, 'motif': 'Besoin personnel', 'statutAvance': 'en_cours'}, agent('21'), reference: () => 'AVS-0014'), cr, 'création', ignorer: {'id', 'statut'});
      expect(cr['rembourse'], 0);
      expect(cr['mensualite'], 16667);
      final modif = liste(m(m(m(av['modification'])['ecart'])['modifs'])['avances']).single;
      expect(modif['patch'], {'nbMensualites': 4, 'mensualite': 12500}, reason: 'ni « remboursé » remis à zéro, ni numéro nouveau');
      // la transformation d'une fiche existante ne perd rien
      final t = paiAvanceTransform({'employeId': a['id'], 'montant': 50000, 'nbMensualites': 4, 'rembourse': 30000, 'reference': 'AVS-0011'}, a, reference: () => 'AVS-9999');
      expect([t['rembourse'], t['reference'], t['statutAvance'], t['mensualite']], [30000, 'AVS-0011', 'en_cours', 12500]);
    });

    test('prêts : échéancier calculé, reliquat sur la dernière échéance, passage d’année, solde, ligne conditionnelle', () {
      final pr = m(g['prets']);
      final cree = liste(m(m(m(pr['creation'])['ecart'])['inserts'])['pretsEtudes']).single;
      final a = agent('${m(m(pr['creation'])['agent'])['matricule']}');
      memes(paiPretTransform({'employeId': a['id'], 'nature': 'pret_etudes', 'objet': 'Formation continue', 'montant': 100001, 'dateAccord': '2026-10-30', 'premiereEcheance': '2026-12', 'nbEcheances': 3, 'autorisePar': 'TAKI Alimatou'}, a, reference: 'PRT-0013'), cree, 'prêt', ignorer: {'id', 'statut'});
      final e = paiEcheancier(cree);
      expect([for (final x in e) (x.mois, x.montant)], [('2026-12', 33333), ('2027-01', 33333), ('2027-02', 33335)]);
      expect(e.fold<num>(0, (a, x) => a + x.montant), 100001, reason: 'le total des échéances vaut le montant accordé au franc près');
      expect(paiSoldePret(cree), 100001);
      final tab = m(pr['tiroirCree'])['tables'] as List;
      final lignesTiroir = liste([for (final l in m(tab.first)['lignes'] as List) {'c': l}]);
      expect([for (final l in lignesTiroir) premier('${(l['c'] as List)[2]}')], [for (final x in e) x.montant]);
      final annee = liste(m(m(m(pr['creationAnnee'])['ecart'])['inserts'])['pretsEtudes']).single;
      expect([for (final x in paiEcheancier(annee)) x.mois], ['2026-11', '2026-12', '2027-01', '2027-02', '2027-03']);
      expect(paiEcheancier({...annee, 'retenues': ['2026-11', '2026-12']}).where((x) => x.retenue).length, 2);
      expect(paiSoldePret({...annee, 'retenues': ['2026-11', '2026-12']}), 150000);
      // les tiroirs lus sur le jeu : « retenue effectuée » = le mois figure dans `retenues`
      for (final t in liste(pr['tiroirs'])) {
        final ligne = (t['ligne'] as List).cast<String>();
        final ref = ligne[0];
        expect(ref.startsWith('PRT-'), true);
      }
      expect(paiNaturePret('avance'), 'Avance sur salaire');
      expect(paiNaturePret('x'), 'x');
    });
  });
}

String mo2(num v) => sp(money(v));
