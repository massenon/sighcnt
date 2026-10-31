// Rejoue les vecteurs de M12 (B) tirés des écrans réels de la maquette (prototype_html/build/vecteurs-comptabilite-b.js) : comptabilité analytique, budgets,
// immobilisations & amortissements, banques & rapprochements. Le jeu est celui du poste (apps/poste/assets/donnees/jeu).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) => ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
Map<String, Object?> carte(Object? v) => (v as Map).cast<String, Object?>();
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();
String mof(Object? v) => nt(money(v));
String mo(Object? v) => nt(money(v, avecDevise: false));

List<F> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));
List<List<String>> lignesDe(Object? tableau) => liste(carte(tableau)['lignes']).map((l) => (l['cellules'] as List).cast<String>()).toList();

void main() {
  final f = File('test/vecteurs/comptabilite_b.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-comptabilite-b.js`');
  final v = carte(jsonDecode(f.readAsStringSync()));
  final ecrans = carte(v['ecrans']);
  final toutes = jeu('ecritures').where((e) => e['statut'] != 'archive').toList();
  final e26 = cpaEcrituresExercice(toutes, 2026);
  final auj = DateTime(2026, 10, 30, 10);

  group('m12-analytique : le résultat par centre de coûts se déduit du centre porté par chaque écriture', () {
    final s = carte(ecrans['m12-analytique']);
    final rows = cpbAnalytique(e26);

    test('une ligne par centre du référentiel statique (six secteurs + Direction), triée par résultat décroissant à l\'écran', () {
      expect(rows.map((r) => r.centre).toList(),
          ['Laboratoire', 'Pharmacie', 'Consultation', 'Imagerie médicale', 'Maternité', 'Hospitalisation et soins', 'Direction']);
      final tri = [...rows]..sort((a, b) => b.resultat.compareTo(a.resultat));
      final cellules = lignesDe(liste(s['tables'])[0]);
      expect(cellules.length, rows.length);
      for (final (i, r) in tri.indexed) {
        expect(cellules[i][0], r.centre);
        expect(cellules[i][1], '${r.nb}');
        expect(nt(cellules[i][2]), mo(r.produits));
        expect(nt(cellules[i][3]), mo(r.charges));
        expect(nt(cellules[i][4]), mo(r.resultat));
        expect(cellules[i][5], r.produits != 0 ? '${r.marge} %' : '—');
      }
    });

    test('quatre indicateurs : somme des centres', () {
      final k = liste(s['kpis']);
      expect(k.map((x) => x['valeur']).toList(), [
        '${rows.length}',
        mof(rows.fold<double>(0, (a, r) => a + r.produits)),
        mof(rows.fold<double>(0, (a, r) => a + r.charges)),
        mof(rows.fold<double>(0, (a, r) => a + r.resultat)),
      ]);
    });

    test('un centre SANS produit n\'a pas de marge (—), pas un zéro : la Direction porte des charges seules', () {
      final d = rows.firstWhere((r) => r.id == 'direction');
      expect(d.produits, 0);
      expect(d.charges, greaterThan(0));
      expect(d.marge, 0);
    });

    test('la marge arrondit comme JavaScript : la moitié monte (Math.round)', () {
      expect(const CpbLigneAnalytique('x', 'x', 1, 50, 100).marge, 50);
      expect(const CpbLigneAnalytique('x', 'x', 1, 105, 100).marge, -5);
      expect(const CpbLigneAnalytique('x', 'x', 1, 100.5, 100).marge, 0);
      expect(const CpbLigneAnalytique('x', 'x', 1, 101.5, 100).marge, -1);
    });

    test('graphiques : barres produits / charges triées par résultat, anneau des centres qui ont des produits (ordre du référentiel)', () {
      final g = liste(s['graphiques']);
      final tri = [...rows]..sort((a, b) => b.resultat.compareTo(a.resultat));
      expect((g[0]['etiquettes'] as List).cast<String>(), tri.map((r) => r.centre).toList());
      expect(liste(g[0]['series'])[1]['data'], tri.map((r) => r.charges.toInt()).toList());
      final avec = rows.where((r) => r.produits > 0).toList();
      expect((g[1]['etiquettes'] as List).cast<String>(), avec.map((r) => r.centre).toList());
    });

    test('la pièce imprimée : mêmes lignes dans l\'ordre du référentiel, total refait depuis les lignes', () {
      final p = carte(s['piece']);
      final t = carte(liste(p['tables']).isEmpty ? {'lignes': []} : liste(p['tables'])[0]);
      expect(p['titre'], 'Balance analytique');
      expect(nt(p['contenu']), contains('TOTAL${mo(rows.fold<double>(0, (a, r) => a + r.produits))}${mo(rows.fold<double>(0, (a, r) => a + r.charges))}${mo(rows.fold<double>(0, (a, r) => a + r.resultat))}'));
      expect(t, isNotNull);
    });
  });

  group('m12-budgets : le réalisé est lu aux écritures, la référence aux budgets EXISTANTS', () {
    final s = carte(ecrans['m12-budgets']);
    final budgets = jeu('budgets');

    test('chaque ligne : prévu, réalisé du centre, disponible, consommation arrondie, triées par budget décroissant', () {
      final tri = [...budgets]..sort((a, b) => (b['prevu'] as num).compareTo(a['prevu'] as num));
      final cellules = lignesDe(liste(s['tables'])[0]);
      expect(cellules.length, tri.length);
      for (final (i, b) in tri.indexed) {
        final real = cpbRealise(e26, b['centreCout']);
        final prevu = (b['prevu'] as num).toDouble();
        expect(cellules[i][1], b['reference']);
        expect(nt(cellules[i][5]), mo(prevu));
        expect(nt(cellules[i][6]), mo(real));
        expect(nt(cellules[i][7]), mo(prevu - real));
        expect(cellules[i][8], '${cpbConsommation(prevu, real)} %');
      }
    });

    test('quatre indicateurs : total prévu, consommé, disponible, taux', () {
      final prevu = budgets.fold<double>(0, (a, b) => a + (b['prevu'] as num));
      final real = budgets.fold<double>(0, (a, b) => a + cpbRealise(e26, b['centreCout']));
      final k = liste(s['kpis']);
      expect(k.map((x) => x['valeur']).toList(), [mof(prevu), mof(real), mof(prevu - real), nt(pourcent(prevu != 0 ? real / prevu * 100 : 0))]);
    });

    test('une consommation au-delà de 100 % se lit (Direction : 337 %) ; sans prévision, 0', () {
      expect(cpbConsommation(5000000, 16831000), 337);
      expect(cpbConsommation(0, 1000), 0);
    });

    test('E772 — la référence d\'un nouveau budget vient des budgets EXISTANTS (le compteur de page redonnait BG-2026-001)', () {
      expect(cpbReferenceSuivante('BG-2026-', 3, budgets), 'BG-2026-008');
      expect(s['creeRef'], 'BG-2026-008');
      expect(liste(carte(carte(carte(s['deuxiemeCreation'])['ecart'])['inserts'])['budgets'])[0]['reference'], 'BG-2026-009');
      expect(cpbReferenceSuivante('BG-2026-', 3, [...budgets, {'reference': 'BG-2026-008'}]), 'BG-2026-009');
      // les archivées comptent aussi : ne jamais redonner un numéro déjà attribué
      expect(cpbReferenceSuivante('BG-2026-', 3, [...budgets, {'reference': 'BG-2026-012', 'statut': 'archive'}]), 'BG-2026-013');
    });

    test('la comparaison budget / réalisé (onglet) : prévu et réalisé par budget, dans l\'ordre de la collection', () {
      final g = liste(carte(s['suivi'])['graphiques'])[0];
      expect((g['etiquettes'] as List).cast<String>(), budgets.map((b) => '${b['centre']}').toList());
      expect(liste(g['series'])[1]['data'], budgets.map((b) => cpbRealise(e26, b['centreCout']).toInt()).toList());
    });
  });

  group('m12-immobilisations : l\'amortissement court au SEMESTRE, le dernier semestre solde le reliquat', () {
    final s = carte(ecrans['m12-immobilisations']);
    final biens = jeu('immobilisations');

    test('chaque ligne du registre : durée en semestres, amortissement cumulé, valeur nette — par la fiche', () {
      final tri = [...biens]..sort((a, b) => (b['valeurAcquisition'] as num).compareTo(a['valeurAcquisition'] as num));
      final cellules = lignesDe(liste(s['tables'])[0]);
      expect(cellules.length, tri.length);
      for (final (i, b) in tri.indexed) {
        final c = cellules[i];
        expect(c[1], b['reference']);
        expect(c[6], '${b['dureeAmortissement']} ans (${cpbSemestresTotal(b)} sem.)');
        expect(nt(c[5]), mo(b['valeurAcquisition']));
        expect(nt(c[8]), mo(cpbAmortiCumule(b, auj)), reason: '${b['reference']} amortissement');
        expect(nt(c[9]), mo(cpbVnc(b, auj)), reason: '${b['reference']} VNC');
      }
    });

    test('quatre indicateurs : les trois totaux SONT les colonnes BRUT / AMORT. / NET du bilan, les biens sortis en sont exclus', () {
      final t = cpbTotauxImmobilisations(biens, auj);
      final k = liste(s['kpis']);
      expect([k[0]['valeur'], nt(k[0]['indice'])], ['${biens.length}', '${t.sorties} sortie(s) du patrimoine']);
      expect(k[1]['valeur'], mof(t.brut));
      expect(k[2]['valeur'], mof(t.amort));
      expect(k[3]['valeur'], mof(t.net));
    });

    test('le dernier semestre solde le reliquat : la somme des dotations FAIT la valeur d\'acquisition', () {
      for (final b in biens) {
        final plan = cpbPlanAmortissement(b, auj);
        expect(plan.fold<double>(0, (a, l) => a + l.dotation), (b['valeurAcquisition'] as num).toDouble(), reason: '${b['reference']}');
        expect(plan.last.vnc, 0);
      }
      // 1 000 000 sur 3 semestres : 333 333 + 333 333 + 333 334
      final p = cpbPlanAmortissement({'valeurAcquisition': 1000000, 'dureeAmortissement': 1.5, 'dateAcquisition': '2026-01-01'}, auj);
      expect(p.map((l) => l.dotation).toList(), [333333, 333333, 333334]);
    });

    test('un bien acquis en février et un bien acquis en novembre ne portent PLUS le même amortissement', () {
      Map<String, Object?> bien(String d) => {'valeurAcquisition': 1200000, 'dureeAmortissement': 3, 'dateAcquisition': d};
      final fev = cpbAmortiCumule(bien('2026-02-10'), DateTime(2026, 12, 31));
      final nov = cpbAmortiCumule(bien('2026-11-10'), DateTime(2026, 12, 31));
      expect(fev, 200000, reason: 'dix mois écoulés : UN semestre couru sur six');
      expect(nov, 0);
    });

    test('le plan du premier bien (tiroir) : périodes S1/S2 comptées depuis l\'acquisition, « Couru » jusqu\'au semestre écoulé', () {
      final tri = [...biens]..sort((a, b) => (b['valeurAcquisition'] as num).compareTo(a['valeurAcquisition'] as num));
      final b = tri.first;
      final plan = cpbPlanAmortissement(b, auj);
      final t = liste(carte(s['tiroir'])['tables'])[0];
      final lignes = (t['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
      expect(lignes.length, plan.length);
      for (final (i, l) in plan.indexed) {
        expect(lignes[i][0], l.periode);
        expect(nt(lignes[i][2]), mo(l.dotation));
        expect(nt(lignes[i][3]), mo(l.cumul));
        expect(nt(lignes[i][4]), mo(l.vnc));
        expect(lignes[i][5], l.couru ? 'Couru' : 'À venir');
      }
      expect(nt(carte(s['tiroir'])['texte']), contains('Semestres courus ${cpbSemestresEcoules(b, auj)} / ${cpbSemestresTotal(b)} (${cpbAnneesEcoulees(b, auj)} an(s) écoulé(s))'));
    });

    test('E772 — la référence d\'un nouveau bien vient des biens existants (IM-011), et E773 — elle ne change pas à la modification', () {
      expect(cpbReferenceSuivante('IM-', 3, biens), 'IM-011');
      expect(s['creeRef'], 'IM-011');
    });

    test('un bien CÉDÉ cesse de s\'amortir à sa date de sortie, quitte le bilan, et sa fiche reste', () {
      final bien = {
        'reference': 'IM-011', 'valeurAcquisition': 1000000, 'dureeAmortissement': 4, 'dateAcquisition': '2025-03-15', 'compte': '241000', 'etat': 'En service',
        ...carte(liste(carte(carte(carte(s['cession'])['ecart'])['modifs'])['immobilisations'])[0]['patch']),
      };
      expect(cpbCede(bien), isTrue);
      expect(cpbAmortiCumule(bien, auj), 125000, reason: 'arrêté au 20/12/2025 : un seul semestre couru, pas les trois de l\'horloge');
      expect(cpbVnc(bien, auj), 875000);
      final cellules = (s['ligneCedee'] as List).cast<String>();
      expect(nt(cellules[8]), mo(125000));
      expect(nt(cellules[9]), mo(875000));
      expect(nt(cellules[7]), nt('20/12/2025 Cession · ${mo(400000)}'));
      // quitte le bilan : les trois totaux ne bougent pas, la note le dit
      final avant = cpbTotauxImmobilisations(biens, auj);
      final apres = cpbTotauxImmobilisations([...biens, bien], auj);
      expect([apres.brut, apres.amort, apres.net], [avant.brut, avant.amort, avant.net]);
      expect(apres.sorties, 1);
    });

    test('l\'état « Cédé » sans date de sortie sort aussi du bilan', () {
      expect(cpbCede({'etat': 'Cédé'}), isTrue);
      expect(cpbCede({'etat': 'En service', 'dateCession': ''}), isFalse);
    });

    test('report au bilan : l\'ordre de la liasse, un bien par COMPTE (jamais par catégorie), « 229 en cours » n\'est PAS un terrain', () {
      final r = cpbReportBilan(biens, auj);
      final cellules = lignesDe(liste(carte(s['bilan'])['tables'])[0]);
      expect(r.lignes.length, cellules.length - 1);
      for (final (i, l) in r.lignes.indexed) {
        expect(cellules[i][0], l.ref);
        expect(cellules[i][1], l.libelle);
        expect(cellules[i][2], '${l.nb}');
        expect([nt(cellules[i][3]), nt(cellules[i][4]), nt(cellules[i][5])], [mo(l.brut), mo(l.amort), mo(l.net)], reason: l.ref);
      }
      final z = cellules.last;
      expect([z[0], z[1], z[2], nt(z[3]), nt(z[4]), nt(z[5])], ['AZ', 'TOTAL ACTIF IMMOBILISÉ', '${r.total.nb}', mo(r.total.brut), mo(r.total.amort), mo(r.total.net)]);

      // un bien par compte de classe 2, comme la maquette le relit
      final par = carte(s['bilanParCompte']);
      final comptes = (par['comptes'] as List).cast<String>();
      final fiches = [
        for (final (i, c) in comptes.indexed)
          {'reference': 'IX-${i + 1}', 'designation': 'Bien $c', 'categorie': 'Installations', 'valeurAcquisition': 1000000 * (i + 1), 'dureeAmortissement': 2, 'compte': c, 'dateAcquisition': '2026-01-10', 'etat': 'En service'},
        ...biens,
      ];
      final rr = cpbReportBilan(fiches, auj);
      final lg = (par['lignes'] as List).map((x) => (x as List).cast<String>()).toList();
      expect(rr.lignes.length, lg.length - 1);
      for (final (i, l) in rr.lignes.indexed) {
        expect([lg[i][0], lg[i][1], lg[i][2], nt(lg[i][3]), nt(lg[i][4]), nt(lg[i][5])], [l.ref, l.libelle, '${l.nb}', mo(l.brut), mo(l.amort), mo(l.net)], reason: l.ref);
      }
      expect(lg.last[1], 'TOTAL ACTIF IMMOBILISÉ');
      expect(nt(lg[lg.length - 2][1]), 'Compte non rattaché à une rubrique du bilan');
      expect(cpbRubriqueBilanDe({'compte': '229000'}), isNull);
      expect(cpbRubriquesBilanImmo[cpbRubriqueBilanDe({'compte': '221000'})!].$1, 'AJ');
    });

    test('la pièce du report : le total ne compte QUE les lignes de détail (additionner les sous-totaux de famille doublerait la colonne)', () {
      final p = carte(s['pieceReport']);
      final r = cpbReportBilan(biens, auj);
      expect(p['titre'], 'Report des immobilisations à l’actif du bilan');
      final detail = r.lignes.where((l) => !l.sousTotal).fold<double>(0, (a, l) => a + l.brut);
      expect(detail, r.total.brut);
      expect(nt(p['contenu']), contains('TOTAL ACTIF IMMOBILISÉ${mo(r.total.brut)}${mo(r.total.amort)}${mo(r.total.net)}'));
    });

    test('la fiche imprimée : cartouche et dotation totale', () {
      final p = carte(s['pieceFiche']);
      expect(p['titre'], 'Fiche d’immobilisation & plan d’amortissement');
      expect(nt(p['contenu']), contains('TOTAL DES DOTATIONS'));
    });

    test('les filtres Catégorie et État comptent ce que la maquette compte', () {
      final f = carte(s['filtresNb']);
      f.forEach((k, n) {
        final (champ, val) = (k.split('|')[0], k.split('|')[1]);
        final cle = champ == 'Catégorie' ? 'categorie' : 'etat';
        expect(biens.where((b) => b[cle] == val).length, n, reason: k);
      });
    });
  });

  group('m12-banques : comptes de trésorerie et rapprochements', () {
    final s = carte(ecrans['m12-banques']);
    final banques = jeu('banques').where((b) => b['statut'] != 'archive').toList();
    final rapp = jeu('rapprochements').where((b) => b['statut'] != 'archive').toList();

    test('quatre indicateurs', () {
      final b = cpbBilanRapprochements(rapp);
      expect(liste(s['kpis']).map((x) => x['valeur']).toList(), ['${banques.length}', '${b.effectues}', '${b.sansEcart}', '${b.avecEcart}']);
    });

    test('le filtre « Banque » vient des comptes de trésorerie et ne retrouve AUCUN rapprochement (écart E775, porté fidèlement) ; « Résultat » filtre', () {
      final f = carte(s['filtresNb']);
      for (final k in ['Caisse', 'BOA', 'Orabank', 'Coris Bank']) {
        expect(f['Banque|$k'], 0);
        expect(rapp.where((r) => r['banque'] == k), isEmpty, reason: 'aucun rapprochement ne porte « $k »');
      }
      expect(f['Résultat|rapproche'], rapp.where((r) => r['statutRappro'] == 'rapproche').length);
      expect(f['Résultat|ecart'], rapp.where((r) => r['statutRappro'] == 'ecart').length);
    });

    test('l\'état imprimé : trois rubriques, la phrase suit l\'écart', () {
      for (final p in liste(s['pieces'])) {
        final r = carte(p['piece']);
        final ligne = (p['ligne'] as List).cast<String>();
        final fiche = rapp.firstWhere((x) => x['reference'] == ligne[0]);
        expect(r['sousTitre'], '${fiche['banque']} — ${fiche['periode']}');
        expect(nt(r['contenu']), contains(nt(cpbPhraseRapprochement((fiche['ecart'] as num).toDouble()))));
        expect(ligne[6], fiche['ecart'] == 0 ? 'Rapproché' : (fiche['ecart'] as num) > 0 ? '+${mo(fiche['ecart'])}' : mo(fiche['ecart']));
      }
    });
  });
}
