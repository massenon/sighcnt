import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';

import 'aide_grand_stock.dart';

/// LOT 8B CONTRE LA VRAIE MÈRE DART (et de vrais moteurs de fileul, la mère arrêtée pour de vrai) : un jeu de chaque groupe.
///  - PRIX : des prix ne s'écrivent JAMAIS chez le fileul ; deux fileuls déposent le même fichier la mère coupée ; au retour de la mère, UNE seule série de versions est écrite (au nom et au rôle de
///    l'auteur, en PROPOSITIONS : la décision d'un prix reste à la mère), le verdict revient, un verdict rejoué n'ajoute rien, rien ne part vers un téléphone ;
///  - GARANTIES : écrites chez le fileul avec leur demande ; deux fileuls, le même fichier : la mère confirme UNE fois, le second est ADOPTÉ ;
///  - COMPTABILITÉ : budgets, immobilisations et courriers s'écrivent chez le fileul sans aucune demande (aucune configuration de la mère) ; la garde d'exercice clos tient aussi chez lui.
/// Non éprouvé ici : le relais cPanel réel, deux machines distinctes, Windows.
final jour = DateTime(2026, 11, 13, 9);

ProfilImport profil(String role, {bool fileul = true}) => ProfilImport(role: role, libelleRole: role, matrice: donnees.matrice.matriceImport, fileul: fileul);

AnalyseImport analyser(Poste p, String jeu, String cas, {String? role}) {
  final a = analyserLignes(jeuImportParId(jeu)!, lignesDuCas(cas), '$cas.xlsx', PortMagasin(p.m, aujourdhui: () => jour, nomAgent: p.par, profil: profil(role ?? p.role)))..empreinte = 'e-$cas';
  expect(a.accepte, isTrue, reason: '$cas : ${[for (final x in a.problemes) '${x.code}:${x.motif}']}');
  return a;
}

Iterable<Fiche> versions(Magasin m, {String? statut}) => m.collection('versionsTarif').toutes.where((v) => v['origine'] == 'import' && (statut == null || v['statut'] == statut));

