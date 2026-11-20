import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';

import 'aide_grand_stock.dart';

/// LOT SYNC-CFG (décision 26 de la Direction, 15/11/2026) : les BUDGETS, les IMMOBILISATIONS et les COUVERTURES D'ASSURANCE se synchronisent, contre la VRAIE mère Dart et de VRAIS moteurs de
/// fileul (la mère arrêtée pour de vrai) :
///  - une fiche écrite chez un fileul arrive à la mère et à l'autre fileul (avant ce lot : restée locale au poste qui l'écrivait) ;
///  - famille A (champ à champ) : une couverture se CLÔT (sa fin s'écrit) quand la suivante prend effet, un budget se corrige ; une version datée n'est jamais réécrite autrement ;
///  - identité COMMUNE par le contenu (budget : exercice, centre, nature ; immobilisation : désignation, date, valeur ; couverture : assuré, date d'effet) : deux postes qui écrivent la même
///    chose, mère coupée, ne font qu'UNE fiche ; un rejeu n'ajoute rien ;
///  - la mère REFUSE au rejeu le budget d'un exercice clos (refus nommé, le fileul n'est pas bloqué) ;
///  - jamais vers un téléphone (RG-13).
/// Non éprouvé ici : le relais cPanel réel, deux machines distinctes, Windows.
Fiche exercice(int a, String etat) => {'id': 'EXO-$a', 'annee': a, 'debut': '$a-01-01', 'fin': '$a-12-31', 'statut': 'actif', 'etat': etat, 'source': 'journal'};

Fiche budget(int exercice, String centre, num prevu, {String ref = 'BG-X'}) =>
    {'reference': ref, 'exercice': exercice, 'centreCout': centre, 'centre': centre, 'nature': 'Charges de fonctionnement', 'prevu': prevu, 'statut': 'actif'};

Fiche bien(String designation, num valeur, {String ref = 'IM-X'}) => {
      'reference': ref,
      'designation': designation,
      'categorie': 'Matériel médical',
      'dateAcquisition': '2026-02-01',
      'valeurAcquisition': valeur,
      'dureeAmortissement': 5,
      'compte': '241000',
      'etat': 'En service',
      'statut': 'actif'
    };

Fiche couverture(String debut, {num taux = 80}) => {
      'patientId': 'PAT0003',
      'patientCode': 'CNT/3/26',
      'assureur': 'AFR',
      'numeroPolice': 'AFR/2024/0100',
      'tauxPriseEnCharge': taux,
      'carteExpiration': '2029-12-31',
      'souscripteurId': 'SOU001',
      'debut': debut,
      'motif': 'Changement d’employeur',
      'statut': 'actif'
    };

Iterable<Fiche> budgets(Magasin m, String centre) => m.collection('budgets').actives.where((b) => b['centreCout'] == centre);
Iterable<Fiche> biens(Magasin m, String d) => m.collection('immobilisations').actives.where((b) => b['designation'] == d);
Iterable<Fiche> couvertures(Magasin m, String debut) => m.collection('couverturesAssurance').actives.where((c) => c['debut'] == debut);

