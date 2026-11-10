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

  group('les gestes de l\'écran (lot Y)', () {
    test('le circuit et « l\'agent modifie directement » se RÈGLENT au registre (version datée d\'aujourd\'hui, journalisée), par la DA et l\'administrateur seulement', () {
      final m = _magasin();
      expect(_p(m).definirCircuit('daf')['code'], 'REGLAGE_RESERVE', reason: 'le surveillant ne règle pas');
      expect(_p(m, role: 'da', nom: 'DAF').definirCircuit('tous')['code'], 'CIRCUIT_INCONNU');
      final r = _p(m, role: 'da', nom: 'DAF').definirCircuit('surveillant_puis_daf', motif: 'Sonde');
      expect(r, {'ok': true, 'circuit': 'surveillant_puis_daf', 'avant': 'surveillant'});
      expect(_p(m).circuit(), 'surveillant_puis_daf');
      expect(m.collection('audit').toutes.any((l) => l['action'] == 'Circuit de validation des présences' && (l['avant'] as Map)['circuit'] == 'surveillant' && (l['apres'] as Map)['circuit'] == 'surveillant_puis_daf'), isTrue);
      expect(_p(m, role: 'medecin', nom: 'Dr Aaa').definirAgentDirect(true)['code'], 'REGLAGE_RESERVE');
      expect(_p(m, role: 'admin', nom: 'Admin').definirAgentDirect(true)['ok'], isTrue);
      expect(_p(m).agentModifieDirectement(), isTrue);
      expect(_p(m, role: 'admin', nom: 'Admin').definirAgentDirect('oui')['valeur'], isFalse, reason: 'tout ce qui n\'est pas vrai vaut non');
    });

    test('poser une vacation : réservé au surveillant, à la DA et à l\'administrateur ; le contrôle du domaine s\'applique ; la vacation naît validée avec son régime', () {
      final m = _magasin();
      expect(_p(m, role: 'medecin', nom: 'Dr Aaa').poserVacation(employeId: 'A', date: '2026-11-20', type: 'garde')['code'], 'PLANNING_RESERVE');
      final r = _p(m).poserVacation(employeId: 'A', date: '2026-11-20', type: 'garde', observation: 'Remplace B');
      expect(r['ok'], isTrue);
      final v = m.collection('planning').toutes.single;
      expect([v['validationEtat'], v['origine'], v['statut'], v['regimeLibelle'], v['observation']], ['validee', 'poste', 'validee', 'Médecins', 'Remplace B']);
      expect(_p(m).poserVacation(employeId: 'A', date: '2026-11-21', type: 'garde')['code'], 'INCOMPATIBILITE_REPOS');
      expect(m.collection('planning').toutes.length, 1, reason: 'rien n\'est écrit si refus');
      expect(_p(m).poserVacation(employeId: 'A', date: '2026-11-20', type: 'permanence')['code'], 'DOUBLE_AFFECTATION');
      expect(_p(m).poserVacation(employeId: 'A', date: '2026-11-20', type: 'permanence', existantId: v['id'])['ok'], isTrue, reason: 'on remplace sa propre vacation');
      expect(m.collection('planning').parId(v['id'])!['type'], 'permanence');
    });

    test('retirer une vacation archive (RG-14), annulablement ; refus nommés', () {
      final m = _magasin();
      final id = m.collection('planning').inserer({'employeId': 'A', 'date': '2026-11-20', 'type': 'garde', 'statut': 'actif'}, prefixe: 'PLN').fiche['id'];
      expect(_p(m, role: 'medecin', nom: 'Dr Aaa').retirerVacation(id)['code'], 'PLANNING_RESERVE');
      expect(_p(m).retirerVacation('ABSENTE')['code'], 'VACATION_INTROUVABLE');
      final r = _p(m).retirerVacation(id);
      expect(r['ok'], isTrue);
      expect(m.collection('planning').archivees.length, 1);
      (r['annuler'] as void Function())();
      expect(m.collection('planning').actives.length, 1);
    });

    test('régulariser un pointage VALIDÉ : l\'état change, la trace est datée avec son auteur et son motif ; un pointage validé ne se modifie pas directement (garde)', () {
      final m = _magasin();
      _p(m).trancher('presences', 'PR1', 'valider');
      final col = m.collection('presences');
      expect(() => col.mettreAJour('PR1', {'etat': 'present'}), throwsA(isA<EcritureRefusee>()), reason: 'PRESENCE_VALIDEE');
      expect(col.parId('PR1')!['etat'], 'retard');
      expect(_p(m, role: 'medecin', nom: 'Dr Aaa').regulariser('PR1', {'etat': 'present', 'motif': 'x'})['code'], 'REGULARISATION_RESERVEE');
      expect(_p(m).regulariser('PR1', {'etat': 'present', 'motif': ' '})['code'], 'MOTIF_OBLIGATOIRE');
      final r = _p(m).regulariser('PR1', {'etat': 'present', 'motifCode': 'maladie', 'justificatif': 'CERT-1', 'motif': 'Certificat remis'});
      expect(r['ok'], isTrue);
      final f = col.parId('PR1')!;
      expect([f['etat'], f['motifCode'], f['justificatif']], ['present', 'maladie', 'CERT-1']);
      final trace = (f['regularisations'] as List).single as Map;
      expect([trace['le'], trace['par'], trace['etatAvant'], trace['etatApres']], ['2026-11-09', 'Surveillant de test', 'retard', 'present']);
      expect(f['validationEtat'], 'valide', reason: 'la pièce reste validée');
    });

    test('l\'avis du chef de service : consigné par un habilité, requis avant la validation d\'un ordre, un avis défavorable exige son motif', () {
      final m = Magasin({
        'audit': <M>[],
        'personnel': <M>[],
        'missions': <M>[{'id': 'OM1', 'statut': 'actif', 'agentId': 'B', 'statutMission': 'a_valider'}],
      }, 'POSTE');
      expect(_p(m).trancher('missions', 'OM1', 'valider')['code'], 'AVIS_REQUIS');
      expect(_p(m, role: 'medecin', nom: 'Dr Aaa').avisMission('OM1', {'avis': 'favorable', 'chef': 'Dr Chef'})['code'], 'AVIS_RESERVE');
      expect(_p(m).avisMission('OM1', {'avis': 'defavorable', 'chef': 'Dr Chef'})['code'], 'MOTIF_OBLIGATOIRE');
      expect(_p(m).avisMission('OM1', {'avis': 'favorable', 'chef': 'Dr Chef'})['ok'], isTrue);
      final avis = m.collection('missions').parId('OM1')!['avisChefService'] as Map;
      expect([avis['avis'], avis['chef'], avis['consignePar'], avis['le']], ['favorable', 'Dr Chef', 'Surveillant de test', '2026-11-09']);
      expect(_p(m).trancher('missions', 'OM1', 'valider')['ok'], isTrue);
      expect(m.collection('missions').parId('OM1')!['statutMission'], 'validee');
      expect(_p(m).avisMission('OM1', {'avis': 'favorable', 'chef': 'Dr Chef'})['code'], 'DEJA_TRANCHEE');
    });

    test('l\'agent retire sa propre proposition tant qu\'elle n\'est pas tranchée ; jamais celle d\'un autre', () {
      final m = _magasin();
      final id = _p(m, role: 'medecin', nom: 'Dr Aaa').proposer(type: 'ajout', date: '2026-11-25', typeVacation: 'garde', motif: 'Ok')['id'];
      expect(_p(m, role: 'medecin', nom: 'Dr Bbb').annulerProposition(id)['code'], 'PROPOSITION_D_AUTRUI');
      final r = _p(m, role: 'medecin', nom: 'Dr Aaa').annulerProposition(id);
      expect(r['ok'], isTrue);
      expect(m.collection('propositionsPlanning').parId(id)!['etat'], 'annulee');
      expect(_p(m, role: 'medecin', nom: 'Dr Aaa').annulerProposition(id)['code'], 'DEJA_TRANCHEE');
      (r['annuler'] as void Function())();
      expect(m.collection('propositionsPlanning').parId(id)!['etat'], 'proposee');
    });

    test('une version de régime individuel est FIGÉE : ni modifiée ni archivée (garde du moteur), l\'historique est numéroté', () {
      final m = _magasin();
      final da = _p(m, role: 'da', nom: 'DAF');
      expect(da.deroger(employeId: 'A', dateEffet: '2026-11-09', champs: {'repos': 'repos24'}, motif: 'Sonde')['ok'], isTrue);
      expect(da.deroger(employeId: 'A', dateEffet: '2026-12-01', champs: {}, retourCategorie: true, motif: 'Retour')['ok'], isTrue);
      final id = m.collection('regimesIndividuels').toutes.first['id'];
      expect(() => m.collection('regimesIndividuels').mettreAJour(id, {'motif': 'Réécrit'}), throwsA(isA<EcritureRefusee>()));
      expect(() => m.collection('regimesIndividuels').archiver(id), throwsA(isA<EcritureRefusee>()));
      final h = da.historique('A');
      expect([for (final x in h) x['version']], [1, 2]);
      expect([for (final x in h) x['dateEffet']], ['2026-11-09', '2026-12-01']);
      expect(h.last['retourCategorie'], isTrue);
    });
  });
}
