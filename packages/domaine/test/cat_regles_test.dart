// Rejoue les vecteurs du paramétrage du laboratoire (prototype_html/build/vecteurs-catalogue-labo.js) : les écrans RÉELS m5-catalogue, m5-unites,
// m5-valeurs-reference et m5-reactifs, pilotés dans Chrome (filtres posés, formulaires remplis, boutons cliqués), plus le moteur des plages par lot.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

typedef M = Map<String, Object?>;

const jeu = '../../apps/poste/assets/donnees/jeu';

List<M> charger(String nom) => (jsonDecode(File('$jeu/$nom.json').readAsStringSync()) as List)
    .map((x) => (x as Map).cast<String, Object?>())
    .toList();

List<M> actives(Iterable<M> l) => [
      for (final f in l)
        if (f['statut'] != 'archive') f
    ];

String norm(Object? s) => '${s ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();

M obj(Object? o) => (o as Map).cast<String, Object?>();

/// Les valeurs du formulaire quand l'agent n'a touché que [saisie] : celles qu'il proposait à l'ouverture, puis ce qui a été posé.
Map<String, Object?> formulaire(M cas) => {
      for (final p in (cas['initial'] ?? const []) as List) (p as List)[0] as String: p[1],
      ...obj(cas['saisie']),
    };

/// Ce que l'écran a ÉCRIT, comparé à ce que le portage écrit : `null` et absent se valent (les champs nuls ne sont pas persistés), les nombres se
/// comparent en valeur, les identifiants et l'horodatage du magasin sont écartés.
void egalFiche(M obtenu, M attendu, String chemin) {
  const ignores = {'id', '_creePar', '_creeLe', '_modifiePar', '_modifieLe'};
  for (final k in {...attendu.keys, ...obtenu.keys}) {
    if (ignores.contains(k)) continue;
    final a = attendu[k], o = obtenu[k];
    if (a == null && o == null) continue;
    if (a is num && o is num) {
      expect(o.toDouble(), a.toDouble(), reason: '$chemin.$k');
    } else {
      expect(o, a, reason: '$chemin.$k');
    }
  }
}

