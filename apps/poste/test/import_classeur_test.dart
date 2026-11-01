import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/classeur_xlsx.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/modules/imp/imp_ecrans.dart';

/// Le classeur .xlsx du poste, éprouvé contre les classeurs ÉCRITS PAR LA MAQUETTE (`test/fixtures/import/*.xlsx`, engendrés par
/// `prototype_html/build/vecteurs-import.js`) : deux implémentations indépendantes (JavaScript, Dart) qui doivent se relire à l'identique.
/// Limite nommée : aucun de ces classeurs ne sort d'Excel lui-même ; la compatibilité avec un Excel réel n'est pas vérifiée ici.
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();

Uint8List fixture(String nom) => File('test/fixtures/import/$nom.xlsx').readAsBytesSync();

String _t(Object? v) => texteDe(v);

Magasin magasinVecteurs() => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });

PortMagasin portVecteurs(Magasin m) => PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 1), nomAgent: 'ADMIN TEST');

void main() {
  group('lecture des classeurs écrits par la maquette', () {
    for (final c in (vecteurs['cas'] as List).cast<Map>()) {
      test('${c['id']} : mêmes lignes, même verdict que la maquette', () {
        final feuilles = lireClasseur(fixture('${c['id']}'));
        expect(feuilles.map((f) => f.nom), ['Données']);
        final attendues = [
          for (final l in (c['lignes'] as List).cast<List>()) [for (final x in l) _t(x)]
        ];
        // Un classeur ne garde pas les cellules vides de queue ni les lignes vides de queue : on compare sans elles.
        List<String> sansQueue(Iterable<Object?> l) {
          final t = [for (final x in l) _t(x)];
          while (t.isNotEmpty && t.last.isEmpty) {
            t.removeLast();
          }
          return t;
        }

        final lues = [for (final l in feuilles.single.lignes) sansQueue(l)];
        final att = [for (final l in attendues) sansQueue(l)];
        while (att.isNotEmpty && att.last.isEmpty) {
          att.removeLast();
        }
        expect(lues, att);
        // Et le moteur du domaine rend le verdict de la maquette sur ces lignes lues par Dart.
        final jeu = jeuImportParId('${c['jeu']}')!;
        final a = analyserLignes(jeu, feuilles.single.lignes, '${c['id']}.xlsx', portVecteurs(magasinVecteurs()));
        final attendu = (c['attendu'] as Map).cast<String, Object?>();
        expect(a.accepte, attendu['accepte'], reason: '${c['id']} : accepté');
        expect(a.compte.versJson(), attendu['compte']);
        expect([for (final p in a.problemes) '${p.n}:${p.code}:${p.niveau}'],
            [for (final p in (attendu['problemes'] as List).cast<Map>()) '${p['n']}:${p['code']}:${p['niveau']}']);
      });
    }
  });

  group('modèles : celui du poste et celui de la maquette disent la même chose', () {
    for (final j in jeuxImport) {
      test(j.id, () {
        final m = (vecteurs['modeles'] as Map).cast<String, Object?>()[j.id] as Map;
        // Le modèle de la maquette, relu par Dart.
        final maquette = lireClasseur(fixture('modele-${j.id}'));
        expect(maquette.map((f) => f.nom), ['Données', 'Instructions', 'Listes']);
        expect([for (final x in maquette[0].lignes.first) '$x'], m['entetes']);
        // Le modèle du poste, relu par Dart : mêmes feuilles, mêmes en-têtes, mêmes lignes que celui de la maquette.
        final port = portVecteurs(magasinVecteurs());
        final poste = lireClasseur(classeurModele(j, port));
        expect(poste.map((f) => f.nom), ['Données', 'Instructions', 'Listes']);
        List<String> sansQueue(Iterable<Object?> l) {
          final t = [for (final x in l) _t(x)];
          while (t.isNotEmpty && t.last.isEmpty) {
            t.removeLast();
          }
          return t;
        }

        for (var i = 0; i < 3; i++) {
          expect([for (final l in poste[i].lignes) sansQueue(l)], [for (final l in maquette[i].lignes) sansQueue(l)], reason: 'feuille ${poste[i].nom}');
        }
      });
    }

    test('le modèle intact (ligne d\'exemple non modifiée) est refusé comme fichier vide, jamais importé', () {
      final lu = lireClasseur(fixture('modele-grand-stock'));
      final a = analyserLignes(jeuGrandStock, lu.first.lignes, 'modele.xlsx', portVecteurs(magasinVecteurs()));
      expect(a.accepte, isFalse);
      expect(a.globaux.single.code, 'FICHIER_VIDE');
    });
  });

  test('des classeurs compressés par un autre compresseur (zlib, niveaux 1 et 9) se relisent comme leurs originaux', () {
    for (final (comp, ref) in [('compresse-gs-valide', 'gs-valide'), ('compresse-niveau1-modele-patients', 'modele-patients')]) {
      final a = lireClasseur(fixture(comp)), b = lireClasseur(fixture(ref));
      expect([for (final x in a) x.nom], [for (final x in b) x.nom]);
      expect([for (final x in a) x.lignes], [for (final x in b) x.lignes], reason: comp);
    }
  });

  group('écrire puis relire', () {
    test('types, chaînes accentuées, booléens, cellules vides et feuille sans entête', () {
      final octets = ecrireClasseur([
        const FeuilleXlsx('Données', [
          ['Nom', 'Âge', 'Actif', 'Note'],
          ['ADJOVI Marie', 36, true, 'a & b < c'],
          ['', 2.5, false, ''],
        ]),
        const FeuilleXlsx('Texte', [
          ['Mode d’emploi']
        ], entete: false),
      ]);
      expect(octets.sublist(0, 2), [0x50, 0x4b], reason: 'archive ZIP « PK »');
      final f = lireClasseur(octets);
      expect(f.map((x) => x.nom), ['Données', 'Texte']);
      expect(f[0].lignes[1], ['ADJOVI Marie', 36, true, 'a & b < c']);
      expect(f[0].lignes[2], ['', 2.5, false]);
      expect(f[1].lignes.single, ['Mode d’emploi']);
    });

    test('un fichier qui n\'est pas un classeur est refusé avec un motif lisible', () {
      expect(() => lireClasseur(utf8.encode('ceci n’est pas un classeur')), throwsA(isA<FormatException>()));
      final lu = lireFichierImport(FichierChoisi('faux.xlsx', Uint8List.fromList(utf8.encode('ceci n’est pas un classeur'))));
      expect(lu.lignes, isNull);
      expect(lu.motif, contains('archive ZIP'));
      final a = analyserFichier(jeuGrandStock, lu.lignes, 'faux.xlsx', portVecteurs(magasinVecteurs()), motifIllisible: lu.motif);
      expect(a.accepte, isFalse);
      expect(a.globaux.single.code, 'FORMAT_FICHIER');
    });

    test('un .csv (BOM, point-virgule, guillemets doublés) se lit comme un classeur', () {
      const csv = 'Code fournisseur;Raison sociale;Type;Ville;Adresse;Téléphone;IFU;Délai de livraison (jours);Banque;N° de compte\r\n'
          'TST-F1;"Fournisseur ""test"" SARL";Grossiste;Parakou;;0191000000;3202112446701;4;;\r\n';
      final lu = lireFichierImport(FichierChoisi('f.csv', Uint8List.fromList(utf8.encode('\uFEFF$csv'))));
      final a = analyserLignes(jeuFournisseurs, lu.lignes!, 'f.csv', portVecteurs(magasinVecteurs()));
      expect(a.accepte, isTrue, reason: '${a.problemes.map((p) => p.code)}');
      expect(a.lignes.single.v['nom'], 'Fournisseur "test" SARL');
    });
  });

  test('le rapport d\'erreurs se relit : sept colonnes, une ligne par constat', () {
    final port = portVecteurs(magasinVecteurs());
    final c = (vecteurs['cas'] as List).cast<Map>().firstWhere((x) => x['id'] == 'gs-quantite-negative');
    final a = analyserLignes(jeuGrandStock, lireClasseur(fixture('gs-quantite-negative')).single.lignes, 'x.xlsx', port);
    final rapport = lireClasseur(classeurRapport('Importation Grand Stock', 'x.xlsx', 'IMP-2026-001', a.nbLignes, [for (final p in a.problemes) p.versJson()]));
    expect(rapport.map((f) => f.nom), ['Erreurs', 'Résumé']);
    expect(rapport[0].lignes.first, (vecteurs['rapport'] as Map)['entete']);
    expect(rapport[0].lignes[1][4], 'RG03_STOCK_NEGATIF');
    expect(c['id'], 'gs-quantite-negative');
  });
}
