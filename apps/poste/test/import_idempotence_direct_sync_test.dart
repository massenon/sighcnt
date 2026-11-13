import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';
import 'package:sigh_poste/sync/service_verdicts_import.dart';

import 'aide_grand_stock.dart';

/// L'IDEMPOTENCE DE L'IMPORT CHEZ LES FILEULS (lot IDEM, décisions de la Direction du 13/11/2026, section V), contre la VRAIE mère Dart et de VRAIS moteurs de fileul.
/// Le même inventaire (même contenu normalisé) est reconnu comme le MÊME lot, quel que soit le fileul et le moment :
///  1. deux fileuls, même fichier : la mère confirme UNE fois, le second est « déjà confirmé, adopté » (jamais refusé, jamais restitué), mêmes identifiants, aucun double comptage ;
///  2. une sortie faite chez CHACUN des deux fileuls sur le lot en attente est comptée une fois ;
///  3. chaque étape rejouée (verdict, levée du marquage, restitution, demande à la mère, redémarrage des ponts et des services) est un NO-OP ;
///  4. le même fichier importé plus tard par un autre fileul : rien à écrire, nommé ; réimporté par le MÊME fileul après annulation avant la réponse de la mère : permis, une fois ;
///  5. un fichier dont UNE cellule change est un AUTRE lot ; le premier lot REFUSÉ par la mère : le refus s'applique au second dépôt, sans écriture de la mère ni doublon.
const total = {'fichesProduit': 1, 'stockGros': stockMed1, 'fichesLot': 2, 'sommeLots': 150, 'mouvementsEntree': 2, 'sommeEntrees': 150};

