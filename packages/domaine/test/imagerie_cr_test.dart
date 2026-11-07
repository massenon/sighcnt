// Rejoue les vecteurs de l'imagerie (prototype_html/build/vecteurs-imagerie-cr.js) : les cinq tableaux et la page de compte rendu RÉELS,
// pilotés dans Chrome sur le jeu complet. Chaque ligne du registre (156 comptes rendus) est relue : tiroir, pièce imprimée, indicateurs.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

String brut(Object? s) => '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  final doc = lireVecteurs('imagerie-cr');
  final variables = liste(doc['variables']);
  final catalogue = liste(doc['catalogue']);
  final ecrans = (doc['ecrans'] as Map).cast<String, Object?>();
  const modalites = [
    'echographie',
    'radiographie',
    'mammographie',
    'scanner',
    'irm'
  ];

  // Tous les comptes rendus du registre, dans l'ordre où la maquette les affiche (toutes pages, toutes modalités).
  final lignes = <String, List<Map<String, Object?>>>{
    for (final m in modalites)
      m: [
        for (final p in ((ecrans[m] as Map)['pages'] as List)) ...liste(p),
      ]
  };
  final parRef = {
    for (final m in modalites)
      for (final l in lignes[m]!)
        '${(l['fiche'] as Map)['reference']}':
            (l['fiche'] as Map).cast<String, Object?>()
  };
  // L'ordre du MAGASIN (celui de `col.active()`) : à égalité de date, le tri de la maquette en dépend.
  final tous = [
    for (final ref in (doc['ordreMagasin'] as List))
      if (parRef.containsKey(ref)) parRef[ref]!
  ];

  group('modalités et catalogue', () {
    test('cinq modalités, leurs écrans et leurs rubriques rédigées', () {
      expect(modalitesImagerie.map((m) => m.code), modalites);
      expect(
          modaliteImagerie('echographie')!.rubriquesLibres.map((r) => r.code),
          ['conclusion']);
      for (final m in modalites.skip(1)) {
        expect(modaliteImagerie(m)!.rubriquesLibres.map((r) => r.code),
            ['resultats', 'conclusion', 'recommandation'],
            reason: m);
        expect(modaliteImagerie(m)!.aValider, propositionImagerie);
      }
      expect(modaliteImagerie('echographie')!.aValider, isNull);
    });

    test(
        'la modalité se lit au CATALOGUE ; un examen introuvable reste à l\'échographie',
        () {
      for (final x in catalogue) {
        expect(modaliteDeCodeExamen(catalogue, x['code']), x['modalite']);
      }
      expect(modaliteDeCodeExamen(catalogue, 'INCONNU'), 'echographie');
      expect(modaliteDeExamen({'code': 'X'}), 'echographie');
    });

    test(
        'un écart n\'existe que pour une valeur SIMPLE qui s\'écarte de la normale déclarée',
        () {
      final v = {'normal': 'homogène'};
      expect(ecartDeLaNormale(v, 'hétérogène'), isTrue);
      expect(ecartDeLaNormale(v, 'homogène'), isFalse);
      expect(ecartDeLaNormale(v, ''), isFalse);
      expect(ecartDeLaNormale(v, ['a']), isFalse);
      expect(ecartDeLaNormale({}, 'x'), isFalse);
    });
  });

  group('les cinq tableaux : registre et indicateurs', () {
    for (final m in modalites) {
      test(m, () {
        final e = (ecrans[m] as Map).cast<String, Object?>();
        final rows = crsDeModalite(m, tous, catalogue);
        expect(rows.length, lignes[m]!.length,
            reason: 'les comptes rendus de la modalité');
        // L'ordre du registre : date croissante PUIS inversée (`C.sortBy(rows, 'date').reverse()`).
        final ordre = trierPar(rows, (r) => r['date']).reversed.toList();
        expect(ordre.map((r) => r['reference']).toList(),
            lignes[m]!.map((l) => (l['cellules'] as List)[0]).toList());

        final kpis = liste(e['kpis']);
        final ind = indicateursImagerie(m, rows, const []);
        expect(ind.map((i) => i.libelle).toList(),
            kpis.map((k) => k['label']).toList());
        expect(ind.map((i) => nombre(i.valeur)).toList(),
            kpis.map((k) => k['value']).toList());
        expect(ind.map((i) => i.indice).toList(),
            kpis.map((k) => k['hint']).toList());
      });
    }

    test(
        'les en-têtes de colonnes, les commandes et la note « à valider » de chaque tableau',
        () {
      for (final m in modalites) {
        final e = (ecrans[m] as Map).cast<String, Object?>();
        expect(e['entete'], [
          'Référence',
          'Date',
          'Patient',
          'Examen',
          'Prescripteur',
          'Réalisé par',
          'État',
          'Actions'
        ]);
        final note = liste(e['blocs'])
            .where((b) =>
                '${b['texte']}'.startsWith('Examens et variables proposés'))
            .toList();
        expect(note.length, modaliteImagerie(m)!.aValider == null ? 0 : 1,
            reason: m);
      }
    });
  });

  group('tiroir « Consulter » et pièce imprimée de chaque compte rendu', () {
    var vus = 0;
    for (final m in modalites) {
      test(m, () {
        for (final l in lignes[m]!) {
          final r = (l['fiche'] as Map).cast<String, Object?>();
          final ref = r['reference'];
          final vars = variablesDeExamen(variables, '${r['examenCode']}');
          final libres = rubriquesLibresDe(catalogue, r['examenCode']);
          final t = (l['tiroir'] as Map).cast<String, Object?>();

          // Le tiroir : la grille d'abord, les résultats ensuite, les rubriques rédigées enfin.
          expect(
              pairesDetailCR(r).map((p) => [p.$1, p.$2]).toList(),
              [
                for (final p in (t['paires'] as List))
                  (p as List).map(brut).toList()
              ],
              reason: '$ref grille');
          final groupes = groupesCR(r, vars);
          expect([
            for (final g in groupes)
              for (final x in g.lignes)
                [g.titre, '${x.variable['libelle']}', x.lu]
          ], [
            for (final p in (t['tableau'] as List))
              (p as List).map(brut).toList()
          ], reason: '$ref résultats');
          final redigees = [
            for (final lib in libres)
              if (r[lib.code] != null && r[lib.code] != '') brut(r[lib.code])
          ];
          final anc = annexesAnterieures(r, libres);
          expect([if (anc != null) brut(anc), ...redigees].toSet(),
              liste(t['sections']).map((s) => brut(s['texte'])).toSet(),
              reason: '$ref rubriques rédigées');

          // La pièce imprimée.
          final imp = (l['impression'] as Map).cast<String, Object?>();
          final mod = modaliteDeCodeExamen(catalogue, r['examenCode']);
          expect(brut(('${r['examen']}').toUpperCase()), brut(imp['titre']),
              reason: '$ref titre');
          expect(
              cartoucheCR(r, mod).map((p) => [p.$1, brut(p.$2)]).toList(),
              [
                for (final p in (imp['cartouche'] as List))
                  (p as List).map(brut).toList()
              ],
              reason: '$ref cartouche');
          final contenu = contenuImpressionCR(r, vars, libres);
          final attendu = liste(imp['contenu']);
          expect(contenu.map((c) => brut(c.texte)).toList(),
              attendu.map((c) => brut(c['t'])).toList(),
              reason: '$ref contenu');
          expect(contenu.map((c) => c.gras).toList(),
              attendu.map((c) => c['gras'] == true).toList(),
              reason: '$ref gras');
          vus++;
        }
      });
    }
    test('156 comptes rendus relus', () => expect(vus, 156));
  });

  group('la boîte de saisie de chaque examen', () {
    final formulaires = (doc['formulaires'] as Map).cast<String, Object?>();
    test('un formulaire par examen du catalogue', () {
      expect(formulaires.keys.toSet(), catalogue.map((x) => x['code']).toSet());
    });
    for (final code in formulaires.keys) {
      test(code, () {
        final f = (formulaires[code] as Map).cast<String, Object?>();
        final cartes = liste(f['cartes']);
        final vars = variablesDeExamen(variables, code);
        final libres = rubriquesLibresDe(catalogue, code);
        final texte = saisieTexteDe(catalogue, code);
        final plan = planSaisieCR(vars, texte: texte, libres: libres);

        expect(cartes.map((c) => c['titre']).toList(), [
          ...plan.rubriques.map((r) => r.rubrique),
          ...libres.map((l) => l.label)
        ]);
        for (var i = 0; i < plan.rubriques.length; i++) {
          final r = plan.rubriques[i];
          final c = cartes[i];
          final champs = liste(c['champs']);
          expect(champs.map((x) => brut(x['label'])).toList(),
              r.champs.map((x) => x.libelle).toList(),
              reason: '$code/${r.rubrique} libellés');
          for (var k = 0; k < champs.length; k++) {
            final attendu = champs[k];
            final ch = r.champs[k];
            // Un champ de précision est masqué à l'ouverture ; les autres sont visibles.
            expect(attendu['cache'], ch.conditionnel,
                reason: '${ch.nom} masqué');
            expect(attendu['nom'], ch.nom);
            final genre = '${attendu['genre']}';
            switch (ch.genre) {
              case GenreChampCR.selection:
                // Liste native jusqu'à 8 entrées (+ l'entrée vide), panneau à recherche au-delà.
                expect(genre, ch.options.length > 8 ? 'combo' : 'select',
                    reason: ch.nom);
                if (genre == 'select') {
                  expect(attendu['options'], ['', ...ch.options],
                      reason: ch.nom);
                }
              case GenreChampCR.multiple:
                expect(genre, 'combo');
              case GenreChampCR.zone:
                expect(genre, 'textarea');
              case GenreChampCR.texte:
                expect(genre, 'input:text');
              case GenreChampCR.nombre:
                expect(genre, 'input:number');
            }
          }
          final blocs = liste(c['blocs']);
          expect(blocs.length, r.exemplaires.length,
              reason: '${r.rubrique} blocs');
          for (final b in blocs) {
            final k = int.parse('${b['resume']}'.split('n°').last);
            expect(b['resume'], '${r.rubrique} n°$k');
            expect(b['cache'], isTrue,
                reason: 'les blocs répétés sont masqués à l\'ouverture');
            expect(liste(b['champs']).map((x) => brut(x['label'])).toList(),
                r.exemplaires[k]!.map((x) => x.libelle).toList());
            expect(liste(b['champs']).map((x) => x['nom']).toList(),
                r.exemplaires[k]!.map((x) => x.nom).toList());
          }
        }
        // Les rubriques rédigées : un textarea chacune, « * » sur la conclusion.
        for (var i = 0; i < libres.length; i++) {
          final c = cartes[plan.rubriques.length + i];
          final x = liste(c['champs']).single;
          expect(brut(x['label']),
              libres[i].requis ? '${libres[i].label} *' : libres[i].label);
          expect(x['genre'], 'textarea');
        }
      });
    }
  });

  group('blocs répétés et champs de précision', () {
    final dyn = liste(doc['dyn']);
    test('le nombre déclaré fait paraître autant de blocs (2 et 3 seulement)',
        () {
      for (final e in dyn) {
        final etape = '${e['etape']}';
        if (!etape.startsWith('SG_NB')) continue;
        final v = etape.substring('SG_NB = '.length);
        final valeur = v == '""' ? '' : v.replaceAll('"', '');
        final blocs = {
          for (final b in (e['blocs'] as List)) (b as List)[0]: b[1]
        };
        expect(!(blocs['Sac gestationnel|2'] as bool),
            exemplaireVisible(valeur, 2),
            reason: etape);
        expect(!(blocs['Sac gestationnel|3'] as bool),
            exemplaireVisible(valeur, 3),
            reason: etape);
      }
    });
    test('« Autre » ouvre sa précision, quelle que soit la casse', () {
      expect(valeurCorrespond(['Autre'], 'autre'), isTrue);
      expect(valeurCorrespond(['Autre'], 'intra-utérine'), isFalse);
      expect(valeurCorrespond(['Autre'], null), isFalse);
    });
    test('exemplairesDe lit un préfixe numérique, comme parseInt', () {
      expect(exemplairesDe({'repete': 'N'}, {'N': '02'}), 2);
      expect(exemplairesDe({'repete': 'N'}, {'N': '3 sacs'}), 3);
      expect(exemplairesDe({'repete': 'N'}, {'N': 'autre'}), 1);
      expect(exemplairesDe({'repete': 'N'}, {'N': '04'}), 1);
      expect(exemplairesDe({}, {'N': '02'}), 1);
    });
    test('un exemplaire suffixe son code et celui de ses précisions', () {
      final v = {
        'code': 'SG_LOC',
        'libelle': 'Localisation',
        'conditionnels': [
          {
            'code': 'SG_LOC_AUTRE',
            'quand': ['Autre'],
            'libelle': 'préciser'
          }
        ]
      };
      final e = exemplaire(v, 2);
      expect(e['code'], 'SG_LOC__2');
      expect((e['conditionnels'] as List).single['code'], 'SG_LOC_AUTRE__2');
      expect(exemplaire(v, 1), same(v));
    });
  });

  group('valeur lisible', () {
    test('âge gestationnel : deux chiffres, jours à zéro par défaut', () {
      final v = {'code': 'AG', 'type': 'gestationnel'};
      expect(
          valeurLisibleCR(v, {'AG_sa': '9', 'AG_j': '3'}), '09 SA + 03 jours');
      expect(valeurLisibleCR(v, {'AG_sa': '12'}), '12 SA + 00 jours');
      expect(valeurLisibleCR(v, {}), '—');
    });
    test('dimensions, multiple, unité et précision', () {
      expect(
          valeurLisibleCR(
              {'code': 'D', 'type': 'dimensions'}, {'D_a': '12', 'D_c': '5'}),
          '12 x 5 mm');
      expect(valeurLisibleCR({'code': 'D', 'type': 'dimensions'}, {}), '—');
      expect(
          valeurLisibleCR({
            'code': 'S',
            'type': 'multiple'
          }, {
            'S': ['T2', 'FLAIR']
          }),
          'T2, FLAIR');
      expect(
          valeurLisibleCR({'code': 'S', 'type': 'multiple'}, {'S': []}), '—');
      expect(
          valeurLisibleCR(
              {'code': 'C', 'type': 'mesure', 'unite': 'mg/l'}, {'C': 275}),
          '275 mg/l');
      // Une unité déjà écrite par le praticien n'est pas doublée.
      expect(
          valeurLisibleCR(
              {'code': 'C', 'type': 'mesure', 'unite': 'mm'}, {'C': '12 mm'}),
          '12 mm');
      final avecPrecision = {
        'code': 'L',
        'type': 'liste',
        'conditionnels': [
          {
            'code': 'L_A',
            'quand': ['Autre'],
            'libelle': 'Localisation — préciser'
          }
        ]
      };
      expect(valeurLisibleCR(avecPrecision, {'L': 'Autre', 'L_A': 'tubaire'}),
          'Autre — Localisation — préciser : tubaire');
      expect(valeurLisibleCR(avecPrecision, {'L': 'intra', 'L_A': 'tubaire'}),
          'intra');
    });
  });

  group('les gestes d\'écriture', () {
    final gestes = liste(doc['gestes']);
    Map<String, Object?> geste(String debut) =>
        gestes.firstWhere((g) => '${g['nom']}'.startsWith(debut));

    test(
        'rendre sans conclusion est refusé en le disant ; avec conclusion, il est permis',
        () {
      final refus = geste('rendre sans conclusion');
      expect(refusRendreCR({'conclusion': ''}),
          (liste(refus['toasts']).single)['texte']);
      expect(refusRendreCR({}), isNotNull);
      expect(refusRendreCR({'conclusion': 'ok'}), isNull);
      expect((refus['ecritures'] as Map)['modifiees'], isEmpty);
    });

    test('la confirmation de rendu nomme la pièce et le prescripteur', () {
      final ok = geste('rendre avec conclusion');
      final c = liste(ok['confirms']).single;
      expect(
          messageRendreCR(
              {'reference': 'IMG-0155', 'prescripteur': 'BOUKARI Nadège'}),
          brut(c['message']));
    });

    test('la notification de rendu s\'adresse au POSTE de consultation', () {
      final ok = geste('rendre avec conclusion');
      final attendue =
          liste((ok['ecritures'] as Map)['creees']).single['fiche'] as Map;
      final cr = tous.firstWhere((r) => r['reference'] == 'IMG-0155');
      final n = notificationRenduCR(cr, '2026-10-30T10:00:00.000Z');
      for (final k in [
        'type',
        'poste',
        'libelle',
        'detail',
        'priorite',
        'patientId',
        'reference',
        'lue'
      ]) {
        expect(n[k], attendue[k], reason: k);
      }
    });

    test(
        'enregistrer : valeurs, rubriques rédigées, et la demande « payée » passe « exécutée »',
        () {
      final g = geste('enregistrer avec conclusion');
      final mod = liste((g['ecritures'] as Map)['modifiees']);
      final cr = mod.firstWhere((m) => m['coll'] == 'cr')['champs'] as Map;
      final dem = mod.firstWhere((m) => m['coll'] == 'dem')['champs'] as Map;
      final libres = modaliteImagerie('radiographie')!.rubriquesLibres;
      final p = patchEnregistrerCR(
          {
            'resultats': 'Pas de lésion osseuse.',
            'conclusion': 'Examen normal.',
            'recommandation': 'Contrôle si douleur.',
            'SEG': 'lombaire',
          },
          libres,
          demande: {'statut': 'payee'},
          maintenantIso: 'T');
      expect(p.patch['resultats'], cr['resultats']);
      expect(p.patch['conclusion'], cr['conclusion']);
      expect(p.patch['recommandation'], cr['recommandation']);
      // Les rubriques rédigées ne sont PAS rangées parmi les valeurs.
      expect((p.patch['valeurs'] as Map).keys, ['SEG']);
      expect(p.patchDemande, {'statut': dem['statut'], 'executeLe': 'T'});
      // Une demande déjà validée ne revient pas en arrière ; sans demande, rien.
      expect(
          patchEnregistrerCR({}, libres,
                  demande: {'statut': 'validee'}, maintenantIso: 'T')
              .patchDemande,
          isNull);
      expect(patchEnregistrerCR({}, libres, maintenantIso: 'T').patchDemande,
          isNull);
      expect(
          patchEnregistrerCR({'conclusion': ''}, libres, maintenantIso: 'T')
              .patch['conclusion'],
          '');
    });

    test('nouveau compte rendu : la fiche qui naît à l\'enregistrement', () {
      for (final n in liste(doc['nouveaux'])) {
        final e = (n['entete'] as Map).cast<String, Object?>();
        final creee =
            liste((n['ecritures'] as Map)['creees']).single['fiche'] as Map;
        final f = ficheDepuisEntete(e,
            reference: '${creee['reference']}',
            dateIso: '${creee['date']}',
            examenLibelle: '${creee['examen']}',
            patient: {
              'id': creee['patientId'],
              'nom': '${creee['patient']}'.split(' ').first,
              'prenom': '${creee['patient']}'.split(' ').skip(1).join(' ')
            },
            age: creee['age'] as int?,
            prescripteur: nomPrescripteurCR(e, (_) => '—'),
            prescripteurId: idPrescripteurCR(e),
            realisateur: '${creee['realisateur']}');
        for (final k in [
          'reference',
          'examenCode',
          'examen',
          'patient',
          'patientCode',
          'age',
          'indication',
          'ddr',
          'condition',
          'provenance',
          'prescripteur',
          'prescripteurId',
          'realisateurId',
          'realisateur',
          'statut',
          'annexes',
          'conclusion'
        ]) {
          expect(f[k], k == 'conclusion' ? '' : creee[k],
              reason: '${n['modalite']} $k');
        }
        expect(f['valeurs'], isEmpty);
      }
    });

    test('un prescripteur interne se nomme, un extérieur se dit', () {
      expect(nomPrescripteurCR({'prescripteurId': 'SOI01'}, (id) => 'Dr $id'),
          'Dr SOI01');
      expect(idPrescripteurCR({'prescripteurId': 'SOI01'}), 'SOI01');
      expect(nomPrescripteurCR({'prescripteurId': 'EXTERNE'}, (_) => ''),
          'Prescripteur extérieur');
      expect(
          nomPrescripteurCR(
              {'prescripteurId': 'EXTERNE', 'prescripteurIdExterne': ' Dr X '},
              (_) => ''),
          'Dr X (extérieur)');
      expect(idPrescripteurCR({'prescripteurId': 'EXTERNE'}), isNull);
    });
  });

  group('l\'âge du patient', () {
    final auj = DateTime(2026, 10, 30);
    test(
        'la date de naissance fait foi ; à défaut l\'âge déclaré, vieilli depuis sa référence',
        () {
      expect(ageDePatient({'dateNaissance': '1979-03-12'}, auj), 47);
      expect(ageDePatient({'age': 30}, auj), 30);
      expect(
          ageDePatient({'age': 30, 'ageReferenceLe': '2024-10-01'}, auj), 32);
      expect(ageDePatient({}, auj), isNull);
      expect(ageDePatient(null, auj), isNull);
      expect(ageDePatient({'age': -1}, auj), isNull);
    });
  });
}
