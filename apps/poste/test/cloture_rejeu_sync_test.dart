import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';

import 'aide_grand_stock.dart';

/// LOT CLO-2 (C5, E3) : BANC À DEUX POSTES contre la VRAIE mère Dart. Un fileul qui n'a pas reçu le statut d'un exercice écrit une pièce datée de cet exercice ; la mère, qui fait
/// foi, la REFUSE au rejeu en nommant le refus (code, motif, geste). Le fileul n'est JAMAIS bloqué : ses autres écritures passent, la pièce refusée est mise de côté et dite.
Fiche exercice(int a, String etat) => {'id': 'EXO-$a', 'annee': a, 'debut': '$a-01-01', 'fin': '$a-12-31', 'statut': 'actif', 'etat': etat, 'source': 'journal'};
Fiche piece(String num, String date, {String origine = 'Facturation', String journal = 'VTE'}) =>
    {'numero': num, 'date': date, 'journal': journal, 'compte': '706000', 'debit': 0, 'credit': 10, 'statut': 'validee', 'origine': origine, 'libelle': 'Pièce $num'};

Future<void> tours(Clinique c, int n) async {
  for (var i = 0; i < n; i++) {
    await c.tour();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

bool laMereA(Clinique c, String num) => c.mm.collection('ecritures').toutes.any((e) => e['numero'] == num);

void main() {
  test('E3 : un fileul qui n\'a pas reçu le statut écrit une pièce de l\'exercice clos ; la mère la REFUSE au rejeu (refus nommé), le fileul reçoit le statut et n\'est pas bloqué', () async {
    final c = Clinique(9441, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'comptable', 'COMPTABLE UN');
      await c.tour();
      // L'exercice 2026 est ouvert partout (identité commune EXO-2026) ; 2027 aussi.
      for (final m in [c.mm, f1.m]) {
        m.collection('exercices').inserer(exercice(2026, 'ouvert'));
        m.collection('exercices').inserer(exercice(2027, 'ouvert'));
      }
      await tours(c, 3);
      // La mère clôt 2026. Le fileul, qui n'a pas encore le statut, écrit sa pièce du 01/03/2026 : sa garde locale la laisse passer (il croit l'exercice ouvert).
      c.mm.collection('exercices').mettreAJour('EXO-2026', {'etat': 'clos', 'valideLe': '2026-11-14T10:00:00.000Z', 'validePar': 'Direction'});
      expect(() => f1.m.collection('ecritures').inserer(piece('VTE-2026-E3A', '2026-03-01')), returnsNormally, reason: 'statut non reçu : la garde locale ne peut pas refuser');
      await c.converger(() => f1.m.collection('exercices').parId('EXO-2026')?['etat'] == 'clos', 'le fileul reçoit le statut', apres: 4);
      // 1. La mère n'a PAS appliqué la pièce, elle l'a refusée en nommant.
      expect(laMereA(c, 'VTE-2026-E3A'), isFalse, reason: 'la mère refuse la pièce datée d\'un exercice clos au rejeu');
      final refus = await f1.moteur.refusees();
      expect(refus, hasLength(1));
      expect(refus.single['code'], 'exercice_clos');
      expect('${refus.single['motif']}', allOf(contains('REFUSÉE au rejeu'), contains('Exercice 2026 clôturé')));
      expect('${refus.single['geste']}', contains('exercice ouvert'));
      // 2. Le fileul reçoit le statut : sa garde locale refuse désormais sa propre saisie datée de 2026.
      expect(() => f1.m.collection('ecritures').inserer(piece('VTE-2026-E3B', '2026-03-02')), throwsA(isA<EcritureRefusee>()));
      // 3. NON BLOQUANT : le travail courant du fileul (exercice ouvert 2027) passe et arrive à la mère.
      f1.m.collection('ecritures').inserer(piece('VTE-2027-E3C', '2027-01-05'));
      await c.converger(() => laMereA(c, 'VTE-2027-E3C'), 'une pièce de l\'exercice ouvert arrive à la mère', apres: 2);
      expect(laMereA(c, 'VTE-2027-E3C'), isTrue);
      expect(laMereA(c, 'VTE-2026-E3A'), isFalse, reason: 'rejouée plusieurs fois, la pièce refusée n\'entre toujours pas');
      // 4. Les pièces de la clôture elle-même passent : un fileul qui clôt pose sa pièce CL datée de l'exercice clos.
      final cl = {...piece('CL-2026-00001', '2026-12-31', origine: 'Clôture : résultat', journal: 'CL'), 'origineCloture': 'cl'};
      expect(cpcRefusRejeuPiece([exercice(2026, 'clos')], cl), isNull);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('E3 : un exercice EN CLÔTURE refuse la pièce d\'un module reçue d\'un autre poste, mais accepte la saisie manuelle (l\'inventaire : le rôle a été contrôlé sur son poste)', () {
    final exo = [exercice(2026, 'en_cloture')];
    expect(cpcRefusRejeuPiece(exo, piece('A', '2026-05-05'))?.code, 'exercice_en_cloture');
    expect(cpcRefusRejeuPiece(exo, piece('B', '2026-05-05', origine: 'Saisie manuelle', journal: 'OD')), isNull);
    expect(cpcRefusRejeuPiece([exercice(2026, 'clos')], piece('C', '2026-05-05', origine: 'Saisie manuelle', journal: 'OD'))?.code, 'exercice_clos');
    expect(cpcRefusRejeuPiece([exercice(2026, 'ouvert')], piece('D', '2026-05-05')), isNull);
    expect(cpcRefusRejeuPiece(const [], piece('E', '2026-05-05')), isNull, reason: 'exercice inconnu : ouvert, rien n\'est supposé clos');
  });
}