Future<void> attendreTours(Clinique c, int n) async {
  for (var i = 0; i < n; i++) {
    await c.tour();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

int journalImport(Clinique c) => [for (final l in c.mm.collection('audit').toutes) if ('${l['action']}'.startsWith('Import')) l].length;
List<Fiche> lotsApplique(Clinique c) => [for (final l in c.mm.collection(collectionLots).toutes) if (l['etat'] == 'applique') l];

void main() {
  test('CAS 1, DEUX FILEULS, MÊME INVENTAIRE : la mère confirme UNE fois, le second est ADOPTÉ (ni refus ni restitution), mêmes identifiants, 150 unités partout, jamais 300', () async {
    final c = Clinique(9431, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final r1 = f1.importer('gs-valide');
      final r2 = f2.importer('gs-valide');
      expect(r1.resultat.ok && r2.resultat.ok, isTrue, reason: 'chacun écrit chez lui');
      final id1 = '${r1.demande!['id']}', id2 = '${r2.demande!['id']}';
      // Les deux fileuls écrivent SOUS LES MÊMES identifiants de fiche (identité du contenu), pas sous deux séries différentes.
      expect({for (final p in f1.produits('MED1')) p['id']}, {for (final p in f2.produits('MED1')) p['id']}, reason: 'même fichier, mêmes identifiants de fiche chez les deux fileuls');
      expect(r1.demande!['serieIdentifiants'], r2.demande!['serieIdentifiants']);
      await c.converger(
          () => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportAppliquee && f1.demande(id1)?['marquageLeve'] == true && f2.demande(id2)?['marquageLeve'] == true,
          'la mère tranche les deux demandes',
          apres: 6);
      final v2 = f2.demande(id2)!;
      expect(v2['resultatCode'], '', reason: 'adopté : ce n\'est pas un refus');
      expect(v2['resultatAdoptee'], true);
      expect(f1.demande(id1)!['resultatAdoptee'], isNot(true), reason: 'la première demande est la confirmation, pas une adoption');
      expect(v2['restitution'], isNull, reason: 'aucune restitution nécessaire');
      expect(libelleEtatDemandeImport(v2).libelle, 'Déjà confirmé par la mère, adopté');
      for (final (nom, e) in [('fileul 1', f1.etat('MED1')), ('mère', c.etatMere('MED1')), ('fileul 2', f2.etat('MED1'))]) {
        expect(e, total, reason: '$nom : une fiche, deux lots, deux entrées, 150 unités, jamais le double');
      }
      expect(lotsApplique(c), hasLength(1), reason: 'la mère confirme UNE fois : un seul lot appliqué');
      expect([for (final x in f2.m.collection('mouvements').toutes) if (x['restitutionDe'] != null) x], isEmpty, reason: 'aucun mouvement inverse : rien n\'a été restitué');
      expect(f2.m.collection('produits').toutes.where((p) => p['statut'] == 'archive'), isEmpty, reason: 'aucune fiche archivée');
      for (final m in [f1.m, c.mm, f2.m]) {
        expect({for (final f in m.collection('produits').actives) if (f['code'] == 'MED1') f['id']}, {'PRO-${r1.demande!['serieIdentifiants']}-1'});
      }
      expect(f2.m.collection('lots').toutes.where((f) => f.containsKey(champEnAttenteMere)), isEmpty);
      // JAMAIS VERS UN TÉLÉPHONE (RG-13) : ni les demandes (leurs lignes, leur identité de lot, leur verdict d'adoption), ni les variations de stock.
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile.where((o) => o.collection == demandesImportCollection), isEmpty, reason: 'les demandes d\'import, leurs lignes et leur identité de lot ne voyagent pas vers un téléphone');
      expect(mobile.where((o) => o.collection == 'deltasCompteurs'), isEmpty);
      expect(mobile.where((o) => o.fiche.contains(r1.demande!['serieIdentifiants'] as String) && o.collection == demandesImportCollection), isEmpty);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 2, UNE SORTIE FAITE CHEZ CHACUN DES DEUX FILEULS sur le lot en attente est comptée UNE fois (130 partout), la mère coupée puis relancée', () async {
    final c = Clinique(9432, '${Directory.systemTemp.createTempSync('sigh-idem-2-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      await c.mere.arreter();
      final r1 = f1.importer('gs-valide');
      final r2 = f2.importer('gs-valide');
      final id1 = '${r1.demande!['id']}', id2 = '${r2.demande!['id']}';
      f1.sortir('MED1', 'L1', 10);
      f2.sortir('MED1', 'L1', 10);
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(f1.demande(id1)!['etat'], demandeImportEnAttente);
      await c.demarrerMere();
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportAppliquee && f1.demande(id1)?['marquageLeve'] == true && f2.demande(id2)?['marquageLeve'] == true, 'la mère revient et tranche', apres: 8);
      final attendu = {...total, 'stockGros': 130, 'sommeLots': 130};
      for (final (nom, e) in [('fileul 1', f1.etat('MED1')), ('mère', c.etatMere('MED1')), ('fileul 2', f2.etat('MED1'))]) {
        expect(e, attendu, reason: '$nom : 150 importées, 2 x 10 sorties, chacune UNE fois, jamais les 300 d\'un double import');
      }
      expect([for (final x in c.mm.collection('mouvements').actives) if (x['type'] == 'sortie') x], hasLength(2));
      expect(f2.demande(id2)!['resultatAdoptee'], true);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 3, LE REJEU : verdict reçu deux fois, marquage relevé deux fois, demande rejouée à la mère, redémarrage des ponts et des services : état final identique, rien d\'ajouté', () async {
    final c = Clinique(9433, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final id1 = '${f1.importer('gs-valide').demande!['id']}', id2 = '${f2.importer('gs-valide').demande!['id']}';
      await c.converger(() => f1.demande(id1)?['marquageLeve'] == true && f2.demande(id2)?['marquageLeve'] == true, 'la mère tranche', apres: 5);
      int fiches(Magasin m) => ['lots', 'mouvements', 'produits'].fold(0, (t, k) => t + m.collection(k).toutes.length);
      final etat = [fiches(f1.m), fiches(f2.m), fiches(c.mm)];
      final lotsMere = c.mm.collection(collectionLots).toutes.length, journal = journalImport(c);
      final demandesMere = c.mm.collection(demandesImportCollection).toutes.length;
      for (var i = 0; i < 3; i++) {
        // Le verdict de la mère est RE-REÇU (la mère le republie) et le marquage de chaque fileul est relevé de nouveau : comme après une coupure entre l'écriture et son accusé.
        for (final (f, id) in [(f1, id1), (f2, id2)]) {
          f.m.collection(demandesImportCollection).mettreAJour(id, {'marquageLeve': false});
          f.imp.traiterVerdicts();
        }
        // La demande revient « en attente » à la mère (verdict perdu) : elle la rejoue.
        for (final d in c.mm.collection(demandesImportCollection).toutes) {
          c.mm.collection(demandesImportCollection).mettreAJour(d['id'], {'etat': demandeImportEnAttente});
        }
        // Redémarrage des services et des ponts sur les mêmes magasins.
        final pontM2 = PontActivite(c.mm, c.pontM.transport, etiquette: 'M');
        final pont1 = PontActivite(f1.m, f1.pont.transport, etiquette: 'F1', enLectureSeule: collectionsDeLaMereSeule);
        final pont2 = PontActivite(f2.m, f2.pont.transport, etiquette: 'F2', enLectureSeule: collectionsDeLaMereSeule);
        final srv2 = ServiceDemandesImport(c.mm, donnees: () async => donnees, horloge: () => DateTime(2026, 11, 13));
        await srv2.traiter();
        final sv = ServiceVerdictsImport(f2.m, role: 'stock', auteur: () => 'GESTIONNAIRE DEUX', donnees: () async => donnees, horloge: () => DateTime(2026, 11, 13), etiquette: 'F2');
        await sv.traiter();
        await pontM2.cycle();
        await pont1.cycle();
        await pont2.cycle();
        await attendreTours(c, 2);
      }
      for (final e in [f1.etat('MED1'), c.etatMere('MED1'), f2.etat('MED1')]) {
        expect(e, total, reason: 'rejoué trois fois : 150, une fiche, deux lots');
      }
      expect([fiches(f1.m), fiches(f2.m), fiches(c.mm)], etat, reason: 'aucune fiche de plus nulle part');
      expect(c.mm.collection(collectionLots).toutes.length, lotsMere, reason: 'aucun lot d\'import de plus à la mère');
      expect(c.mm.collection(demandesImportCollection).toutes.length, demandesMere);
      expect(journalImport(c), journal, reason: 'aucune ligne de journal d\'import de plus : un rejeu est un NO-OP prouvé');
      expect(lotsApplique(c), hasLength(1));
      expect(c.mm.collection(demandesImportCollection).toutes.every((d) => d['etat'] == demandeImportAppliquee), isTrue, reason: 'le même verdict');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 4, LE MÊME FICHIER PLUS TARD par un autre fileul : rien à écrire, nommé (LOT_DEJA_IMPORTE), ni demande ni fiche ; par le même fileul : de même', () async {
    final c = Clinique(9434, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final id1 = '${f1.importer('gs-valide').demande!['id']}';
      await c.converger(() => f1.demande(id1)?['marquageLeve'] == true && f2.produits('MED1').isNotEmpty, 'la mère confirme, le stock arrive chez le second fileul', apres: 4);
      final avant = f2.etat('MED1');
      final lotsF2 = f2.m.collection(collectionLots).toutes.length, demandes = c.mm.collection(demandesImportCollection).toutes.length;
      final r = f2.importer('gs-valide');
      expect(r.resultat.ok, isFalse);
      expect(r.resultat.code, 'LOT_DEJA_IMPORTE');
      expect(r.resultat.motif, contains('déjà importé'));
      expect(r.demande, isNull);
      final r1 = f1.importer('gs-valide');
      expect(r1.resultat.code, 'LOT_DEJA_IMPORTE');
      await attendreTours(c, 2);
      expect(f2.etat('MED1'), avant);
      expect(f2.m.collection(collectionLots).toutes.length, lotsF2, reason: 'aucun lot consigné pour un fichier déjà importé');
      expect(c.mm.collection(demandesImportCollection).toutes.length, demandes, reason: 'aucune demande déposée');
      expect(c.etatMere('MED1'), total);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 5, ANNULATION PUIS RÉIMPORT par le MÊME fileul avant la réponse de la mère : permis ; la mère confirme UNE fois ; un second fileul (première tentative) est adopté, son écriture rebasée sans doublon', () async {
    final c = Clinique(9435, '${Directory.systemTemp.createTempSync('sigh-idem-5-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      await c.mere.arreter();
      final r1 = f1.importer('gs-valide');
      expect(r1.resultat.ok, isTrue);
      final a = f1.imp.annulerLotDuFileul(r1.resultat.lot!['id'], motif: 'erreur de fichier');
      expect(a.ok, isTrue, reason: 'annulation permise tant que la mère n\'a pas statué : ${a.motif}');
      expect(f1.produits('MED1'), isEmpty, reason: 'archivé');
      final r1b = f1.importer('gs-valide');
      expect(r1b.resultat.ok, isTrue, reason: 'le même fichier peut être réimporté après annulation : ${r1b.resultat.motif}');
      expect(r1b.demande!['serieIdentifiants'], isNot(r1.demande!['serieIdentifiants']), reason: 'une nouvelle tentative a sa série : jamais une fiche archivée réutilisée');
      expect(f1.etat('MED1'), total, reason: 'chez le fileul, une fois');
      final r2 = f2.importer('gs-valide');
      final id1 = '${r1b.demande!['id']}', id2 = '${r2.demande!['id']}';
      await c.demarrerMere();
      await c.converger(
          () => f1.demande(id1)?['marquageLeve'] == true && f2.demande(id2)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['restitution'] != null && f2.demande(id2)?['marquageLeve'] != null,
          'la mère tranche',
          apres: 8);
      for (final (nom, e) in [('fileul 1', f1.etat('MED1')), ('mère', c.etatMere('MED1')), ('fileul 2', f2.etat('MED1'))]) {
        expect(e, total, reason: '$nom : 150 une fois');
      }
      expect(lotsApplique(c), hasLength(1));
      expect(f2.demande(id2)!['resultatAdoptee'], true);
      expect(f2.demande(id2)!['restitution'], restitutionFaite, reason: 'séries différentes : l\'écriture locale du second est rebasée (archivée), jamais doublée');
      expect(f1.demande(r1.demande!['id'])!['etat'], demandeImportRetiree);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 6, UNE CELLULE CHANGE : un AUTRE lot (autre identité) ; ses articles recouvrent ceux du premier : refus DOUBLON_MAGASIN nommé et restitution, jamais reconnu comme le même lot', () async {
    final c = Clinique(9436, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final r1 = f1.importer('gs-valide');
      final r2 = f2.importerLignes(lignesModifiees(), 'modifie.xlsx');
      expect(r2.resultat.ok, isTrue);
      expect(r2.demande!['serieIdentifiants'], isNot(r1.demande!['serieIdentifiants']), reason: 'une cellule change : une autre identité de lot');
      final id1 = '${r1.demande!['id']}', id2 = '${r2.demande!['id']}';
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportRefusee && f2.demande(id2)?['restitution'] != null, 'la mère tranche', apres: 6);
      expect(f2.demande(id2)!['resultatCode'], 'DOUBLON_MAGASIN');
      expect(f2.demande(id2)!['resultatAdoptee'], isNot(true));
      expect(c.etatMere('MED1'), total);
      expect(f2.etat('MED1'), total, reason: 'chez le second : l\'article de la mère, le sien est restitué');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 7, LE PREMIER LOT EST REFUSÉ PAR LA MÈRE (l\'article existe déjà chez elle) puis le même fichier d\'un second fileul : le refus s\'applique aux deux, nommé, la mère n\'écrit rien, chaque fileul restitue, rien n\'est adopté ; un rejeu ne consigne rien de plus', () async {
    final c = Clinique(9437, '${Directory.systemTemp.createTempSync('sigh-idem-7-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      await c.mere.arreter();
      final id1 = '${f1.importer('gs-valide').demande!['id']}', id2 = '${f2.importer('gs-valide').demande!['id']}';
      // La mère a créé MED1 chez elle avant d'avoir tranché : le fichier lui est refusé, quel que soit le fileul qui le dépose (la première demande, puis la seconde, même contenu).
      c.mm.collection('produits').inserer({'id': 'PRD-MERE-1', 'code': 'MED1', 'designation': 'Paracétamol 500 mg', 'categorie': 'Médicaments', 'unite': 'Boîte', 'stockGros': 3, 'stock': 3, 'statut': 'actif'});
      await c.demarrerMere();
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportRefusee && f1.demande(id1)?['restitution'] != null && f2.demande(id2)?['etat'] == demandeImportRefusee && f2.demande(id2)?['restitution'] != null, 'la mère refuse les deux', apres: 2);
      expect(f1.demande(id1)!['resultatCode'], 'DOUBLON_MAGASIN');
      final lotsMere = c.mm.collection(collectionLots).toutes.length;
      expect(lotsApplique(c), isEmpty, reason: 'la mère n\'a rien écrit');
      final v2 = f2.demande(id2)!;
      expect(v2['resultatCode'], 'DOUBLON_MAGASIN', reason: 'le refus s\'applique au second dépôt, nommé');
      expect(v2['resultatAdoptee'], isNot(true), reason: 'jamais adopté : le lot n\'a jamais été confirmé');
      expect(lotsApplique(c), isEmpty, reason: 'la mère n\'écrit rien pour le second non plus');
      for (final p in [f1, f2]) {
        expect(p.m.collection('produits').toutes.where((x) => x['serieDemande'] != null && x['statut'] != 'archive'), isEmpty, reason: '${p.nom} : son écriture est restituée, rien ne reste actif');
      }
      expect(c.etatMere('MED1')['fichesProduit'], 1, reason: 'la seule fiche de la mère');
      // Un rejeu à la mère (verdict perdu, demande reçue deux fois) ne consigne pas un lot refusé de plus.
      final consignes = c.mm.collection(collectionLots).toutes.length;
      expect(consignes, greaterThanOrEqualTo(lotsMere));
      for (var i = 0; i < 3; i++) {
        for (final d in c.mm.collection(demandesImportCollection).toutes) {
          c.mm.collection(demandesImportCollection).mettreAJour(d['id'], {'etat': demandeImportEnAttente});
        }
        await attendreTours(c, 2);
      }
      expect(c.mm.collection(collectionLots).toutes.length, consignes, reason: 'un rejeu d\'une demande refusée ne consigne pas un second lot refusé');
      expect(c.mm.collection(demandesImportCollection).toutes.every((d) => d['etat'] == demandeImportRefusee), isTrue);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 8, UNE RESTITUTION PARTIELLE REJOUÉE reste PARTIELLE (jamais « faite »), sans second mouvement inverse ni seconde contre-passation', () async {
    final c = Clinique(9438, '${Directory.systemTemp.createTempSync('sigh-idem-8-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      await c.tour();
      await c.mere.arreter();
      final id1 = '${f1.importer('gs-valide').demande!['id']}';
      f1.sortir('MED1', 'L1', 10);
      await c.demarrerMere();
      // La mère refuse (un article identique existe chez elle) : GANT1 est restitué, MED1 (déjà sorti) reste.
      c.mm.collection('produits').inserer({'id': 'PRD-MERE-1', 'code': 'MED1', 'designation': 'Paracétamol 500 mg', 'categorie': 'Médicaments', 'unite': 'Boîte', 'stockGros': 3, 'stock': 3, 'statut': 'actif'});
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportRefusee && f1.demande(id1)?['restitution'] != null, 'la mère refuse', apres: 2);
      expect(f1.demande(id1)!['restitution'], restitutionPartielle);
      int inverses() => [for (final x in f1.m.collection('mouvements').toutes) if (x['restitutionDe'] != null) x].length;
      final n = inverses(), journal = [for (final l in f1.m.collection('audit').toutes) if ('${l['action']}'.startsWith('Import restitué')) l].length;
      final gardees = (f1.demande(id1)!['restitutionGardees'] as List).length;
      // Le drapeau de restitution est PERDU (coupure entre la restitution et son accusé) : le verdict est suivi de nouveau, trois fois.
      for (var i = 0; i < 3; i++) {
        f1.m.collection(demandesImportCollection).retirerChamp(id1, 'restitution');
        f1.m.collection(demandesImportCollection).retirerChamp(id1, 'restitutionGardees');
        f1.imp.traiterVerdicts();
        expect(f1.demande(id1)!['restitution'], restitutionPartielle, reason: 'rejeu $i : une restitution partielle ne devient jamais « faite »');
        expect((f1.demande(id1)!['restitutionGardees'] as List).length, gardees, reason: 'les fiches gardées sont rendues de nouveau, sans rien perdre');
      }
      expect(inverses(), n, reason: 'aucune seconde contre-passation');
      expect([for (final l in f1.m.collection('audit').toutes) if ('${l['action']}'.startsWith('Import restitué')) l].length, journal, reason: 'aucune ligne de journal de restitution de plus');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}

