import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/plan_annuel_poste.dart';

import 'aide_grand_stock.dart';

/// LOT PTA : le plan annuel de travail SE SYNCHRONISE entre postes (jamais vers un téléphone), contre la VRAIE mère Dart et de VRAIS moteurs de fileul :
///  - une action écrite chez un fileul arrive à la mère et à l'autre fileul (avant ce lot : restée locale au poste qui l'écrivait) ; son suivi (champ à champ) aussi ;
///  - identité COMMUNE par le contenu (exercice, libellé, version) : deux postes qui écrivent la même action, mère coupée, ne font qu'UNE fiche ; l'adoption d'un exercice aussi ;
///  - une RÉVISION après adoption est une autre version : elle arrive, l'ancienne archivée aussi ;
///  - les référentiels du plan et les signataires (configuration de la mère) arrivent aux fileuls ;
///  - rien de tout cela ne va vers un téléphone (RG-13).
/// Non éprouvé ici : le relais cPanel réel, deux machines distinctes, Windows.
Fiche exercice(int a) => {'id': 'EXO-$a', 'annee': a, 'debut': '$a-01-01', 'fin': '$a-12-31', 'statut': 'actif', 'etat': 'ouvert', 'source': 'journal'};

Fiche action(String libelle, {int exercice = 2026, String etat = 'en_cours', int version = 1, String ref = 'PA-2026-001'}) => {
      'exercice': exercice,
      'reference': ref,
      'version': version,
      'action': libelle,
      'axe': 'qualite',
      'trimestreDebut': 1,
      'trimestreFin': 2,
      'avancement': etat,
      'responsableType': 'poste',
      'responsableRef': 'PS1',
      'statut': 'actif'
    };

Iterable<Fiche> actions(Magasin m, String libelle) => m.collection('planAnnuel').toutes.where((a) => a['action'] == libelle);