void main() {
  test('PRIX, DEUX FILEULS, MÈRE COUPÉE PUIS RELANCÉE : rien n\'est écrit chez les fileuls, UNE seule série de propositions à la mère, au nom et au rôle de l\'auteur ; verdict rejoué sans effet ; rien vers un téléphone', () async {
    final c = Clinique(9441, '${Directory.systemTemp.createTempSync('sigh-8b-prix-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      await c.mere.arreter();
      final d1 = f1.imp.deposer(jeuTarifs, analyser(f1, 'tarifs', 'ta-proposition'));
      final d2 = f2.imp.deposer(jeuTarifs, analyser(f2, 'tarifs', 'ta-proposition'));
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      for (final f in [f1, f2]) {
        expect(versions(f.m), isEmpty, reason: '${f.nom} : des prix ne s\'écrivent pas chez un fileul');
      }
      expect(f1.demande(d1['id'])!['etat'], demandeImportEnAttente, reason: 'la mère est coupée : la demande attend dans la file');
      expect(versions(c.mm), isEmpty);
      await c.demarrerMere();
      await c.converger(() => f1.demande(d1['id'])?['etat'] != demandeImportEnAttente && f2.demande(d2['id'])?['etat'] != demandeImportEnAttente, 'la mère tranche les deux demandes', apres: 6);
      final propositions = versions(c.mm).toList();
      expect(propositions.length, 2, reason: 'MG01 et NFS, UNE fois : jamais quatre pour deux fileuls (${[for (final v in propositions) v['id']]})');
      for (final v in propositions) {
        expect(v['statut'], 'propose', reason: 'la décision d\'un prix reste à la mère');
        expect(v['proposeRole'], 'stock');
        expect({'GESTIONNAIRE UN', 'GESTIONNAIRE DEUX'}, contains(v['proposePar']));
      }
      final verdicts = [f1.demande(d1['id'])!, f2.demande(d2['id'])!];
      expect(verdicts.where((v) => v['etat'] == demandeImportAppliquee).length, greaterThanOrEqualTo(1));
      for (final v in verdicts) {
        expect(v['lignes'], isEmpty, reason: 'les lignes du fichier sont effacées au verdict');
        if (v['etat'] == demandeImportRefusee) {
          expect(v['resultatCode'], isNotEmpty, reason: 'un refus se nomme');
          expect(v['resultatMotif'], isNotEmpty);
          expect(v['resultatGeste'], isNotEmpty);
        }
      }
      // Les versions écrites par la mère descendent aux fileuls (famille R), sans qu'ils aient jamais pu les écrire.
      await c.converger(() => versions(f1.m).length == 2 && versions(f2.m).length == 2, 'les versions arrivent aux fileuls par la configuration', apres: 3);
      // Un verdict REJOUÉ (la mère rejoue la demande déjà traitée) n'ajoute rien.
      final avant = versions(c.mm).length;
      c.mm.collection('demandesImport').mettreAJour(d1['id'], {'etat': demandeImportEnAttente});
      await c.converger(() => true, 'rejeu', apres: 4);
      expect(versions(c.mm).length, avant, reason: 'un rejeu n\'écrit pas deux fois');
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile.where((o) => o.collection == demandesImportCollection || o.collection == 'propositionsTarif'), isEmpty, reason: 'ni les demandes, ni leurs lignes, ni leur verdict vers un téléphone (RG-13)');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('GARANTIES, DEUX FILEULS, MÊME FICHIER : la mère confirme UNE fois, le second est ADOPTÉ ; COMPTABILITÉ : écrite chez le fileul, sans aucune demande, la garde d\'exercice clos tient chez lui', () async {
    final c = Clinique(9442, '${Directory.systemTemp.createTempSync('sigh-8b-gar-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'comptable', 'COMPTABLE UN');
      final f2 = await c.fileul('F2', 'comptable', 'COMPTABLE DEUX');
      await c.tour();
      final r1 = f1.imp.importerEtDemander(jeuGaranties, analyser(f1, 'garanties', 'ga-valide'));
      final r2 = f2.imp.importerEtDemander(jeuGaranties, analyser(f2, 'garanties', 'ga-valide'));
      expect(r1.resultat.ok && r2.resultat.ok, isTrue, reason: '${r1.resultat.motif} ${r2.resultat.motif}');
      final id1 = '${r1.demande!['id']}', id2 = '${r2.demande!['id']}';
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportAppliquee, 'la mère tranche les deux demandes', apres: 6);
      expect(f2.demande(id2)!['resultatAdoptee'], true, reason: 'le même contenu est « déjà confirmé, adopté », jamais refusé');
      expect(c.mm.collection(collectionLots).toutes.where((l) => l['jeu'] == 'garanties' && l['etat'] == 'applique'), hasLength(1), reason: 'la mère confirme UNE fois');
      final serie = [for (final g in c.mm.collection('garanties').actives) if (g['libelle'] == 'Consultation généraliste') g];
      expect(serie.length, 2, reason: 'la version remplacée reste écrite, la nouvelle s\'ajoute UNE fois');
      for (final f in [f1, f2]) {
        expect([for (final g in f.m.collection('garanties').actives) if (g['libelle'] == 'Consultation généraliste') g['id']].toSet(), {for (final g in serie) g['id']}, reason: '${f.nom} : mêmes identifiants que la mère');
      }
      // COMPTABILITÉ : aucune demande, et la garde d'exercice clos tient aussi chez le fileul.
      final avantDemandes = f1.m.collection(demandesImportCollection).toutes.length;
      final b = analyserLignes(jeuBudgets, lignesDuCas('bu-valide'), 'bu.xlsx', PortMagasin(f1.m, aujourdhui: () => jour, nomAgent: 'COMPTABLE UN', profil: profil('comptable')));
      expect(b.accepte, isTrue);
      final ra = appliquer(jeuBudgets, b, PortMagasin(f1.m, aujourdhui: () => jour, nomAgent: 'COMPTABLE UN', profil: profil('comptable')));
      expect(ra.ok, isTrue, reason: '${ra.motif}');
      expect(f1.m.collection(demandesImportCollection).toutes.length, avantDemandes, reason: 'aucune demande : un budget n\'est pas de la configuration de la mère');
      final clos = analyserLignes(jeuBudgets, lignesDuCas('bu-exercice-clos'), 'bu-clos.xlsx', PortMagasin(f1.m, aujourdhui: () => jour, nomAgent: 'COMPTABLE UN', profil: profil('comptable')));
      expect(clos.accepte, isFalse);
      expect([for (final p in clos.problemes) p.code], contains('EXERCICE_CLOS'));
      expect(() => f1.m.collection('budgets').inserer({'reference': 'BG-2025-900', 'exercice': 2025, 'statut': 'actif'}), throwsA(isA<EcritureRefusee>()), reason: 'la garde est au MOTEUR du magasin du fileul');
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile.where((o) => o.collection == demandesImportCollection), isEmpty);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('STOCK (jeux du lot 8, non éprouvés contre la vraie mère à ce lot) : la mère écrit le stock détail initial et le bon de transfert ; les fiches et les variations descendent au fileul, une fois ; le fileul, lui, est refusé en nommant', () async {
    final c = Clinique(9443, '${Directory.systemTemp.createTempSync('sigh-8b-stock-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      await c.tour();
      PortMagasin portDe(Magasin m, {Set<String> reserves = const {}}) =>
          PortMagasin(m, aujourdhui: () => jour, nomAgent: 'LE GESTIONNAIRE', profil: ProfilImport(role: 'stock', libelleRole: 'Gestionnaire de stock', matrice: donnees.matrice.matriceImport, reservesALaMere: reserves));
      // Le fileul rattaché : refus nommé, rien n'est écrit.
      final pf = portDe(f1.m, reserves: {'stock-detail-initial', 'transfert-lignes'});
      final refus = appliquer(jeuStockDetailInitial, analyserLignes(jeuStockDetailInitial, lignesDuCas('sd-valide'), 'sd.xlsx', pf), pf);
      expect(refus.code, 'JEU_RESERVE_A_LA_MERE');
      // La mère écrit : le détail initial (DOLIP, 40 au détail) puis le bon de transfert (AMOXI et COTON du gros vers le détail).
      final pm = portDe(c.mm);
      final r1 = appliquer(jeuStockDetailInitial, analyserLignes(jeuStockDetailInitial, lignesDuCas('sd-valide'), 'sd.xlsx', pm), pm);
      expect(r1.ok, isTrue, reason: '${r1.motif}');
      final r2 = appliquer(jeuTransfertLignes, analyserLignes(jeuTransfertLignes, lignesDuCas('tl-valide'), 'tl.xlsx', pm), pm);
      expect(r2.ok, isTrue, reason: '${r2.motif}');
      num stockDe(Magasin m, String code, String champ) => m.collection('produits').actives.firstWhere((p) => p['code'] == code)[champ] as num;
      final attendu = {
        'DOLIP': {'stockDetail': 40, 'stock': 80},
        'AMOXI': {'stockGros': 15, 'stockDetail': 15},
        'COTON': {'stockGros': 8},
      };
      for (final e in attendu.entries) {
        for (final k in e.value.entries) {
          expect(stockDe(c.mm, e.key, k.key), k.value, reason: 'mère : ${e.key}.${k.key}');
        }
      }
      await c.converger(() => stockDe(f1.m, 'DOLIP', 'stockDetail') == 40 && stockDe(f1.m, 'AMOXI', 'stockDetail') == 15, 'les fiches et les variations de stock descendent au fileul', apres: 6);
      for (final e in attendu.entries) {
        for (final k in e.value.entries) {
          expect(stockDe(f1.m, e.key, k.key), k.value, reason: 'fileul : ${e.key}.${k.key}, une seule fois (jamais le double)');
        }
      }
      expect(f1.m.collection('mouvements').toutes.where((x) => x['type'] == 'transfert').length, c.mm.collection('mouvements').toutes.where((x) => x['type'] == 'transfert').length);
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile.where((o) => o.collection == demandesImportCollection), isEmpty);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
