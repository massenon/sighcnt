// Rejoue les vecteurs de M12 (comptabilité de base) tirés des écrans réels de la maquette (prototype_html/build/vecteurs-comptabilite.js) : tableau de
// bord, journaux, écritures, grand livre, balance, dépenses. Le jeu est celui du poste (apps/poste/assets/donnees/jeu).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) => ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();
Map<String, Object?> carte(Object? v) => (v as Map).cast<String, Object?>();

/// `innerText` normalisé de la maquette : toute espace (insécable et fine comprises) vaut une espace.
String nt(Object? s) => '$s'.replaceAll(RegExp(r'[\s  ]+'), ' ').trim();
String mo(Object? v) => nt(cpaMontant(v));
String mof(Object? v) => nt(money(v));

List<F> jeu(String nom) => liste(jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()));

void main() {
  final f = File('test/vecteurs/comptabilite.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-comptabilite.js`');
  final v = carte(jsonDecode(f.readAsStringSync()));
  final ref = carte(v['referentiels']);
  final ecrans = carte(v['ecrans']);
  final cas = carte(v['cas']);

  final toutes = jeu('ecritures').where((e) => e['statut'] != 'archive').toList();
  final comptes = jeu('comptes').where((e) => e['statut'] != 'archive').toList();
  final e26 = cpaEcrituresExercice(toutes, 2026);
  final auj = DateTime(2026, 10, 30, 10);

  group('référentiels : ce que la maquette porte', () {
    test('journaux, catégories de dépense, centres de coûts', () {
      expect([for (final j in cpaJournaux) {'code': j.$1, 'libelle': j.$2, 'contrepartie': j.$3}],
          liste(ref['journaux']).map((j) => {'code': j['code'], 'libelle': j['libelle'], 'contrepartie': j['contrepartie']}).toList());
      expect([for (final c in cpaCategoriesDepense) c.$1], liste(ref['categoriesDepense']).map((c) => c['id']).toList());
      expect([for (final c in cpaCategoriesDepense) c.$2], liste(ref['categoriesDepense']).map((c) => c['label']).toList());
      expect([for (final c in cpaCentresCout) [c.$1, c.$2, c.$3]],
          liste(ref['centres']).map((c) => [c['id'], c['label'], c['type']]).toList());
    });
    test('le plan statique engendré est celui de D.PLAN_COMPTABLE', () {
      final p = liste(ref['planComptable']);
      expect(cpaPlanEnFiches().length, p.length);
      for (var i = 0; i < p.length; i++) {
        expect(cpaPlanEnFiches()[i], {'num': p[i]['num'], 'libelle': p[i]['libelle'], 'classe': p[i]['classe'], 'journal': p[i]['journal'], 'source': p[i]['source']});
      }
    });
    test('exercices : 2024 et 2025 clos par la liasse déposée, 2026 ouvert', () {
      for (final x in liste(ref['exercices'])) {
        expect(cpaEtatExercice(x['annee'] as int), x['etat'], reason: '${x['annee']}');
      }
      expect(carte(ref['depot'])['dateDepot'], cpaLiasseDateDepot);
      expect(ref['provisoires2026'], 0, reason: 'N-1 clos : aucun à-nouveau provisoire');
    });
    test('un numéro de compte inconnu s\'affiche tel quel ; « — » pour une catégorie absente', () {
      expect(cpaCompteLibelle('999999'), '999999');
      expect(cpaCompteLibelle('601100'), 'Achats de marchandises');
      expect(cpaCategorieDepenseLibelle(null), '—');
      expect(cpaClasseLibelle(6), 'Classe 6 — Charges');
    });
  });

  group('m12-plan-comptable', () {
    final r = carte(ecrans['m12-plan-comptable']);
    final cr = carte(r['creations']);
    String? refus(String nom) => carte((carte(cr[nom])['toasts'] as List).first)['message'] as String?;

    test('les refus de numéro sont ceux de la maquette : six chiffres, puis unicité à la création seulement', () {
      expect(cpaVerifierNumeroCompte('12345', comptes, edition: false), refus('numeroCourt'));
      expect(cpaVerifierNumeroCompte('60A900', comptes, edition: false), refus('numeroLettres'));
      expect(cpaVerifierNumeroCompte('601100', comptes, edition: false), refus('doublon'));
      expect(cpaVerifierNumeroCompte('605900', comptes, edition: false), isNull);
      // à la modification, un numéro déjà pris n'est pas contrôlé (porté fidèlement) ; six chiffres le restent
      expect(cpaVerifierNumeroCompte('601100', comptes, edition: true), isNull);
      expect(cpaVerifierNumeroCompte('1234567', comptes, edition: true), isNotNull);
    });
    test('la création écrit un « Complément » de classe numérique, comme la maquette', () {
      final a = liste(carte(carte(carte(cr['valide'])['ecart'])['inserts'])['comptes']).single;
      final f = cpaCompteDeSaisie({'num': '605900', 'libelle': 'Petit outillage — essai', 'classe': '6', 'journal': 'ACH'});
      for (final k in ['num', 'libelle', 'classe', 'journal', 'source']) {
        expect(f[k], a[k], reason: k);
      }
    });
    test('modifier un compte du DOCUMENT conserve sa provenance (E721 corrigé dans la maquette, vecteur relu)', () {
      final doc = comptes.firstWhere((c) => c['num'] == '601100');
      final f = cpaCompteDeSaisie({'num': '601100', 'libelle': 'Achats de marchandises (corrigé)', 'classe': '6', 'journal': 'ACH'}, record: doc);
      expect(f.containsKey('source'), isFalse, reason: 'le patch ne touche pas la provenance');
      final p = (carte(carte(r['editionDocument'])['ecart'])['modifs'] as Map)['comptes'] as List;
      expect(carte(carte(p.single)['patch']).containsKey('source'), isFalse);
    });
    test('la balance et le tiroir : 112 comptes au jeu', () => expect(comptes.length, 112));
  });

  group('m12-dashboard', () {
    final r = carte(ecrans['m12-dashboard']);
    final t = cpaTableauDeBord(e26);
    test('les huit indicateurs', () {
      final k = {for (final x in liste(r['kpis'])) x['label']: nt(x['valeur'])};
      expect(mof(t.tresorerie), k['Trésorerie disponible']);
      expect(mof(t.chiffreAffaires), k['Chiffre d’affaires']);
      expect(mof(t.charges), k['Charges']);
      expect(mof(t.resultat), k['Résultat']);
      expect(mof(t.clients), k['Créances clients']);
      expect(mof(t.fournisseurs), k['Dettes fournisseurs']);
      expect(nombre(t.nbEcritures), k['Écritures de l’exercice']);
      expect(t.equilibre ? 'Équilibré' : mof(t.ecart), k['Équilibre (RG-10)']);
    });
    test('l\'alerte : brouillons à valider', () {
      expect(nt((r['alertes'] as List).first), contains('${t.brouillons} écriture(s) en brouillon à valider.'));
    });
    test('charges par centre, écritures par journal, origine', () {
      final cl = (r['classements'] as List).first as List;
      final centres = cpaChargesParCentre(e26, (k) {
        for (final c in cpaCentresCout) {
          if (c.$1 == k) return c.$2;
        }
        return k;
      });
      expect([for (final c in centres) [c.$1, nt(cpaMontant(c.$2))]], [for (final x in cl) [(x as List)[0], nt(x[1])]]);
      final gr = liste(r['graphiques']);
      final parJournal = cpaGrouper(e26, 'journal');
      expect([for (final k in parJournal.keys) cpaJournalLibelle(k)], gr[1]['etiquettes']);
      expect([for (final k in parJournal.keys) parJournal[k]!.length], gr[1]['series']);
      final parOrigine = cpaGrouper(e26, 'origine');
      expect(parOrigine.keys.toList(), gr[2]['etiquettes']);
      expect([for (final k in parOrigine.keys) parOrigine[k]!.length], carte((gr[2]['series'] as List).first)['data']);
    });
    test('automatisation : huit opérations', () => expect(cpaAutomatisations.length, 8));
  });

  group('m12-journaux', () {
    final r = carte(ecrans['m12-journaux']);
    test('une ligne par journal, équilibre et écart', () {
      final l = cpaLignesJournaux(e26);
      final att = (r['lignes'] as List).map((x) => (x as List).map(nt).toList()).toList();
      expect(l.length, att.length);
      for (var i = 0; i < l.length; i++) {
        final c = att[i];
        expect(c[0], l[i].code);
        expect(c[1], l[i].libelle);
        expect(c[2], l[i].contrepartie ?? 'Variable');
        expect(c[3], '${l[i].nb}');
        expect(c[4], mo(l[i].debit));
        expect(c[5], mo(l[i].credit));
        expect(c[6], l[i].equilibre ? 'Équilibré' : 'Écart ${mo(l[i].ecart)}');
      }
    });
    test('le tiroir du journal de caisse : totaux et quarante lignes au plus', () {
      final j = cpaLignesJournaux(e26).firstWhere((x) => x.code == 'CAI');
      final t = carte(r['tiroir']);
      expect((t['kpis'] as List).map((k) => nt((k as List)[1])).toList(), [mof(j.debit), mof(j.credit)]);
      expect((t['lignes'] as List).length, j.nb < 40 ? j.nb : 40);
    });
    test('la pièce imprimée : totaux refaits depuis les lignes', () {
      final p = carte(r['piece']);
      final j = cpaLignesJournaux(e26).firstWhere((x) => x.code == 'CAI');
      expect(nt(p['contenu']).replaceAll(' ', ''), contains('TOTAUX${mo(j.debit)}${mo(j.credit)}'.replaceAll(' ', '')));
      expect((p['cartouche'] as List).map((c) => nt((c as List)[1])), containsAll(['${j.nb}', mof(j.debit), mof(j.credit), 'Équilibré']));
    });
  });

  group('m12-balance', () {
    final r = carte(ecrans['m12-balance']);
    final b = cpaBalance(comptes, e26);
    test('les KPI et l\'équilibre', () {
      final k = {for (final x in liste(r['kpis'])) x['label']: nt(x['valeur'])};
      expect(k['Comptes mouvementés'], '${b.length}');
      expect(k['Total débit'], mof(b.fold<double>(0, (a, x) => a + x.debit)));
      expect(k['Total crédit'], mof(b.fold<double>(0, (a, x) => a + x.credit)));
    });
    test('chaque classe : numéro, intitulé, mouvements et soldes', () {
      final pc = carte(r['parClasse']);
      for (final cl in pc.keys) {
        final att = (pc[cl] as List).map((l) => (l as List).map(nt).toList()).toList();
        final mes = trierPar([for (final x in b) if ('${x.classe}' == cl) x], (x) => x.num);
        expect(mes.length, att.length, reason: 'classe $cl');
        for (var i = 0; i < mes.length; i++) {
          expect(att[i][0], mes[i].num);
          expect(att[i][1], mes[i].libelle);
          expect(att[i][2], 'C${mes[i].classe}');
          expect(att[i][3], '${mes[i].nb}');
          expect(att[i][4], mo(mes[i].debit));
          expect(att[i][5], mo(mes[i].credit));
          expect(att[i][6], mes[i].soldeDebiteur > 0 ? mo(mes[i].soldeDebiteur) : '—');
          expect(att[i][7], mes[i].soldeCrediteur > 0 ? mo(mes[i].soldeCrediteur) : '—');
        }
      }
    });
    test('la balance âgée des tiers, tranche par tranche', () {
      final tr = cpaBalanceAgee(jeu('factures').where((x) => x['statut'] != 'archive'), auj);
      final att = (carte(r['agee'])['lignes'] as List).map((l) => (l as List).map(nt).toList()).toList();
      expect(tr.length, att.length);
      for (var i = 0; i < tr.length; i++) {
        expect(att[i], [tr[i].libelle, '${tr[i].nbPatients}', mo(tr[i].montantPatients), '${tr[i].nbAssureurs}', mo(tr[i].montantAssureurs), mo(tr[i].total)]);
      }
    });
    test('la pièce imprimée : totaux calculés', () {
      final p = carte(r['piece']);
      final td = b.fold<double>(0, (a, x) => a + x.debit), tc = b.fold<double>(0, (a, x) => a + x.credit);
      expect(nt(p['contenu']).replaceAll(' ', ''), contains('TOTAUX${mo(td)}${mo(tc)}'.replaceAll(' ', '')));
    });
  });

  group('m12-grand-livre', () {
    final r = carte(ecrans['m12-grand-livre']);
    test('les comptes mouvementés sont ceux de la maquette', () {
      final mv = cpaComptesMouvementes(comptes, e26).map((c) => c['num']).toList();
      expect(mv.toSet().toList(), r['comptesMouvementes']);
    });
    test('pour chaque compte : mouvements, totaux, solde et solde progressif', () {
      final cs = carte(r['comptes']);
      for (final num in cs.keys) {
        final c = carte(cs[num]);
        final s = cpaSoldeCompte(e26, num);
        final k = (c['kpis'] as List).map((x) => (x as List).map((y) => y == null ? null : nt(y)).toList()).toList();
        expect(k[0][1], '${s.nb}', reason: num);
        expect(k[1][1], mof(s.debit), reason: num);
        expect(k[2][1], mof(s.credit), reason: num);
        expect(k[3][1], mof(s.solde), reason: num);
        expect(k[3][2], s.solde >= 0 ? 'Débiteur' : 'Créditeur', reason: num);
        final gl = cpaGrandLivre(e26, num);
        expect(c['nb'], gl.length < 20 ? gl.length : 20);
        final att = (c['premieres'] as List).map((l) => (l as List).map(nt).toList()).toList();
        for (var i = 0; i < att.length; i++) {
          expect(att[i][0], '${gl[i]['numero']}', reason: '$num/$i');
          expect(att[i][3], '${gl[i]['libelle']}');
          expect(att[i][7], mo(gl[i]['soldeProgressif']), reason: '$num/$i : solde progressif');
        }
      }
    });
  });

  group('m12-ecritures : la saisie en partie double', () {
    List<F> saisir(String statut, String journal, String libelle, List<F> lignes,
            {String date = '2026-10-30', String centre = '', String piece = '', Iterable<F>? existantes}) =>
        cpaEcrituresDeSaisie(
            date: date, journal: journal, libelle: libelle, centreCout: centre, piece: piece, lignes: lignes, statut: statut, exercice: 2026, toutes: existantes ?? toutes);

    void memes(List<F> obtenu, List<F> attendu) {
      List<F> tri(List<F> l) => (List<F>.of(l)..sort((a, b) => '${a['compte']}'.compareTo('${b['compte']}')));
      final o = tri(obtenu), a = tri(attendu);
      expect(o.length, a.length);
      for (var i = 0; i < a.length; i++) {
        for (final k in a[i].keys) {
          final x = o[i][k], y = a[i][k];
          expect(x is num ? x.toDouble() : x, y is num ? y.toDouble() : y, reason: k);
        }
      }
    }

    test('une écriture validée équilibrée : deux lignes plates, numérotée dans la série du journal', () {
      final a = liste(carte(carte(carte(cas['validerEquilibree'])['ecart'])['inserts'])['ecritures']);
      final l = saisir('validee', 'CAI', 'Achat de petit matériel', [
        {'compte': '605600', 'debit': 7500, 'credit': 0},
        {'compte': '571000', 'debit': 0, 'credit': 7500}
      ], centre: 'pharmacie', piece: 'PJ-validerEquilibree');
      memes(l, a);
    });
    test('un brouillon déséquilibré est ACCEPTÉ, sa validation est REFUSÉE en nommant l\'écart', () {
      final a = liste(carte(carte(carte(cas['brouillonDesequilibre'])['ecart'])['inserts'])['ecritures']);
      final lignes = [
        {'compte': '601100', 'debit': 5000, 'credit': 0},
        {'compte': '571000', 'debit': 0, 'credit': 4000}
      ];
      memes(saisir('brouillon', 'OD', 'Brouillon déséquilibré', lignes, piece: 'PJ-brouillonDesequilibre'), a);
      expect(() => saisir('validee', 'OD', 'x', lignes), throwsA(isA<CpaRefus>().having((e) => e.message, 'message', 'RG-10 — écriture déséquilibrée : validation impossible.').having((e) => nt(e.detail), 'détail', 'Écart de ${mof(1000)}.')));
      final t = (cas['validerDesequilibree'] as Map)['toasts'] as List;
      expect(nt(carte(t.first)['detail']), 'Écart de ${mof(1000)}.');
    });
    test('aucune ligne : refus nommé ; une ligne à zéro ou des deux sens : refus nommés', () {
      expect(() => saisir('brouillon', 'OD', 'x', []), throwsA(isA<CpaRefus>().having((e) => e.message, 'm', 'Ajouter au moins une ligne.')));
      expect(() => cpaVerifierLigne(0, 0), throwsA(isA<CpaRefus>().having((e) => e.message, 'm', carte((cas['ligneZero'] as Map)['toasts'] is List ? ((cas['ligneZero'] as Map)['toasts'] as List).first : {})['message'])));
      expect(() => cpaVerifierLigne(10, 5), throwsA(isA<CpaRefus>().having((e) => e.message, 'm', 'Une ligne ne peut être simultanément au débit et au crédit.')));
      cpaVerifierLigne(10, 0);
    });
    test('un exercice clos refuse, avec le motif du moteur, et rien n\'est écrit', () {
      final motif = cas['exerciceClos'] as Map;
      final attendu = carte((motif['toasts'] as List).first)['detail'];
      expect(cpaGardeEcriture('2025-12-20'), attendu);
      expect(cpaGardeEcriture('2026-01-01'), isNull);
      expect(cpaGardeEcriture(null), isNull);
      expect(() => saisir('validee', 'OD', 'x', [{'compte': '601100', 'debit': 1000, 'credit': 0}, {'compte': '571000', 'debit': 0, 'credit': 1000}], date: '2025-12-20'),
          throwsA(isA<CpaRefus>().having((e) => e.detail, 'détail', attendu)));
    });
    test('la numérotation lit les fiches existantes : archivées comprises, jamais « lignes actives + 1 » (E711)', () {
      final n = cas['numeros'] as Map;
      final tous = [...toutes];
      expect(cpaNumeroPiece('OD', 2026, tous), n['desequilibre']);
      expect(cpaNumeroPiece('BQ', 2026, tous), n['equilibre']);
      // une pièce archivée garde son rang : le suivant ne le réattribue pas
      expect(cpaNumeroPiece('OD', 2026, [...tous, {'numero': 'OD-2026-00500', 'statut': 'archive'}]), 'OD-2026-00501');
    });
    test('valider une ligne valide la PIÈCE entière, RG-10 contrôlé sur l\'ensemble (E710)', () {
      final piece = [
        {'id': 'a', 'numero': 'OD-1', 'statut': 'brouillon', 'debit': 1000, 'credit': 0},
        {'id': 'b', 'numero': 'OD-1', 'statut': 'brouillon', 'debit': 0, 'credit': 700},
        {'id': 'c', 'numero': 'OD-2', 'statut': 'brouillon', 'debit': 5, 'credit': 0},
      ];
      expect(() => cpaValiderPiece(piece, piece[0]), throwsA(isA<CpaRefus>().having((e) => nt(e.detail), 'détail', 'Pièce OD-1 : écart de ${mof(300)}.')));
      final ok = [
        {'id': 'a', 'numero': 'OD-1', 'statut': 'brouillon', 'debit': 1000, 'credit': 0},
        {'id': 'b', 'numero': 'OD-1', 'statut': 'brouillon', 'debit': 0, 'credit': 1000},
      ];
      expect(cpaValiderPiece(ok, ok[1]).map((x) => x['id']), ['a', 'b']);
      final t = (cas['validerLigneDesequilibree'] as Map)['toasts'] as List;
      expect(carte(t.first)['message'], 'RG-10 — écriture déséquilibrée : validation impossible.');
      expect(((cas['validerPieceEquilibree'] as Map)['nbLignes']), 2);
    });
  });

  group('m12-depenses', () {
    final r = carte(ecrans['m12-depenses']);
    final dep = jeu('depenses').where((x) => x['statut'] != 'archive').toList();
    final banques = jeu('banques');
    test('les quatre indicateurs (pas cinq) sur tout l\'historique', () {
      final i = cpaIndicateursDepenses(dep, '2026-10-30');
      final k = liste(r['kpis']);
      expect(k.length, 4);
      expect([mof(i.duJour), mof(i.duMois), mof(i.total), '${i.nbSansRecu}'], [nt(k[0]['valeur']), nt(k[1]['valeur']), nt(k[2]['valeur']), nt(k[3]['valeur'])]);
      expect(['${i.nbJour} pièce(s)', '${i.nbMois} pièce(s)', '${i.nb} dépense(s)', '${mof(i.sansRecu)} contestables'], [nt(k[0]['indice']), nt(k[1]['indice']), nt(k[2]['indice']), nt(k[3]['indice'])]);
    });
    test('sur une plage : le filtre retient les dates, les indicateurs suivent', () {
      final p = [for (final x in dep) if ('${x['date']}'.compareTo('2026-10-01') >= 0 && '${x['date']}'.compareTo('2026-10-30') <= 0) x];
      final i = cpaIndicateursDepenses(p, '2026-10-30');
      final k = [for (final x in (carte(r['plageOctobre'])['kpis'] as List)) {'l': (x as List)[0], 'v': x[1], 'h': x[2]}];
      expect([mof(i.duJour), mof(i.duMois), mof(i.total)], [nt(k[0]['v']), nt(k[1]['v']), nt(k[2]['v'])]);
      expect(p.length < 15 ? p.length : 15, (carte(r['plageOctobre'])['lignes'] as List).length);
    });
    test('cumul par catégorie et dépenses par mois', () {
      final c = cpaCumulCategories(dep);
      final att = (r['cumul'] as List).map((l) => (l as List).map(nt).toList()).toList();
      expect([for (final x in c) [x.libelle, '${x.nombre}', mo(x.total)]], att);
      final gr = liste(r['graphiques']);
      final mois = cpaDepensesParMois(dep);
      expect([for (final m in mois) m.$1], gr[0]['etiquettes']);
      expect([for (final m in mois) m.$2], (carte((gr[0]['series'] as List).first)['data'] as List).map((x) => (x as num).toDouble()).toList());
      expect([for (final x in c) x.total], (gr[1]['series'] as List).map((x) => (x as num).toDouble()).toList());
    });
    test('une dépense à trois lignes : le total est la somme, UN débit par ligne, UN crédit de trésorerie du total, en brouillon', () {
      final n = carte(r['nouvelles']);
      final lignes = <F>[
        {'libelle': 'Gants d’examen', 'compteCharge': '601100', 'montant': 12000},
        {'libelle': 'Compresses', 'compteCharge': '604100', 'montant': 8000},
        {'libelle': 'Sparadrap', 'compteCharge': '605600', 'montant': 4500},
      ];
      final t = cpaTotauxDepense('', lignes);
      expect(t.montant, 24500);
      expect(t.libelle, 'Gants d’examen (+2 autre(s))');
      final reference = cpaReferenceDepense('2026-10-30', dep);
      final attendu = liste(carte(carte(carte(n['troisLignes'])['ecart'])['inserts'])['ecritures']);
      expect(reference, attendu.first['numero']);
      final e = cpaEcrituresDepense({'id': 'D', 'reference': reference, 'date': '2026-10-30', 'libelle': t.libelle, 'montant': t.montant, 'lignes': lignes},
          banques.firstWhere((b) => b['id'] == 'BQ00'));
      expect(e.length, 4);
      expect(e.every((x) => x['statut'] == 'brouillon' && x['numero'] == reference), isTrue);
      expect(e.fold<double>(0, (a, x) => a + (x['debit'] as num)), e.fold<double>(0, (a, x) => a + (x['credit'] as num)), reason: 'RG-10');
      String nb(Object? x) => '${(x as num).round()}';
      List<String> cle(List<F> l) => [for (final x in l) '${x['compte']}|${nb(x['debit'])}|${nb(x['credit'])}|${x['libelle']}|${x['compteLibelle']}|${x['journal']}']..sort();
      expect(cle(e), cle(attendu));
    });
    test('le reçu n\'est pas bloquant ; une ligne sur banque : journal BQE (absent de D.JOURNAUX, E719), compte 5xx de la fiche', () {
      final attendu = liste(carte(carte(carte(carte(r['nouvelles'])['uneLigneBanque'])['ecart'])['inserts'])['ecritures']);
      final e = cpaEcrituresDepense({'id': 'D', 'reference': 'DEP-2026-0192', 'date': '2026-10-29', 'libelle': 'Droits de timbre — essai', 'montant': 3000, 'lignes': [{'libelle': 'Timbres fiscaux', 'compteCharge': '646210', 'montant': 3000}]},
          banques.firstWhere((b) => b['id'] == 'BQ01'));
      expect({for (final x in e) x['compte']: x['journal']}, {for (final x in attendu) x['compte']: x['journal']});
      expect(e.first['journal'], 'BQE');
      expect(cpaJournaux.any((j) => j.$1 == 'BQE'), isFalse);
      expect([for (final x in e) x['libelle']]..sort(), [for (final x in attendu) x['libelle']]..sort());
    });
    test('refus nommés : aucune ligne ; exercice clos refusé AVANT toute écriture (E714)', () {
      expect(() => cpaTotauxDepense('x', []), throwsA(isA<CpaRefus>().having((e) => e.message, 'm', 'La pièce exige au moins une ligne de dépense.')));
      final n = carte(r['nouvelles']);
      expect(carte((carte(n['sansLigne'])['toasts'] as List).first)['message'], 'La pièce exige au moins une ligne de dépense.');
      final attendu = carte((carte(n['exerciceClos'])['toasts'] as List).first)['detail'];
      expect(
          () => cpaEcrituresDepense({'id': 'D', 'reference': 'DEP-2025-0001', 'date': '2025-11-12', 'libelle': 'x', 'montant': 9000, 'lignes': [{'libelle': 'x', 'compteCharge': '631810', 'montant': 9000}]}, banques.first),
          throwsA(isA<CpaRefus>().having((e) => e.detail, 'détail', attendu)));
    });
    test('une pièce d\'ancienne génération se lit comme UNE ligne', () {
      expect(cpaLignesDepense({'libelle': 'Ancien', 'compteCharge': '604700', 'montant': '1500'}), [
        {'libelle': 'Ancien', 'compteCharge': '604700', 'montant': 1500}
      ]);
    });
  });
}
