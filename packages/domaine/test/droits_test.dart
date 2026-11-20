import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final brut = jsonDecode(File('../rbac/data/rbac.json').readAsStringSync())
      as Map<String, Object?>;
  final m = MatriceDroits.depuisJson(brut);
  final parRole = (brut['parRole'] as Map).cast<String, Map>();

  test(
      'PARITÉ EXHAUSTIVE : chaque couple rôle × écran de la matrice extraite se relit à l\'identique',
      () {
    var n = 0;
    parRole.forEach((role, ecrans) {
      ecrans.forEach((ecran, t) {
        final d = m.droit(role, '$ecran');
        expect([d.voir, d.editer, d.annuler], [t[0] == 1, t[1] == 1, t[2] == 1],
            reason: '$role → $ecran');
        expect([
          m.peutVoir(role, '$ecran'),
          m.peutEditer(role, '$ecran'),
          m.peutAnnuler(role, '$ecran')
        ], [
          t[0] == 1,
          t[0] == 1 && t[1] == 1,
          t[0] == 1 && t[2] == 1
        ], reason: '$role → $ecran (raccourcis)');
        n++;
      });
    });
    expect(n, greaterThan(1000));
  });

  test('tout ce qui n\'est pas listé est REFUSÉ : écran inconnu, rôle inconnu',
      () {
    expect(m.droit('caissier', 'ecran-inexistant'), Droit.aucun);
    expect(m.droit('role-invente', 'm8-caisse'), Droit.aucun);
    expect(m.peutVoir('role-invente', 'm8-caisse'), isFalse);
    expect(m.roleConnu('role-invente'), isFalse);
  });

  test('rôles archivés (RG-14) : aucun écran, mais le rôle reste connu', () {
    for (final r in ['pharmacien', 'rh']) {
      expect(m.roleConnu(r), isTrue, reason: r);
      expect(m.estArchive(r), isTrue, reason: r);
      expect(m.ecransVisibles(r), isEmpty, reason: r);
      expect(m.peutVoir(r, 'm8-caisse'), isFalse, reason: r);
    }
  });

  test('décisions de la Direction (miroir de packages/rbac/test) : caissier',
      () {
    expect(m.peutVoir('caissier', 'm6-stock-gros'), isFalse);
    expect(m.peutVoir('caissier', 'm12-depenses'), isFalse);
    expect(m.droit('caissier', 'm8-facture-avoir'),
        const Droit(voir: true, editer: false, annuler: false));
    expect(m.droit('caissier', 'm8-caisse'),
        const Droit(voir: true, editer: true, annuler: false));
    expect(m.droit('caissier', 'm8-facture-avoir').lectureSeule, isTrue);
  });

  test(
      'biologiste (id laborantin) : pas de bon de livraison ; échographiste : exécute l\'imagerie, voit pas la caisse',
      () {
    expect(m.peutVoir('laborantin', 'm7-livraisons'), isFalse);
    expect(m.peutEditer('echographiste', 'm2-imagerie'), isTrue);
    expect(m.peutVoir('echographiste', 'm8-caisse'), isFalse);
  });

  test('« éditer » et « annuler » ne valent jamais sans « voir »', () {
    parRole.forEach((role, ecrans) {
      for (final ecran in ecrans.keys) {
        final d = m.droit(role, '$ecran');
        if (!d.voir) {
          expect(m.peutEditer(role, '$ecran'), isFalse);
          expect(m.peutAnnuler(role, '$ecran'), isFalse);
        }
      }
    });
  });

  test('ecransVisibles = exactement les écrans à droit « voir »', () {
    final vus = m.ecransVisibles('medecin');
    expect(vus, isNotEmpty);
    for (final e in vus) {
      expect(m.peutVoir('medecin', e), isTrue);
    }
  });
}
