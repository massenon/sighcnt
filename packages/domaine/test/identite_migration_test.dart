// LOT IDENT-MIG (Direction, 16/11/2026) : un poste déjà installé qui n'a que la version 1 de `identiteLegale` reçoit la version 2 (RCCM à jour, effet le 16/11/2026) ;
// la version 1 est close au 15/11/2026 sans être réécrite ; signé, idempotent, jamais d'écrasement, refus nommé en cas de conflit.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

/// La version 1 TELLE QU'UN POSTE D'AVANT LA VERSION 2 LA TIENT : jamais close (`fin` nul).
M v1Installee() => {...cfbSemenceIdentite(), 'fin': null};

/// Applique ce que la migration commande, comme le fait le poste.
List<M> appliquer(List<M> versions, CfbMigrationIdentite r) {
  expect(r.migree, isTrue, reason: '${r.refus ?? r.raison}');
  return [
    for (final v in versions) if (v['id'] == r.precedenteId) {...v, ...r.patchPrecedente!} else v,
    r.fiche!,
  ];
}

void main() {
  final maintenant = DateTime.utc(2026, 11, 16, 8, 30);

  test('un poste qui n\'a que la version 1 reçoit la version 2 ; la version 1 n\'est close que par sa date de fin, rien d\'autre ne bouge', () {
    final avant = [v1Installee()];
    final r = cfbMigrerIdentiteV2(avant, maintenant: maintenant);
    expect(r.migree, isTrue);
    final v2 = r.fiche!;
    expect(v2['version'], 2);
    expect(v2['id'], 'IDL002');
    expect(v2['debut'], '2026-11-16');
    expect(v2['fin'], isNull);
    expect(v2['rccm'], 'NAT/2021/M02-020');
    expect(v2['creePar'], cfbActeurMigrationIdentite, reason: 'signée');
    expect(v2['valideLe'], isNull, reason: 'la version 2 n\'est pas validée à la place de la Direction');
    expect(r.precedenteId, 'IDL001');
    expect(r.patchPrecedente!.keys.toSet(), {'fin', 'modifieLe', 'modifiePar'});
    expect(r.patchPrecedente!['fin'], '2026-11-15');
    expect(r.patchPrecedente!['modifiePar'], cfbActeurMigrationIdentite);
    final apres = appliquer(avant, r);
    final v1 = apres.firstWhere((v) => v['id'] == 'IDL001');
    for (final k in avant.single.keys) {
      if (k == 'fin') continue;
      expect(v1[k], avant.single[k], reason: 'la version 1 n\'est pas réécrite : $k');
    }
    expect(v1['rccm'], 'RB/NAT/2016-B-268', reason: 'l\'ancien RCCM reste celui de la version 1');
  });

  test('les pièces lisent l\'identité de LEUR date : l\'ancien RCCM jusqu\'au 15/11/2026, le nouveau dès le 16/11/2026', () {
    final apres = appliquer([v1Installee()], cfbMigrerIdentiteV2([v1Installee()], maintenant: maintenant));
    expect(cfbIdentiteALaDate(apres, DateTime(2026, 11, 15))!['rccm'], 'RB/NAT/2016-B-268');
    expect(cfbIdentiteALaDate(apres, DateTime(2026, 11, 16))!['rccm'], 'NAT/2021/M02-020');
    expect(cfbIdentiteALaDate(apres, DateTime(2025, 3, 1))!['rccm'], 'RB/NAT/2016-B-268');
  });

  test('IDEMPOTENT : une seconde passe ne fait rien', () {
    final une = appliquer([v1Installee()], cfbMigrerIdentiteV2([v1Installee()], maintenant: maintenant));
    final deux = cfbMigrerIdentiteV2(une, maintenant: maintenant.add(const Duration(days: 1)));
    expect(deux.etat, 'sans_objet');
    expect(deux.raison, 'DEJA_A_JOUR');
    expect(deux.fiche, isNull);
  });

  test('une version 1 déjà close au 15/11/2026 (jeu récent) : la version 2 s\'ajoute, la version 1 n\'est pas touchée', () {
    final r = cfbMigrerIdentiteV2([cfbSemenceIdentite()], maintenant: maintenant);
    expect(r.migree, isTrue);
    expect(r.precedenteId, isNull);
    expect(r.patchPrecedente, isNull);
  });

  test('JAMAIS ÉCRASÉ : une version 2 déjà présente (posée par l\'agent, archivée ou semée) : rien à faire', () {
    final posee = {...cfbSemenceIdentiteV2(id: 'IDL007'), 'rccm': 'NAT/2030/X', 'debut': '2026-12-01'};
    for (final versions in [
      [cfbSemenceIdentite(), cfbSemenceIdentiteV2()],
      [v1Installee(), posee],
      [v1Installee(), {...cfbSemenceIdentiteV2(), 'statut': 'archive'}],
    ]) {
      final r = cfbMigrerIdentiteV2(versions, maintenant: maintenant);
      expect(r.etat, 'sans_objet');
      expect(r.raison, 'DEJA_A_JOUR');
    }
  });

  test('aucune version du tout : sans objet (le jeu livré s\'applique), aucune écriture', () {
    final r = cfbMigrerIdentiteV2(const [], maintenant: maintenant);
    expect(r.etat, 'sans_objet');
    expect(r.raison, 'AUCUNE_VERSION');
  });

  test('REFUS NOMMÉ : une identité modifiée par l\'utilisateur n\'est jamais écrasée (champ différent, RCCM déjà changé à la main, fiche réécrite)', () {
    final telephone = {...v1Installee(), 'telephones': ['01 11 11 11 11']};
    final r = cfbMigrerIdentiteV2([telephone], maintenant: maintenant);
    expect(r.etat, 'refusee');
    expect(r.refus!.code, 'IDENTITE_MODIFIEE');
    expect(r.refus!.motif, contains('telephones'));
    expect(r.refus!.geste, isNotEmpty);
    expect(r.fiche, isNull);
    expect(r.patchPrecedente, isNull);
    final rccm = cfbMigrerIdentiteV2([{...v1Installee(), 'rccm': 'NAT/2021/M02-020'}], maintenant: maintenant);
    expect(rccm.refus!.code, 'IDENTITE_MODIFIEE');
    expect(rccm.refus!.motif, contains('rccm'));
    final reecrite = cfbMigrerIdentiteV2([{...v1Installee(), 'modifieLe': '2026-11-10T09:00:00.000Z', 'modifiePar': 'DA'}], maintenant: maintenant);
    expect(reecrite.refus!.code, 'IDENTITE_MODIFIEE');
  });

  test('REFUS NOMMÉ : version 1 close à une autre date, en double, absente, ou fiche IDL002 déjà prise par autre chose', () {
    expect(cfbMigrerIdentiteV2([{...v1Installee(), 'fin': '2026-10-01'}], maintenant: maintenant).refus!.code, 'IDENTITE_FIN_DIFFERENTE');
    expect(cfbMigrerIdentiteV2([v1Installee(), {...v1Installee(), 'id': 'IDL009'}], maintenant: maintenant).refus!.code, 'IDENTITE_VERSION_1_EN_DOUBLE');
    expect(cfbMigrerIdentiteV2([{...v1Installee(), 'statut': 'archive'}], maintenant: maintenant).refus!.code, 'IDENTITE_VERSION_1_ABSENTE');
    expect(cfbMigrerIdentiteV2([v1Installee(), {...v1Installee(), 'id': 'IDL002', 'statut': 'archive'}], maintenant: maintenant).refus!.code, 'IDENTITE_ID_PRIS');
  });
}
