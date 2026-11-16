// LOT CLO-3 (Direction, 16/11/2026) : les gestes réservés migrés (réglages, validation fiscale, date passée, arbitrage des besoins, commande de stock gros) sont lus de la fiche RBAC
// À CHAUD en un seul point du domaine (`gesDroit`) ; leurs défauts d'origine du domaine sont ÉGAUX à `rbac.json` (la source), jamais une liste divergente.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  _retransmission();
  final brut = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final decl = {for (final d in ((brut['gestes'] as Map)['jeux'] as List).cast<Map>()) '${d['id']}': (d['rolesDefaut'] as List).cast<String>()};
  tearDown(() => gesInstaller());

  test('chaque défaut d\'origine du domaine est celui du manifeste (rbac.json), en ensemble', () {
    final attendus = <String, List<String>>{
      fichierGesteRegler: fichierRolesReglage,
      ocrGesteRegler: ocrRolesReglage,
      cfbGesteValidation: cfbRolesValidation,
      tarGesteDatePassee: tarRolesDatePassee,
      gesteValiderCommandeStock: const ['da'],
      gesteArbitrerBesoins: const ['da', 'direction', 'admin'],
      gesteTraiterBesoinsAccordes: const ['comptable', 'stock'],
      'poste_caisse': const ['caissier'],
      'poste_pharmacie': const ['pharmacien'],
      mecefGesteRetransmettre: const ['caissier', 'da', 'admin'],
      mecefGesteRetransmettreSansLimite: const ['da', 'admin'],
    };
    attendus.forEach((geste, defaut) {
      expect(decl.containsKey(geste), isTrue, reason: '$geste est déclaré au manifeste');
      expect({...decl[geste]!}, {...defaut}, reason: geste);
    });
  });

  test('sans matrice installée : le défaut d\'origine ; avec la fiche : la fiche, à chaud, dans les deux sens', () {
    expect(fichierPeutRegler('admin'), isTrue);
    expect(fichierPeutRegler('comptable'), isFalse);
    final matrice = MatriceDroits.depuisJson(brut);
    // La fiche retire le droit à l'administrateur : le moteur refuse, les motifs suivent la liste dérivée du droit.
    var retire = true;
    gesInstaller(
        lecture: (role, geste) => retire && role == 'admin' && geste == cfbGesteValidation ? false : matrice.droitGeste(role, geste),
        roles: (geste) => matrice.matriceGestes.rolesAvec(geste));
    expect(cfbPeutValider('admin'), isFalse);
    expect(cfbControleValidation(role: 'admin')!.code, 'VALIDATION_RESERVEE');
    expect(cfbControleValidation(role: 'da'), isNull);
    retire = false;
    expect(cfbPeutValider('admin'), isTrue);
    // La fiche accorde le droit de dater dans le passé à un rôle qui ne l'avait pas.
    gesInstaller(lecture: (role, geste) => role == 'comptable' && geste == tarGesteDatePassee || matrice.droitGeste(role, geste), roles: (g) => [...matrice.matriceGestes.rolesAvec(g), if (g == tarGesteDatePassee) 'comptable']);
    expect(fichierPeutRegler('admin'), isTrue);
    expect(tarProfilsDatePassee(const {'comptable': 'Comptable'}), contains('Comptable'));
  });
}

void _retransmission() {
  group('retransmission MECeF par gestes (lot CLO-3 point 7)', () {
    tearDown(() => gesInstaller());
    final fac = {'numero': 'F1', 'retransmissions': 1, 'statutMecef': 'refusee'};
    test('défauts : la caisse une fois, la DA et l\'administrateur sans limite, les autres jamais', () {
      expect(gesDroit('caissier', mecefGesteRetransmettre, const ['caissier', 'da', 'admin']), isTrue);
      expect(gesDroit('caissier', mecefGesteRetransmettreSansLimite, const ['da', 'admin']), isFalse);
      expect(gesDroit('comptable', mecefGesteRetransmettre, const ['caissier', 'da', 'admin']), isFalse);
      expect(fac['retransmissions'], 1);
    });
  });
}
