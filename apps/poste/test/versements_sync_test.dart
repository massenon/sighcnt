import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/donnees/versements_poste.dart';

import 'aide_grand_stock.dart';

/// LOT PAIE-V : les versements de caisse voyagent, contre la VRAIE mère Dart et de VRAIS moteurs de fileul (la mère arrêtée pour de vrai) :
///  - deux versements (mobile money avec sa référence, espèces) encaissés chez un fileul arrivent à la mère et à l'autre fileul, avec l'identité COMMUNE par le contenu ;
///  - deux fileuls coupés de la mère encaissent la MÊME pièce : à la reprise la mère REFUSE, nommé, le versement qui ferait dépasser le dû (VERSEMENT_SUPERIEUR_AU_DU), un seul reste ;
///  - deux versements identiques d'un même lot (5 000 en espèces deux fois) restent DEUX fiches (le rang entre dans l'identité).
/// Non éprouvé ici : le relais cPanel réel, deux machines distinctes, Windows.
Fiche piece(String id, num a, num b) => {
      'id': id,
      'statut': 'actif',
      'numero': 'FN-$id',
      'date': '2026-10-30',
      'patientId': 'PAT0003',
      'patient': 'Patient Trois',
      'type': 'Consultation',
      'montantTTC': a + b,
      'partAssurance': 0,
      'partPatient': a + b,
      'montantPaye': 0,
      'reliquat': a + b,
      'statutPaiement': 'impayee',
      'lignes': [
        {'id': 'L1', 'categorie': 'acte', 'designation': 'Acte 1', 'quantite': 1, 'prixUnitaire': a, 'partPatient': a, 'statutPaiement': 'du'},
        {'id': 'L2', 'categorie': 'acte', 'designation': 'Acte 2', 'quantite': 1, 'prixUnitaire': b, 'partPatient': b, 'statutPaiement': 'du'},
      ],
    };

Iterable<Fiche> versements(Magasin m, String factureId) => versementsDePiecePoste(m, m.collection('factures').parId(factureId)!);

void main() {
  test('PAIE-V : les versements voyagent (identité par le contenu), la mère refuse le dépassement du dû au rejeu, deux versements identiques d’un lot restent deux', () async {
    final c = Clinique(9902, '${Directory.systemTemp.createTempSync('sigh-paiev-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'caissier', 'CAISSIER UN');
      final f2 = await c.fileul('F2', 'caissier', 'CAISSIER DEUX');
      bool partout(bool Function(Magasin) p) => [c.mm, f1.m, f2.m].every(p);
      final auj = DateTime(2026, 10, 30, 10);
      for (final m in [c.mm, f1.m, f2.m]) {
        m.horloge = () => auj;
      }
      // Les pièces naissent chez F1 par les gestes du magasin (elles voyagent : la mère contrôle un versement contre la pièce qu'elle connaît).
      for (final x in ['P1', 'P2', 'P3']) {
        f1.m.collection('factures').inserer(piece(x, 15000, 8500), prefixe: 'FAC');
      }
      // Une pièce née chez un fileul n'a pas le même identifiant local partout (identité de synchronisation distincte) : on la retrouve par son NUMÉRO, comme le font les versements.
      String idLocal(Magasin m, String numero) => '${m.collection('factures').actives.firstWhere((f) => f['numero'] == numero)['id']}';
      bool pieces(Magasin m) => ['FN-P1', 'FN-P2', 'FN-P3'].every((n) => m.collection('factures').actives.any((f) => f['numero'] == n));
      await c.converger(() => partout(pieces), 'les trois pièces arrivent partout', apres: 4);
      // 1. Deux versements de modes différents chez F1 : la mère et F2 les reçoivent, avec leurs références et leurs fiches liées.
      final r = encaisserFacture(f1.m, idLocal(f1.m, 'FN-P1'),
          versements: [
            {'type': 'acompte', 'modalite': 'mobile_money', 'operateur': 'mtn', 'referenceTransaction': 'M123', 'montant': 15000},
            {'type': 'solde', 'modalite': 'especes', 'montant': 8500},
          ],
          maintenant: auj);
      expect(r.versements.length, 2);
      await c.converger(() => partout((m) => versements(m, idLocal(m, 'FN-P1')).length == 2), 'les deux versements arrivent partout', apres: 4);
      for (final m in [c.mm, f2.m]) {
        final vs = versementsDePiecePoste(m, m.collection('factures').actives.firstWhere((f) => f['numero'] == 'FN-P1'));
        expect([for (final v in vs) [v['modalite'], v['operateur'], v['referenceTransaction'], v['montant']]], [['mobile_money', 'mtn', 'M123', 15000], ['especes', null, null, 8500]]);
        expect('${vs.first['id']}', startsWith('VRS-'), reason: 'identité commune par le contenu, posée par le poste');
      }

      // 2. Mère COUPÉE : F1 et F2 encaissent chacun 20 000 sur la même pièce (23 500 dus) : chacun est valide chez lui.
      await c.mere.arreter();
      for (final (i, f) in [f1, f2].indexed) {
        // Deux caissiers, deux instants : deux versements distincts (le même instant exact serait LE MÊME versement, identité par le contenu).
        final x = encaisserFacture(f.m, idLocal(f.m, 'FN-P2'), versements: [{'type': 'acompte', 'modalite': 'especes', 'montant': 20000}], maintenant: auj.add(Duration(seconds: 5 * i)));
        expect(x.versements.length, 1, reason: '${f.nom} : valide localement');
      }
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await c.demarrerMere();
      await c.converger(() => versements(c.mm, idLocal(c.mm, 'FN-P2')).length == 1, 'mère relancée : UN seul des deux versements entre (le second ferait dépasser le dû)', apres: 6);
      var refus = <Map<String, Object?>>[];
      final fin = DateTime.now().add(const Duration(seconds: 40));
      while (refus.isEmpty && DateTime.now().isBefore(fin)) {
        await f1.tour();
        await f2.tour();
        await c.pontM.cycle();
        refus = [for (final f in [f1, f2]) for (final x in await f.moteur.refusees()) if (x['code'] == 'VERSEMENT_SUPERIEUR_AU_DU') x];
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final etat = 'mère : ${[for (final v in c.mm.collection('versementsCaisse').actives) [v['factureNumero'], v['montant']]]} ; F1 : ${[for (final x in await f1.moteur.refusees()) x['code']]} ; F2 : ${[for (final x in await f2.moteur.refusees()) x['code']]} ; F1 versements : ${[for (final v in f1.m.collection('versementsCaisse').actives) [v['factureNumero'], v['montant']]]}';
      expect(refus, isNotEmpty, reason: 'la mère REFUSE au rejeu en nommant : le fileul voit le refus à « traiter » ; $etat');
      expect(versements(c.mm, idLocal(c.mm, 'FN-P2')).single['montant'], 20000);

      // 3. Deux versements identiques d'un même lot : DEUX fiches (le rang entre dans l'identité), aucune fusion.
      encaisserFacture(f1.m, idLocal(f1.m, 'FN-P3'),
          versements: [
            {'type': 'acompte', 'modalite': 'especes', 'montant': 5000},
            {'type': 'acompte', 'modalite': 'especes', 'montant': 5000},
          ],
          maintenant: auj);
      await c.converger(() => partout((m) => versements(m, idLocal(m, 'FN-P3')).length == 2), 'les deux versements identiques d’un même lot restent deux partout', apres: 4);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
