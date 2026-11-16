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

    test('lot PTA : le plan annuel et son adoption ont une identité par le contenu (exercice, libellé, version ; exercice) ; une révision est une AUTRE identité', () {
      final a = identiteSyncGestion('planAnnuel', {'exercice': 2026, 'action': 'Audit qualité', 'version': 1});
      expect(a, startsWith('PTA-2026-'));
      expect(identiteSyncGestion('planAnnuel', {'exercice': 2026, 'action': '  audit   QUALITÉ ', 'version': 1}), a, reason: 'libellé normalisé');
      expect(identiteSyncGestion('planAnnuel', {'exercice': 2026, 'action': 'Audit qualité', 'version': 2}), isNot(a), reason: 'la version 2 ne fusionne pas avec la version qu\'elle remplace');
      expect(identiteSyncGestion('planAnnuel', {'exercice': 2027, 'action': 'Audit qualité', 'version': 1}), isNot(a));
      expect(identiteSyncGestion('planAnnuel', {'exercice': 2026, 'action': ''}), isNull);
      expect(identiteSyncGestion('adoptionsPlan', {'exercice': 2026}), 'ADP-2026');
      expect(identiteSyncGestion('adoptionsPlan', {}), isNull);
      expect(collectionsGestionJamaisMobile, containsAll({'planAnnuel', 'adoptionsPlan', 'referentielsPlan', 'reglagesPlan'}), reason: 'RG-13 : rien du plan vers un téléphone');
      expect(paCollectionsConfiguration, {'referentielsPlan', 'reglagesPlan'});
    });

    test('une autre collection n\'a pas d\'identité par le contenu', () {
      expect(identiteSyncGestion('patients', {'code': 'CNT/1/26'}), isNull);
      expect(collectionsGestionSynchronisees, {'budgets', 'immobilisations', 'couverturesAssurance', 'planAnnuel', 'adoptionsPlan'}, reason: 'le lot PTA y ajoute le plan annuel et son adoption');
      expect(collectionsGestionJamaisMobile, containsAll(collectionsGestionSynchronisees), reason: 'RG-13 : aucune des trois vers un téléphone');
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
