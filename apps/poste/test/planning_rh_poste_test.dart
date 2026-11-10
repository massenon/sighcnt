import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/planning_rh_poste.dart';

/// Lots L4 à L6 : le planning RH au poste. Les règles sont au domaine (rejouées sur les vecteurs de la maquette, `packages/domaine/test/planning_rh_test.dart`) ;
/// ici le BRANCHEMENT au magasin du poste : le circuit et « l'agent modifie directement » se lisent au registre des paramètres, une dérogation s'écrit comme une
/// version immuable, une pièce se tranche selon le circuit, une proposition ne change le planning validé qu'à sa validation.
typedef M = Map<String, Object?>;

Magasin _magasin() {
  final m = Magasin({
    'utilisateurs': <M>[],
    'audit': <M>[],
    'personnel': <M>[
      {'id': 'A', 'statut': 'actif', 'nomComplet': 'Dr Aaa', 'matricule': 'M1', 'fonction': 'medecin', 'service': 'Médecine générale'},
      {'id': 'B', 'statut': 'actif', 'nomComplet': 'Dr Bbb', 'matricule': 'M2', 'fonction': 'medecin', 'service': 'Médecine générale'},
    ],
    'regimesTravail': <M>[],
    'regimesIndividuels': <M>[],
    'planning': <M>[],
    'presences': <M>[
      {'id': 'PR1', 'statut': 'actif', 'employeId': 'B', 'date': '2026-11-09', 'etat': 'retard', 'validationEtat': 'a_valider', 'etapesFaites': <M>[]},
    ],
    'conges': <M>[
      {'id': 'CG1', 'statut': 'actif', 'employeId': 'B', 'statutConge': 'en_attente'},
    ],
    'propositionsPlanning': <M>[],
  });
  serviceParametres(m, auteur: () => 'Poste mère').semerDefauts();
  return m;
}

PlanningRhPoste _p(Magasin m, {String role = 'surveillant', String nom = 'Surveillant de test', String jour = '2026-11-09'}) =>
    PlanningRhPoste(m, auteur: () => nom, role: role, horloge: () => DateTime.parse(jour));

