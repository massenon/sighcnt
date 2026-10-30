// Le ruban Dart doit rendre EXACTEMENT ce que N.tree(rôle) rend dans la maquette, pour chaque rôle.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> json(String chemin) => (jsonDecode(File(chemin).readAsStringSync()) as Map).cast<String, Object?>();

void main() {
  final manifeste = Manifeste.depuisJson(json('../referentiels/data/manifeste.json'));
  final matrice = MatriceDroits.depuisJson(json('../rbac/data/rbac.json'));
  final cas = ((json('test/vecteurs/ruban.json'))['cas'] as List).cast<Map>();

  for (final c in cas) {
    final role = '${c['role']}';
    test('ruban du rôle « $role » = N.tree($role) de la maquette', () {
      final attendu = [
        for (final d in (c['domaines'] as List))
          for (final r in (d as Map)['rangees'] as List) ['${d['domaine']}', '${(r as Map)['code']}', '${r['label']}', ...(r['ecrans'] as List).cast<String>()],
      ];
      final obtenu = [
        for (final d in manifeste.ruban(matrice, role, estMere: true))
          for (final r in d.rangees) [d.nom, r.code, r.label, ...r.ecrans.map((e) => e.id)],
      ];
      expect(obtenu, attendu);
    });
  }

  test('un poste FILEUL n\'a jamais le domaine « Poste mère », même pour l\'administrateur', () {
    expect(manifeste.ruban(matrice, 'admin', estMere: true).map((d) => d.nom), contains('Poste mère'));
    expect(manifeste.ruban(matrice, 'admin', estMere: false).map((d) => d.nom), isNot(contains('Poste mère')));
  });

  test('« Poste mère » ne s\'ouvre pas au caissier parce que le poste est la mère : les droits restent ceux de la matrice', () {
    expect(manifeste.ruban(matrice, 'caissier', estMere: true).map((d) => d.nom), isNot(contains('Poste mère')));
  });

  test('les 22 modules complémentaires de la mère sont au manifeste', () {
    final mere = manifeste.tousLesEcrans.where((e) => e.id.startsWith('mere-')).toList();
    expect(mere.length, 22);
  });

  test('un rôle archivé n\'a aucun ruban (RG-14)', () {
    expect(manifeste.ruban(matrice, 'pharmacien', estMere: true), isEmpty);
  });
}
