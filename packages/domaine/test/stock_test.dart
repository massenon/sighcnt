// Rejoue les VECTEURS des écrans de stock M6 (prototype_html/build/vecteurs-stock.js) : les fiches d'ENTRÉE (produits, lots, mouvements) sont celles que
// la maquette a reçues, les SORTIES sont ce qu'elle a AFFICHÉ. Le domaine Dart doit rendre les mêmes chiffres, au caractère près.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

late final Map<String, Object?> v;
late final List<Map<String, Object?>> produits, lots, mouvements;
late final Map<String, Object?> s;
final auj = DateTime(2026, 8, 16);

List<Map<String, Object?>> liste(Object? o) =>
    [for (final x in (o! as List)) (x as Map).cast<String, Object?>()];
Map<String, Object?> carte(Object? o) => (o! as Map).cast<String, Object?>();

/// Une colonne d'un tableau lu à l'écran par ses EN-TÊTES (jamais par son rang : la case de sélection décale tout).
List<String> colonne(Object? tableau, String entete) {
  final t = carte(tableau);
  final i = (t['entetes']! as List).indexOf(entete);
  expect(i, greaterThanOrEqualTo(0), reason: 'en-tête $entete introuvable');
  return [for (final l in (t['lignes']! as List)) '${(l as List)[i]}'];
}

String kpi(Object? ecran, String libelle) => [
      for (final k in liste(carte(ecran)['kpis']))
        if (k['libelle'] == libelle) '${k['valeur']}'
    ].single;

const etats = {
  'rupture': 'Rupture',
  'critique': 'Critique',
  'normal': 'Normal'
};