void main() {
  test('PTA : une action et son adoption écrites chez un fileul arrivent à la mère et à l\'autre fileul ; mère coupée, deux postes, même contenu : UNE fiche ; une révision voyage ; configuration du plan reçue', () async {
    final c = Clinique(9832, '${Directory.systemTemp.createTempSync('sigh-pta-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'da', 'DA UN');
      final f2 = await c.fileul('F2', 'da', 'DA DEUX');
      for (final m in [c.mm, f1.m, f2.m]) {
        m.collection('exercices').inserer(exercice(2026));
      }
      c.mm.collection('postes').inserer({'id': 'PS1', 'statut': 'actif', 'poste': 'Directrice Administrative', 'titulaire': 'TITULAIRE', 'role': 'da'});
      // la CONFIGURATION du plan est posée à la mère : référentiels et signataires arrivent aux fileuls
      for (final r in [
        {'id': 'RFP-001', 'statut': 'actif', 'type': 'axe', 'code': 'qualite', 'libelle': 'Qualité', 'ordre': 1},
        {'id': 'RFP-002', 'statut': 'actif', 'type': 'etat', 'code': 'en_cours', 'libelle': 'En cours', 'nature': 'en_cours', 'ton': 'info', 'ordre': 1},
        {'id': 'RFP-003', 'statut': 'actif', 'type': 'etat', 'code': 'realisee', 'libelle': 'Réalisée', 'nature': 'realisee', 'ton': 'success', 'ordre': 2},
      ]) {
        c.mm.collection('referentielsPlan').inserer(r);
      }
      c.mm.collection('reglagesPlan').inserer({'id': 'RPL-001', 'statut': 'actif', 'dateEffet': null, 'signataires': [{'posteId': 'PS1'}]});
      await c.tour();
      await c.converger(() => f1.m.collection('referentielsPlan').toutes.length == 3 && f1.m.collection('postes').parId('PS1') != null && f2.m.collection('postes').parId('PS1') != null && f2.m.collection('reglagesPlan').toutes.length == 1, 'les référentiels et le réglage du plan arrivent aux fileuls', apres: 4);
      // 1. ÉCRIT CHEZ F1 : la mère et F2 le reçoivent, puis le suivi (champ à champ).
      f1.m.collection('planAnnuel').inserer(action('Audit qualité'));
      bool partout(bool Function(Magasin) p) => [c.mm, f1.m, f2.m].every(p);
      await c.converger(() => partout((m) => actions(m, 'Audit qualité').length == 1), 'l\'action de F1 arrive à la mère et à F2', apres: 4);
      actions(f1.m, 'Audit qualité').single; // exactement une action chez F1
      f2.m.collection('planAnnuel').mettreAJour(actions(f2.m, 'Audit qualité').single['id'], {'tauxAvancement': 40, 'budgetRealise': 250000});
      await c.converger(() => partout((m) => actions(m, 'Audit qualité').single['tauxAvancement'] == 40), 'le suivi de F2 arrive partout (champ à champ)', apres: 4);
      // 2. MÈRE COUPÉE : F1 et F2 écrivent la MÊME action et adoptent le MÊME exercice.
      await c.mere.arreter();
      f1.m.collection('planAnnuel').inserer(action('Formation', ref: 'PA-2026-002'));
      f2.m.collection('planAnnuel').inserer(action('Formation', ref: 'PA-2026-002'));
      f1.m.collection('adoptionsPlan').inserer({'statut': 'actif', 'exercice': 2026, 'dateAdoption': '2026-10-30', 'motif': 'Délibération', 'adoptePar': 'DA UN', 'nbActions': 2});
      f2.m.collection('adoptionsPlan').inserer({'statut': 'actif', 'exercice': 2026, 'dateAdoption': '2026-10-30', 'motif': 'Délibération', 'adoptePar': 'DA UN', 'nbActions': 2});
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(actions(c.mm, 'Formation'), isEmpty, reason: 'la mère est coupée : rien n\'est arrivé');
      await c.demarrerMere();
      await c.converger(() => partout((m) => actions(m, 'Formation').isNotEmpty && m.collection('adoptionsPlan').toutes.isNotEmpty), 'la mère relancée reçoit les écritures des deux fileuls', apres: 6);
      for (final m in [c.mm, f1.m, f2.m]) {
        expect(actions(m, 'Formation').length, 1, reason: 'la même action écrite par deux postes, mère coupée : UNE fiche (identité commune par le contenu)');
        expect(m.collection('adoptionsPlan').toutes.where((a) => a['exercice'] == 2026).length, 1, reason: 'une adoption par exercice : UNE fiche');
      }
      // 3. UNE RÉVISION après adoption est une AUTRE version (autre identité) : elle arrive, l'ancienne archivée aussi.
      final rv = reviserActionPlan(f1.m, actions(f1.m, 'Formation').single['id'], {'trimestreFin': 3}, 'Report au troisième trimestre');
      expect(rv.refus, isNull, reason: '${rv.refus}');
      await c.converger(() => partout((m) => actions(m, 'Formation').where((a) => a['version'] == 2).length == 1), 'la version 2 arrive partout', apres: 4);
      await c.converger(() => true, 'tours de plus', apres: 6);
      String etat(Magasin m) => actions(m, 'Formation').map((a) => '${a['id']}:v${a['version']}:${a['statut']}').join(',');
      expect([etat(c.mm), etat(f1.m), etat(f2.m)].map((e) => e.split(',').where((x) => x.endsWith(':archive')).length), [1, 1, 1], reason: 'mère ${etat(c.mm)} | F1 ${etat(f1.m)} | F2 ${etat(f2.m)}');
      // 4. REJEU : des tours de plus n'ajoutent rien ; aucun refus « fiche_existe ».
      final avant = {for (final col in ['planAnnuel', 'adoptionsPlan']) col: c.mm.collection(col).toutes.length};
      await c.converger(() => true, 'rejeu', apres: 5);
      for (final e in avant.entries) {
        expect(c.mm.collection(e.key).toutes.length, e.value, reason: '${e.key} : un rejeu n\'écrit pas deux fois');
        expect(f1.m.collection(e.key).toutes.length, e.value, reason: '${e.key} : F1 tient le même nombre de fiches que la mère');
        expect(f2.m.collection(e.key).toutes.length, e.value, reason: '${e.key} : F2 tient le même nombre de fiches que la mère');
      }
      for (final f in [f1, f2]) {
        final refus = [
          for (final r in await f.moteur.refusees())
            if (r['code'] == 'fiche_existe') r
        ];
        expect(refus, isEmpty, reason: '${f.nom} : aucun refus fiche_existe');
      }
      // 5. RG-13 : rien du plan vers un téléphone.
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile.where((o) => const {'planAnnuel', 'adoptionsPlan', 'referentielsPlan', 'reglagesPlan'}.contains(o.collection)), isEmpty, reason: 'le plan et sa configuration sont fermés aux téléphones');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
