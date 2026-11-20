import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/identite_migration_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';

/// LOT IDENT-MIG (Direction, 16/11/2026) : la migration de l'identité au démarrage d'un poste DÉJÀ INSTALLÉ, contre le magasin du poste : version 2 posée, version 1 close au 15/11/2026 sans être
/// réécrite, signée, journalisée (RG-12), idempotente, jamais d'écrasement, refus nommé, un fileul ne migre pas.
typedef M = Map<String, Object?>;

Magasin poste(List<M> versions) {
  final m = Magasin({'identiteLegale': versions, 'audit': <M>[]});
  m.horloge = () => DateTime(2026, 11, 16, 9, 30);
  return m;
}

M v1Installee() => {...cfbSemenceIdentite(), 'fin': null};

List<M> versions(Magasin m) => m.collection('identiteLegale').toutes;
List<M> audit(Magasin m) => m.collection('audit').toutes;

void main() {
  test('poste d\'avant : la version 2 est posée, la version 1 close au 15/11/2026, signé et journalisé', () {
    final m = poste([v1Installee()]);
    final r = migrerIdentiteVersion2(m);
    expect(r.etat, 'migree');
    final vs = versions(m);
    expect(vs, hasLength(2));
    final v1 = vs.firstWhere((v) => v['version'] == 1);
    final v2 = vs.firstWhere((v) => v['version'] == 2);
    expect(v1['fin'], '2026-11-15');
    expect(v1['rccm'], 'RB/NAT/2016-B-268', reason: 'la version 1 n\'est pas réécrite');
    expect(v1['modifiePar'], cfbActeurMigrationIdentite);
    expect(v2['rccm'], 'NAT/2021/M02-020');
    expect(v2['debut'], '2026-11-16');
    expect(v2['id'], 'IDL002');
    expect(v2['creePar'], cfbActeurMigrationIdentite);
    final lignes = [for (final a in audit(m)) if ('${a['action']}'.startsWith('Identité : migration automatique vers la version 2')) a];
    expect(lignes, hasLength(1), reason: 'RG-12 : une ligne de journal nomme la migration');
    expect(lignes.single['poste'], isNotNull);
    expect((lignes.single['apres'] as Map)['signePar'], cfbActeurMigrationIdentite);
    expect(cfbIdentiteALaDate(versions(m), DateTime(2026, 11, 15))!['rccm'], 'RB/NAT/2016-B-268');
    expect(cfbIdentiteALaDate(versions(m), DateTime(2026, 11, 16))!['rccm'], 'NAT/2021/M02-020');
  });

  test('IDEMPOTENT : trois démarrages de suite, une seule version 2, une seule ligne de journal de migration', () {
    final m = poste([v1Installee()]);
    expect(migrerIdentiteVersion2(m).etat, 'migree');
    for (var i = 0; i < 2; i++) {
      final r = migrerIdentiteVersion2(m);
      expect(r.etat, 'sans_objet');
      expect(r.raison, 'DEJA_A_JOUR');
    }
    expect(versions(m), hasLength(2));
    expect([for (final a in audit(m)) if ('${a['action']}'.contains('migration automatique vers')) a], hasLength(1));
  });

  test('JAMAIS ÉCRASÉ : une version 2 déjà présente (même modifiée par l\'utilisateur) reste exactement ce qu\'elle est', () {
    final posee = {...cfbSemenceIdentiteV2(id: 'IDL005'), 'rccm': 'NAT/2030/X', 'debut': '2026-12-01', 'telephones': ['01 22 22 22 22']};
    final m = poste([cfbSemenceIdentite(), posee]);
    final avant = [for (final v in versions(m)) {...v}];
    final r = migrerIdentiteVersion2(m);
    expect(r.etat, 'sans_objet');
    expect(versions(m), avant);
    expect(audit(m), isEmpty, reason: 'rien n\'est écrit, rien n\'est journalisé');
  });

  test('REFUS NOMMÉ : une identité modifiée par l\'utilisateur n\'est pas écrasée, le conflit est écrit UNE fois au journal', () {
    final m = poste([
      {...v1Installee(), 'telephones': ['01 11 11 11 11']}
    ]);
    final avant = [for (final v in versions(m)) {...v}];
    final r = migrerIdentiteVersion2(m);
    expect(r.etat, 'refusee');
    expect(r.refus!.code, 'IDENTITE_MODIFIEE');
    expect(versions(m), avant, reason: 'aucune écriture');
    expect(migrerIdentiteVersion2(m).refus!.code, 'IDENTITE_MODIFIEE', reason: 'le refus se redit à chaque démarrage');
    final lignes = [for (final a in audit(m)) if (a['action'] == 'Identité : migration automatique refusée') a];
    expect(lignes, hasLength(1), reason: 'mais le journal ne le répète pas');
    expect(lignes.single['succes'], false);
    expect((lignes.single['apres'] as Map)['code'], 'IDENTITE_MODIFIEE');
  });

  test('un poste neuf (aucune version : le jeu livré s\'applique) et un fileul rattaché (l\'identité vient de la mère) : rien n\'est écrit', () {
    final neuf = poste([]);
    expect(migrerIdentiteVersion2(neuf).raison, 'AUCUNE_VERSION');
    expect(versions(neuf), isEmpty);
    final fileul = poste([v1Installee()]);
    final r = migrerIdentiteVersion2(fileul, fileul: true);
    expect(r.raison, 'FILEUL_ATTEND_LA_MERE');
    expect(versions(fileul), hasLength(1));
    expect(versions(fileul).single['fin'], isNull);
  });
}
