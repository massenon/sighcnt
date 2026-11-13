import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/sync/pont_activite.dart';

import 'aide_grand_stock.dart';

/// LE GRAND STOCK ÉCRIT CHEZ LE FILEUL, AVEC IDEMPOTENCE PROUVÉE (lot IMP-E, décision de la Direction du 13/11/2026), contre la VRAIE mère Dart et de VRAIS moteurs de fileul :
///  1. la mère APPLIQUE : une fiche, un lot, un mouvement par identité chez le fileul, chez la mère et chez un second fileul ; rien de doublé après des tours supplémentaires ni après
///     le redémarrage du pont ;
///  2. la mère est INJOIGNABLE : le fileul garde son stock et en sort ; à son retour la demande est rejouée UNE fois, les sorties ne sont ni perdues ni comptées deux fois ;
///  3. DEUX fileuls importent le même inventaire : la seconde demande est refusée en nommant, son fileul restitue (mouvements inverses, archivage), le stock n'est jamais doublé ;
///  4. une SORTIE déjà faite sur un lot en attente : l'article ne se restitue pas, la restitution est PARTIELLE, rien n'est négatif ni compté deux fois ;
///  5. un REJEU de la demande à la mère et un REDÉMARRAGE du pont ne comptent rien deux fois.
const total = {'fichesProduit': 1, 'stockGros': stockMed1, 'fichesLot': 2, 'sommeLots': 150, 'mouvementsEntree': 2, 'sommeEntrees': 150};
const totalGant = {'fichesProduit': 1, 'stockGros': stockGant1, 'fichesLot': 0, 'sommeLots': 0, 'mouvementsEntree': 1, 'sommeEntrees': 40};