void main() {
  // chargés AVANT la déclaration des groupes : certains génèrent un test par cas
  final f = File('test/vecteurs/stock.json');
  if (!f.existsSync()) {
    fail(
        'vecteurs absents : lancer `node prototype_html/build/vecteurs-stock.js`');
  }
  v = carte(jsonDecode(f.readAsStringSync()));
  final jeu = carte(v['jeu']);
  produits = liste(jeu['produits']);
  lots = liste(jeu['lots']);
  mouvements = liste(jeu['mouvements']);
  s = carte(v['sorties']);

  test('l\'horloge des vecteurs est le 16/08/2026', () {
    expect(v['auj'], '2026-08-16');
  });

  group(
      'référentiels statiques (D.CATEGORIES_PRODUIT, TYPES_MOUVEMENT, TYPES_STOCK)',
      () {
    test('identiques à ceux de la maquette', () {
      final r = carte(v['referentiels']);
      expect([
        for (final c in categoriesProduit) {'id': c.id, 'label': c.label}
      ], liste(r['categories']));
      expect([
        for (final t in typesMouvement)
          {'id': t.id, 'label': t.label, 'badge': t.badge}
      ], liste(r['typesMouvement']));
      expect([
        for (final t in typesStock) {'id': t.id, 'label': t.label}
      ], liste(r['typesStock']));
    });
  });

  group('état du stock et seuils', () {
    test('chaque ligne du référentiel produits : état, valeur, total', () {
      final t = carte(s['produits'])['tableaux']! as List;
      final table = t.first;
      final codes = colonne(table, 'CODE');
      final lesEtats = colonne(table, 'ÉTAT');
      final valeurs = colonne(table, 'VALEUR');
      final totaux = colonne(table, 'TOTAL');
      expect(codes.length, produits.length);
      for (var i = 0; i < codes.length; i++) {
        final p = produits.firstWhere((x) => x['code'] == codes[i]);
        expect(etats[etatStock(p['stock'], p['seuilAlerte'])], lesEtats[i],
            reason: codes[i]);
        expect(
            money(nombreOuZero(p['stock']) * nombreOuZero(p['cump']),
                avecDevise: false),
            valeurs[i],
            reason: codes[i]);
        expect(nombre(p['stock']), totaux[i], reason: codes[i]);
      }
    });

    test('KPI du référentiel produits', () {
      final e = s['produits'];
      expect(kpi(e, 'Références'), nombre(produits.length));
      expect(kpi(e, 'Valeur du stock'), money(valeurStock(produits)));
      expect(
          kpi(e, 'Sous le seuil'),
          nombre(produits
              .where((p) => sousSeuilHorsRupture(p['stock'], p['seuilAlerte']))
              .length));
      expect(kpi(e, 'En rupture'),
          nombre(produits.where((p) => nombreOuZero(p['stock']) == 0).length));
    });

    test(
        'bornes : stock = seuil est critique, seuil + 1 est normal, zéro est rupture',
        () {
      expect(etatStock(5, 5), 'critique');
      expect(etatStock(6, 5), 'normal');
      expect(etatStock(0, 5), 'rupture');
      expect(etatStock(0, 0), 'rupture');
      expect(etatStock(10, 0), 'normal');
    });

    test('un seuil NON FIXÉ n\'est pas un seuil de zéro : signalé à part', () {
      expect(seuilFixe(null), isFalse);
      expect(seuilFixe(''), isFalse);
      expect(seuilFixe(0), isTrue);
      expect(seuilFixe('12'), isTrue);
      // la maquette lit `stock <= null` comme `stock <= 0` : mêmes résultats pour une rupture, mais l'article est nommé
      expect(etatStock(3, null), 'normal');
      expect(etatStock(0, null), 'rupture');
      expect(sousSeuil(0, null), isTrue);
      expect(sousSeuil(3, null), isFalse);
      expect(sansSeuilFixe(produits).map((p) => p['code']).toSet(),
          {'GNS', 'SER5M'});
    });

    test(
        '« à commander » : max(2 × seuil − stock, 0), NON CALCULABLE sans seuil (écart E18)',
        () {
      final t = carte(s['alertes'])['parOnglet'] as Map;
      for (final onglet in ['Ruptures', 'Sous le seuil']) {
        final table = t[onglet];
        final codes = colonne(table, 'CODE');
        final cmd = colonne(table, 'À COMMANDER');
        for (var i = 0; i < codes.length; i++) {
          final p = produits.firstWhere((x) => x['code'] == codes[i]);
          final calcule = aCommander(p['stock'], p['seuilAlerte']);
          if (seuilFixe(p['seuilAlerte'])) {
            expect(nombre(calcule), cmd[i], reason: codes[i]);
          } else {
            // la maquette affiche « 0 » : le domaine dit « non calculable », l'écran affiche un tiret
            expect(calcule, isNull, reason: codes[i]);
            expect(cmd[i], '0');
          }
        }
      }
    });
  });

  group('tableau de bord', () {
    final d = () => carte(s['dashboard']);

    test('les huit KPI', () {
      expect(kpi(d(), 'Valeur totale du stock'), money(valeurStock(produits)));
      expect(kpi(d(), 'Références gérées'), nombre(produits.length));
      expect(
          kpi(d(), 'Produits critiques'),
          nombre(produits
              .where((p) => sousSeuil(p['stock'], p['seuilAlerte']))
              .length));
      expect(
          kpi(d(), 'Produits périmés'),
          nombre(lots
              .where((l) =>
                  statutLot(joursAvantPeremption(auj, l['datePeremption'])) ==
                  'perime')
              .length));
      expect(kpi(d(), 'Valeur stock gros'),
          money(valeurStock(produits, 'stockGros')));
      expect(kpi(d(), 'Valeur stock détail'),
          money(valeurStock(produits, 'stockDetail')));
      expect(kpi(d(), 'Mouvements du mois'),
          nombre(mouvementsDuMois(mouvements, auj)));
      expect(
          kpi(d(), 'Péremption sous 90 j'),
          nombre(lots
              .where((l) =>
                  statutLot(joursAvantPeremption(auj, l['datePeremption'])) ==
                  'alerte')
              .length));
    });

    test('les deux bandeaux d\'alerte', () {
      final nb =
          produits.where((p) => sousSeuil(p['stock'], p['seuilAlerte'])).length;
      final pe = lots
          .where((l) =>
              statutLot(joursAvantPeremption(auj, l['datePeremption'])) ==
              'perime')
          .length;
      expect((d()['notes']! as List), [
        '$nb produit(s) sous le seuil d’alerte — établir un bon de commande (validation DA requise, RG-04).',
        '$pe lot(s) périmé(s) — retour aux fournisseurs habilités (CAME, SoBAPS) et valorisation de la perte.',
      ]);
    });

    test('valeur du stock par catégorie : ordre de première apparition', () {
      final g = grouperPar(produits, 'categorie');
      final graphes = liste(d()['graphiques']);
      final args = graphes[0]['args']! as List;
      expect([for (final k in g.keys) libelleCategorie(k)], args[0]);
      final data = ((args[1] as List).first as Map)['data'] as List;
      for (var i = 0; i < data.length; i++) {
        expect(valeurStock(g.values.elementAt(i)),
            closeTo((data[i] as num).toDouble(), 1e-9));
      }
    });

    test('répartition gros / détail et état des péremptions', () {
      final graphes = liste(d()['graphiques']);
      final gd = (graphes[1]['args']! as List)[1] as List;
      expect(valeurStock(produits, 'stockGros'),
          closeTo((gd[0] as num).toDouble(), 1e-9));
      expect(valeurStock(produits, 'stockDetail'),
          closeTo((gd[1] as num).toDouble(), 1e-9));
      final pe = (graphes[3]['args']! as List)[1] as List;
      final st = [
        for (final l in lots)
          statutLot(joursAvantPeremption(auj, l['datePeremption']))
      ];
      expect([
        st.where((x) => x == 'perime').length,
        st.where((x) => x == 'alerte').length,
        st.length -
            st.where((x) => x == 'perime').length -
            st.where((x) => x == 'alerte').length
      ], pe);
    });

    test(
        'produits à réapprovisionner en priorité : du plus bas stock au plus haut, ex æquo dans l\'ordre de la collection',
        () {
      final table = (d()['tableaux']! as List).first;
      final attendus = colonne(table, 'CODE');
      expect(
          [for (final p in aReapprovisionner(produits)) p['code']], attendus);
    });

    test('dix lignes au plus', () {
      final beaucoup = [
        for (var i = 0; i < 15; i++)
          {'code': 'X$i', 'stock': 0, 'seuilAlerte': 5}
      ];
      expect(aReapprovisionner(beaucoup).length, 10);
    });
  });

  group('stock gros et stock détail', () {
    for (final (cle, champ, type) in [
      ('stockGros', 'stockGros', 'gros'),
      ('stockDetail', 'stockDetail', 'detail')
    ]) {
      group(cle, () {
        final e = () => carte(s[cle]);
        List<Map<String, Object?>> rows() => [
              for (final p in produits)
                if (nombreOuZero(p[champ]) > 0 || nombreOuZero(p['stock']) == 0)
                  p
            ];

        test('KPI', () {
          final r = rows();
          expect(kpi(e(), 'Références présentes'),
              nombre(r.where((p) => nombreOuZero(p[champ]) > 0).length));
          expect(kpi(e(), 'Quantité totale'), nombre(sommeChamp(r, champ)));
          expect(kpi(e(), 'Valeur (CUMP)'), money(valeurStock(r, champ)));
          // la quantité de CE stock est comparée au seuil (l'état, lui, regarde le total : la maquette ne les confond pas)
          expect(
              kpi(e(), 'Sous le seuil'),
              nombre(r
                  .where((p) => sousSeuil(p[champ], p['seuilAlerte']))
                  .length));
        });

        test('lignes : valeur au CUMP et état', () {
          final table = (e()['tableaux']! as List).first;
          final codes = colonne(table, 'CODE');
          expect(codes.toSet(), {for (final p in rows()) p['code']});
          final val = colonne(table, 'VALEUR');
          final et = colonne(table, 'ÉTAT');
          for (var i = 0; i < codes.length; i++) {
            final p = produits.firstWhere((x) => x['code'] == codes[i]);
            expect(
                money(nombreOuZero(p[champ]) * nombreOuZero(p['cump']),
                    avecDevise: false),
                val[i]);
            expect(etats[etatStock(p['stock'], p['seuilAlerte'])], et[i]);
          }
        });

        test(
            'mouvements de la période : défaut = 30 jours jusqu\'à aujourd\'hui, bornes incluses',
            () {
          final def = (e()['periodeDefaut']! as List).cast<String>();
          expect(def, [iso(ajouterJoursStock(auj, -30)), iso(auj)]);
          final m = mouvementsDuStock(mouvements, type, def[0], def[1]);
          final att = carte(e()['mouvementsDefaut']);
          expect([for (final x in m) x['justificatif']],
              colonne(att, 'JUSTIFICATIF (RG-03)'));
          expect([for (final x in m) '${x['quantite']}'],
              colonne(att, 'QUANTITÉ'));
        });

        test(
            'mouvements d\'une plage choisie : un mouvement sans type de stock figure dans les deux',
            () {
          final pl = carte(e()['mouvementsPlage']);
          final m = mouvementsDuStock(
              mouvements, type, '${pl['debut']}', '${pl['fin']}');
          expect([for (final x in m) x['justificatif']],
              colonne(pl['table'], 'JUSTIFICATIF (RG-03)'));
        });
      });
    }
  });

  group('lots et péremptions (FEFO)', () {
    test('échéance : jours calendaires, textes du registre', () {
      final table = (carte(s['lots'])['tableaux']! as List).first;
      final num = colonne(table, 'N° LOT');
      final ech = colonne(table, 'ÉCHÉANCE');
      final etat = colonne(table, 'ÉTAT FEFO');
      for (var i = 0; i < num.length; i++) {
        final l = lots.firstWhere((x) => x['numeroLot'] == num[i]);
        final j = joursAvantPeremption(auj, l['datePeremption']);
        expect(texteEcheance(j), ech[i], reason: num[i]);
        expect(
            {
              'perime': 'Périmé',
              'alerte': 'Péremption proche',
              'actif': 'Normal'
            }[statutLot(j)],
            etat[i],
            reason: num[i]);
      }
    });

    test(
        'bornes du préavis : 0 jour = alerte, 90 = alerte, 91 = actif, -1 = périmé',
        () {
      expect(statutLot(-1), 'perime');
      expect(statutLot(0), 'alerte');
      expect(statutLot(90), 'alerte');
      expect(statutLot(91), 'actif');
      expect(teinteEcheance(30), 'danger');
      expect(teinteEcheance(31), 'attention');
      expect(teinteEcheance(90), 'attention');
      expect(teinteEcheance(91), 'neutre');
      expect(teinteEcheance(-5), 'danger');
    });

    test(
        'jours calendaires : l\'heure de la journée ne change rien (écart E17)',
        () {
      expect(
          joursAvantPeremption(DateTime(2026, 8, 16, 23, 59), '2026-08-17'), 1);
      expect(
          joursAvantPeremption(DateTime(2026, 8, 16, 0, 0), '2026-08-16'), 0);
      expect(
          joursAvantPeremption(DateTime(2026, 8, 16, 14, 30), '2026-08-16'), 0);
      expect(joursAvantPeremption(DateTime(2026, 8, 16), '2026-08-15'), -1);
      expect(joursAvantPeremption(DateTime(2026, 8, 16), 'n\'importe quoi'),
          isNull);
      // changement d'année et année bissextile
      expect(joursAvantPeremption(DateTime(2027, 12, 31), '2028-03-01'), 61);
    });

    test('KPI du registre des lots', () {
      final e = s['lots'];
      final st = [
        for (final l in lots)
          statutLot(joursAvantPeremption(auj, l['datePeremption']))
      ];
      expect(kpi(e, 'Lots suivis'), nombre(lots.length));
      expect(kpi(e, 'Périmés'), nombre(st.where((x) => x == 'perime').length));
      expect(kpi(e, 'Péremption sous 90 j'),
          nombre(st.where((x) => x == 'alerte').length));
      expect(
          kpi(e, 'Lots valides'), nombre(st.where((x) => x == 'actif').length));
      final perimes = [
        for (final l in lots)
          if (statutLot(joursAvantPeremption(auj, l['datePeremption'])) ==
              'perime')
            l
      ];
      final indice = [
        for (final k in liste(carte(e)['kpis']))
          if (k['libelle'] == 'Périmés') k['indice']
      ].single;
      expect(indice,
          '${nombre(sommeChamp(perimes, 'quantiteRestante'))} unités à retourner');
    });

    test(
        'ordre de sortie FEFO : date de péremption croissante, quantité non nulle, ex æquo dans l\'ordre de la collection',
        () {
      final fefo = carte(carte(s['lots'])['fefo']);
      final att = colonne(fefo, 'N° LOT');
      expect([for (final l in ordreFefo(lots)) l['numeroLot']], att);
      expect(
          colonne(fefo, 'RANG'), [for (var i = 1; i <= att.length; i++) '$i']);
    });

    test(
        'valeur perdue d\'un lot : quantité × CUMP du produit, 0 si le produit manque',
        () {
      final lot = lots.firstWhere(
          (l) => l['numeroLot'] == 'LOT-A01'); // 4 PARACETAMOL à 250
      expect(valeurPerdue(lot, produits), 1000);
      expect(
          valeurPerdue(
              {'produitId': 'INCONNU', 'quantiteRestante': 3}, produits),
          0);
    });
  });

  group('alertes', () {
    test('KPI et comptes des onglets', () {
      final e = carte(s['alertes']);
      final st = [
        for (final l in lots)
          statutLot(joursAvantPeremption(auj, l['datePeremption']))
      ];
      final ruptures =
          produits.where((p) => nombreOuZero(p['stock']) == 0).toList();
      final critiques = produits
          .where((p) => sousSeuilHorsRupture(p['stock'], p['seuilAlerte']))
          .toList();
      expect(kpi(e, 'Ruptures de stock'), nombre(ruptures.length));
      expect(kpi(e, 'Sous le seuil d’alerte'), nombre(critiques.length));
      expect(kpi(e, 'Lots périmés'),
          nombre(st.where((x) => x == 'perime').length));
      expect(kpi(e, 'Péremption sous 90 j'),
          nombre(st.where((x) => x == 'alerte').length));
      final p = carte(e['parOnglet']);
      expect(colonne(p['Ruptures'], 'CODE').toSet(),
          {for (final x in ruptures) x['code']});
      expect(colonne(p['Sous le seuil'], 'CODE').toSet(),
          {for (final x in critiques) x['code']});
    });

    test(
        'onglet Péremptions : périmés et proches, par date croissante, textes d\'échéance',
        () {
      final t = carte(carte(s['alertes'])['parOnglet'])['Péremptions'];
      final ech = colonne(t, 'ÉCHÉANCE');
      final num = colonne(t, 'N° LOT');
      final concernes = trierStable([
        for (final l in lots)
          if (statutLot(joursAvantPeremption(auj, l['datePeremption'])) !=
              'actif')
            l
      ], (l) => l['datePeremption']);
      expect([for (final l in concernes) l['numeroLot']], num);
      expect([
        for (final l in concernes)
          texteEcheanceAlerte(joursAvantPeremption(auj, l['datePeremption']))
      ], ech);
    });

    test('texte de l\'état d\'un lot dans la fiche produit', () {
      final d = carte(carte(s['produits'])['detail']);
      final lotsFiche = carte(carte(d['PAR5'])['Lots (FEFO)']);
      final t = (lotsFiche['tableaux']! as List).first;
      final num = colonne(t, 'N° LOT');
      final etat = colonne(t, 'ÉTAT');
      for (var i = 0; i < num.length; i++) {
        final l = lots.firstWhere((x) => x['numeroLot'] == num[i]);
        expect(
            texteEtatLotFiche(joursAvantPeremption(auj, l['datePeremption'])),
            etat[i]);
      }
    });
  });

  group('création : transformation et refus à l\'enregistrement', () {
    for (final c in liste(s['creationProduits'])) {
      test('produit — ${c['nom']}', () {
        final entree = carte(c['entree']);
        final sortie = carte(c['sortie']);
        final refus = refuserProduit(entree);
        final erreurs = (sortie['erreurs']! as List);
        final toasts = (sortie['toasts']! as List).cast<String>();
        if (sortie['creee'] == null) {
          // soit un champ obligatoire manque (contrôle du formulaire, côté écran), soit RG-03
          if (erreurs.isEmpty) {
            expect(refus, 'RG-03 — le stock ne peut pas devenir négatif.');
            expect(toasts, contains(refus));
          } else {
            expect(refus, isNull);
          }
          return;
        }
        expect(refus, isNull);
        final t = transformerProduit(entree);
        final att = carte(sortie['creee']);
        for (final k in [
          'prixAchat',
          'prixVente',
          'cump',
          'stockGros',
          'stockDetail',
          'stock',
          'seuilAlerte',
          'categorie'
        ]) {
          expect(t[k], att[k], reason: k);
        }
      });
    }

    for (final c in liste(s['creationLots'])) {
      test('lot — ${c['nom']}', () {
        final sortie = carte(c['sortie']);
        if (sortie['creee'] == null)
          return; // champ obligatoire : contrôle du formulaire
        final t = transformerLot(carte(c['entree']), auj, produits);
        final att = carte(sortie['creee']);
        for (final k in [
          'statut',
          'produit',
          'datePeremption',
          'quantiteRestante',
          'numeroLot'
        ]) {
          expect(t[k], att[k], reason: k);
        }
      });
    }
  });

  group('magasin vide : états vides', () {
    test('KPI à zéro, aucun bandeau', () {
      final d = carte(carte(s['vide'])['dashboard']);
      expect((d['notes']! as List), isEmpty);
      expect(kpi(d, 'Valeur totale du stock'), money(valeurStock([])));
      expect(aReapprovisionner(<Map<String, Object?>>[]), isEmpty);
      expect(ordreFefo(<Map<String, Object?>>[]), isEmpty);
    });
  });

  group('tri stable', () {
    test('les ex æquo gardent l\'ordre de la collection', () {
      final r = trierStable([
        for (var i = 0; i < 200; i++) {'i': i, 'k': i % 3}
      ], (x) => x['k']);
      for (var i = 1; i < r.length; i++) {
        if (r[i]['k'] == r[i - 1]['k']) {
          expect(r[i]['i']! as int, greaterThan(r[i - 1]['i']! as int));
        }
      }
    });
  });
}

DateTime ajouterJoursStock(DateTime d, int n) =>
    DateTime(d.year, d.month, d.day + n);