void main() {
  test('les défauts de la Direction : surveillant seul, l\'agent ne modifie pas directement', () {
    final p = _p(_magasin());
    expect(p.circuit(), 'surveillant');
    expect(p.agentModifieDirectement(), isFalse);
  });

  test('le circuit se lit au registre des paramètres : une version datée le change à partir de sa date', () {
    final m = _magasin();
    final s = serviceParametres(m, auteur: () => 'Poste mère', horloge: () => DateTime.parse('2026-11-09'));
    expect(s.regler('planning.circuitPresences', 'daf', '2026-11-10', motif: 'Sonde').ok, isTrue);
    expect(_p(m, jour: '2026-11-09').circuit(), 'surveillant');
    expect(_p(m, jour: '2026-11-10').circuit(), 'daf');
  });

  test('un pointage non validé ne compte pas ; le surveillant le valide seul, la pièce compte et le circuit est consigné', () {
    final m = _magasin();
    final p = _p(m);
    expect(p.compte('presences', m.collection('presences').parId('PR1')!), isFalse);
    final r = p.trancher('presences', 'PR1', 'valider');
    expect(r['ok'], isTrue);
    final f = m.collection('presences').parId('PR1')!;
    expect(f['validationEtat'], 'valide');
    expect(f['validePar'], 'Surveillant de test');
    expect(f['circuitUtilise'], 'surveillant');
    expect(p.compte('presences', f), isTrue);
  });

  test('refus nommés : la DAF n\'est pas l\'étape du circuit par défaut, un refus exige son motif, une décision ne se réécrit pas', () {
    final m = _magasin();
    expect(_p(m, role: 'da', nom: 'DAF').trancher('presences', 'PR1', 'valider')['code'], 'VALIDATION_RESERVEE');
    expect(_p(m).trancher('presences', 'PR1', 'refuser')['code'], 'MOTIF_OBLIGATOIRE');
    expect(_p(m).trancher('presences', 'PR1', 'refuser', motif: 'Pointage contesté')['ok'], isTrue);
    expect(m.collection('presences').parId('PR1')!['validationEtat'], 'refuse');
    expect(_p(m).trancher('presences', 'PR1', 'valider')['code'], 'DEJA_TRANCHEE');
  });

  test('un congé en attente (avant le circuit) est accordé par le surveillant : statutConge suit', () {
    final m = _magasin();
    expect(_p(m).trancher('conges', 'CG1', 'valider')['ok'], isTrue);
    expect(m.collection('conges').parId('CG1')!['statutConge'], 'valide');
  });

  test('la dérogation s\'écrit comme une version immuable, datée, qui ne porte que les champs renseignés ; réservée à la DA et à l\'administrateur', () {
    final m = _magasin();
    expect(_p(m).deroger(employeId: 'A', dateEffet: '2026-11-09', champs: {'repos': 'repos24'}, motif: 'Sonde')['code'], 'DEROGATION_RESERVEE');
    final r = _p(m, role: 'da', nom: 'DAF').deroger(employeId: 'A', dateEffet: '2026-11-09', champs: {'repos': 'repos24', 'honoraire': 20000}, motif: 'Sonde');
    expect(r['ok'], isTrue);
    final v = m.collection('regimesIndividuels').toutes.single;
    expect((v['champs'] as Map).keys.toSet(), {'repos', 'honoraire'});
    expect(v['version'], 1);
    final agent = m.collection('personnel').parId('A')!;
    final regime = _p(m).regimeALaDate(agent, '2026-11-09');
    expect(regime.repos, 'repos24');
    expect(regime.honoraire, 20000);
    expect(regime.cycle, 2, reason: 'le cycle suit la catégorie');
    expect(_p(m).regimeALaDate(m.collection('personnel').parId('B')!, '2026-11-09').repos, 'repos48', reason: 'l\'autre médecin garde la catégorie');
  });

  test('le repos individuel gouverne le contrôle : 24 h pour A (dérogation), 48 h pour B', () {
    final m = _magasin();
    m.collection('planning').inserer({'employeId': 'A', 'date': '2026-11-10', 'type': 'garde', 'statut': 'actif'}, prefixe: 'PLN');
    m.collection('planning').inserer({'employeId': 'B', 'date': '2026-11-10', 'type': 'garde', 'statut': 'actif'}, prefixe: 'PLN');
    expect(_p(m).controlerVacation('A', '2026-11-12', 'garde'), isNotNull, reason: '48 h de la catégorie avant la dérogation');
    _p(m, role: 'da', nom: 'DAF').deroger(employeId: 'A', dateEffet: '2026-11-09', champs: {'repos': 'repos24'}, motif: 'Sonde');
    expect(_p(m).controlerVacation('A', '2026-11-12', 'garde'), isNull);
    expect(_p(m).controlerVacation('A', '2026-11-11', 'garde')!.code, 'INCOMPATIBILITE_REPOS');
    expect(_p(m).controlerVacation('B', '2026-11-12', 'garde')!.code, 'INCOMPATIBILITE_REPOS');
    expect(_p(m).controlerVacation('A', '2026-11-10', 'permanence')!.code, 'DOUBLE_AFFECTATION');
  });

  test('l\'agent propose : le planning validé ne bouge pas ; le surveillant valide ; le contrôle est refait à la validation', () {
    final m = _magasin();
    final r = _p(m, role: 'medecin', nom: 'Dr Aaa').proposer(type: 'ajout', date: '2026-11-20', typeVacation: 'garde', motif: 'Je prends cette garde');
    expect(r['ok'], isTrue);
    expect(r['direct'], isFalse);
    expect(m.collection('planning').toutes, isEmpty, reason: 'une proposition ne change rien tant qu\'elle n\'est pas validée');
    final id = r['id'];
    expect(_p(m, role: 'medecin', nom: 'Dr Bbb').trancherProposition(id, 'valider')['code'], 'VALIDATION_RESERVEE');
    expect(_p(m, role: 'surveillant', nom: 'Dr Aaa').trancherProposition(id, 'valider')['code'], 'AUTO_VALIDATION');
    expect(_p(m).trancherProposition(id, 'valider')['ok'], isTrue);
    final v = m.collection('planning').toutes.single;
    expect(v['employeId'], 'A');
    expect(v['origine'], 'proposition');
    expect(v['validationEtat'], 'validee');
    expect(v['regimeLibelle'], 'Médecins');
    expect(_p(m).trancherProposition(id, 'valider')['code'], 'DEJA_TRANCHEE');
  });

  test('une proposition qui violerait le repos est refusée à la proposition (rien d\'enregistré) ; chacun ne voit que les siennes', () {
    final m = _magasin();
    m.collection('planning').inserer({'employeId': 'A', 'date': '2026-11-20', 'type': 'garde', 'statut': 'actif'}, prefixe: 'PLN');
    final trop = _p(m, role: 'medecin', nom: 'Dr Aaa').proposer(type: 'ajout', date: '2026-11-21', typeVacation: 'garde', motif: 'Trop tôt');
    expect(trop['code'], 'INCOMPATIBILITE_REPOS');
    expect(m.collection('propositionsPlanning').toutes, isEmpty);
    _p(m, role: 'medecin', nom: 'Dr Aaa').proposer(type: 'ajout', date: '2026-11-25', typeVacation: 'garde', motif: 'Ok');
    expect(_p(m, role: 'medecin', nom: 'Dr Aaa').propositionsVisibles().length, 1);
    expect(_p(m, role: 'medecin', nom: 'Dr Bbb').propositionsVisibles(), isEmpty);
    expect(_p(m, role: 'medecin', nom: 'Inconnu').propositionsVisibles(), isEmpty);
    expect(_p(m).propositionsVisibles().length, 1);
  });

  test('un échange passe toujours par la validation, même en application directe ; les deux vacations changent d\'agent', () {
    final m = _magasin();
    final s = serviceParametres(m, auteur: () => 'Poste mère', horloge: () => DateTime.parse('2026-11-09'));
    expect(s.regler('planning.agentModifieDirectement', true, '2026-11-10', motif: 'Sonde').ok, isTrue);
    final col = m.collection('planning');
    final a = col.inserer({'employeId': 'A', 'employe': 'Dr Aaa', 'date': '2026-11-20', 'type': 'garde', 'statut': 'actif'}, prefixe: 'PLN').fiche['id'];
    final b = col.inserer({'employeId': 'B', 'employe': 'Dr Bbb', 'date': '2026-12-01', 'type': 'garde', 'statut': 'actif'}, prefixe: 'PLN').fiche['id'];
    final direct = _p(m, role: 'medecin', nom: 'Dr Aaa', jour: '2026-11-10');
    expect(direct.agentModifieDirectement(), isTrue);
    final ajout = direct.proposer(type: 'ajout', date: '2026-12-10', typeVacation: 'garde', motif: 'Direct');
    expect(ajout['direct'], isTrue);
    expect(col.actives.any((f) => f['modifieDirectement'] == true && f['origine'] == 'agent'), isTrue);
    expect(direct.proposer(type: 'ajout', date: '2026-12-11', typeVacation: 'garde', motif: 'Trop tôt')['code'], 'INCOMPATIBILITE_REPOS');
    final ech = direct.proposer(type: 'echange', vacationId: '$a', contrepartieId: '$b', motif: 'Échange');
    expect(ech['ok'], isTrue);
    expect(ech['direct'], isFalse);
    expect(_p(m, jour: '2026-11-10').trancherProposition(ech['id'], 'valider')['ok'], isTrue);
    expect(col.parId(a)!['employeId'], 'B');
    expect(col.parId(b)!['employeId'], 'A');
    expect(col.parId(a)!['echangeAvec'], 'Dr Aaa');
  });

  test('un compte sans agent ne propose pas (AGENT_NON_IDENTIFIE)', () {
    final m = _magasin();
    expect(_p(m, role: 'medecin', nom: 'Compte inconnu').proposer(type: 'retrait', vacationId: 'X', motif: 'x')['code'], 'AGENT_NON_IDENTIFIE');
  });
}
