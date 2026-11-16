import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show qualCollectionsJamaisMobile;
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_sync/src/commun.dart' show maintenantMs;
import 'package:sigh_sync/src/mere.dart' show Appareil, familleDeBase;

import 'aide_grand_stock.dart';

/// LOT SAT (ADR-0009) : les RÉPONSES de satisfaction et les LIENS de collecte voyagent entre la mère et les postes, contre la VRAIE mère Dart et de VRAIS moteurs de fileul :
///  - un lien ouvert (« En ligne », point de collecte) chez un fileul arrive à la mère et à l'autre fileul ;
///  - une réponse écrite par la mère à l'ouverture d'une enveloppe (`REPW-<id>`, famille B) arrive aux deux fileuls, identique ;
///  - une réponse recueillie au guichet d'un fileul arrive à la mère et à l'autre fileul ;
///  - un rejeu n'ajoute rien ; jamais vers un téléphone (RG-13).
/// Non éprouvé ici : le relais cPanel réel, deux machines distinctes, Windows.
void main() {
  test('SAT : liens et réponses de satisfaction arrivent à tous les postes ; la réponse ouverte par la mère est la même partout ; rejeu sans effet', () async {
    final c = Clinique(9760, '${Directory.systemTemp.createTempSync('sigh-sat-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'direction', 'DIRECTION UN');
      final f2 = await c.fileul('F2', 'direction', 'DIRECTION DEUX');
      await c.tour();
      // 1. UN LIEN « EN LIGNE » ouvert chez F1.
      f1.m.collection('jetonsEnquete').inserer({'jeton': 'jetonsatisfaction0123456a', 'enqueteId': 'ENQ0001', 'enqueteTitre': 'Satisfaction', 'enLigne': true, 'point': 'laboratoire', 'anonyme': true, 'creeLe': '2026-11-16', 'expireLe': '2026-12-16'}, prefixe: 'JET');
      bool partout(bool Function(Magasin) p) => [c.mm, f1.m, f2.m].every(p);
      await c.converger(() => partout((m) => m.collection('jetonsEnquete').toutes.any((j) => j['jeton'] == 'jetonsatisfaction0123456a' && j['point'] == 'laboratoire' && j['enLigne'] == true)), 'le lien arrive à la mère et à F2', apres: 4);
      // 2. LA MÈRE ouvre une enveloppe : la réponse `REPW-<id>` (famille B) est écrite à sa base.
      const id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
      final st = await c.mere.verrou.executer(() => c.mere.base.tx(() => c.mere.traiter({
            'id': 'sat-test-1',
            'collection': 'reponsesEnquetes',
            'fiche': 'REPW-$id',
            'type': 'creer',
            'champs': {'statut': 'actif', 'enqueteId': 'ENQ0001', 'date': '2026-11-16', 'canal': 'Lien public', 'version': 'V1', 'point': 'laboratoire', 'langue': 'fr', 'reponses': {'Q_ACCUEIL': 5}, 'saisiPar': 'Réponse anonyme — lien partagé', 'enLigne': true},
            'hlc': maintenantMs(),
            'vu': const <String, Object?>{},
          }, Appareil('mere', 'mere'))));
      expect(st['statut'], 'acceptee');
      await c.converger(() => partout((m) => m.collection('reponsesEnquetes').toutes.any((r) => r['canal'] == 'Lien public' && r['point'] == 'laboratoire')), 'la réponse de la mère arrive aux deux fileuls', apres: 4);
      for (final m in [f1.m, f2.m]) {
        final r = m.collection('reponsesEnquetes').toutes.singleWhere((x) => x['canal'] == 'Lien public');
        expect((r['reponses'] as Map)['Q_ACCUEIL'], 5);
        expect(r['version'], 'V1');
        expect(r['saisiPar'], contains('anonyme'));
      }
      // 3. UNE RÉPONSE AU GUICHET d'un fileul : la mère et l'autre fileul la reçoivent.
      f1.m.collection('reponsesEnquetes').inserer({'enqueteId': 'ENQ0001', 'date': '2026-11-16', 'canal': 'Au guichet', 'version': 'V1', 'reponses': {'Q_ACCUEIL': 3}, 'saisiPar': 'DIRECTION UN'}, prefixe: 'REP');
      await c.converger(() => partout((m) => m.collection('reponsesEnquetes').toutes.length == 2), 'la réponse du guichet arrive partout', apres: 4);
      // 4. REJEU : des tours de plus n'ajoutent rien.
      await c.converger(() => true, 'rejeu', apres: 5);
      for (final m in [c.mm, f1.m, f2.m]) {
        expect(m.collection('reponsesEnquetes').toutes.length, 2);
        expect(m.collection('jetonsEnquete').toutes.length, 1);
      }
      // 5. Les familles et l'interdit au téléphone.
      expect(familleDeBase['reponsesEnquetes'], 'B');
      expect(familleDeBase['jetonsEnquete'], 'A');
      expect(qualCollectionsJamaisMobile, {'reponsesEnquetes', 'jetonsEnquete'});
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