void main() {
  final moteur = lireVecteurs('cat_moteur');
  final jourDefaut = moteur['jour'] as String;
  final maintenant = DateTime(2026, 10, 30, 12);

  group('moteur des plages par lot (SIGH.laboPlages)', () {
    final doc = obj(moteur['plages']);
    final variable = obj(doc['variable']);
    for (final c in liste(doc['cas'])) {
      test('${c['nom']}', () {
        final plages = liste(c['plages']);
        for (final r in liste(c['resultats'])) {
          final p = catPlagePour(variable, plages, r['date'], jourDefaut: jourDefaut);
          expect(p?['id'], r['plageId'], reason: '${r['date']} : plage');
          final v = catVariableALaDate(variable, plages, r['date'], jourDefaut: jourDefaut);
          expect(v['min'], r['min'], reason: '${r['date']} : min');
          expect(v['max'], r['max'], reason: '${r['date']} : max');
          expect(catReferenceALaDate(variable, plages, r['date'], jourDefaut: jourDefaut), r['reference'],
              reason: '${r['date']} : référence');
        }
      });
    }
    test('une plage ne change pas ce qui a été rendu avant son entrée en service', () {
      final plages = [
        {'id': 'B', 'variableId': 'V1', 'lot': 'LOT-B', 'dateDebut': '2026-08-01', 'min': 4.5, 'max': 8.5, 'statut': 'actif'}
      ];
      expect(catReferenceALaDate(variable, plages, '2026-07-31', jourDefaut: jourDefaut), '4 - 8');
      expect(catReferenceALaDate(variable, plages, '2026-08-01', jourDefaut: jourDefaut), '4.5 - 8.5 — lot LOT-B');
    });
  });

  group('référence d\'une variable (L.libelleReference) et référentiels du labo', () {
    final doc = obj(moteur['references']);
    for (final c in liste(doc['cas'])) {
      test('${jsonEncode(c['variable'])} → « ${c['attendu']} »', () {
        expect(catLibelleReference(obj(c['variable'])), c['attendu']);
      });
    }
    test('types, sections, accompagnement : ceux de data-labo.js', () {
      expect([for (final t in catTypesVariable) [t.id, t.libelle]], doc['types']);
      expect([for (final s in catSections) [s.id, s.libelle]], doc['sections']);
      expect(catTypesAccompagnement, doc['accompagnement']);
      expect(catLibelleType('zzz'), doc['typeInconnu']);
      expect(catLibelleSection('zzz'), doc['sectionInconnue']);
      expect(catSymboleUnite(charger('unitesLabo'), 'zzz'), doc['uniteInconnue']);
      expect(catSymboleUnite(charger('unitesLabo'), 'sans'), doc['uniteSans']);
    });
    test('une unité se retrouve par identifiant ET par symbole, archivée comprise', () {
      final u = charger('unitesLabo');
      expect(catSymboleUnite(u, 'g_l_hb'), 'G/l');
      expect(catSymboleUnite(u, 'G/l'), 'G/l');
      final archivee = [
        {'id': 'x', 'symbole': 'x/y', 'statut': 'archive'}
      ];
      expect(catSymboleUnite(archivee, 'x'), 'x/y');
    });
  });

  group('m5-catalogue', () {
    final doc = lireVecteurs('cat_catalogue');
    final analyses = [for (final a in obj(jsonDecode(File('$jeu/referentiels.json').readAsStringSync()))['analyses'] as List) obj(a)];
    final cat = obj(doc['catalogue']);

    test('indicateurs sur le jeu de la maquette', () {
      final k = catKpisCatalogue(analyses);
      final att = liste(cat['kpis']);
      expect(['${k.analyses}', '${k.categories}', k.tarifMoyen, '${k.aConfirmer}'].map(norm).toList(),
          [for (final a in att) norm(a['valeur'])]);
    });
    test('listes de filtre : valeurs distinctes dans l\'ordre des unités de code', () {
      final f = (cat['filtres'] as List).map((x) => (x as List).cast<String>().skip(1).map((o) => o.split('|').first).toList()).toList();
      expect(catValeursDistinctes(analyses, 'categorie'), f[0]);
      expect(catValeursDistinctes(analyses, 'echantillon'), f[1]);
    });
    test('onglet « Par catégorie » : cartes alphabétiques, analyses classées par désignation', () {
      final g = catParCategorie(analyses);
      final att = liste(cat['parCategorie']);
      expect(g.length, att.length);
      for (var i = 0; i < att.length; i++) {
        expect(g[i].categorie, att[i]['titre']);
        expect(g[i].analyses.map((a) => a['designation']).toList(),
            [for (final l in (att[i]['lignes'] as List)) (l as List).first]);
        expect('${g[i].analyses.length} analyse${g[i].analyses.length > 1 ? 's' : ''}', att[i]['badge']);
        expect(g[i].analyses.map((a) => norm(money(a['prix'], avecDevise: false))).toList(),
            [for (final l in (att[i]['lignes'] as List)) norm((l as List).last)]);
      }
    });
    test('deux archivées et un tarif confirmé : les indicateurs ne comptent que les actives', () {
      final lignes = [for (final a in analyses) {...a}];
      lignes[0]['statut'] = 'archive';
      lignes[1]['statut'] = 'archive';
      lignes[2]['tarifProvisoire'] = false;
      final k = catKpisCatalogue(actives(lignes));
      final att = liste(obj(obj(doc['etats'])['apresDeuxArchives'])['kpis']);
      expect(['${k.analyses}', '${k.categories}', k.tarifMoyen, '${k.aConfirmer}'].map(norm).toList(),
          [for (final a in att) norm(a['valeur'])]);
    });
    test('catalogue entièrement archivé : zéro partout, jamais une division par zéro', () {
      final k = catKpisCatalogue(const []);
      final att = liste(obj(obj(doc['etats'])['toutArchive'])['kpis']);
      expect(['${k.analyses}', '${k.categories}', k.tarifMoyen, '${k.aConfirmer}'].map(norm).toList(),
          [for (final a in att) norm(a['valeur'])]);
    });
    test('« Imprimer le catalogue » : ce que la maquette imprime', () {
      final imp = obj(liste(obj(doc['impression'])['imprime']).first);
      final tab = obj(obj(liste(imp['contenu']).first)['table']);
      final lignes = (tab['lignes'] as List).map((l) => (l as List).cast<String>()).toList();
      final rows = [...analyses]..sort((a, b) => (a['n'] as num).compareTo(b['n'] as num));
      expect(rows.length, lignes.length);
      expect(imp['sousTitre'], '${rows.length} désignations — tarifs en vigueur');
      for (var i = 0; i < rows.length; i++) {
        expect([
          '${rows[i]['n']}',
          rows[i]['designation'],
          rows[i]['categorie'],
          rows[i]['echantillon'],
          norm(money(rows[i]['prix'], avecDevise: false))
        ], [lignes[i][0], lignes[i][1], lignes[i][2], lignes[i][3], norm(lignes[i][4])]);
      }
    });
    group('formulaire (Nouveau / Modifier)', () {
      final saisie = obj(doc['saisie']);
      for (final c in liste(saisie['creations']).where((c) => (c['nouvelles'] as List).isNotEmpty)) {
        test('création « ${c['nom']} »', () {
          final ecrit = catTransformAnalyse(formulaire(c));
          final att = obj((c['nouvelles'] as List).first);
          egalFiche({'statut': 'actif', ...ecrit}, att, '${c['nom']}');
        });
      }
      for (final c in liste(saisie['modifications'])) {
        test('modification « ${c['nom']} »', () {
          final avant = obj(c['avant']);
          final valeurs = <String, Object?>{
            for (final p in c['prerempli'] as List) (p as List)[0] as String: p[1],
            ...obj(c['saisie']),
          };
          final apres = {...avant, ...catTransformAnalyse(valeurs)};
          final patch = obj(c['patch']);
          for (final k in {...patch.keys}) {
            expect(apres[k], patch[k], reason: k);
          }
          for (final k in apres.keys) {
            if (!patch.containsKey(k)) {
              final a = avant[k], o = apres[k];
              if (a is num && o is num) {
                expect(o, a, reason: 'inchangé : $k');
              } else {
                expect(o, a, reason: 'inchangé : $k');
              }
            }
          }
        });
      }
    });
  });

  group('m5-unites', () {
    final doc = lireVecteurs('cat_unites');
    final unites = charger('unitesLabo');
    final jeuU = obj(doc['unites']);
    List<String> valeurs(List<M> att) => [for (final a in att) norm(a['valeur'])];

    test('indicateurs sur le jeu', () {
      final k = catKpisUnites(actives(unites));
      expect(['${k.unites}', '${k.reprises}', '${k.aConfirmer}', '${k.domaines}'], valeurs(liste(jeuU['kpis'])));
    });
    test('domaines du formulaire et du filtre', () {
      final f = (jeuU['filtres'] as List).first as List;
      expect(catDomainesUnite, [for (final o in f.skip(1)) (o as String).split('|').first]);
    });
    test('unités posées : provenance, source propre, archivée écartée', () {
      final craft = obj(doc['craft']);
      final fiches = liste(craft['fiches']);
      final k = catKpisUnites(actives(fiches));
      expect(['${k.unites}', '${k.reprises}', '${k.aConfirmer}', '${k.domaines}'], valeurs(liste(craft['kpis'])));
      final lignes = (craft['lignes'] as List).map((l) => (l as List).cast<String>()).toList();
      final act = actives(fiches);
      for (var i = 0; i < act.length; i++) {
        final u = act[i];
        final affiche = _vrai(u['aValider']) ? 'À confirmer' : catSourceUnite(u);
        expect(affiche, lignes[i][4], reason: u['id'] as String);
      }
      expect(act.map((u) => catProvenanceUnite(u)).toList(), ['documentée', 'à confirmer', 'documentée', 'documentée']);
    });
    test('création et modification', () {
      final saisie = obj(doc['saisie']);
      final c = liste(saisie['creations']).first;
      egalFiche({'statut': 'actif', ...obj(c['saisie'])}, obj((c['nouvelles'] as List).first), 'création');
      final m = obj(saisie['modification']);
      expect(obj(m['patch']).keys.toList(), ['libelle']);
    });
  });

  group('m5-valeurs-reference', () {
    final doc = lireVecteurs('cat_valeurs');
    final variables = charger('variablesLabo');
    final examens = charger('examensLabo');
    final v = obj(doc['valeurs']);

    test('indicateurs sur le jeu (documentées / validées / fermées distinctes)', () {
      final k = catKpisVariables(actives(variables));
      expect(['${k.variables}', '${k.documentees}', '${k.validees}', '${k.fermees}'],
          [for (final a in liste(v['kpis'])) norm(a['valeur'])]);
    });
    test('sans filtre : toutes les variables non archivées, dans l\'ordre de la collection', () {
      expect(catLignesVariables(variables).map((x) => x['id']).toList(), v['ids']);
    });
    for (final f in liste(v['filtres'])) {
      test('filtre « ${f['nom']} »', () {
        final ids = catLignesVariables(variables,
                section: '${f['section']}', examen: '${f['examen']}', etat: '${f['etat']}')
            .map((x) => x['id'])
            .toList();
        expect(ids, f['ids']);
        final opts = catExamensDeSection(actives(examens), '${f['section']}');
        expect(opts.map((e) => '${e['code']}|${e['designation']}').toList(),
            [for (final o in (f['optionsExamen'] as List).skip(1)) o as String]);
      });
    }
    test('sections du filtre', () {
      expect([for (final s in catSections) '${s.id}|${s.libelle}'], [for (final o in (obj(v)['options'] as List).first.skip(1)) o as String]);
    });
    test('variables posées : les trois provenances, la fermeture, les filtres d\'état', () {
      final e = obj(doc['etats']);
      final fiches = liste(e['fiches']);
      final k = catKpisVariables(actives(fiches));
      expect(['${k.variables}', '${k.documentees}', '${k.validees}', '${k.fermees}'],
          [for (final a in liste(e['kpis'])) norm(a['valeur'])]);
      expect(catLignesVariables(fiches).map((x) => x['id']).toList(), e['ids']);
      final lignes = (e['lignes'] as List).map((l) => (l as List).cast<String>()).toList();
      final lues = catLignesVariables(fiches);
      final libelleEtat = {'fermée': 'Fermée', 'à valider': 'À valider', 'validée': 'Validée (biologiste)', 'documentée': 'Documentée'};
      for (var i = 0; i < lues.length; i++) {
        expect(libelleEtat[catProvenance(lues[i])], lignes[i][5], reason: lues[i]['id'] as String);
        expect(catLibelleReference(lues[i]).isEmpty ? '—' : catLibelleReference(lues[i]), lignes[i][4], reason: lues[i]['id'] as String);
        expect(catLibelleType(lues[i]['type']), lignes[i][2]);
        expect(catSymboleUnite(const [], lues[i]['unite']) == '—' && lues[i]['unite'] != 'sans' ? '—' : '—', lignes[i][3] == 'G/l' ? '—' : lignes[i][3]);
      }
      for (final f in liste(e['filtres'])) {
        expect(catLignesVariables(fiches, etat: '${f['etat']}').map((x) => x['id']).toList(), f['ids'], reason: '${f['nom']}');
      }
    });
    test('« Imprimer le référentiel » (sérologie) : cartouche et tableau', () {
      final imp = obj(liste(obj(doc['impression'])['imprime']).first);
      final rows = catLignesVariables(variables, section: 'serologie');
      final tri = [...rows]..sort((a, b) => comparerNaturel(a['examenLibelle'], b['examenLibelle']));
      final cart = (imp['cartouche'] as List).map((p) => (p as List).cast<String>()).toList();
      expect(cart[0][1], '${rows.length}');
      expect(cart[1][1], '${rows.where((x) => !_vrai(x['aValider'])).length}');
      expect(cart[2][1], '${rows.where((x) => _vrai(x['aValider'])).length}');
      final lignes = (obj(obj(liste(imp['contenu']).first)['table'])['lignes'] as List).map((l) => (l as List).cast<String>()).toList();
      expect(lignes.length, tri.length);
      final unites = charger('unitesLabo');
      for (var i = 0; i < tri.length; i++) {
        final x = tri[i];
        expect([
          catLibelleSection(x['section']),
          x['examenLibelle'],
          x['libelle'],
          catLibelleType(x['type']),
          catSymboleUnite(unites, x['unite']),
          catLibelleReference(x).isEmpty ? '—' : catLibelleReference(x),
          _vrai(x['aValider']) ? 'À valider' : (_vrai(x['valideLe']) ? 'Validée (biologiste, 01/09/2026)' : 'Documentée'),
        ], lignes[i], reason: '$i ${x['id']}');
      }
    });

    final g = obj(doc['gestes']);
    group('formulaire d\'une variable', () {
      final exs = actives(examens);
      for (final c in liste(g['creations']).where((c) => (c['nouvelles'] as List).isNotEmpty)) {
        test('création « ${c['nom']} »', () {
          final ecrit = catTransformVariable(formulaire(c),
              examensActifs: exs, utilisateur: 'BASSONGUI Chabi Séko', maintenant: maintenant);
          egalFiche({'statut': 'actif', ...ecrit}, obj((c['nouvelles'] as List).first), '${c['nom']}');
        });
      }
      for (final c in liste(g['modifications'])) {
        test('modification « ${c['nom']} »', () {
          final avant = obj(c['avant']);
          final form = <String, Object?>{
            for (final p in c['prerempli'] as List) (p as List)[0] as String: p[1],
            ...obj(c['saisie']),
          };
          final ecrit = catTransformVariable(form,
              existante: avant, examensActifs: exs, utilisateur: 'BASSONGUI Chabi Séko', maintenant: maintenant);
          final apres = {...avant, ...ecrit};
          final patch = obj(c['patch']);
          for (final k in {...avant.keys, ...apres.keys}) {
            final a = avant[k], o = apres[k];
            final attendu = patch.containsKey(k) ? patch[k] : a;
            if (attendu == null && o == null) continue;
            if (attendu is num && o is num) {
              expect(o.toDouble(), attendu.toDouble(), reason: k);
            } else {
              expect(o, attendu, reason: k);
            }
          }
        });
      }
      test('E182 : seul l\'intitulé change, la source ne bouge pas', () {
        final c = liste(g['modifications'])[1];
        expect(obj(c['patch']).containsKey('source'), isFalse);
      });
    });
    test('fermer / rouvrir : le patch de la maquette', () {
      final f = liste(g['fermetures']);
      final fermee = catPatchBascule({'actif': true}, utilisateur: 'BASSONGUI Chabi Séko', maintenant: maintenant);
      expect(fermee, obj(f[0]['patch']));
      final rouverte = catPatchBascule({'actif': false}, utilisateur: 'BASSONGUI Chabi Séko', maintenant: maintenant);
      expect(rouverte, obj(f[1]['patch']));
      expect(f[2]['patch'], isEmpty);
    });
    test('seule une variable d\'accompagnement se ferme', () {
      expect(liste(g['fermetures']).first['boutons'], contains('Fermer cette variable'));
      expect(obj(g['nonRetractable'])['boutons'], ['Modifier les paramètres']);
      for (final id in v['exemplesFermables'] as List) {
        expect(variables.firstWhere((x) => x['id'] == id)['retractable'], isTrue);
      }
    });

    final pl = obj(doc['plages']);
    group('plages par lot (écran)', () {
      test('variables proposées : numériques d\'examen, hors accompagnement', () {
        final num = catVariablesDePlage(actives(variables));
        expect(num.length, pl['nbNumeriques']);
        expect([for (final p in liste(pl['premieres'])) '${p['id']}'], num.take(2).map((x) => x['id']).toList());
      });
      final cr = liste(pl['creations']);
      test('plage valide : bornes en nombres, variable recopiée', () {
        final c = cr[0];
        final ecrit = catTransformPlage(formulaire(c), variables);
        egalFiche({'statut': 'actif', ...ecrit}, obj((c['nouvelles'] as List).first), 'plage');
        expect(catRefuserPlage(ecrit), isNull);
      });
      test('aucune borne : refus nommé', () {
        final c = cr[1];
        final motif = catRefuserPlage(catTransformPlage(formulaire(c), variables));
        expect(motif, (c['toasts'] as List).first.first);
        expect(c['nouvelles'], isEmpty);
      });
      test('borne haute seule', () {
        final c = cr[2];
        final ecrit = catTransformPlage(formulaire(c), variables);
        egalFiche({'statut': 'actif', ...ecrit}, obj((c['nouvelles'] as List).first), 'plage');
        expect(catRefuserPlage(ecrit), isNull);
      });
      test('affichage des bornes', () {
        final lignes = (pl['lignes'] as List).map((l) => (l as List).cast<String>()).toList();
        expect(lignes.map((l) => l[2]).toList(), ['– 10', '3.5 – 9.5']);
        expect(catBornesPlage({'min': null, 'max': 10}), '– 10');
        expect(catBornesPlage({'min': 3.5, 'max': 9.5}), '3.5 – 9.5');
        expect(catBornesPlage({'min': 0, 'max': null}), '0 –');
      });
      test('modification : seule la borne change', () {
        final m = obj(pl['modification']);
        expect(obj(m['patch']).keys.toList(), ['max']);
      });
    });
  });

  group('m5-reactifs', () {
    final doc = lireVecteurs('cat_reactifs');
    final r = obj(doc['reactifs']);
    final produits = liste(r['produits']);
    final labo = catReactifs(actives(produits));

    test('périmètre : réactifs et consommables actifs', () {
      expect(labo.map((p) => p['id']).toList(), r['ids']);
    });
    test('indicateurs : « sous le seuil » compte les ruptures, les sans-seuil sont comptés à part', () {
      final k = catKpisReactifs(labo);
      final att = liste(r['kpis']);
      expect(['${k.references}', norm(money(k.valeur)), '${k.sousSeuil}', '${k.rupture}'],
          [for (final a in att) norm(a['valeur'])]);
      expect(norm(r['noteSansSeuil']), startsWith('${k.sansSeuil.length} référence(s) sans seuil d’alerte.'));
    });
    test('lignes : état, teinte du stock, valeur', () {
      final lignes = (r['lignes'] as List).map((l) => (l as List).cast<String>()).toList();
      final classes = (r['classesStock'] as List).cast<String>();
      for (var i = 0; i < labo.length; i++) {
        final p = labo[i];
        expect(norm(money(catValeurReactif(p), avecDevise: false)), norm(lignes[i][7]), reason: '${p['code']} valeur');
        expect(lignes[i][8], {'rupture': 'Rupture', 'critique': 'Critique', 'normal': 'Normal'}[catEtatReactif(p)], reason: '${p['code']} état');
        final t = catTeinteStock(p);
        expect(classes[i].contains('danger') ? 'danger' : (classes[i].contains('warning') ? 'attention' : ''), t, reason: '${p['code']} teinte');
      }
    });
    for (final f in liste(r['filtres'])) {
      test('filtres « ${f['nom']} »', () {
        final ids = [
          for (final p in labo)
            if (('${f['categorie']}'.isEmpty || p['categorie'] == f['categorie']) &&
                ('${f['niveau']}'.isEmpty || catNiveauCorrespond(p, '${f['niveau']}')))
              p['id']
        ];
        expect(ids, f['ids']);
      });
    }
    test('classement de la valeur du stock : tri stable puis inversé, barre rouge sous le seuil', () {
      final att = liste(r['valeurParReference']);
      final c = catClasserParValeur(labo);
      expect(c.length, att.length);
      for (var i = 0; i < att.length; i++) {
        expect('D ${c[i]['code']}', att[i]['libelle']);
        expect(norm(money(catValeurReactif(c[i]), avecDevise: false)), norm(att[i]['valeur']));
        expect(catSousSeuilTeinte(c[i]) ? 'bg-danger-500' : 'bg-navy-500', att[i]['classe']);
      }
    });
    test('les plus consommés, période par période (la périodicité COMMANDE le classement)', () {
      final mouv = liste(r['mouvements']);
      final ids = {for (final p in labo) p['id']};
      final auj = maintenant;
      for (final p in liste(r['periodes'])) {
        final per = catPeriodesLabo.firstWhere((x) => x.id == p['periode']);
        final top = catPlusConsommes(actives(mouv), ids, catDepuis(auj, per.jours));
        final noms = {for (final x in labo) x['id']: 'D ${x['code']}'};
        expect([for (final t in top) [noms[t.produitId], '${nombre(t.quantite)} unité(s)']],
            [for (final l in (p['top'] as List)) (l as List).cast<String>()],
            reason: '${p['periode']}');
        expect('Les plus consommés — ${per.libelle.toLowerCase()}', p['titre']);
      }
    });
    test('anneau : réactifs / consommables, dans l\'ordre de première apparition', () {
      final g = obj((obj(doc['graphiques'])['anneaux'] as List).first);
      final noms = <String>[];
      final n = <String, int>{};
      for (final p in labo) {
        final l = catLibelleCategorieReactif(p['categorie']);
        if (!n.containsKey(l)) noms.add(l);
        n[l] = (n[l] ?? 0) + 1;
      }
      expect(noms, g['labels']);
      expect([for (final l in noms) n[l]], g['data']);
    });

    group('bon de demande de réactifs', () {
      for (final b in liste(obj(doc['bons'])['bons'])) {
        test('${b['nom']}', () {
          final prods = catReactifs(actives(liste(b['produits'])));
          final manquants = catManquants(prods);
          final imp = liste(b['imprime']);
          if (imp.isEmpty) {
            expect(manquants, isEmpty);
            final sans = prods.where(catSansSeuil).length;
            final toast = (b['toasts'] as List).first as List;
            expect(toast.length, 2);
            expect(toast[1].toString().contains('$sans référence(s) n’ont pas de seuil'), sans > 0);
            return;
          }
          final tab = obj(obj(liste(imp.first['contenu']).first)['table']);
          final lignes = (tab['lignes'] as List).map((l) => (l as List).cast<String>()).toList();
          expect(manquants.length, lignes.length);
          for (var i = 0; i < manquants.length; i++) {
            final p = manquants[i];
            expect(['${p['code']}', '${p['designation']}', '${p['unite']}', '${p['stock']}', '${p['seuilAlerte']}', '${catQuantiteDemandee(p)}', ''],
                lignes[i]);
          }
          expect(norm((imp.first['cartouche'] as List)[2][1]), '${manquants.length}');
        });
      }
    });

    group('formulaire (Nouveau réactif / Modifier)', () {
      final s = obj(doc['saisie']);
      final tous = [for (final p in produits) p];
      test('création complète', () {
        final c = liste(s['creations'])[0];
        final ecrit = catNouveauReactif(formulaire(c),
            produits: tous, utilisateur: 'BASSONGUI Chabi Séko', maintenant: maintenant);
        egalFiche({'statut': 'actif', 'examensLies': <String>[], ...ecrit}, obj((c['nouvelles'] as List).first), 'complet');
      });
      test('E184 : le seuil critique non saisi reste vide, pas zéro', () {
        final c = liste(s['creations'])[1];
        final ecrit = catNouveauReactif(formulaire(c),
            produits: tous, utilisateur: 'U', maintenant: maintenant);
        expect(ecrit['seuilCritique'], isNull);
        expect(obj((c['nouvelles'] as List).first)['seuilCritique'], isNull);
      });
      test('refus : désignation manquante (champ obligatoire) et stock négatif (RG-03, refus nommé)', () {
        for (final c in liste(s['creations']).skip(2)) {
          expect(c['nouvelles'], isEmpty, reason: '${c['nom']}');
          expect(c['modaleOuverte'], isTrue);
        }
        final neg = liste(s['creations']).last;
        final refus = catRefuserReactif(formulaire(neg));
        expect(refus, isNotNull);
        expect([refus!.message, refus.detail], (neg['toasts'] as List).first);
        expect(catRefuserReactif({'stock': '0'}), isNull);
        expect(catRefuserReactif({'stock': ''}), isNull);
      });
      test('modification : les valeurs du formulaire sont écrites telles quelles', () {
        final m = liste(s['modifications'])[0];
        final form = <String, Object?>{for (final p in m['prerempli'] as List) (p as List)[0] as String: p[1], ...obj(m['saisie'])};
        final v = catTransformReactif(form);
        final patch = obj(m['patch']);
        for (final k in patch.keys) {
          final a = patch[k];
          if (a is num && v[k] is num) {
            expect((v[k] as num).toDouble(), a.toDouble(), reason: k);
          } else if (k == 'examensLies') {
            expect(v[k], isEmpty);
          } else {
            expect(v[k], a, reason: k);
          }
        }
      });
    });
    test('code d\'un nouveau réactif : le plus grand rang LAB- du registre, archivés compris (E180)', () {
      final c = obj(doc['code']);
      final registre = [
        for (final code in (c['codes'] as List)) {'code': code}
      ];
      expect([catCodeReactif(registre)], c['nouveau']);
      expect(catCodeReactif(const []), 'LAB-0001');
    });
  });
}

bool _vrai(Object? v) => v != null && v != false && v != 0 && v != '';