void main() {
  test('CAS 1, LA MÈRE APPLIQUE : le stock exact chez le fileul, la mère et un second fileul, sans doublon après des tours de plus ni après le redémarrage du pont', () async {
    final c = Clinique(9421, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final r = f1.importer('gs-valide');
      expect(r.resultat.ok, isTrue, reason: '${r.resultat.motif}');
      final id = '${r.demande!['id']}';
      expect(f1.etat('MED1'), total, reason: 'écrit chez le fileul tout de suite, exact');
      expect(f1.m.collection('lots').toutes.where((f) => f[champEnAttenteMere] == id), hasLength(2));
      // Le stock en attente est PROPRE à ce poste : ni la mère ni le second fileul ne le voient avant la confirmation.
      await f1.pont.cycle();
      expect(c.etatMere('MED1')['fichesProduit'], 0, reason: 'la mère n\'a rien reçu du fileul avant d\'avoir rejoué la demande');
      expect(c.mm.collection('lots').toutes.where((l) => '${l['id']}'.contains(id)), isEmpty);
      expect(c.mm.collection('mouvements').toutes.where((l) => '${l['id']}'.contains(id)), isEmpty);
      final avantMobile = await collectionsRecuesParUnMobile(c.port);
      expect(avantMobile.where((o) => o.fiche.contains(id)), isEmpty, reason: 'un téléphone ne voit RIEN du stock que le fileul vient d\'écrire, avant la confirmation de la mère');
      await c.converger(() => f1.demande(id)?['etat'] == demandeImportAppliquee && f1.demande(id)?['marquageLeve'] == true && f2.produits('MED1').isNotEmpty, 'la mère confirme, le stock arrive partout', apres: 6);
      for (final (nom, e) in [('fileul 1', f1.etat('MED1')), ('mère', c.etatMere('MED1')), ('fileul 2', f2.etat('MED1'))]) {
        expect(e, total, reason: '$nom : une fiche, deux lots, deux entrées, 150 unités');
      }
      for (final (nom, e) in [('fileul 1', f1.etat('GANT1')), ('mère', c.etatMere('GANT1')), ('fileul 2', f2.etat('GANT1'))]) {
        expect(e, totalGant, reason: nom);
      }
      expect(f1.m.collection('lots').toutes.where((f) => f.containsKey(champEnAttenteMere)), isEmpty, reason: 'plus rien « en attente »');
      expect(f1.m.collection('mouvements').toutes.where((f) => f.containsKey(champEnAttenteMere)), isEmpty);
      // Une identité par fiche : celle de la demande, sur tous les postes.
      for (final m in [f1.m, c.mm, f2.m]) {
        expect(m.collection('lots').toutes.where((f) => f['serieDemande'] == id).every((f) => f['idSync'] == f['id']), isTrue);
        expect({for (final f in m.collection('produits').actives) if (f['code'] == 'MED1') f['id']}, {'PRO-$id-1'});
      }
      // JAMAIS VERS UN TÉLÉPHONE (RG-13) : ni la demande (ses lignes), ni les variations de stock. Les lots et mouvements de la MÈRE vont aux téléphones selon leurs règles actuelles
      // (non changées) : c'est le stock confirmé, jamais celui d'un fileul en attente (voir plus haut : rien n'a quitté le fileul avant la confirmation).
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile.where((o) => o.collection == demandesImportCollection), isEmpty, reason: 'la demande, avec ses lignes, ne voyage pas vers un téléphone');
      expect(mobile.where((o) => o.collection == 'deltasCompteurs'), isEmpty, reason: 'les variations de stock ne voyagent pas vers un téléphone');
      // REDÉMARRAGE : un nouveau pont sur les mêmes magasins (l'état des compteurs est relu du disque) ne republie ni ne recompte rien.
      final pont2 = PontActivite(f1.m, f1.pont.transport, etiquette: 'F1', enLectureSeule: collectionsDeLaMereSeule);
      final pontM2 = PontActivite(c.mm, c.pontM.transport, etiquette: 'M');
      for (var i = 0; i < 3; i++) {
        await pontM2.cycle();
        await pont2.cycle();
        await f2.tour();
      }
      for (final e in [f1.etat('MED1'), c.etatMere('MED1'), f2.etat('MED1')]) {
        expect(e, total, reason: 'après le redémarrage des ponts');
      }
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 2, LA MÈRE EST INJOIGNABLE : le fileul garde son stock et en SORT ; à son retour la demande est rejouée une fois, la sortie n\'est ni perdue ni comptée deux fois', () async {
    final c = Clinique(9422, '${Directory.systemTemp.createTempSync('sigh-gs-2-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      await c.mere.arreter();
      final r = f1.importer('gs-valide');
      final id = '${r.demande!['id']}';
      f1.sortir('MED1', 'L1', 10);
      for (var i = 0; i < 4; i++) {
        await f1.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(f1.demande(id)!['etat'], demandeImportEnAttente);
      expect(libelleEtatDemandeImport(f1.demande(id)!).libelle, 'Écrit chez vous, en attente de la mère');
      expect(f1.etat('MED1'), {...total, 'stockGros': 140, 'sommeLots': 140}, reason: 'le fileul garde son stock et en a sorti 10');
      expect((await f1.moteur.liste('deltasCompteurs')).where((d) => '${d.data['cle']}'.contains(id)), isEmpty, reason: 'la sortie d\'un stock en attente ne part pas au journal avant la confirmation de la mère');
      await c.demarrerMere();
      await c.converger(() => f1.demande(id)?['etat'] == demandeImportAppliquee && f1.demande(id)?['marquageLeve'] == true && f2.produits('MED1').isNotEmpty, 'la mère revient et confirme', apres: 8);
      final attendu = {...total, 'stockGros': 140, 'sommeLots': 140};
      for (final (nom, e) in [('fileul 1', f1.etat('MED1')), ('mère', c.etatMere('MED1')), ('fileul 2', f2.etat('MED1'))]) {
        expect(e, attendu, reason: '$nom : 150 importées, 10 sorties UNE fois (ni perdues, ni comptées deux fois)');
      }
      expect(f1.demande(id)!['etat'], demandeImportAppliquee);
      final sorties = [for (final x in c.mm.collection('mouvements').actives) if (x['type'] == 'sortie') x];
      expect(sorties, hasLength(1), reason: 'le mouvement de sortie du fileul est arrivé à la mère, une fois');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 3, DEUX FILEULS IMPORTENT LE MÊME INVENTAIRE : la seconde demande est refusée en nommant, le second fileul restitue (mouvements inverses, archivage), le stock n\'est jamais doublé', () async {
    final c = Clinique(9423, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final r1 = f1.importer('gs-valide');
      final r2 = f2.importer('gs-valide');
      final id1 = '${r1.demande!['id']}', id2 = '${r2.demande!['id']}';
      expect(r1.resultat.ok && r2.resultat.ok, isTrue, reason: 'chacun écrit chez lui');
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportRefusee && f2.demande(id2)?['restitution'] != null, 'la mère tranche', apres: 8);
      final v2 = f2.demande(id2)!;
      expect(v2['resultatCode'], 'DOUBLON_MAGASIN');
      expect(v2['restitution'], restitutionFaite);
      expect(libelleEtatDemandeImport(v2).libelle, 'Refusée par la mère, écriture restituée');
      // La mère tient 150, une fois. Le second fileul voit celui de la mère, pas le sien (archivé) : jamais 300.
      expect(c.etatMere('MED1'), total);
      expect(f1.etat('MED1'), total);
      expect(f2.etat('MED1'), total, reason: 'chez le second fileul : l\'article de la mère, le sien est archivé');
      expect(f2.m.collection('produits').toutes.where((f) => f['code'] == 'MED1' && f['statut'] == 'archive'), hasLength(1), reason: 'archivé, jamais supprimé (RG-14)');
      final inverses = [for (final x in f2.m.collection('mouvements').toutes) if (x['restitutionDe'] != null) x];
      expect(inverses, hasLength(3), reason: 'un mouvement inverse nommé par entrée');
      expect(inverses.every((x) => x['type'] == 'sortie' && '${x['justificatif']}'.contains('Restitution du lot')), isTrue);
      expect(c.mm.collection('mouvements').toutes.where((x) => x['restitutionDe'] != null), isEmpty, reason: 'la restitution reste chez le fileul : la mère n\'a jamais tenu ce stock');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 4, UNE SORTIE DÉJÀ FAITE SUR UN LOT EN ATTENTE : l\'article ne se restitue pas (restitution PARTIELLE), il reste chez ce poste seul, la mère n\'a rien de doublé ni de négatif', () async {
    final c = Clinique(9424, '${Directory.systemTemp.createTempSync('sigh-gs-4-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      await c.mere.arreter();
      final r1 = f1.importer('gs-valide');
      final r2 = f2.importer('gs-valide');
      final id1 = '${r1.demande!['id']}', id2 = '${r2.demande!['id']}';
      f2.sortir('MED1', 'L1', 10);
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await c.demarrerMere();
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportRefusee && f2.demande(id2)?['restitution'] != null, 'la mère tranche', apres: 8);
      final v2 = f2.demande(id2)!;
      expect([v2['resultatCode'], v2['restitution']], ['DOUBLON_MAGASIN', restitutionPartielle]);
      expect(libelleEtatDemandeImport(v2).libelle, 'Refusée par la mère, restitution partielle');
      final gardees = (v2['restitutionGardees'] as List).cast<Map>();
      expect({for (final g in gardees) '${g['code']}'}, {'STOCK_DEJA_SORTI'});
      expect(gardees.map((g) => g['collection']).toSet(), {'produits', 'lots', 'mouvements'});
      // GANT1, jamais sorti, est restitué ; MED1 reste chez F2 seul, marqué.
      final gant = f2.m.collection('produits').toutes.firstWhere((f) => f['code'] == 'GANT1' && f['id'] == 'PRO-$id2-2');
      expect(gant['statut'], 'archive');
      final med = f2.m.collection('produits').toutes.firstWhere((f) => f['id'] == 'PRO-$id2-1');
      expect(med['statut'], isNot('archive'));
      expect('${med[champRefuseeParMere]}', contains('DOUBLON_MAGASIN'));
      expect(med['stockGros'], 140, reason: 'la sortie déjà faite est conservée, jamais réécrite');
      // La mère : 150 une fois, aucun stock négatif, ni la sortie de F2 ni son stock gardé ne lui sont parvenus.
      expect(c.etatMere('MED1'), total);
      expect((await c.pontM.transport.liste('deltasCompteurs')).where((d) => '${d.data['cle']}'.contains(id2)), isEmpty, reason: 'aucune variation d\'un stock refusé n\'est jamais publiée');
      expect(c.mm.collection('produits').toutes.any((f) => f['id'] == 'PRO-$id2-1'), isFalse);
      expect([for (final x in c.mm.collection('mouvements').actives) if (x['type'] == 'sortie') x], isEmpty, reason: 'la sortie faite sur un stock que la mère a refusé ne part pas');
      for (final m in [c.mm, f1.m, f2.m]) {
        expect([for (final l in m.collection('lots').actives) if (((l['quantiteRestante'] as num?) ?? 0) < 0) l], isEmpty);
        expect([for (final p in m.collection('produits').actives) if (((p['stockGros'] as num?) ?? 0) < 0) p], isEmpty);
      }
      expect(f2.pont.stocksNegatifs.value, 0);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 5, LE REJEU : la même demande rejouée à la mère (verdict perdu, demande reçue deux fois) ne compte rien deux fois ; le journal de la mère ne grossit pas', () async {
    final c = Clinique(9425, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      await c.tour();
      final r = f1.importer('gs-valide');
      final id = '${r.demande!['id']}';
      await c.converger(() => f1.demande(id)?['etat'] == demandeImportAppliquee && f1.demande(id)?['marquageLeve'] == true, 'la mère confirme', apres: 4);
      expect(c.etatMere('MED1'), total);
      final lotsMere = c.mm.collection(collectionLots).toutes.length, fichesMere = c.mm.collection('lots').toutes.length + c.mm.collection('mouvements').toutes.length + c.mm.collection('produits').toutes.length;
      int importsJournal() => [for (final l in c.mm.collection('audit').toutes) if ('${l['action']}'.startsWith('Import')) l].length;
      final journalMere = importsJournal();
      expect(journalMere, greaterThan(0), reason: 'la mère a bien journalisé l\'import');
      // Le verdict est « perdu » : la demande revient à l'état « en attente » à la mère, comme si elle venait d'arriver une seconde fois.
      final d = c.mm.collection(demandesImportCollection).toutes.firstWhere((x) => x['jeu'] == 'grand-stock');
      for (var i = 0; i < 3; i++) {
        c.mm.collection(demandesImportCollection).mettreAJour(d['id'], {'etat': demandeImportEnAttente});
        await c.tour();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(c.etatMere('MED1'), total, reason: 'rejouée trois fois : le stock de la mère n\'a pas bougé');
      expect(f1.etat('MED1'), total);
      expect(c.mm.collection(collectionLots).toutes.length, lotsMere, reason: 'aucun lot d\'import de plus, aucun fichier refusé comme doublon de la mère elle-même');
      expect(c.mm.collection('lots').toutes.length + c.mm.collection('mouvements').toutes.length + c.mm.collection('produits').toutes.length, fichesMere);
      expect(c.mm.collection(demandesImportCollection).toutes.firstWhere((x) => x['id'] == d['id'])['etat'], demandeImportAppliquee, reason: 'le même verdict');
      expect(importsJournal(), journalMere, reason: 'aucune ligne de journal d\'import de plus à la mère : un rejeu est un NO-OP prouvé');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
