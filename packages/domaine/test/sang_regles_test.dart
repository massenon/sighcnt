// Rejoue les vecteurs de la banque de sang, des donneurs et des statistiques de réactifs (prototype_html/build/vecteurs-sang.js) : les écrans RÉELS
// m5-reactifs-stats, m5-banque-sang et m5-donneurs, pilotés dans Chrome (horloge fixée au 16/08/2026).
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

/// La maquette normalise toute espace (y compris U+00A0 et U+202F) avant d'écrire un vecteur : on compare sans aucune espace.
String _s(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');

bool _actif(Map<String, Object?> f) => f['statut'] != 'archive';

void main() {
  final doc = lireVecteurs('sang');
  final auj = DateTime(2026, 8, 16);

  test('les huit groupes et les sections du bulletin sont ceux de la maquette', () {
    expect(sangGroupes, (doc['groupes'] as List).cast<String>());
    final secs = liste(doc['sections']);
    expect({for (final s in secs) s['id']: s['label']}, demSections);
  });

  group('statistiques des réactifs — calculées depuis stock, lots et demandes', () {
    for (final c in liste(doc['stats'])) {
      test('${c['nom']}', () {
        final st = sangStatsReactifs(
            produits: liste(c['produits']).where(_actif),
            lots: liste(c['lots']).where(_actif),
            demandes: liste(c['demandes']).where(_actif),
            examens: liste(doc['examens']));
        final k = liste(c['kpis']);
        expect(_s(nombre(st.references.length)), _s(k[0]['valeur']));
        expect(_s(money(st.valeur)), _s(k[1]['valeur']));
        expect(_s(nombre(st.sousSeuil.length)), _s(k[2]['valeur']));
        expect(
            st.sansSeuil.isEmpty
                ? null
                : '${nombre(st.sansSeuil.length)} référence(s) sans seuil fixé',
            k[2]['indice']);
        expect('${nombre(st.perimes)} / ${nombre(st.alerte)}', k[3]['valeur']);
        // le bandeau n'existe que s'il y a des références sans seuil
        expect((c['notes'] as List).isNotEmpty, st.sansSeuil.isNotEmpty);
        // le graphique : sections, du plus fréquent au moins fréquent
        final args = ((liste(c['graphiques']).single['args']) as List);
        expect([for (final s in st.parSection) s.section], (args[0] as List).cast<String>());
        expect([for (final s in st.parSection) s.demandes],
            ((args[1] as List).single as Map)['data']);
        // le tableau : tri initial par stock croissant (stable), valeur = stock × prix d'achat
        final lignes = trierPar(st.references, (p) => p['stock'] ?? 0);
        final tabs = liste(c['tableaux']);
        // sans référence, la maquette n'affiche aucun tableau mais un message d'état vide
        final attendu = tabs.isEmpty ? <List>[] : (tabs.single['lignes'] as List).cast<List>();
        expect(lignes.length, attendu.length);
        for (var i = 0; i < lignes.length; i++) {
          final p = lignes[i];
          expect(_s(p['designation']), _s(attendu[i][0]));
          expect(p['categorie'] == 'reactif' ? 'Réactif' : 'Consommable labo', attendu[i][1]);
          expect(_s(nombreOuZero(p['stock']).toInt()), _s(attendu[i][2]));
          expect(p['seuilAlerte'] == null ? 'non fixé' : '${p['seuilAlerte']}', attendu[i][3]);
          expect(_s(money(sangValeurReference(p), avecDevise: false)), _s(attendu[i][4]));
        }
      });
    }
  });

  group('banque de sang', () {
    final b = (doc['banque'] as Map).cast<String, Object?>();
    final poches = liste(b['poches']).where(_actif).toList();

    test('indicateurs et disponibilité par groupe', () {
      final k = sangKpisBanque(poches);
      final a = liste(b['kpis']);
      expect([k.enStock, k.disponibles, k.alerte, k.perimees],
          [for (final x in a) int.parse('${x['valeur']}')]);
      final grille = liste(b['grille']);
      expect(grille.length, sangGroupes.length);
      for (var i = 0; i < sangGroupes.length; i++) {
        final n = sangDisponiblesGroupe(poches, sangGroupes[i]);
        expect(grille[i]['groupe'], sangGroupes[i]);
        expect('$n', grille[i]['nombre']);
        expect(sangMotPoche(n), grille[i]['mot']);
        expect(sangTonGroupe(n), grille[i]['ton']);
      }
    });

    test('le tableau : tri par péremption, « Reste » en jours, « Périmée » sous zéro', () {
      final attendu = (liste(b['tableaux']).single['lignes'] as List).cast<List>();
      final l = trierPar(poches, (p) => p['datePeremption']);
      expect(l.length, attendu.length);
      for (var i = 0; i < l.length; i++) {
        final j = sangResteJours(auj, l[i]);
        expect(l[i]['reference'], attendu[i][0]);
        expect(j! < 0 ? 'Périmée' : '$j j', attendu[i][5]);
        expect(_s(l[i]['reserve'] == true ? 'Réservée' : '—'), _s(attendu[i][7]));
      }
    });

    test('un jeu de 17 poches : indicateurs et première page', () {
      final g = (b['grand'] as Map).cast<String, Object?>();
      final ps = liste(g['poches']);
      final k = sangKpisBanque(ps);
      expect([k.enStock, k.disponibles, k.alerte, k.perimees],
          [for (final x in liste(g['kpis'])) int.parse('${x['valeur']}')]);
      final attendu = (liste(g['tableaux']).single['lignes'] as List).cast<List>();
      final l = trierPar(ps, (p) => p['datePeremption']).take(15).toList();
      expect([for (final p in l) p['reference']], [for (final r in attendu) r[0]]);
    });

    test('le bon de demande de sang porte la disponibilité du jour', () {
      final bon = (b['bon'] as Map).cast<String, Object?>();
      expect(_s(bon['texte']), contains(_s('Disponibilité au 16/08/2026 : ${sangLigneDisponibilite(poches)}')));
    });

    test('E201 : l\'ÉTAT enregistré commande les indicateurs, pas la date corrigée', () {
      final m = (b['modification'] as Map).cast<String, Object?>();
      final apres = (m['enregistre'] as Map)['fiche'] as Map;
      expect(apres['datePeremption'], '2026-08-11');
      expect(apres['etat'], 'actif');
      final ap = (b['apresModification'] as Map).cast<String, Object?>();
      expect([for (final x in liste(ap['kpis'])) x['valeur']], [for (final x in liste(b['kpis'])) x['valeur']]);
      // la poche corrigée est périmée au calendrier (11/08 < 16/08) mais reste « disponible » pour l'état
      final f = {...(apres.cast<String, Object?>())};
      expect(sangPocheDisponible(f), isTrue);
      expect(sangResteJours(auj, f)! < 0, isTrue);
    });

    test('le volume corrigé redevient un nombre', () {
      expect(sangFichePoche({'volume': '350', 'donneur': 'x'})['volume'], 350);
    });
  });

  group('donneurs', () {
    final d = (doc['donneurs'] as Map).cast<String, Object?>();
    final dons = liste(d['donneurs']).where(_actif).toList();

    test('indicateurs', () {
      final k = sangKpisDonneurs(auj, dons);
      expect([k.donneurs, k.eligibles, k.dons, k.benevoles],
          [for (final x in liste(d['kpis'])) int.parse('${x['valeur']}')]);
    });

    test('le tableau : tri par dernier don décroissant, éligibilité par ligne', () {
      final attendu = (liste(d['tableaux']).first['lignes'] as List).cast<List>();
      final l = trierPar(dons, (x) => x['dernierDon'], descendant: true);
      expect(l.length, attendu.length);
      for (var i = 0; i < l.length; i++) {
        expect(l[i]['reference'], attendu[i][1]);
        expect(sangEligibilite(auj, l[i]).libelle, attendu[i][8], reason: '${l[i]['reference']}');
      }
    });

    test('éligibilité : bornes du délai de 90 jours', () {
      Map<String, Object?> f(int j, [bool e = true]) => {'eligible': e, 'dernierDon': iso(auj.add(Duration(days: -j)))};
      expect(sangEligibilite(auj, f(90)).libelle, 'Éligible');
      expect(sangEligibilite(auj, f(89)).libelle, 'Délai 1 j');
      expect(sangEligibilite(auj, f(0)).libelle, 'Délai 90 j');
      expect(sangEligibilite(auj, f(200, false)).libelle, 'Non éligible');
      expect(sangDonneurDisponible(auj, f(90)), isTrue);
      expect(sangDonneurDisponible(auj, f(89)), isFalse);
      expect(sangEligibilite(auj, {'eligible': true}).libelle, 'Délai inconnu');
    });

    test('création : valeurs par défaut du formulaire', () {
      final def = ((d['creation'] as Map)['defauts'] as Map).cast<String, Object?>();
      final v = sangValeursInitialesDonneur(auj);
      expect(v['nbDons'], def['nbDons']);
      expect(v['type'], def['type']);
      expect(v['dernierDon'], def['dernierDon']);
      expect(v['eligible'], def['eligible']);
    });

    test('E200 : la référence suit le rang le plus haut, archivées comprises', () {
      final cr = (d['creation'] as Map).cast<String, Object?>();
      final tous = liste(d['donneurs']);
      final saisie = {'nom': 'IMOROU Zaki', 'telephone': '97111111', 'groupe': 'AB-', 'type': 'Compensation', 'dernierDon': '2026-07-01', 'nbDons': '6', 'eligible': false};
      final f1 = sangFicheDonneur(saisie, existants: tous);
      final att1 = ((cr['cree'] as Map)['fiche'] as Map).cast<String, Object?>();
      expect(f1['reference'], att1['reference']);
      expect(f1['nbDons'], att1['nbDons']);
      final f2 = sangFicheDonneur({'nom': 'JOHNSON Mary', 'nbDons': '1'}, existants: [...tous, f1]);
      expect(f2['reference'], ((cr['creeDefauts'] as Map)['fiche'] as Map)['reference']);
    });

    test('une fiche corrigée garde sa référence', () {
      final ancienne = dons.firstWhere((x) => x['reference'] == 'DON-0003');
      final f = sangFicheDonneur({'nbDons': '13', 'telephone': '97999999'}, existants: dons, ancienne: ancienne);
      expect(f['reference'], 'DON-0003');
      expect(f['nbDons'], 13);
    });

    test('la carte de donneur : cartouche de la maquette', () {
      final carte = (d['carte'] as Map).cast<String, Object?>();
      expect(carte['titre'], 'Carte de donneur de sang');
      expect((carte['cartouche'] as List).length, 6);
    });
  });
}
