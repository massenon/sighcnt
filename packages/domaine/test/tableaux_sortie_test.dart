// Lot EXP : la sortie des tableaux rejoue les vecteurs TIRÉS de l'écran réel de la maquette (prototype_html/build/vecteurs-tableaux.js, écran « Factures »).
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';

void main() {
  final v = lireVecteurs('tableaux_sortie');

  test('le geste et la limite d\'attente sont ceux de la maquette', () {
    expect(tabGesteSortie, v['geste']);
    expect(tabLimiteDefaut, v['limiteDefaut']);
    final d = definitionDeParametre(tabCleLimiteLignes);
    expect(d, isNotNull);
    expect(d!.defaut, tabLimiteDefaut);
    expect(d.famille, 'securite', reason: 'jamais vers un téléphone');
    expect(d.mobile, isFalse);
  });

  group('typage d\'une cellule (valeur brute, texte montré)', () {
    for (final c in liste(v['cellules'])) {
      test('${c['brut']} | ${c['montre']}', () {
        final obtenu = tabCelluleSortie(brute: c['brut'], montre: c['montre'] as String?, aucunTexte: c['aucunTexte'] == true);
        memes(obtenu, c['cellule'], 'cellule');
      });
    }
  });

  group('refus nommés, dans l\'ordre de la maquette', () {
    for (final e in liste(v['essais'])) {
      test('${e['nom']}', () {
        final limite = tabLimiteLue(e['limiteReglee']);
        expect(limite, e['limite'], reason: 'limite lue');
        final r = tabControleSortie(
            format: '${e['format']}',
            droit: e['droit'] == true,
            libelleRole: '${e['libelleRole']}',
            lignes: (e['lignes'] as num).toInt(),
            colonnes: (e['colonnes'] as num).toInt(),
            limite: limite);
        final attendu = (e['resultat'] as Map).cast<String, Object?>();
        if (attendu['ok'] == true) {
          expect(r, isNull);
        } else {
          memes(r?.toJson(), attendu, 'refus');
        }
      });
    }
  });

  group('réglage de la limite', () {
    for (final e in liste(v['reglages'])) {
      test('${e['lignes']} « ${e['motif']} »', () {
        final r = tabControleReglageLimite(peutRegler: true, lignes: e['lignes'], motif: e['motif'] as String?);
        final attendu = (e['resultat'] as Map).cast<String, Object?>();
        if (attendu['ok'] == true) {
          expect(r, isNull);
          expect(tabLimiteLue(e['lignes']), attendu['lignes']);
        } else {
          memes(r?.toJson(), attendu, 'refus');
        }
      });
    }
    test('un profil qui n\'écrit pas dans la sécurité ne règle pas la limite', () {
      expect(tabControleReglageLimite(peutRegler: false, lignes: 500, motif: 'm')?.code, 'REGLAGE_RESERVE');
    });
  });

  group('l\'écran réel « Factures » : trois lignes cochées', () {
    final e = (v['ecranReel'] as Map).cast<String, Object?>();
    final matrice = [for (final l in e['matrice'] as List) [for (final x in l as List) x as Object]];
    test('le CSV des lignes cochées est celui que la maquette a écrit, octet pour octet', () {
      expect(tabCsv(matrice), e['csv']);
    });
    test('noms de fichier et de feuille datés', () {
      final jour = DateTime(2026, 10, 30);
      expect(tabNomFichier('factures', 'xlsx', jour), e['fichierXlsx']);
      expect(tabNomFichier('factures', 'csv', jour), e['fichierCsv']);
      expect(tabNomFeuille('factures', jour), e['feuille']);
    });
    test('montants en nombres, dates en dates (jamais du texte)', () {
      final tete = matrice.first;
      final iMont = tete.indexOf('Montant'), iDate = tete.indexOf('Date');
      for (final l in matrice.skip(1)) {
        expect(l[iMont], isA<num>());
        expect(l[iDate], isA<Map>());
      }
    });
    test('l\'entrée du journal a la forme de la maquette (jamais le contenu d\'une cellule)', () {
      for (final j in liste(e['journal'])) {
        final obtenu = tabEntreeJournal(
            format: '${j['format']}', perimetre: '${j['perimetre']}', references: j['references'] as List, utilisateur: 'x', role: j['role'] as String?,
            ecran: j['ecran'] as String?, nom: j['cible'] as String?, module: '${j['module']}');
        memes(obtenu, j, 'journal', sousEnsemble: true);
        final texte = '$obtenu';
        for (final l in matrice.skip(1)) {
          expect(texte.contains('${l[2]}'), isFalse, reason: 'aucun nom de patient au journal');
        }
      }
    });
  });

  test('le journal plafonne les identifiants à 50 et dit le total', () {
    final j = tabEntreeJournal(format: 'xlsx', perimetre: 'tout', references: List.generate(120, (i) => 'F$i'), utilisateur: 'u');
    expect((j['references'] as List).length, 50);
    expect(j['referencesTotal'], 120);
    expect(j['lignes'], 120);
  });

  group('totaux d\'impression calculés sur les lignes imprimées', () {
    String texte(Object? x) => x == null ? '' : x is num ? x.toInt().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '\u202f') : '$x';
    for (final t in liste(v['totaux'])) {
      test('${t['nom']}', () {
        final cols = <ColonneSortie<Map<String, Object?>>>[
          ColonneSortie('Réf.', (r) => tabCelluleSortie(brute: r['id'], aucunTexte: true)),
          ColonneSortie('Montant', (r) => tabCelluleSortie(brute: r['m'], aucunTexte: true), droite: true, somme: true),
          ColonneSortie('Qté', (r) => tabCelluleSortie(brute: r['q'], aucunTexte: true), droite: true, somme: true),
        ];
        final m = tabMatriceSortie(cols, liste(t['lignes']));
        final tot = tabTotaux(cols, m)!;
        expect(['TOTAL', texte(tot[1]), texte(tot[2])], t['pied']);
      });
    }
  });

  group('série Excel d\'une date (versSerie)', () {
    for (final c in liste(v['series'])) {
      test('${c['iso']}', () => memes(tabVersSerie('${c['iso']}'), c['serie'], 'serie'));
    }
  });

  group('cellule d\'un tableau dont on ne connaît que le texte (encarts)', () {
    for (final c in liste(v['textes'])) {
      test('« ${c['texte']} » ${c['droite'] == true ? 'à droite' : ''}', () => memes(tabCelluleTexte('${c['texte']}', droite: c['droite'] == true), c['cellule'], 'cellule'));
    }
  });
}
