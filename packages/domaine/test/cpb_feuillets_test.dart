// Rejoue les vecteurs de M12 (B) tirés des écrans réels de la maquette (prototype_html/build/vecteurs-comptabilite-b.js) : le compte de résultat
// (feuillet 7/51), le tableau des flux de trésorerie (feuillet 8/51) et le seuil de rentabilité. Le jeu est celui du poste (apps/poste/assets/donnees/jeu).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) => ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
Map<String, Object?> carte(Object? v) => (v as Map).cast<String, Object?>();

/// `innerText` normalisé de la maquette : toute espace (insécable et fine comprises) vaut une espace.
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();
String mof(Object? v) => nt(money(v));

List<F> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));

void main() {
  final f = File('test/vecteurs/comptabilite_b.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-comptabilite-b.js`');
  final v = carte(jsonDecode(f.readAsStringSync()));
  final ecrans = carte(v['ecrans']);
  final toutes = jeu('ecritures').where((e) => e['statut'] != 'archive').toList();
  final auj = DateTime(2026, 10, 30, 10);

  List<CpbColonne> colonnes(String genre, F scen) {
    final r = carte(scen['reglages']);
    return cpbColonnesFeuillet(genre, '${r['exercice']}', r['exercice'] == 'depose' ? null : DateTime.parse('${r['arrete']}'), toutes);
  }

  group('la liasse déposée est la source citée, jamais recopiée', () {
    test('le formulaire : 9 sous-totaux du résultat, 8 du tableau des flux, six écarts conservés', () {
      expect(cpbFormulesResultat.keys, ['XA', 'XB', 'XC', 'XD', 'XE', 'XF', 'XG', 'XH', 'XI']);
      expect(cpbFormulesFlux.keys, ['BF', 'ZB', 'ZC', 'ZD', 'ZE', 'ZF', 'ZG', 'ZH']);
      expect(cpbEcarts.length, 6);
      expect(cpbDepot['code'], 'BK505416');
      expect(cpbExerciceN, 2025);
      expect(cpbExerciceN1, 2024);
    });

    test('les 9 sous-totaux du résultat 2025 ET 2024 se recalculent à l\'identique depuis leurs lignes déposées', () {
      for (final a in [2025, 2024]) {
        final ctl = cpbControleSousTotaux(cpbLignesResultat, cpbFormulesResultat, a);
        expect(ctl.length, 9);
        expect(ctl.where((x) => x.ecart.abs() > 0.5), isEmpty, reason: 'exercice $a');
      }
    });

    test('au tableau des flux déposé : « Variation du BF » (N et N-1) et ZB (N) ne se recalculent pas — signalés, non arbitrés', () {
      final n = cpbControleSousTotaux(cpbLignesFlux, cpbFormulesFlux, 2025).where((x) => x.ecart.abs() > 0.5).map((x) => x.ref).toList();
      final n1 = cpbControleSousTotaux(cpbLignesFlux, cpbFormulesFlux, 2024).where((x) => x.ecart.abs() > 0.5).map((x) => x.ref).toList();
      expect(n, ['BF', 'ZB']);
      expect(n1.contains('BF'), isTrue);
      // les écarts s'écrivent comme la maquette les écrit (note lue à l'écran)
      final notes = liste([
        for (final n in (carte(carte(ecrans['m12-flux-tresorerie'])['depose'])['notes'] as List)) {'t': n}
      ]).map((x) => x['t']).join(' ');
      expect(nt(notes), contains('Variation du BF (déposé ${mof(31359405)}, recalculé ${mof(-2632175)})'));
    });
  });

  for (final genre in ['resultat', 'flux']) {
    final id = genre == 'resultat' ? 'm12-compte-resultat' : 'm12-flux-tresorerie';
    final scens = carte(ecrans[id]);
    final lignes = genre == 'resultat' ? cpbLignesResultat : cpbLignesFlux;

    group('$id : chaque cellule du formulaire est celle de la maquette', () {
      for (final nom in scens.keys) {
        test(nom, () {
          final s = carte(scens[nom]);
          final cols = colonnes(genre, s);
          final rows = liste(carte(liste(s['tables'])[0])['lignes']).map((l) => (l['cellules'] as List).cast<String>()).toList();
          var i = 0;
          for (final l in lignes) {
            final c = rows[i++];
            if (l.section != null) {
              expect(c.length, 2);
              expect(c[1], l.section);
              continue;
            }
            expect(c.first, l.ref ?? '', reason: 'ligne $i');
            final nbc = c.length;
            for (var k = 0; k < 2; k++) {
              final attendu = cpbMontantFeuillet(cols[k], l);
              expect(nt(c[nbc - 2 + k]), attendu == null ? '—' : nt(attendu), reason: '${l.cle} colonne ${k == 0 ? 'N' : 'N-1'}');
            }
            if (genre == 'flux' && l.ref == 'ZH') {
              final ctl = rows[i++];
              for (var k = 0; k < 2; k++) {
                expect(nt(ctl[ctl.length - 2 + k]), cols[k].depose ? '' : nt(money(cols[k].controle, avecDevise: false)));
              }
            }
          }
          expect(i, rows.length, reason: 'aucune ligne en trop ni en moins');
        });
      }
    });

    group('$id : indicateurs, colonnes et note de source', () {
      test('les quatre indicateurs lisent les colonnes (« N-1 : … (+x %) » pour le résultat)', () {
        for (final nom in scens.keys) {
          final s = carte(scens[nom]);
          final cols = colonnes(genre, s);
          final k = liste(s['kpis']);
          expect(k.length, 4);
          if (genre == 'resultat') {
            for (final (i, ref) in ['XB', 'XC', 'XD', 'XI'].indexed) {
              expect(mof(cols[0].val(ref)), nt(k[i]['valeur']), reason: '$nom $ref');
              final a = cols[0].val(ref), b = cols[1].val(ref);
              final attendu = b != 0 ? 'N-1 : ${mof(b)} (${a - b >= 0 ? '+' : ''}${pourcent((a - b) / b.abs() * 100)})' : 'N-1 : ${mof(b)}';
              expect(nt(k[i]['indice']), nt(attendu), reason: '$nom $ref');
            }
          } else {
            for (final (i, ref) in ['ZA', 'ZB', 'ZG', 'ZH'].indexed) {
              expect(mof(cols[0].val(ref)), nt(k[i]['valeur']), reason: '$nom $ref');
            }
            expect(nt(k[1]['indice']), nt('CAFG : ${money(cols[0].val('FA'))}'));
            expect(nt(k[2]['indice']), nt('Investissement ${money(cols[0].val('ZC'))} · financement ${money(cols[0].val('ZF'))}'));
            final n = cols[0];
            expect(nt(k[3]['indice']),
                n.depose ? 'Égale au total trésorerie-actif du bilan (BT)' : (n.ecart.abs() < 1 ? 'Contrôle concordant' : 'Écart au contrôle : ${money(n.ecart)}'));
          }
        }
      });

      test('« 2026 » est calculé, son N-1 (2025) est CITÉ ; si le journal portait 2025, il serait calculé et son N-1 (2024) CITÉ ; « déposé » cite les deux', () {
        final d = colonnes(genre, carte(scens['defaut']));
        expect([d[0].depose, d[1].depose], [false, true]);
        expect(d[1].titre, 'Exercice au 31/12/2025');
        final a = cpbColonnesFeuillet(genre, '2025', DateTime(2025, 12, 31), toutes);
        expect([a[0].depose, a[1].depose], [false, true]);
        expect(a[1].titre, 'Exercice au 31/12/2024');
        final dep = colonnes(genre, carte(scens['depose']));
        expect([dep[0].depose, dep[1].depose], [true, true]);
        expect(dep[0].sous, 'déposé — liasse BK505416');
      });

      test('le nombre de brouillons écartés est annoncé, et seules les écritures validées sont retenues', () {
        final s = carte(scens['defaut']);
        final cols = colonnes(genre, s);
        final notes = liste([for (final n in (s['notes'] as List)) {'t': n}]).map((x) => x['t']).join(' ');
        expect(nt(notes), contains('${cols[0].brouillons} brouillon(s) écarté(s)'));
        expect(nt(notes), contains('${cols[0].nbLignes} ligne(s) d’écriture validée(s) retenue(s)'));
        expect(cols[0].nbLignes + cols[0].brouillons, greaterThan(0));
      });
    });
  }

  group('le compte de résultat calculé : un compte n\'alimente QU\'UNE ligne, le préfixe le plus long gagne', () {
    CpaFiche e(String compte, double debit, double credit, {String statut = 'validee', String date = '2026-03-01', String journal = 'OD'}) =>
        {'compte': compte, 'debit': debit, 'credit': credit, 'statut': statut, 'date': date, 'journal': journal, 'numero': 'T-$compte'};
    final b = cpbBornesExercice(2026, DateTime(2026, 12, 31));

    test('« 654 » (cessions) va à RO et non à RJ (« 65 ») ; « 65 » seul va à RJ', () {
      final r = cpbResultatCalcule([e('654100', 500, 0), e('651100', 200, 0)], b);
      expect(r.valeurs['RO'], -500);
      expect(r.valeurs['RJ'], -200);
    });

    test('les charges sont NÉGATIVES, les sous-totaux suivent les formules imprimées', () {
      final r = cpbResultatCalcule([e('706000', 0, 1000), e('602100', 300, 0), e('661100', 200, 0), e('891000', 50, 0)], b);
      expect(r.valeurs['XB'], 1000);
      expect(r.valeurs['XC'], 700); // XB + RC
      expect(r.valeurs['XD'], 500); // XC + RK
      expect(r.valeurs['XI'], 450); // … + RS
    });

    test('un brouillon n\'est pas un fait comptable : écarté, compté', () {
      final r = cpbResultatCalcule([e('706000', 0, 1000), e('706000', 0, 9999, statut: 'brouillon')], b);
      expect(r.valeurs['TC'], 1000);
      expect(r.brouillons, 1);
      expect(r.nbLignes, 1);
    });

    test('un compte de gestion SANS ligne est NOMMÉ (orphelin), jamais compté en silence', () {
      final r = cpbResultatCalcule([e('709000', 0, 100)], b);
      expect(r.orphelins, {'709000': 100});
      expect(r.valeurs['XB'], 0);
    });

    test('une ligne de détail que le journal n\'alimente pas reste VIDE (—) ; un sous-total, jamais', () {
      final col = cpbSourceColonne('resultat', 2026, b, [e('706000', 0, 1000)]);
      final ta = cpbLignesResultat.firstWhere((l) => l.ref == 'TA');
      final xb = cpbLignesResultat.firstWhere((l) => l.ref == 'XB');
      final tc = cpbLignesResultat.firstWhere((l) => l.ref == 'TC');
      expect(cpbMontantFeuillet(col, ta), isNull);
      expect(nt(cpbMontantFeuillet(col, tc)), '1 000');
      expect(nt(cpbMontantFeuillet(col, xb)), '1 000');
    });

    test('la date d\'arrêt borne le calcul : une écriture postérieure n\'y entre pas', () {
      final r = cpbResultatCalcule([e('706000', 0, 1000, date: '2026-03-01'), e('706000', 0, 400, date: '2026-09-01')], cpbBornesExercice(2026, DateTime(2026, 6, 30)));
      expect(r.valeurs['TC'], 1000);
    });
  });

  group('le tableau des flux calculé : méthode indirecte, à-nouveaux = ouverture, contrôle de trésorerie', () {
    CpaFiche e(String compte, double debit, double credit, {String date = '2026-03-01', String journal = 'OD', String statut = 'validee'}) =>
        {'compte': compte, 'debit': debit, 'credit': credit, 'statut': statut, 'date': date, 'journal': journal, 'numero': 'T'};
    final b = cpbBornesExercice(2026, DateTime(2026, 12, 31));

    test('les à-nouveaux (journal AN) forment l\'OUVERTURE, jamais un flux : le capital n\'est pas un apport de l\'année', () {
      final r = cpbFluxCalcule([
        e('521000', 1000, 0, date: '2026-01-01', journal: 'AN'),
        e('101100', 0, 1000, date: '2026-01-01', journal: 'AN'),
      ], b);
      expect(r.valeurs['ZA'], 1000);
      expect(r.valeurs['FK'], 0);
      expect(r.valeurs['ZH'], 1000);
      expect(r.controle, 1000);
      expect(r.ecart, 0);
    });

    test('une vente encaissée : CAFG = produit, trésorerie = classe 5, contrôle concordant', () {
      final r = cpbFluxCalcule([e('521000', 800, 0), e('706000', 0, 800)], b);
      expect(r.valeurs['FA'], 800);
      expect(r.valeurs['ZB'], 800);
      expect(r.valeurs['ZH'], 800);
      expect(r.ecart, 0);
    });

    test('une créance (411 débiteur) pèse sur le besoin de financement : FD négatif, la trésorerie ne bouge pas', () {
      final r = cpbFluxCalcule([e('411000', 500, 0), e('706000', 0, 500)], b);
      expect(r.valeurs['FA'], 500);
      expect(r.valeurs['FD'], -500);
      expect(r.valeurs['ZB'], 0);
      expect(r.controle, 0);
      expect(r.ecart, 0);
    });

    test('un compte de tiers change de côté selon son SOLDE : 411 créditeur compte comme une dette', () {
      final r = cpbFluxCalcule([e('411000', 0, 300), e('571000', 300, 0)], b);
      expect(r.valeurs['FE'], 300);
      expect(r.valeurs['FD'], 0);
    });

    test('un mouvement que le tableau ne classe pas est NOMMÉ au contrôle (écart), jamais corrigé en silence', () {
      final r = cpbFluxCalcule([e('521000', 100, 0), e('131000', 0, 100)], b);
      expect(r.nonClasses.keys, contains('131000'));
      expect(r.ecart, isNot(0));
    });

    test('un brouillon n\'entre pas dans les flux ; il est compté', () {
      final r = cpbFluxCalcule([e('521000', 100, 0, statut: 'brouillon'), e('706000', 0, 100, statut: 'brouillon')], b);
      expect(r.brouillons, 2);
      expect(r.valeurs['ZH'], 0);
    });
  });

  group('m12-seuil-rentabilite : la répartition fixe / variable est une PROPOSITION, le seuil incalculable un DIAGNOSTIC', () {
    final scens = carte(ecrans['m12-seuil-rentabilite']);
    String libelle(String n) => cpaCompteLibelle(n);

    CpbSeuil calc(F s, {Map<String, String> natures = const {}}) {
      final r = carte(s['reglages']);
      return cpbSeuilRentabilite(toutes, bornes('${r['periode']}', DateTime.parse('${r['arrete']}')),
          natures: natures, libelleCompte: libelle);
    }

    for (final nom in ['defaut', 'mois', 'semestre', 'jour', 'trimestre_aout', 'toutVariable', 'toutFixe']) {
      test('$nom : les six indicateurs sont ceux de l\'écran', () {
        final s = carte(scens[nom]);
        Map<String, String> natures = const {};
        if (nom == 'toutVariable' || nom == 'toutFixe') {
          final nums = {for (final x in toutes) if ('${x['compte']}'.startsWith('6')) '${x['compte']}'};
          natures = {for (final n in nums) n: nom == 'toutVariable' ? 'variable' : 'fixe'};
        }
        final r = calc(s, natures: natures);
        final k = liste(s['kpis']);
        expect(mof(r.ca), nt(k[0]['valeur']));
        expect(mof(r.variable), nt(k[1]['valeur']));
        expect(mof(r.fixe), nt(k[2]['valeur']));
        expect(mof(r.marge), nt(k[3]['valeur']));
        expect(nt(k[3]['indice']), nt('taux : ${pourcent(r.taux * 100)}'));
        expect(r.seuil != null ? mof(r.seuil) : 'incalculable', nt(k[4]['valeur']));
        expect(r.securite != null ? mof(r.securite) : '—', nt(k[5]['valeur']));
        if (r.securite != null && r.ca != 0) expect(nt(k[5]['indice']), nt('${pourcent(r.securite! / r.ca * 100)} du CA'));
      });
    }

    test('le seuil se calcule : charges fixes / taux de marge ; la marge de sécurité = CA − seuil', () {
      final r = calc(carte(scens['trimestre_aout']));
      expect(r.seuil, closeTo(r.fixe / r.taux, 1e-6));
      expect(r.securite, closeTo(r.ca - r.seuil!, 1e-6));
    });

    test('marge sur coût variable négative : seuil INCALCULABLE, et l\'écran le dit comme diagnostic', () {
      final s = carte(scens['toutVariable']);
      final r = calc(s, natures: {
        for (final x in {for (final y in toutes) if ('${y['compte']}'.startsWith('6')) '${y['compte']}'}) x: 'variable'
      });
      expect(r.seuil, isNull);
      expect(r.securite, isNull);
      expect(nt((s['notes'] as List).join(' ')), contains('Le seuil ne peut pas être calculé.'));
    });

    test('point mort : seulement si le seuil est atteint (seuil <= CA), en supposant l\'activité régulière', () {
      final r = calc(carte(scens['defaut']));
      expect(r.pointMort, isNull);
      final r2 = cpbSeuilRentabilite([
        {'compte': '706000', 'debit': 0, 'credit': 1000, 'statut': 'validee', 'date': '2026-10-01'},
        {'compte': '605200', 'debit': 100, 'credit': 0, 'statut': 'validee', 'date': '2026-10-01'},
      ], bornes('annee', DateTime(2026, 10, 30)), libelleCompte: libelle);
      expect(r2.seuil, 100);
      expect(r2.pointMort, isNotNull);
      expect(r2.pointMort, ajouterJours(r2.bornes.debut, (100 / 1000 * 365).round()));
    });

    test('la nature corrigée l\'emporte sur la proposition ; sans correction, le préfixe le plus long l\'emporte', () {
      expect(cpbNatureCharge('601100'), 'variable');
      expect(cpbNatureCharge('605200'), 'fixe');
      expect(cpbNatureCharge('999999'), 'fixe');
      final b = bornes('annee', DateTime(2026, 10, 30));
      final a = cpbChargesParNature(toutes, b, libelleCompte: libelle);
      final c = cpbChargesParNature(toutes, b, natures: {'604100': 'fixe'}, libelleCompte: libelle);
      expect(c.variable, a.variable - 6482000);
      expect(c.fixe, a.fixe + 6482000);
    });

    test('la bascule d\'un compte : même effet que l\'écran, sa décision est écrite au magasin', () {
      final s = carte(scens['bascule']);
      expect(s['titreBouton'], 'Basculer en fixe');
      expect(s['reglage'], {'604100': 'fixe'});
      final b = bornes('annee', DateTime(2026, 10, 30));
      final r = cpbSeuilRentabilite(toutes, b, natures: {'604100': 'fixe'}, libelleCompte: libelle);
      final k = liste(s['kpisApres']);
      expect(mof(r.variable), nt(k[1]['valeur']));
      expect(mof(r.fixe), nt(k[2]['valeur']));
      expect(r.seuil != null ? mof(r.seuil) : 'incalculable', nt(k[4]['valeur']));
    });

    test('le tableau des charges : mêmes comptes, même ordre (du plus grand au plus petit), mêmes montants', () {
      final s = carte(scens['defaut']);
      final r = calc(s);
      final rows = liste(carte(liste(s['tables'])[0])['lignes']).map((l) => (l['cellules'] as List).cast<String>()).toList();
      expect(rows.length, r.comptes.length);
      for (final (i, c) in r.comptes.indexed) {
        expect(rows[i][0], c.compte);
        expect(nt(rows[i][3]), nt(money(c.montant, avecDevise: false)));
        expect(rows[i][2], c.nature == 'variable' ? 'Variable — suit l’activité' : 'Fixe — tombe de toute façon');
      }
      final f = carte(s['filtreNb']);
      expect(f['variable'], r.comptes.where((c) => c.nature == 'variable').length);
      expect(f['fixe'], r.comptes.where((c) => c.nature == 'fixe').length);
    });
  });

  group('les exercices du sélecteur', () {
    test('l\'année du jour et celles du journal, de la plus récente à la plus ancienne', () {
      final r = cpbExercicesDuJournal(toutes, auj);
      expect(r.first, 2026);
      final opts = (carte(carte(ecrans['m12-compte-resultat'])['defaut'])['options'] as List).map((o) => (o as List)[0]).toList();
      expect([for (final a in r) '$a', 'depose'], opts);
    });

    test('la date arrêtée ne dépasse jamais le 31 décembre de l\'exercice, ni ne sort de son année', () {
      expect(cpbBornesExercice(2026, DateTime(2027, 2, 1)).fin, DateTime(2026, 12, 31));
      expect(cpbBornesExercice(2025, DateTime(2026, 2, 1)).fin, DateTime(2025, 12, 31));
      expect(cpbBornesExercice(2026, DateTime(2026, 6, 30)).fin, DateTime(2026, 6, 30));
    });
  });
}