void main() {
  test('SYNC-CFG : budget, immobilisation et couverture écrits chez un fileul arrivent à la mère et à l\'autre fileul ; mère coupée, deux postes, même contenu : UNE fiche ; rejeu sans effet',
      () async {
    final c = Clinique(9750, '${Directory.systemTemp.createTempSync('sigh-synccfg-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'comptable', 'COMPTABLE UN');
      final f2 = await c.fileul('F2', 'comptable', 'COMPTABLE DEUX');
      for (final m in [c.mm, f1.m, f2.m]) {
        m.collection('exercices').inserer(exercice(2026, 'ouvert'));
      }
      await c.tour();
      // 1. ÉCRIT CHEZ F1 : la mère et F2 le reçoivent.
      f1.m.collection('budgets').inserer(budget(2026, 'laboratoire', 2000000, ref: 'BG-2026-001'));
      f1.m.collection('immobilisations').inserer(bien('Échographe portable', 4500000, ref: 'IM-002'));
      f1.m.collection('couverturesAssurance').mettreAJour('COU1', {'fin': '2026-10-31'});
      f1.m.collection('couverturesAssurance').inserer(couverture('2026-11-01'));
      bool partout(bool Function(Magasin) p) => [c.mm, f1.m, f2.m].every(p);
      await c.converger(
          () => partout((m) => budgets(m, 'laboratoire').where((b) => b['exercice'] == 2026).length == 1 && biens(m, 'Échographe portable').length == 1 && couvertures(m, '2026-11-01').length == 1),
          'les trois fiches de F1 arrivent à la mère et à F2',
          apres: 4);
      for (final m in [c.mm, f2.m]) {
        expect(budgets(m, 'laboratoire').firstWhere((b) => b['exercice'] == 2026)['prevu'], 2000000);
        expect(m.collection('couverturesAssurance').parId('COU1')!['fin'], '2026-10-31', reason: 'la couverture précédente est CLOSE la veille partout (famille A : la fin s\'écrit sur la même version)');
      }
      // 2. MÈRE COUPÉE : F1 et F2 écrivent le MÊME budget (même exercice, centre, nature) et le MÊME bien ; F2 corrige aussi le montant d'un budget reçu.
      await c.mere.arreter();
      f1.m.collection('budgets').inserer(budget(2026, 'pharmacie', 700000, ref: 'BG-2026-002'));
      f2.m.collection('budgets').inserer(budget(2026, 'pharmacie', 700000, ref: 'BG-2026-002'));
      f1.m.collection('immobilisations').inserer(bien('Autoclave 2', 900000, ref: 'IM-003'));
      f2.m.collection('immobilisations').inserer(bien('Autoclave 2', 900000, ref: 'IM-003'));
      final recu = budgets(f2.m, 'laboratoire').firstWhere((b) => b['exercice'] == 2026);
      f2.m.collection('budgets').mettreAJour(recu['id'], {'prevu': 2500000});
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(budgets(c.mm, 'pharmacie'), isEmpty, reason: 'la mère est coupée : rien n\'est arrivé');
      await c.demarrerMere();
      await c.converger(
          () => partout((m) => budgets(m, 'pharmacie').isNotEmpty && biens(m, 'Autoclave 2').isNotEmpty && budgets(m, 'laboratoire').any((b) => b['prevu'] == 2500000)),
          'la mère relancée reçoit les écritures des deux fileuls',
          apres: 6);
      for (final m in [c.mm, f1.m, f2.m]) {
        expect(budgets(m, 'pharmacie').length, 1, reason: 'le même budget écrit par deux postes, mère coupée : UNE fiche (identité commune par le contenu)');
        expect(biens(m, 'Autoclave 2').length, 1, reason: 'le même bien écrit par deux postes : UNE fiche');
        expect(budgets(m, 'laboratoire').where((b) => b['exercice'] == 2026).single['prevu'], 2500000, reason: 'la correction de F2 (champ à champ) arrive partout');
      }
      // 3. REJEU : des tours de plus n'ajoutent rien.
      final avant = {for (final col in ['budgets', 'immobilisations', 'couverturesAssurance']) col: c.mm.collection(col).toutes.length};
      await c.converger(() => true, 'rejeu', apres: 5);
      for (final e in avant.entries) {
        expect(c.mm.collection(e.key).toutes.length, e.value, reason: '${e.key} : un rejeu n\'écrit pas deux fois');
        expect(f1.m.collection(e.key).toutes.length, e.value, reason: '${e.key} : F1 tient le même nombre de fiches que la mère');
        expect(f2.m.collection(e.key).toutes.length, e.value, reason: '${e.key} : F2 tient le même nombre de fiches que la mère');
      }
      // Les refus que le jeu de vecteurs provoque déjà (écritures d'un exercice de la liasse) ne sont pas de ce lot : aucun refus ne nomme un budget, un bien ou une couverture, et la seconde création de la même fiche (mère coupée) n'est jamais un refus « fiche_existe ».
      for (final f in [f1, f2]) {
        final refus = [
          for (final r in await f.moteur.refusees())
            if (r['code'] == 'fiche_existe' || RegExp('budget|immobilisation|couverture', caseSensitive: false).hasMatch('${r['motif']}')) r
        ];
        expect(refus, isEmpty, reason: '${f.nom} : aucun refus à traiter sur ces trois collections');
      }
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('SYNC-CFG : la mère REFUSE au rejeu le budget d\'un exercice clos (refus nommé), le fileul n\'est pas bloqué ; aucune des trois collections ne va vers un téléphone (RG-13)', () async {
    final c = Clinique(9751, '${Directory.systemTemp.createTempSync('sigh-synccfg-clos-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'comptable', 'COMPTABLE UN');
      for (final m in [c.mm, f1.m]) {
        m.collection('exercices').inserer(exercice(2026, 'ouvert'));
        m.collection('exercices').inserer(exercice(2027, 'ouvert'));
      }
      await c.tour();
      // La mère clôt 2026 ; F1, qui n'a pas encore le statut, écrit un budget 2026 : sa garde locale le laisse passer (il croit l'exercice ouvert).
      c.mm.collection('exercices').mettreAJour('EXO-2026', {'etat': 'clos', 'valideLe': '2026-11-14T10:00:00.000Z', 'validePar': 'Direction'});
      expect(() => f1.m.collection('budgets').inserer(budget(2026, 'maternite', 300000, ref: 'BG-2026-009')), returnsNormally);
      await c.converger(() => f1.m.collection('exercices').parId('EXO-2026')?['etat'] == 'clos', 'le fileul reçoit le statut', apres: 4);
      expect(budgets(c.mm, 'maternite'), isEmpty, reason: 'la mère refuse au rejeu le budget d\'un exercice clos');
      final refus = await f1.moteur.refusees();
      final duBudget = refus.where((r) => r['code'] == 'exercice_clos' && '${r['motif']}'.contains('Budget'));
      expect(duBudget, hasLength(1), reason: '$refus');
      final r = duBudget.single;
      expect('${r['motif']}', allOf(contains('REFUSÉ au rejeu'), contains('2026')));
      expect('${r['geste']}', isNotEmpty);
      // Non bloquant : un budget de l'exercice ouvert passe.
      f1.m.collection('budgets').inserer(budget(2027, 'maternite', 350000, ref: 'BG-2027-002'));
      await c.converger(() => budgets(c.mm, 'maternite').any((b) => b['exercice'] == 2027), 'le budget de l\'exercice ouvert arrive à la mère', apres: 2);
      expect(budgets(c.mm, 'maternite').where((b) => b['exercice'] == 2026), isEmpty, reason: 'rejoué plusieurs fois, le budget refusé n\'entre toujours pas');
      // RG-13 : rien de ces trois collections vers un téléphone, ni par le journal, ni par un lot de tournée.
      f1.m.collection('immobilisations').inserer(bien('Moniteur', 1200000, ref: 'IM-004'));
      f1.m.collection('couverturesAssurance').inserer(couverture('2026-12-01'));
      await c.converger(() => biens(c.mm, 'Moniteur').isNotEmpty && couvertures(c.mm, '2026-12-01').isNotEmpty, 'les fiches arrivent à la mère', apres: 1);
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile.where((o) => const {'budgets', 'immobilisations', 'couverturesAssurance'}.contains(o.collection)), isEmpty, reason: 'familles comptable et d\'assurance fermées aux téléphones');
      final h = HttpClient();
      try {
        final code = await (await (await h.postUrl(Uri.parse('http://127.0.0.1:${c.port}/admin/code'))
                  ..headers.contentType = ContentType.json
                  ..headers.set('x-admin', 'secret-test')
                  ..add(utf8.encode(jsonEncode({'etiquette': 'tel', 'role': 'mobile', 'profil': 'soignant', 'fonction': 'infirmier'}))))
                .close())
            .transform(utf8.decoder)
            .join();
        final jetons = await (await (await h.postUrl(Uri.parse('http://127.0.0.1:${c.port}/appairage'))
                  ..headers.contentType = ContentType.json
                  ..add(utf8.encode(jsonEncode({'code': (jsonDecode(code) as Map)['code'], 'uuid': 'tel-synccfg-1', 'plateforme': 'test'}))))
                .close())
            .transform(utf8.decoder)
            .join();
        expect((jsonDecode(jetons) as Map)['jeton'], isNotNull, reason: jetons);
        for (final col in ['budgets', 'immobilisations', 'couverturesAssurance']) {
          final rep = await (await h.postUrl(Uri.parse('http://127.0.0.1:${c.port}/admin/lot'))
                ..headers.contentType = ContentType.json
                ..headers.set('x-admin', 'secret-test')
                ..add(utf8.encode(jsonEncode({
                  'uuid': 'tel-synccfg-1',
                  'fiches': [
                    {'collection': col, 'id': 'X'}
                  ],
                  'ttl_ms': 60000
                }))))
              .close();
          final corps = await rep.transform(utf8.decoder).join();
          expect(rep.statusCode, 422, reason: '$col : un lot de tournée qui la nomme est refusé ($corps)');
          expect((jsonDecode(corps) as Map)['code'], 'gestion_interdite_au_mobile');
        }
      } finally {
        h.close(force: true);
      }
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
