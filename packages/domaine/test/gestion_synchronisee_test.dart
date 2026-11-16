import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LOT SYNC-CFG (décision 26) : l'identité commune par le contenu des budgets, immobilisations et couvertures d'assurance, et le refus au rejeu du budget d'un exercice clos.
Map<String, Object?> exo(int a, String etat) => {'id': 'EXO-$a', 'annee': a, 'debut': '$a-01-01', 'fin': '$a-12-31', 'statut': 'actif', 'etat': etat};

void main() {
  group('identité commune par le contenu', () {
    test('budget : exercice, centre, nature ; le montant et le numéro n\'y entrent pas ; la casse et les espaces de la nature non plus', () {
      final a = identiteSyncGestion('budgets', {'exercice': 2026, 'centreCout': 'laboratoire', 'nature': 'Charges de fonctionnement', 'prevu': 1, 'reference': 'BG-2026-001'});
      final b = identiteSyncGestion('budgets', {'exercice': 2026, 'centreCout': 'laboratoire', 'nature': '  charges   de fonctionnement ', 'prevu': 9, 'reference': 'BG-2026-007'});
      expect(a, isNotNull);
      expect(a, startsWith('BUD-2026-'));
      expect(b, a);
      expect(identiteSyncGestion('budgets', {'exercice': 2027, 'centreCout': 'laboratoire', 'nature': 'Charges de fonctionnement'}), isNot(a), reason: 'autre exercice');
      expect(identiteSyncGestion('budgets', {'exercice': 2026, 'centreCout': 'pharmacie', 'nature': 'Charges de fonctionnement'}), isNot(a), reason: 'autre centre');
      expect(identiteSyncGestion('budgets', {'exercice': 2026, 'centreCout': 'laboratoire'}), isNull, reason: 'clé incomplète : identité propre au poste, jamais inventée');
    });

    test('immobilisation : désignation, jour d\'acquisition, valeur', () {
      final a = identiteSyncGestion('immobilisations', {'designation': 'Autoclave', 'dateAcquisition': '2025-03-01', 'valeurAcquisition': 1500000, 'reference': 'IM-001'});
      expect(a, startsWith('IMM-'));
      expect(identiteSyncGestion('immobilisations', {'designation': 'autoclave ', 'dateAcquisition': '2025-03-01T00:00:00.000', 'valeurAcquisition': 1500000, 'reference': 'IM-009'}), a);
      expect(identiteSyncGestion('immobilisations', {'designation': 'Autoclave', 'dateAcquisition': '2025-03-01', 'valeurAcquisition': 1500001}), isNot(a));
      expect(identiteSyncGestion('immobilisations', {'designation': '', 'dateAcquisition': '2025-03-01'}), isNull);
    });

    test('couverture : l\'assuré par son identité de synchronisation (pas son identifiant local) et la date d\'effet', () {
      final a = identiteSyncGestion('couverturesAssurance', {'patientId': 'PAT00012', 'debut': '2026-11-01', 'tauxPriseEnCharge': 80}, patientSync: 'F1-PAT00012');
      final b = identiteSyncGestion('couverturesAssurance', {'patientId': 'F1-PAT00012', 'debut': '2026-11-01', 'tauxPriseEnCharge': 70}, patientSync: 'F1-PAT00012');
      expect(a, startsWith('COU-'));
      expect(b, a, reason: 'le même assuré vu de deux postes (identifiants locaux différents) : même identité');
      expect(identiteSyncGestion('couverturesAssurance', {'patientId': 'PAT00012', 'debut': '2026-12-01'}, patientSync: 'F1-PAT00012'), isNot(a), reason: 'autre date d\'effet : une autre version');
      expect(identiteSyncGestion('couverturesAssurance', {'patientId': 'PAT0003', 'debut': '2026-11-01'}), identiteSyncGestion('couverturesAssurance', {'patientId': 'PAT0003', 'debut': '2026-11-01'}, patientSync: ''));
      expect(identiteSyncGestion('couverturesAssurance', {'debut': '2026-11-01'}), isNull);
    });

    test('lot PLAN-INDIV : un planning personnalisé a l\'identité de l\'agent et de la date d\'effet (le motif, le numéro de version et les jours n\'y entrent pas)', () {
      final a = identiteSyncGestion('planningsPersonnalises', {'matricule': '1', 'employeId': 'EMP01', 'dateEffet': '2026-12-01', 'motif': 'x', 'version': 1});
      final b = identiteSyncGestion('planningsPersonnalises', {'matricule': ' 1 ', 'employeId': 'EMPX', 'dateEffet': '2026-12-01T00:00:00.000', 'motif': 'autre', 'version': 2});
      expect(a, isNotNull);
      expect(a, startsWith('PPE-'));
      expect(b, a);
      expect(identiteSyncGestion('planningsPersonnalises', {'matricule': '1', 'dateEffet': '2026-12-02'}), isNot(a));
      expect(identiteSyncGestion('planningsPersonnalises', {'matricule': '2', 'dateEffet': '2026-12-01'}), isNot(a));
      expect(identiteSyncGestion('planningsPersonnalises', {'dateEffet': '2026-12-01'}), isNull, reason: 'agent absent : identité propre au poste');
      expect(collectionsGestionJamaisMobile, contains('planningsPersonnalises'));
    });

    test('une autre collection n\'a pas d\'identité par le contenu', () {
      expect(identiteSyncGestion('patients', {'code': 'CNT/1/26'}), isNull);
      expect(collectionsGestionSynchronisees, {'budgets', 'immobilisations', 'couverturesAssurance', 'planningsPersonnalises'});
      expect(collectionsGestionJamaisMobile, containsAll(collectionsGestionSynchronisees), reason: 'RG-13 : aucune des quatre vers un téléphone');
    });
  });

  group('refus au rejeu du budget d\'un exercice clos', () {
    test('exercice clos : refus nommé (code, motif, geste) ; ouvert ou en clôture : accepté (même garde que le magasin)', () {
      final r = cpcRefusRejeuBudget([exo(2026, 'clos')], {'reference': 'BG-2026-009', 'exercice': 2026});
      expect(r, isNotNull);
      expect(r!.code, 'exercice_clos');
      expect(r.motif, allOf(contains('Budget BG-2026-009'), contains('REFUSÉ au rejeu'), contains('Exercice 2026 clôturé')));
      expect(r.geste, contains('exercice ouvert'));
      expect(cpcRefusRejeuBudget([exo(2026, 'ouvert')], {'exercice': 2026}), isNull);
      expect(cpcRefusRejeuBudget([exo(2026, 'en_cloture')], {'exercice': 2026}), isNull, reason: 'un exercice en clôture reçoit encore ses budgets (cpcGardeBudgets)');
      expect(cpcRefusRejeuBudget(const [], {'exercice': 2027}), isNull, reason: 'exercice inconnu : ouvert');
      expect(cpcRefusRejeuBudget([exo(2026, 'clos')], {'exercice': 2026})!.motif, startsWith('Budget reçu'));
    });
  });
}
