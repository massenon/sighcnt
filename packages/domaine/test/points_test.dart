// Rejoue les vecteurs des points du gestionnaire de stock (m6-point-ventes, m6-point-stock) engendrés par la maquette
// (prototype_html/build/vecteurs-points.js) : les écrans réels PILOTÉS dans Chrome, lus à la sortie.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/stock/points.dart' as pts show etatStock, trierStable;
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

const jeu = '../../apps/poste/assets/donnees/jeu';

List<M> charger(String nom) => (jsonDecode(File('$jeu/$nom.json').readAsStringSync()) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

List<M> liste(Object? v) =>
    ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();

/// `textContent.replace(/\s+/g, ' ').trim()` : la maquette lit les écrans avec cette normalisation (U+00A0 et U+202F y deviennent « espace »).
String norm(Object? s) => '${s ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();

String sansBalises(String s) => norm(s.replaceAll(RegExp(r'<[^>]+>'), ''));

void memes(Object? obtenu, Object? attendu, String chemin) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in {...attendu.keys, ...o.keys}) {
      memes(o[k], attendu[k], '$chemin.$k');
    }
  } else if (attendu is List) {
    expect(obtenu, isA<List>(), reason: chemin);
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]');
    }
  } else if (attendu is num) {
    expect(obtenu, isA<num>(), reason: chemin);
    expect((obtenu as num).toDouble(), attendu.toDouble(), reason: chemin);
  } else if (attendu is String) {
    expect(norm(obtenu), norm(attendu), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}

DateTime jour(Object? s) => jourDe(s)!;

Bornes bornesDe(M saisie) => saisie['libre'] == true
    ? bornesLibres(jour(saisie['du']), jour(saisie['au']))
    : bornes('${saisie['periode'] ?? 'mois'}', jour(saisie['date'] ?? '2026-08-16'));

List<String> listeDe(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

/// Ce que `P.etat` a reçu, ramené à la forme du vecteur : la liste ordonnée des blocs de contenu.
List<Object?> contenuDe(EtatPoint e) => [
      for (final b in e.blocs)
        switch (b) {
          BlocEtatTexte() => {'texte': b.texte},
          BlocEtatTableau() => {
              'table': {
                'entetes': [for (final c in b.tableau.colonnes) c.libelle],
                'lignes': b.tableau.cellules,
                'pied': b.tableau.pied,
              }
            },
        }
    ];

void comparerEtat(EtatPoint e, M vecteur, String chemin) {
  expect(e.titre, vecteur['titre'], reason: '$chemin titre');
  expect(norm(e.sousTitre), norm(vecteur['sousTitre']), reason: '$chemin sous-titre');
  memes([for (final (a, b) in e.cartouche) [a, b]], vecteur['cartouche'], '$chemin cartouche');
  memes(contenuDe(e), vecteur['contenu'], '$chemin contenu');
}

void main() {
  final f = File('test/vecteurs/points.json');
  if (!f.existsSync()) {
    fail('vecteurs absents : lancer `node prototype_html/build/vecteurs-points.js`');
  }
  final v = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
  final factures = charger('factures'), actes = charger('actes');
  final produits = charger('produits'), mouvements = charger('mouvements');
  final secteurs = secteursDesActes(actes);
  final emp = (v['empreinte'] as Map).cast<String, Object?>();

  double somme(Iterable<M> l, String k) =>
      l.fold(0.0, (a, x) => a + nombreOuZero(x[k]));

  test('les registres rejoués sont ceux que la maquette a lus (empreinte)', () {
    final lignes = [for (final x in factures) ...liste(x['lignes'])];
    expect(factures.length, emp['factures']);
    expect(lignes.length, emp['lignes']);
    expect(somme(lignes, 'montant'), (emp['sommeNet'] as num).toDouble());
    expect(produits.length, emp['produits']);
    expect(somme(produits, 'stock'), (emp['sommeStock'] as num).toDouble());
    expect(mouvements.length, emp['mouvements']);
    expect(somme(mouvements, 'quantite'), (emp['sommeQteMouvements'] as num).toDouble());
    expect(actes.length, emp['actes']);
  });

  test('les référentiels de la maquette (six secteurs, catégories, sept familles)', () {
    memes([for (final g in groupesPrestation) {'id': g.id, 'label': g.label, 'categories': g.categories, if (g.secteurs.isNotEmpty) 'secteurs': g.secteurs}],
        [for (final g in liste(v['groupes'])) {'id': g['id'], 'label': g['label'], 'categories': g['categories'], if (g['secteurs'] != null) 'secteurs': g['secteurs']}], 'groupes');
    memes([for (final c in categoriesLigne) {'id': c.id, 'label': c.label}], v['categories'], 'catégories');
    memes([for (final x in famillesArticles) {'id': x.id, 'label': x.label, 'groupe': x.groupe}], v['familles'], 'familles');
  });

  test('l\'apostrophe typographique est de la ponctuation : « N’TCHA » précède « NKOUÉ » (écart E45)', () {
    expect(comparerNaturel('N’TCHA Alassane', 'NKOUÉ Jean'), lessThan(0));
    expect(comparerNaturel('N\'TCHA', 'NKOUÉ'), lessThan(0));
    expect(pts.trierStable(['NKOUÉ Jean', 'N’TCHA Alassane', 'NAMBONI'], (x) => x), ['N’TCHA Alassane', 'NAMBONI', 'NKOUÉ Jean'],
        reason: 'la ponctuation passe avant les lettres (ICU, non-ignorable)');
  });

  test('un état dit la période d\'un flux : la périodicité ne vaut que pour lui', () {
    expect(vuesStock.where((x) => !x.flux).map((x) => x.id), ['pharmacie_restant', 'magasin_restant']);
    expect(vuesStock.where((x) => x.flux).length, 3);
  });

  group('m6-point-ventes', () {
    final cas = liste(v['ventes']);
    test('vingt situations ont été engendrées', () => expect(cas.length, greaterThanOrEqualTo(20)));

    for (final c in cas) {
      test(c['nom'] as String, () {
        final s = (c['saisie'] as Map).cast<String, Object?>();
        final b = bornesDe(s);
        final clients = listeDe(s['clients']), groupes = listeDe(s['groupes']), articles = listeDe(s['articles']);
        final toutes = lignesVendues(factures, b, secteurParCode: secteurs);
        final lignes = filtrerVentes(toutes, clients: clients, groupes: groupes, articles: articles);
        final t = cumuler(lignes);

        expect(sansBalises(noteVentes(b, t, clients: clients.length, groupes: groupes.length, articles: articles.length)), norm(c['note']));
        memes([for (final k in indicateursVentes(t)) {'label': k.libelle, 'valeur': k.valeur, 'indice': k.indice}], c['kpis'], 'kpis');
        expect(norm(c['badgeJournal']), contains('${t.pieces}'));

        final on = (c['onglets'] as Map).cast<String, Object?>();
        List<Object?> tables(String id) => ((on[id] as Map)['tables'] as List);
        memes(journalVentes(lignes), tables('journal')[0], 'journal');
        memes(clientsVentes(lignes), tables('clients')[0], 'clients');
        memes(articlesVentes(lignes), tables('articles')[0], 'articles');
        memes(groupesVentes(lignes), tables('groupes')[0], 'groupes');
        memes(categoriesVentes(lignes), tables('groupes')[1], 'catégories');

        final gr = groupesVentes(lignes);
        final graphG = ((on['groupes'] as Map)['graphiques'] as List);
        if (gr.isEmpty) {
          expect(graphG, isEmpty);
        } else {
          memes({'labels': [for (final r in gr) r['groupe']], 'data': [for (final r in gr) r['net']]},
              {'labels': (graphG.single as Map)['labels'], 'data': (graphG.single as Map)['data']}, 'anneau des groupes');
        }

        final ev = evolutionVentes(lignes, b);
        final graphE = ((on['evolution'] as Map)['graphiques'] as List);
        if (ev.vide) {
          expect(graphE, isEmpty);
        } else {
          final g = (graphE.single as Map).cast<String, Object?>();
          expect(ev.titre, ev.parJour ? 'Ventes par jour' : 'Ventes par mois');
          memes(ev.etiquettes, g['labels'], 'évolution : étiquettes');
          memes([
            {'label': 'Net facturé', 'data': ev.net},
            {'label': 'Encaissé', 'data': ev.encaisse}
          ], g['series'], 'évolution : séries');
        }

        if (clients.isNotEmpty) {
          final blocs = blocsParPatient(lignes);
          final attendus = liste((on['patients'] as Map)['blocs']);
          expect(blocs.length, attendus.length);
          for (var i = 0; i < blocs.length; i++) {
            final p = blocs[i], a = attendus[i];
            expect(norm(p.patient), norm(a['patient']));
            expect(norm(p.sousTitre), norm(a['sous']));
            expect(norm(money(p.total.net)), norm(a['net']));
            expect(p.secteurs.length, (a['secteurs'] as List).length);
            for (var j = 0; j < p.secteurs.length; j++) {
              final sec = p.secteurs[j], sa = (a['secteurs'] as List)[j] as Map;
              expect(sec.groupe.label, sa['titre']);
              expect(norm(resumeSecteur(sec)), norm(sa['resume']));
              if (sec.lignes.isNotEmpty) {
                memes([for (final l in sec.lignes) cellulesLignePatient(l)], sa['lignes'], 'patient ${p.patient} / ${sec.groupe.label}');
              }
            }
          }
        }

        final imp = (c['impressions'] as Map).cast<String, Object?>();
        for (final mode in ['detaille', 'global', 'patient']) {
          final e = etatVentes(mode, lignes, b, clients: clients.length, groupes: groupes.length, articles: articles.length);
          comparerEtat(e, (imp[mode] as Map).cast<String, Object?>(), 'impression $mode');
        }
      });
    }

    test('l\'état détaillé est chronologique (écart E40 corrigé dans la maquette)', () {
      final b = bornes('annee', DateTime(2026, 8, 16));
      final e = etatVentes('detaille', lignesVendues(factures, b, secteurParCode: secteurs), b);
      final dates = [for (final r in ((e.blocs.first as BlocEtatTableau).tableau.cellules)) r[0]];
      final iso = [for (final d in dates) '${d.substring(6)}-${d.substring(3, 5)}-${d.substring(0, 2)}'];
      expect(iso, [...iso]..sort(), reason: 'trié sur la date ISO, pas sur « jj/mm/aaaa »');
    });

    test('les pourcentages sont sur le BRUT, une décimale, écrits comme JavaScript', () {
      const t = Cumul(1, 1, 1, 3, 1, 2, 1, 0, 2, 0);
      final p = pourcentages(t);
      expect([p.assureur, p.remise, p.personnel], [33.3, 33.3, 0]);
      expect(texteNombreJs(80.0), '80');
      expect(texteNombreJs(8.8), '8.8');
      expect(pourcentages(const Cumul(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)).assureur, 0, reason: 'brut nul : zéro, jamais NaN');
    });
  });

  group('m6-point-stock', () {
    final cas = liste(v['stock']);
    test('vingt-quatre situations ont été engendrées', () => expect(cas.length, greaterThanOrEqualTo(24)));

    for (final c in cas) {
      test(c['nom'] as String, () {
        final s = (c['saisie'] as Map).cast<String, Object?>();
        final vue = vuesStock.firstWhere((x) => x.id == s['vue']);
        final methode = MethodeValorisation.depuis(s['methode']);
        final b = bornes('${s['periode'] ?? 'mois'}', jour(s['date'] ?? '2026-08-16'));
        final familles = listeDe(s['familles']);
        // Le vecteur consigne les CUMP corrigés pour que la bascule de méthode se MESURE.
        final corr = (s['corrections'] as Map?)?.cast<String, Object?>() ?? const {};
        final prods = [
          for (final p in produits)
            corr.containsKey(p['id']) ? {...p, ...(corr[p['id']] as Map).cast<String, Object?>()} : p
        ];

        expect(c['periodeDesactivee'], !vue.flux);
        // L'écran totalise, cumule et dessine sur les lignes TELLES QUE LE MOUVEMENT LES A DONNÉES ; seul le tableau (et l'état) les classe.
        final brutes = lignesVueStock(vue, prods, mouvements, b, methode, familles: familles);
        final lignes = trierParMontant(brutes);
        final tot = totauxStock(brutes);

        expect(sansBalises(noteStock(vue, b)), norm(c['note']));
        memes([for (final k in indicateursStock(vue, tot)) {'label': k.libelle, 'valeur': k.valeur, 'indice': k.indice}], c['kpis'], 'kpis');

        final tables = c['tables'] as List;
        memes([for (final l in lignes) l.toMap()], tables[0], 'lignes');
        final fam = cumulParFamille(brutes);
        if (fam.length > 1) {
          memes(cumulParFamilleTrie(brutes), tables[1], 'cumul par famille');
          final g = ((c['graphiques'] as List).single as Map);
          memes({'labels': [for (final r in fam) r['famille']], 'data': [for (final r in fam) r['montant']]},
              {'labels': g['labels'], 'data': ((g['series'] as List).single as Map)['data']}, 'répartition');
        } else {
          expect(tables.length, 1, reason: 'le cumul par famille est masqué à une seule famille');
          expect(c['graphiques'], isEmpty);
        }

        comparerEtat(pts.etatStock(vue, lignes, b, jour(s['date'] ?? '2026-08-16'), methode, familles: familles.length),
            (c['impression'] as Map).cast<String, Object?>(), 'impression');
      });
    }

    test('la valeur unitaire suit la méthode : CUMP ou prix de vente, arrondie, repli sur le prix d\'achat', () {
      final p = {'prixVente': 1000, 'cump': 499.6, 'prixAchat': 800};
      expect(valeurUnitaire(p, MethodeValorisation.prixVente), 1000);
      expect(valeurUnitaire(p, MethodeValorisation.cump), 500);
      expect(valeurUnitaire({'prixAchat': 800}, MethodeValorisation.cump), 800, reason: 'cump absent : prix d\'achat');
      expect(valeurUnitaire({'prixVente': 0, 'prixAchat': 650}, MethodeValorisation.prixVente), 650);
      expect(valeurUnitaire(const {}, MethodeValorisation.prixVente), 0);
    });
  });
}
