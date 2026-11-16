// LOT VAL (Direction, 16/11/2026) : plus de liste de rôles dans les moteurs, des gestes réservés de la fiche RBAC lus À CHAUD ; sans fiche branchée, le défaut d'origine décide comme avant.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final json = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final m = MatriceDroits.depuisJson(json);
  // Une fiche qui retire des gestes : surcharge locale au-dessus de la matrice engendrée.
  final retires = <String>{};
  bool lecteur(String role, String geste) => !retires.contains('$role/$geste') && m.droitGeste(role, geste);

  setUp(() {
    retires.clear();
    gesInstaller();
  });
  tearDown(() => gesInstaller());

  test('sans fiche branchée, les listes d\'origine décident comme avant', () {
    expect(valPeut(valFamille('actes')!, 'da'), isTrue);
    expect(valPeut(valFamille('actes')!, 'comptable'), isFalse);
    expect(valVoitTout('direction'), isTrue);
    expect(valVoitTout('medecin'), isFalse);
    expect(estArbitre('da'), isTrue);
    expect(tarPeutDatePassee('direction'), isTrue);
    expect(aibMotifEcriture(role: 'comptable', libelleRole: 'C'), isNull);
  });

  test('la matrice engendrée porte, pour chaque famille, le défaut du registre (une source, jamais deux)', () {
    gesInstaller(lecteur: lecteur, roles: () => m.matriceGestes.roles);
    for (final f in valFamilles) {
      if (f.id == 'prix') continue;
      expect(valRolesDe(f)..sort(), ([...f.roles]..sort()), reason: f.id);
    }
    expect(aibRolesEcriture.every((r) => gesDroit(r, aibGesteEcrire, const [])), isTrue);
    expect(gesRoles(aibGesteEcrire, aibRolesEcriture), aibRolesEcriture, reason: 'détenteurs d\'origine dans l\'ordre du manifeste');
  });

  test('retirer un geste à un rôle le ferme dans les moteurs, et le refus CITE le droit', () {
    gesInstaller(lecteur: lecteur, roles: () => m.matriceGestes.roles);
    retires.addAll(['da/valider_famille_actes', 'comptable/ecrire_bareme_aib', 'da/valider_configuration_fiscale', 'admin/valider_etape_surveillant', 'caissier/retransmettre_mecef']);
    expect(valPeut(valFamille('actes')!, 'da'), isFalse);
    expect(valPeut(valFamille('actes')!, 'admin'), isTrue);
    expect(valRolesDe(valFamille('actes')!), ['direction', 'admin']);
    final refus = aibMotifEcriture(role: 'comptable', libelleRole: 'Comptable')!;
    expect(refus['code'], 'AIB_ECRITURE_RESERVEE');
    expect(refus['droit'], aibGesteEcrire);
    expect('${refus['motif']}', contains(aibGesteEcrire));
    expect(cfbControleValidation(role: 'da')!.code, 'VALIDATION_RESERVEE');
    expect(cfbControleValidation(role: 'da')!.motif, contains(cfbGesteValider));
    expect(cfbControleValidation(role: 'direction'), isNull);
    expect(refusRetransmission({'statutMecef': 'rejete'}, 'caissier')!.code, 'RETRANSMISSION_INTERDITE');
    expect(refusRetransmission({'statutMecef': 'rejete', 'retransmissions': 1}, 'da'), isNull);
    retires.add('da/retransmettre_mecef_sans_limite');
    final limite = refusRetransmission({'statutMecef': 'rejete', 'retransmissions': 1}, 'da')!;
    expect(limite.code, 'RETRANSMISSION_RESERVEE');
    expect(limite.motif, contains(mecefGesteSansLimite));
    expect(refusRetransmission({'statutMecef': 'rejete', 'retransmissions': 0}, 'da'), isNull, reason: 'la première retransmission reste permise');
  });

  test('trancher et valider un flux de pont sont des gestes de la fiche ; la mère (appareil) tranche toujours', () {
    final droits = droitsDepuisMatrice(peutEditer: m.peutEditer, peutAnnuler: m.peutAnnuler, peutGeste: lecteur);
    OperationPair op(String type, String? role) => OperationPair(id: 'x', appareil: 'a', hlc: 1, collection: 'besoins', fiche: 'f', type: type, role: role);
    expect(droits(op('trancher', 'da')), isTrue);
    expect(droits(op('valider', 'da')), isTrue);
    expect(droits(op('valider', 'direction')), isFalse);
    retires.addAll(['da/trancher_pair', 'da/valider_pair']);
    expect(droits(op('trancher', 'da')), isFalse);
    expect(droits(op('valider', 'da')), isFalse);
    expect(droits(op('trancher', 'mere')), isTrue);
    expect(droits(op('valider', 'admin')), isTrue);
  });
}
