// Rejoue les vecteurs de la DÉLIVRANCE engendrés par la maquette (prototype_html/build/vecteurs-delivrance.js) :
// le moteur PR.delivrer, les deux pharmacies et la dispensation, pilotés comme le fait l'agent.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

const _instant = '2026-10-30T10:00:00.000Z';

void main() {
  final v = lireVecteurs('delivrance');

  group('voieDe — la voie décide de la pharmacie', () {
    test('la voie portée par la ligne prime', () {
      expect(voieDe({'voie': 'parenterale'}, {'designation': 'PARACETAMOL CP'}), 'parenterale');
      expect(voieDe({'voie': 'orale'}, {'designation': 'ADRENALINE INJ'}), 'orale');
    });
    test('à défaut, la désignation révèle l\'injectable — « inj » compris (E41)', () {
      expect(voieDe({}, {'designation': 'ADRENALINE 1 MG INJ'}), 'parenterale');
      expect(voieDe({}, {'designation': 'SERUM SALE 0,9 % 500 ML INJ'}), 'parenterale');
      expect(voieDe({}, {'designation': 'PERFUSEUR'}), 'parenterale');
      expect(voieDe({}, {'designation': 'PARACETAMOL 500 MG CP'}), 'orale');
      expect(voieDe({}, {'designation': 'INJECTABLE X'}), 'parenterale');
    });
    test('la forme prime sur la désignation ; un produit inconnu est oral', () {
      expect(voieDe({}, {'forme': 'sirop', 'designation': 'X INJ'}), 'orale');
      expect(voieDe({}, null), 'orale');
    });
    test('« inj » ne se confond pas avec un mot qui le contient', () {
      expect(voieDe({}, {'designation': 'ANJINJOU'}), 'orale');
    });
  });

  group('PR.delivrer — le moteur', () {
    final cas = liste(v['moteur']);
    test('au moins 19 situations ont été engendrées', () => expect(cas.length, greaterThanOrEqualTo(19)));

    for (final c in cas) {
      final e = (c['entree']! as Map).cast<String, Object?>();
      final s = (c['sortie']! as Map).cast<String, Object?>();
      test('${c['nom']}', () {
        final taches = liste(e['taches']);
        final refMax = e['refMouvementMax'] as String?;
        Delivrance faire() => delivrerOrdonnance(
              ordonnance: (e['ordonnance'] as Map).cast(),
              produits: liste(e['produits']),
              taches: taches,
              mouvementsExistants: [if (refMax != null) {'reference': refMax}],
              methode: e['methode']! as String,
              utilisateur: e['utilisateur']! as String,
              instant: _instant,
            );
        if (s['erreur'] != null) {
          expect(faire, throwsA(isA<RefusDelivrance>().having((r) => r.motif, 'motif', s['erreur'])));
          // Rien n'est écrit : les produits attendus sont ceux d'entrée.
          memes(liste(s['produits']), liste(e['produits']), 'produits', ignorer: const {'id'});
          return;
        }
        final r = faire();
        expect(r.deja, s['deja'], reason: 'déjà servie');
        if (r.deja) return;

        // Le magasin d'après : les patchs de produits s'appliquent dans l'ordre des lignes.
        final prods = {for (final p in liste(e['produits'])) p['id']: {...p}};
        for (final p in r.produits) {
          prods[p.id]!.addAll(p.patch);
        }
        final attenduP = liste(s['produits']);
        final ordre = liste(e['produits']);
        for (var i = 0; i < ordre.length; i++) {
          memes(prods[ordre[i]['id']], attenduP[i], 'produit $i', ignorer: const {'id'});
        }

        final o = (s['ordonnance'] as Map).cast<String, Object?>();
        expect(r.ordonnancePatch['statutDispensation'], o['statutDispensation']);
        expect(r.ordonnancePatch['dispensePar'], o['dispensePar']);
        expect(r.ordonnancePatch['dispenseLe'], isNotNull);

        memes(r.mouvements, liste(s['mouvements']), 'mouvements', ignorer: const {'date', 'id'});

        // Les tâches : celles du magasin d'entrée, patchées, puis les nouvelles.
        final apres = <Map<String, Object?>>[
          for (final t in taches) {...t},
        ];
        for (final f in r.tachesFermees) {
          apres.firstWhere((t) => t['id'] == f.id).addAll(f.patch);
        }
        for (final m in r.tachesMisesAJour) {
          apres.firstWhere((t) => t['id'] == m.id).addAll(m.patch);
        }
        for (final n in r.tachesCreees) {
          apres.add({...n, 'id': '<nouvelle>'});
        }
        for (final t in apres) {
          t.remove('faitLe');
          t.remove('creeLe');
          t.remove('date');
        }
        List<Map<String, Object?>> parId(List<Map<String, Object?>> l) =>
            [...l]..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
        memes(parId(apres), parId(liste(s['taches'])), 'taches');

        memes([
          for (final a in r.alertes) {'produitId': a.produitId, 'niveau': a.niveau, 'dispo': a.dispo, 'seuil': a.seuil}
        ], liste(s['alertes']), 'alertes');
      });
    }

    test('RG-03 : aucun cas ne laisse un stock de détail négatif', () {
      for (final c in cas) {
        final s = (c['sortie']! as Map).cast<String, Object?>();
        for (final p in liste(s['produits'])) {
          expect((p['stockDetail'] as num?) ?? 0, greaterThanOrEqualTo(0), reason: '${c['nom']}');
          expect((p['stock'] as num?) ?? 0, greaterThanOrEqualTo(0), reason: '${c['nom']}');
        }
      }
    });

    test('la série des mouvements ne reprend jamais une référence existante (E41b)', () {
      final r = delivrerOrdonnance(
        ordonnance: {'id': 'O', 'numero': 'ORD-1', 'statutPaiement': 'soldee', 'statutDispensation': 'en_attente', 'medicaments': [
          {'produitId': 'P', 'produit': 'X', 'quantite': 1},
          {'produitId': 'Q', 'produit': 'Y', 'quantite': 1},
        ]},
        produits: [
          {'id': 'P', 'designation': 'X', 'stock': 5, 'stockDetail': 5, 'prixVente': 10, 'seuilAlerte': 1},
          {'id': 'Q', 'designation': 'Y', 'stock': 5, 'stockDetail': 5, 'prixVente': 10, 'seuilAlerte': 1},
        ],
        taches: const [],
        mouvementsExistants: [{'reference': 'M000123'}, {'reference': 'MVT-00999'}],
        methode: 'prixVente',
        utilisateur: 'U',
        instant: _instant,
      );
      expect(r.mouvements.map((m) => m['reference']), ['M000124', 'M000125']);
    });
  });

  group('les deux pharmacies', () {
    for (final c in liste(v['pharmacie'])) {
      final voie = '${c['voie']}';
      final e = (c['entree']! as Map).cast<String, Object?>();
      final lu = (c['lu']! as Map).cast<String, Object?>();

      test('${c['ecran']} : indicateurs et lignes comme l\'écran les affiche', () {
        final ls = lignesPharmacie(ordonnances: liste(e['ordonnances']), produits: liste(e['produits']), voie: voie);
        final st = statsPharmacie(ls);
        expect(['${st.lignes}', '${st.aDelivrer}', '${st.bloquees}', '${st.decouvertes}'], (lu['kpi'] as List).cast<String>());
        final rows = aDelivrerTriees(ls);
        final attendu = liste(lu['lignes']);
        expect(rows.length, attendu.length);
        for (var i = 0; i < rows.length; i++) {
          final r = rows[i];
          final cel = (attendu[i]['cellules'] as List).cast<String>();
          expect(r.numero, cel[0]);
          expect(dateFR(DateTime.parse('${r.date}')), cel[1]);
          expect('${r.patient} — ${r.patientCode}', cel[2]);
          expect(r.designation, cel[3]);
          expect('${r.quantite}', cel[4]);
          expect(r.stock == null ? 'produit inconnu' : nombre(r.stock), cel[6], reason: 'stock de ${r.numero}');
          expect(r.etat, cel[7], reason: 'état de ${r.numero}');
          // Le bouton : « Délivrer » si l'ordonnance est réglée, sinon le cadenas.
          final actions = (attendu[i]['actions'] as List).cast<String>();
          expect(actions.single, r.paye ? '|Délivrer' : 'Bloquée : l’ordonnance n’est pas réglée|');
        }
      });

      test('${c['ecran']} : les gestes (ligne bloquée, refus nommé, délivrance) laissent le magasin comme la maquette', () {
        final produits = liste(e['produits']);
        final ordonnances = liste(e['ordonnances']);
        final mouvements = <Map<String, Object?>>[
          if (e['refMvtMax'] != null) {'reference': e['refMvtMax']}
        ];
        for (final a in liste(c['actions'])) {
          final numOrd = '${a['ordonnance']}';
          final ls = lignesPharmacie(ordonnances: ordonnances, produits: produits, voie: voie)
              .where((l) => l.numero == numOrd && !l.delivre)
              .toList();
          expect(ls, hasLength(1), reason: numOrd);
          final l = ls.single;
          if (!l.paye) {
            expect(a['bouton'], 'Bloquée');
            expect(((a['toasts'] as List).single as List).single, 'Délivrance bloquée — l’ordonnance $numOrd n’est pas réglée.');
            continue;
          }
          final toasts = (a['toasts'] as List).map((t) => (t as List).cast<String>()).toList();
          if (!l.couvert) {
            expect(() => delivrerLigne(l, voie, reference: 'X', jour: '2026-10-30'),
                throwsA(isA<RefusDelivrance>().having((r) => r.motif, 'motif', toasts.single.single)));
            expect(a['changements'], false);
            continue;
          }
          final modale = '${a['modale']}';
          expect(modale, contains(messageConfirmation(l, voie)));
          expect(modale, startsWith('Délivrer ${l.designation} ?'));
          final r = delivrerLigne(l, voie,
              reference: referenceSuivante('MVT-', 5, mouvements), jour: '2026-10-30');
          expect([r.message, r.detail], toasts.single);
          memes([r.mouvement], liste(a['mouvements']), 'mouvement', ignorer: const {'date', 'id'});
          // Le magasin d'après.
          mouvements.add(r.mouvement);
          final p = produits.firstWhere((x) => x['id'] == l.produit!['id']);
          p.addAll(r.produitPatch);
          final attenduP = liste(a['produits']).firstWhere((x) => x['id'] == p['id']);
          memes(p, attenduP, 'produit', ignorer: const {'id'});
          ordonnances.firstWhere((o) => o['id'] == l.ordonnance['id']).addAll(r.ordonnancePatch);
          expect((a['ordonnance_apres'] as Map)['statutDispensation'], 'servie');
          // L'écran se repeint : mêmes indicateurs que ceux qu'il relit.
          final apres = statsPharmacie(lignesPharmacie(ordonnances: ordonnances, produits: produits, voie: voie));
          final lecture = ((a['lu_apres'] as Map)['kpi'] as List).cast<String>();
          expect(['${apres.lignes}', '${apres.aDelivrer}', '${apres.bloquees}', '${apres.decouvertes}'], lecture);
        }
      });
    }
  });

  group('m6-dispensation', () {
    final d = (v['dispensation']! as Map).cast<String, Object?>();
    final e = (d['entree']! as Map).cast<String, Object?>();
    final lu = (d['lu']! as Map).cast<String, Object?>();

    test('les quatre indicateurs', () {
      final k = kpisDispensation(liste(e['dispensations']), liste(e['produits']));
      expect(['${k.dispensations}', money(k.valeur), '${k.references}', '${k.ruptures}'], (lu['kpi'] as List).cast<String>());
    });

    test('la file : délivrance d\'une ordonnance encaissée (justificatif = n° d\'ordonnance)', () {
      final a = liste(d['actions']).firstWhere((x) => x['ordonnance'] == 'ORD-D1');
      final ord = liste(e['ordonnances']).firstWhere((o) => o['numero'] == 'ORD-D1');
      final etat = verifierStock(ord, liste(e['produits']));
      expect(etat.every((x) => x.suffisant), isTrue);
      expect('${a['modale']}', contains('ARTESUNATE 60 MG INJ 1 inj/j 2 12 Oui'));
      final r = delivrerOrdonnance(
        ordonnance: ord,
        produits: liste(e['produits']),
        taches: liste(e['taches']),
        mouvementsExistants: const [
          {'reference': 'M000415'}
        ],
        methode: 'prixVente',
        utilisateur: 'BASSONGUI Chabi Séko',
        instant: _instant,
      );
      expect('Médicaments délivrés — ${r.mouvements.length} sortie(s) de stock.', (a['toasts'] as List).first.first);
      // L'ordre du magasin est celui de l'insertion en tête : le plus récent d'abord.
      memes(r.mouvements.reversed.toList(), liste(a['mouvements']), 'mouvements', ignorer: const {'date', 'id'});
      expect(r.tachesFermees, hasLength(1));
      expect(r.tachesFermees.single.patch['statut'], 'fait');
    });

    test('une ligne non couverte : la modale renvoie aux transferts, la délivrance est refusée (RG-03)', () {
      final a = liste(d['actions']).firstWhere((x) => x['ordonnance'] == 'ORD-D2');
      final ord = liste(e['ordonnances']).firstWhere((o) => o['numero'] == 'ORD-D2');
      final etat = verifierStock(ord, liste(e['produits']));
      expect(etat.map((x) => x.suffisant), [true, false]);
      expect((a['boutonsModale'] as List), ['Fermer', 'Aller aux transferts']);
      expect(
          () => delivrerOrdonnance(
              ordonnance: ord,
              produits: liste(e['produits']),
              taches: const [],
              mouvementsExistants: const [],
              methode: 'prixVente',
              utilisateur: 'U',
              instant: _instant),
          throwsA(isA<RefusDelivrance>()));
    });

    test('une ordonnance non encaissée : « Délivrance impossible » avec le motif du moteur', () {
      final a = liste(d['actions']).firstWhere((x) => x['ordonnance'] == 'ORD-D3');
      final ord = liste(e['ordonnances']).firstWhere((o) => o['numero'] == 'ORD-D3');
      expect('${a['modale']}', contains('Règlement NON ENCAISSÉ'));
      try {
        delivrerOrdonnance(
            ordonnance: ord,
            produits: liste(e['produits']),
            taches: const [],
            mouvementsExistants: const [],
            methode: 'prixVente',
            utilisateur: 'U',
            instant: _instant);
        fail('devait être refusée');
      } on RefusDelivrance catch (r) {
        expect('Délivrance impossible : ${r.motif}', ((a['toasts'] as List).single as List).single);
      }
    });
  });
}
