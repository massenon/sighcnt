// Rejoue les vecteurs des écrans de mouvements de stock (M6) engendrés par la maquette
// (prototype_html/build/vecteurs-stock-mouvements.js) : transferts multi-lignes, mouvements saisis, feuille d'inventaire, pertes.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> liste(Object? v) =>
    ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();

F carte(Object? v) => (v! as Map).cast<String, Object?>();

void memes(Object? obtenu, Object? attendu, String chemin, {Set<String> ignorer = const {}}) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      if (ignorer.contains(k) || '$k'.startsWith('_')) continue;
      memes(o[k], attendu[k], '$chemin.$k', ignorer: ignorer);
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]', ignorer: ignorer);
    }
  } else if (attendu is num) {
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

const _ignorees = {'statut', 'id'};

/// Applique un correctif de stock à la copie du produit (ce que fait `col.update`).
void appliquer(List<F> produits, String id, F patch) {
  produits.firstWhere((p) => p['id'] == id).addAll(patch);
}

List<F> etat(List<F> produits, Iterable<String> ids) => [
      for (final id in ids)
        () {
          final p = produits.firstWhere((x) => x['id'] == id);
          return <String, Object?>{'id': id, 'stockGros': p['stockGros'], 'stockDetail': p['stockDetail'], 'stock': p['stock']};
        }()
    ];

void main() {
  final f = File('test/vecteurs/stock_mouvements.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-stock-mouvements.js`');
  }
  final j = carte(jsonDecode(f.readAsStringSync()));

  test('les quatre écrans ont été pilotés (39 situations)', () {
    expect(liste(j['transferts']).length, greaterThanOrEqualTo(15));
    expect(liste(j['mouvements']).length, greaterThanOrEqualTo(10));
    expect(liste(j['inventaires']).length, greaterThanOrEqualTo(6));
    expect(liste(j['pertes']).length, greaterThanOrEqualTo(6));
  });

  group('transferts gros → détail (multi-lignes)', () {
    for (final c in liste(j['transferts'])) {
      final e = carte(c['entree']);
      final s = carte(c['sortie']);
      test('${e['nom']}', () {
        final produits = liste(e['produits']).map((p) => {...p}).toList();
        final lots = liste(e['lots']);
        final bons = liste(e['bons']);
        var lignes = <F>[];
        final refus = <String>[];
        F? retiree;
        var rangRetire = 0;
        final recaps = <String>[];
        for (final g in liste(e['gestes'])) {
          try {
            if (g['ajouter'] != null) {
              final a = carte(g['ajouter']);
              lignes = ajouterLigneTransfert(
                  lignes: lignes, produitId: a['produitId'] as String?, quantite: a['quantite'], produits: produits, lots: lots);
            } else if (g['modifier'] != null) {
              final m = carte(g['modifier']);
              lignes = modifierQuantiteLigne(lignes: lignes, rang: m['rang'] as int, quantite: m['quantite'], produits: produits);
            } else if (g['retirer'] != null) {
              rangRetire = g['retirer'] as int;
              retiree = lignes[rangRetire];
              lignes = [...lignes]..removeAt(rangRetire);
            } else if (g['retablir'] != null) {
              lignes = [...lignes]..insert(rangRetire, retiree!);
            } else if (g['stockBouge'] != null) {
              final b = carte(g['stockBouge']);
              appliquer(produits, b['produitId'] as String, carte(b['patch']));
            }
          } on RefusStock catch (x) {
            refus.add(x.motif);
          }
          if (g['ajouter'] != null || g['modifier'] != null || g['retirer'] != null || g['retablir'] != null) {
            recaps.add('${nombre(lignes.length)} ligne(s) — valeur totale ${money(totalValeur(lignes))}');
          }
        }
        // Le récapitulatif affiché sous la table suit les lignes (la maquette ne le recalcule qu'à chaque geste sur la liste).
        final attenduRecaps = [for (final r in (s['recapitulatifs'] as List)) if (r != null) '$r'];
        if (attenduRecaps.isNotEmpty) {
          expect(recaps.length, lessThanOrEqualTo(attenduRecaps.length));
        }

        final en = carte(e['entete']);
        TransfertEmis? emis;
        try {
          controlerBonAvantEcriture(lignes, produits);
          emis = emettreTransfert(
              date: '${en['date']}',
              demandeur: '${en['demandeur']}',
              motif: '${en['motif'] ?? ''}',
              lignes: lignes,
              produits: produits,
              bons: bons,
              utilisateur: '${e['utilisateur']}');
        } on RefusStock catch (x) {
          refus.add(x.motif);
        }

        // Les messages d'ERREUR (refus nommés), dans l'ordre où l'agent les a lus.
        final attendusRefus = [
          for (final m in liste(s['messages']))
            if (m['type'] == 'error') '${m['message']}'
        ];
        expect(refus, attendusRefus);

        final bonsAttendus = liste(s['bons']);
        if (emis == null) {
          expect(bonsAttendus, isEmpty);
          expect(liste(s['mouvements']), isEmpty);
          memes(etat(produits, produits.map((p) => '${p['id']}')), s['produits'], 'produits');
          return;
        }
        memes(emis.bon, bonsAttendus.single, 'bon', ignorer: _ignorees);
        // L'ordre de la collection : le plus récent en tête.
        memes(emis.mouvements.reversed.toList(), s['mouvements'], 'mouvements', ignorer: _ignorees);
        for (final p in emis.produits) {
          appliquer(produits, p.id, p.patch);
        }
        memes(etat(produits, produits.map((p) => '${p['id']}')), s['produits'], 'produits');
        // Symétrie (RG-03) : par ligne, la sortie du magasin et l'entrée à la pharmacie portent la même quantité.
        for (var i = 0; i < emis.mouvements.length; i += 2) {
          expect(emis.mouvements[i]['stockType'], 'gros');
          expect(emis.mouvements[i + 1]['stockType'], 'detail');
          expect(emis.mouvements[i]['quantite'], emis.mouvements[i + 1]['quantite']);
          expect(emis.mouvements[i]['justificatif'], 'Bon de transfert ${emis.reference}');
        }
        if (s['apresAnnulation'] != null) {
          // L'annulation restitue TOUTES les lignes.
          for (final a in emis.avant) {
            appliquer(produits, a.id, a.patch);
          }
          memes(etat(produits, produits.map((p) => '${p['id']}')), carte(s['apresAnnulation'])['produits'], 'après annulation');
        }
      });
    }
  });

  group('mouvements saisis (RG-03 à l\'enregistrement)', () {
    for (final c in liste(j['mouvements'])) {
      final e = carte(c['entree']);
      final s = carte(c['sortie']);
      final saisie = carte(e['saisie']);
      final existant = e['edition'] == null ? null : carte(e['edition']);
      test('${e['nom']}', () {
        if (saisie['justificatif'] == '') {
          // Champ obligatoire : l'erreur est celle du FORMULAIRE (mesurée au test d'écran), le moteur n'est pas atteint.
          expect(liste(s['mouvements']), isEmpty);
          expect(liste(s['messages']).single['message'], 'Le formulaire comporte des erreurs.');
          return;
        }
        final produit = carte(e['produit']);
        final base = existant ??
            {'produitId': produit['id'], 'type': 'entree', 'stockType': 'gros', 'date': e['jour']};
        final valeurs = <String, Object?>{
          for (final k in ['produitId', 'type', 'quantite', 'date', 'stockType', 'justificatif']) k: base[k],
          ...saisie,
        };
        final erreur = controleMouvement(produit: produit, type: valeurs['type'], stockType: valeurs['stockType'], quantite: valeurs['quantite']);
        if (erreur != null) {
          expect(liste(s['messages']).single['message'], erreur);
          expect(liste(s['mouvements']), isEmpty);
          return;
        }
        final rang = e['rangMax'] as int;
        final prepare = preparerMouvement(valeurs,
            existant: existant,
            produits: [produit],
            mouvements: [rangMax(rang)],
            utilisateur: '${e['utilisateur']}');
        if (existant == null) {
          memes(prepare, carte(liste(s['mouvements']).single), 'mouvement', ignorer: _ignorees);
        } else {
          // Édition : le NUMÉRO est conservé (E19), l'opérateur devient l'agent connecté.
          memes({...existant, ...prepare}, s['modifie'], 'mouvement édité', ignorer: _ignorees);
          expect(prepare['reference'], existant['reference']);
        }
        // Un mouvement saisi n'écrit RIEN dans le stock du produit (le registre peut diverger : écart E20).
        memes(carte(s['produit']), {'id': produit['id'], 'stockGros': produit['stockGros'], 'stockDetail': produit['stockDetail'], 'stock': produit['stock']}, 'produit');
      });
    }
  });

  group('feuille d\'inventaire (un magasin nommé)', () {
    for (final c in liste(j['inventaires'])) {
      final e = carte(c['entree']);
      final s = carte(c['sortie']);
      test('${e['nom']}', () {
        final en = carte(e['entete']);
        final produits = liste(e['produits']).map((p) => {...p}).toList();
        final cible = ciblesInventaire(produits, '${en['perimetre']}');
        expect(cible.length, s['lignesAffichees']);
        final comptes = carte(e['comptes']);
        final physiques = <String, Object?>{
          for (final p in cible)
            if (comptes.containsKey(p['code'])) '${p['id']}': comptes[p['code']]
        };
        // Écart et valeur affichés en direct, tels que la feuille les écrit.
        for (final d in liste(s['enDirect'])) {
          final p = cible.firstWhere((x) => x['code'] == d['code']);
          final l = ligneComptage(p, '${en['magasin']}', comptes[d['code']]);
          final ecart = l['ecart']! as num;
          expect('${ecart > 0 ? '+' : ''}${nombre(ecart)}', d['ecart']);
          expect(money(l['valeur'], avecDevise: false), d['valeur']);
        }
        final v = validerInventaire(
            entete: en,
            cible: cible,
            physiques: physiques,
            inventaires: [for (final r in (e['inventairesExistants'] as List)) {'reference': r}],
            mouvements: [rangMax(e['rangMax'] as int)]);
        memes(v.inventaire, carte(liste(s['inventaires']).single), 'inventaire', ignorer: _ignorees);
        memes(v.mouvements.reversed.toList(), s['mouvements'], 'mouvements', ignorer: _ignorees);
        for (final p in v.produits) {
          appliquer(produits, p.id, p.patch);
        }
        memes(etat(produits, [for (final p in liste(e['produits'])) '${p['id']}']), s['produits'], 'produits');
        // Le magasin NON compté n'est jamais touché.
        final autre = en['magasin'] == 'detail' ? 'stockGros' : 'stockDetail';
        for (final p in liste(e['produits'])) {
          expect(produits.firstWhere((x) => x['id'] == p['id'])[autre], p[autre], reason: 'le magasin non compté reste intact');
        }
        // Jamais sous zéro.
        for (final p in produits) {
          expect(p['stock']! as num, greaterThanOrEqualTo(0));
        }
        if (s['apresAnnulation'] != null) {
          for (final a in v.avant) {
            appliquer(produits, a.id, a.patch);
          }
          memes(etat(produits, [for (final p in liste(e['produits'])) '${p['id']}']), carte(s['apresAnnulation'])['produits'], 'après annulation');
        }
      });
    }
  });

  group('pertes, casses & rebuts', () {
    for (final c in liste(j['pertes'])) {
      final e = carte(c['entree']);
      final s = carte(c['sortie']);
      final saisie = carte(e['saisie']);
      test('${e['nom']}', () {
        if (saisie['justificatif'] == '') {
          expect(liste(s['mouvements']), isEmpty); // erreur de FORMULAIRE : le moteur n'est pas atteint
          return;
        }
        final produit = carte(e['produit']);
        try {
          final r = declarerPerte(
              produit: produit,
              type: '${saisie['type']}',
              quantite: saisie['quantite'],
              date: '${saisie['date']}',
              justificatif: '${saisie['justificatif']}',
              constatePar: '${saisie['constatePar']}',
              observation: saisie['observation'] as String?,
              utilisateur: '${e['utilisateur']}',
              mouvements: [rangMaxPerte(e['rangMax'] as int)]);
          expect(liste(s['messages']).single['type'], 'success');
          expect(r.detail, liste(s['messages']).single['detail']);
          memes(r.mouvement, carte(liste(s['mouvements']).single), 'mouvement', ignorer: _ignorees);
          // Le stock décroît d'autant — champ `stock` seulement (écart E20 : ni stockGros ni stockDetail).
          expect(carte(s['produit'])['stock'], r.stockApres);
          expect(carte(s['produit'])['stockGros'], produit['stockGros']);
          expect(carte(s['produit'])['stockDetail'], produit['stockDetail']);
          if (s['apresAnnulation'] != null) {
            expect(carte(carte(s['apresAnnulation'])['produit'])['stock'], r.stockAvant);
          }
        } on RefusStock catch (x) {
          final m = liste(s['messages']).single;
          expect(m['type'], 'error');
          expect(x.motif, m['message']);
          expect(x.detail, m['detail']);
          expect(liste(s['mouvements']), isEmpty);
        }
      });
    }
  });

  group('séries de références (E17)', () {
    test('la série suit le plus grand rang existant, archivés compris', () {
      expect(
          referenceSuivante('M', 6, [
            {'reference': 'M000024'},
            {'reference': 'MVT-00099'},
            {'reference': 'M000130', 'statut': 'archive'}
          ]),
          'M000131');
      expect(referenceSuivante('TR-', 5, const []), 'TR-00001');
      expect(referenceSuivante('INV-', 4, [{'reference': 'INV-0009'}]), 'INV-0010');
    });
  });

  group('lignes d\'un bon, deux générations', () {
    test('un bon antérieur au multi-lignes est ADAPTÉ à la lecture, jamais réécrit', () {
      final ancien = {'produitId': 'P1', 'produit': 'Gants', 'unite': 'Boîte', 'quantite': 4, 'cump': 250};
      final lg = lignesDeBon(ancien);
      expect(lg.length, 1);
      expect(totalQuantite(lg), 4);
      expect(totalValeur(lg), 1000);
      expect(ancien.containsKey('lignes'), isFalse);
    });
  });
}

F rangMax(int rang) => {'reference': 'M${rang.toString().padLeft(6, '0')}'};
F rangMaxPerte(int rang) => {'reference': 'MVT-${rang.toString().padLeft(5, '0')}'};
