import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';
import 'import_test.dart' show MagasinMemoire, profilDe;

/// L'IDEMPOTENCE DE L'IMPORT CHEZ LES FILEULS (lot IDEM, décisions de la Direction du 13/11/2026, section V). L'identité d'un lot dérive de son CONTENU : le même inventaire est le
/// MÊME lot quel que soit le fileul ou le moment (la mère le confirme UNE fois, un autre dépôt est « déjà confirmé, adopté »), et chaque étape rejouée est un NO-OP.
void main() {
  final V = lireVecteurs('import');
  final magasinInitial = (V['magasin'] as Map).cast<String, Object?>();
  final jeu = jeuImportParId('grand-stock')!;
  List<List<Object?>> lignesDuCas(String id) {
    final c = liste(V['cas']).firstWhere((x) => x['id'] == id);
    return [
      for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
    ];
  }

  const compteurs = {
    'produits': {'stockGros', 'stockDetail', 'stock'},
    'lots': {'quantiteRestante'},
  };
  List<List<Object?>> inventaire() => lignesDuCas('gs-valide');

  /// Ce que le FILEUL fait : identité et série de ses fiches, écriture sous le port de la demande, demande composée.
  ({Map<String, Object?> demande, MagasinMemoire fileul, ResultatImport resultat, String serie, String identite}) fileulEcrit(String idDemande,
      {List<List<Object?>>? lignes, MagasinMemoire? sur}) {
    final fileul = sur ?? (MagasinMemoire(magasinInitial, profil: profilDe('stock'))..utilisateurFixe = 'GESTIONNAIRE $idDemande');
    final l = lignes ?? inventaire();
    final prep = preparerLotImport(jeu, l, fileul);
    final a = analyserLignes(jeu, l, 'x.xlsx', fileul)..empreinte = 'abc';
    expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
    final r = appliquerDemande(
        jeu, a, PortDemandeImport(fileul, demandeId: prep.serie, marquage: idDemande, identiteLot: prep.identite, marquerEnAttente: true, compteurs: compteurs));
    expect(r.ok, isTrue, reason: '${r.motif}');
    final d = composerDemandeImport(
        id: idDemande,
        jeu: jeu,
        analyse: a,
        role: 'stock',
        par: 'GESTIONNAIRE $idDemande',
        jour: '2026-11-13',
        restreint: false,
        lotLocal: '${r.lot!['reference']}',
        lotLocalId: r.lot!['id'],
        serie: prep.serie,
        identiteLot: prep.identite);
    return (demande: d, fileul: fileul, resultat: r, serie: prep.serie, identite: prep.identite);
  }

  VerdictDemandeImport lamere(Map<String, Object?> demande, MagasinMemoire mere) {
    mere
      ..profil = profilDe('${demande['demandeRole']}')
      ..utilisateurFixe = '${demande['demandePar']}';
    return traiterDemandeImport(demande, mere, jeuImportParId, compteurs: compteurs);
  }

  int fiches(MagasinMemoire m) => ['produits', 'lots', 'mouvements', collectionLots].fold<int>(0, (t, c) => t + m.toutes(c).length);

  // =================================================================================================================================
  group('L\'IDENTITÉ DE CONTENU', () {
    test('64 hexadécimaux, stable sous les variations de FORME du même inventaire, différente à la moindre variation de CONTENU', () {
      final base = identiteLotImport('grand-stock', inventaire());
      expect(base, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(identiteLotImport('grand-stock', inventaire()), base, reason: 'déterministe');
      // La forme ne change pas le lot : cellules rognées, espaces insécables, entier lu en décimal, lignes finales vides, casse et accent de l'en-tête, cellules vides en fin de ligne.
      final forme = [for (final r in inventaire()) [...r]];
      forme[0] = [for (final c in forme[0]) '${c.toString().toUpperCase()} '];
      forme[1][1] = ' ${forme[1][1]} ';
      forme[1][4] = (forme[1][4] as num).toDouble();
      forme[2] = [...forme[2], '', ''];
      forme.addAll([
        ['', '', ''],
        [null, null]
      ]);
      expect(identiteLotImport('grand-stock', forme), base, reason: 'un classeur et un CSV du même inventaire donnent la même identité');
      // Le contenu change : UNE cellule, UNE ligne de plus, le jeu.
      final cellule = [for (final r in inventaire()) [...r]]..[1][4] = ((inventaire()[1][4] as num) + 1);
      expect(identiteLotImport('grand-stock', cellule), isNot(base), reason: 'une seule cellule qui change : un AUTRE lot');
      expect(identiteLotImport('grand-stock', [...inventaire(), ['GANT2', 'Gants', 'Consommables', 'Boîte', 5]]), isNot(base));
      expect(identiteLotImport('autre-jeu', inventaire()), isNot(base), reason: 'le même contenu dans un autre jeu est un autre lot');
    });

    test('la SÉRIE dérive de l\'identité ; la tentative n\'ajoute que son suffixe ; une série n\'est reconnue que pour sa propre identité', () {
      final id = identiteLotImport('grand-stock', inventaire());
      final s1 = serieDuLotImport(id), s2 = serieDuLotImport(id, 2);
      expect([s1, s2], ['IMP${id.substring(0, 20)}', 'IMP${id.substring(0, 20)}T2']);
      expect([serieEstDeLIdentite(s1, id), serieEstDeLIdentite(s2, id), serieEstDeLIdentite('IMPautre', id), serieEstDeLIdentite('${s1}x', id)], [true, true, false, false]);
    });
  });

  // =================================================================================================================================
  group('DEUX FILEULS, MÊME FICHIER', () {
    test('les deux écrivent sous les MÊMES identifiants de fiche (série commune), chacun avec son marquage propre', () {
      final a = fileulEcrit('DIMF1a'), b = fileulEcrit('DIMF2a');
      expect(a.serie, b.serie);
      expect(a.demande['serieIdentifiants'], b.demande['serieIdentifiants']);
      for (final c in ['produits', 'lots', 'mouvements']) {
        expect({for (final f in a.fileul.toutes(c)) f['id']}.where((i) => '$i'.contains(a.serie)), {for (final f in b.fileul.toutes(c)) f['id']}.where((i) => '$i'.contains(a.serie)),
            reason: c);
      }
      expect(a.fileul.toutes('produits').firstWhere((f) => f['code'] == 'MED1')['id'], 'PRO-${a.serie}-1');
      expect(a.fileul.toutes('produits').firstWhere((f) => f['code'] == 'MED1')[champEnAttenteMere], 'DIMF1a', reason: 'le marquage est celui de la DEMANDE, jamais la série commune');
      expect(b.fileul.toutes('produits').firstWhere((f) => f['code'] == 'MED1')[champEnAttenteMere], 'DIMF2a');
    });

    test('LA MÈRE CONFIRME UNE FOIS : la première demande écrit, la seconde est ADOPTÉE (même lot, rien réécrit, rien journalisé), jamais refusée', () {
      final a = fileulEcrit('DIMF1b'), b = fileulEcrit('DIMF2b');
      final mere = MagasinMemoire(magasinInitial);
      final v1 = lamere(a.demande, mere);
      expect([v1.appliquee, v1.adoptee, v1.serie], [true, false, a.serie], reason: '${v1.motif}');
      final fichesApres = fiches(mere), journal = mere.journal.length;
      final v2 = lamere(b.demande, mere);
      expect([v2.appliquee, v2.adoptee, v2.lot, v2.ecrits, v2.serie], [true, true, v1.lot, v1.ecrits, a.serie], reason: '${v2.motif}');
      expect(fiches(mere), fichesApres, reason: 'rien n\'est réécrit à la mère');
      expect(mere.journal.length, journal, reason: 'aucune ligne de journal de plus');
      expect(mere.toutes(collectionLots).where((l) => l['etat'] == 'applique'), hasLength(1), reason: 'UN seul lot confirmé');
      expect(mere.toutes('produits').where((f) => f['code'] == 'MED1'), hasLength(1));
      final champs = v2.versChamps(traitePar: 'Mère', traiteLe: '2026-11-13');
      expect([champs['etat'], champs['resultatAdoptee'], champs['resultatCode'], champs['resultatSerie']], [demandeImportAppliquee, true, '', a.serie]);
      expect(libelleEtatDemandeImport({...b.demande, ...champs}).libelle, 'Déjà confirmé par la mère, adopté');
      expect(libelleEtatDemandeImport({...a.demande, ...v1.versChamps(traitePar: 'Mère', traiteLe: 'x')}).libelle, 'Appliquée par la mère');
      // Même série : aucune suite de restitution pour le second, il lève simplement son marquage.
      expect(suiteDuVerdict({...b.demande, ...champs}), SuiteDuVerdict.leverLeMarquage);
    });

    test('LE REJEU : chaque demande rejouée 1, 2, 3 fois, dans le désordre, rend le même verdict et n\'ajoute ni fiche ni ligne de journal', () {
      final a = fileulEcrit('DIMF1c'), b = fileulEcrit('DIMF2c');
      final mere = MagasinMemoire(magasinInitial);
      final premiers = [lamere(a.demande, mere), lamere(b.demande, mere)];
      final fichesApres = fiches(mere), journal = mere.journal.length;
      for (final ordre in [
        [b, a],
        [a, b, b, a],
        [b, b, b]
      ]) {
        for (final x in ordre) {
          final v = lamere(x.demande, mere);
          final attendu = premiers[identical(x, a) ? 0 : 1];
          expect([v.appliquee, v.adoptee, v.lot, v.ecrits], [attendu.appliquee, attendu.adoptee, attendu.lot, attendu.ecrits]);
        }
      }
      expect(fiches(mere), fichesApres);
      expect(mere.journal.length, journal);
      expect(mere.toutes(collectionLots).where((l) => l['etat'] == 'applique'), hasLength(1));
    });

    test('UNE DEMANDE NE SE FAIT PAS PASSER POUR UN AUTRE LOT : l\'identité déclarée doit être celle des lignes et la série celle de l\'identité (jamais d\'adoption d\'un lot qui n\'est pas le sien)', () {
      final a = fileulEcrit('DIMF1d');
      final mere = MagasinMemoire(magasinInitial);
      expect(lamere(a.demande, mere).appliquee, isTrue);
      final fichesApres = fiches(mere);
      // Un fichier DIFFÉRENT qui déclare l'identité (et la série) du premier pour se faire adopter sans écrire.
      final autre = [for (final r in inventaire()) [...r]]..[1][4] = 999;
      final b = fileulEcrit('DIMF2d', lignes: autre);
      final forgee = {...b.demande, 'identiteLot': a.identite, 'serieIdentifiants': a.serie};
      final v = lamere(forgee, mere);
      expect([v.appliquee, v.code], [false, 'IDENTITE_LOT_INCOHERENTE']);
      // Une série qui n'est pas celle de l'identité déclarée est refusée de même.
      final v2 = lamere({...b.demande, 'serieIdentifiants': a.serie}, mere);
      expect([v2.appliquee, v2.code], [false, 'IDENTITE_LOT_INCOHERENTE']);
      expect(fiches(mere), fichesApres, reason: 'rien n\'est écrit');
    });

    test('UNE CELLULE CHANGE : un AUTRE lot, jamais reconnu comme le même ; ses articles recouvrent ceux du premier lot : refus DOUBLON_MAGASIN nommé', () {
      final a = fileulEcrit('DIMF1e');
      final autre = [for (final r in inventaire()) [...r]]..[1][4] = ((inventaire()[1][4] as num) + 1);
      final b = fileulEcrit('DIMF2e', lignes: autre);
      expect(b.identite, isNot(a.identite));
      expect(b.serie, isNot(a.serie));
      final mere = MagasinMemoire(magasinInitial);
      expect(lamere(a.demande, mere).appliquee, isTrue);
      final v = lamere(b.demande, mere);
      expect([v.appliquee, v.adoptee, v.code], [false, false, 'DOUBLON_MAGASIN']);
      expect(mere.toutes('produits').where((f) => f['code'] == 'MED1'), hasLength(1), reason: 'jamais doublé');
    });

    test('LE PREMIER LOT EST REFUSÉ : le refus s\'applique au second dépôt, nommé, sans écriture ni adoption ; un rejeu ne consigne pas un second lot refusé', () {
      final a = fileulEcrit('DIMF1f'), b = fileulEcrit('DIMF2f');
      final mere = MagasinMemoire(magasinInitial);
      mere.inserer('produits', {'id': 'PRD-MERE-1', 'code': 'MED1', 'designation': 'Tenu à la mère', 'categorie': 'Médicaments', 'statut': 'actif'});
      final avant = fiches(mere);
      final v1 = lamere(a.demande, mere), v2 = lamere(b.demande, mere);
      expect([v1.appliquee, v1.code, v2.appliquee, v2.adoptee, v2.code], [false, 'DOUBLON_MAGASIN', false, false, 'DOUBLON_MAGASIN']);
      expect(mere.toutes(collectionLots).where((l) => l['etat'] == 'applique'), isEmpty, reason: 'la mère n\'a rien écrit');
      final consignes = mere.toutes(collectionLots).where((l) => l['etat'] == 'refuse').length;
      expect(consignes, 2, reason: 'un fichier refusé consigné par demande');
      expect(fiches(mere), avant + 2);
      for (var i = 0; i < 3; i++) {
        lamere(a.demande, mere);
        lamere(b.demande, mere);
      }
      expect(mere.toutes(collectionLots).where((l) => l['etat'] == 'refuse'), hasLength(2), reason: 'un rejeu ne consigne rien de plus');
      expect(mere.journal.where((l) => l.startsWith('Import refusé')), hasLength(2));
    });

    test('UN LOT ANNULÉ À LA MÈRE n\'est jamais ressuscité par une demande de la même série : refus nommé LOT_ANNULE_A_LA_MERE (une nouvelle tentative prend une série neuve)', () {
      final a = fileulEcrit('DIMF1g'), b = fileulEcrit('DIMF2g');
      final mere = MagasinMemoire(magasinInitial, profil: profilDe('admin'));
      final v1 = lamere(a.demande, mere);
      final lot = mere.toutes(collectionLots).firstWhere((l) => l['etat'] == 'applique');
      mere
        ..profil = profilDe('admin')
        ..utilisateurFixe = '${lot['par']}';
      expect(annulerLot(jeuImportParId, lot['id'], 'erreur', mere).ok, isTrue, reason: '${v1.lot}');
      final fichesApres = fiches(mere);
      final v2 = lamere(b.demande, mere);
      expect([v2.appliquee, v2.code], [false, 'LOT_ANNULE_A_LA_MERE']);
      expect(fiches(mere), fichesApres);
    });
  });

  // =================================================================================================================================
  group('LE MÊME FICHIER ENCORE UNE FOIS', () {
    test('DÉJÀ TENU : le même fichier est analysé comme déjà importé (lignes ignorées et nommées LOT_DEJA_IMPORTE), appliquer répond le même code, rien n\'est écrit', () {
      final a = fileulEcrit('DIMF1h');
      final avant = fiches(a.fileul);
      final analyse = analyserLignes(jeu, inventaire(), 'x.xlsx', a.fileul);
      expect([analyse.accepte, analyse.aEcrire, analyse.compte.ignores, analyse.compte.refus], [true, 0, 3, 0]);
      expect({for (final p in analyse.problemes) p.code}, {'LOT_DEJA_IMPORTE'});
      expect(analyse.problemes.first.motif, allOf(contains('déjà importé'), contains(a.serie)));
      final r = appliquer(jeu, analyse, a.fileul);
      expect([r.ok, r.code], [false, 'LOT_DEJA_IMPORTE']);
      expect(r.motif, contains('déjà importé'));
      expect(fiches(a.fileul), avant, reason: 'ni fiche, ni lot consigné');
      // Même chose sur un AUTRE poste qui a reçu les fiches de la mère (elles portent l'identité du contenu).
      final autre = MagasinMemoire(magasinInitial, profil: profilDe('stock'));
      for (final c in ['produits', 'lots', 'mouvements']) {
        for (final f in a.fileul.toutes(c)) {
          if (f[champSerieDemande] != null) autre.toutes(c).add({...f}..remove(champEnAttenteMere));
        }
      }
      final tardif = analyserLignes(jeu, inventaire(), 'y.csv', autre);
      expect([tardif.accepte, tardif.aEcrire], [true, 0]);
      expect({for (final p in tardif.problemes) p.code}, {'LOT_DEJA_IMPORTE'});
      // Un fichier dont UNE cellule change n'est pas le même lot : DOUBLON_MAGASIN, refus.
      final cellule = [for (final r in inventaire()) [...r]]..[1][4] = 7;
      final modifie = analyserLignes(jeu, cellule, 'z.xlsx', autre);
      expect(modifie.accepte, isFalse);
      expect({for (final p in modifie.problemes) p.code}, contains('DOUBLON_MAGASIN'));
      expect({for (final p in modifie.problemes) p.code}, isNot(contains('LOT_DEJA_IMPORTE')));
    });

    test('UNE FICHE ARCHIVÉE À LA MAIN (ou d\'un lot que personne n\'a défait) continue de compter comme déjà tenue ; seule la défaite d\'un lot libère ses fiches', () {
      final a = fileulEcrit('DIMF1i');
      // Le gestionnaire archive tout à la main : le lot reste appliqué (personne ne l'a défait), les articles existent toujours (RG-14).
      for (final c in ['produits', 'lots', 'mouvements']) {
        for (final f in a.fileul.toutes(c).where((f) => f[champSerieDemande] != null).toList()) {
          a.fileul.archiver(c, f['id'], 'à la main');
        }
      }
      final analyse = analyserLignes(jeu, inventaire(), 'x.xlsx', a.fileul);
      expect(analyse.accepte, isFalse, reason: 'sans lot défait, la fiche archivée bloque encore le même code');
    });

    test('RÉIMPORT APRÈS ANNULATION par le MÊME fileul : permis, sous une série neuve (tentative 2), jamais une fiche archivée réutilisée ; une fois écrit, il ne se réimporte plus', () {
      final a = fileulEcrit('DIMF1j');
      a.fileul.profil = profilDe('stock');
      a.fileul.utilisateurFixe = 'GESTIONNAIRE DIMF1j';
      expect(annulerLot(jeuImportParId, a.resultat.lot!['id'], 'erreur de fichier', a.fileul).ok, isTrue);
      expect(a.fileul.actives('produits').where((f) => f['code'] == 'MED1'), isEmpty);
      final prep = preparerLotImport(jeu, inventaire(), a.fileul);
      expect(prep.identite, a.identite);
      expect(prep.serie, '${a.serie}T2', reason: 'la série de la première tentative porte des fiches archivées : une série neuve');
      final b = fileulEcrit('DIMF1k', sur: a.fileul);
      expect(b.serie, '${a.serie}T2');
      expect(b.fileul.actives('produits').where((f) => f['code'] == 'MED1'), hasLength(1), reason: 'écrit une fois');
      expect({for (final f in b.fileul.toutes('produits')) f['id']}, containsAll(['PRO-${a.serie}-1', 'PRO-${a.serie}T2-1']), reason: 'l\'archivée reste, la neuve s\'ajoute');
      // La même série ne se réécrit jamais sur une fiche archivée : le port refuse.
      final p = PortDemandeImport(a.fileul, demandeId: a.serie, compteurs: compteurs);
      expect(() => p.inserer('produits', {'id': 'PRO-${a.serie}-1', 'code': 'X'}), throwsStateError);
      // Une troisième tentative (après une seconde annulation) prend T3.
      expect(annulerLot(jeuImportParId, b.resultat.lot!['id'], 'encore', a.fileul).ok, isTrue);
      expect(preparerLotImport(jeu, inventaire(), a.fileul).serie, '${a.serie}T3');
    });

    test('L\'ADOPTION D\'UNE AUTRE SÉRIE : la mère tient le lot de la tentative 2 ; le second fileul (série de la tentative 1) est adopté, nommé, et REBASÉ (restitution, pas un refus)', () {
      final a = fileulEcrit('DIMF1l');
      a.fileul.profil = profilDe('stock');
      a.fileul.utilisateurFixe = 'GESTIONNAIRE DIMF1l';
      annulerLot(jeuImportParId, a.resultat.lot!['id'], 'erreur', a.fileul);
      final a2 = fileulEcrit('DIMF1m', sur: a.fileul);
      final b = fileulEcrit('DIMF2l');
      expect(a2.serie, isNot(b.serie));
      final mere = MagasinMemoire(magasinInitial);
      final v1 = lamere(a2.demande, mere);
      expect([v1.appliquee, v1.adoptee, v1.serie], [true, false, a2.serie]);
      final fichesApres = fiches(mere);
      final v2 = lamere(b.demande, mere);
      expect([v2.appliquee, v2.adoptee, v2.serie, v2.lot], [true, true, a2.serie, v1.lot], reason: '${v2.motif}');
      expect(fiches(mere), fichesApres);
      final champs = v2.versChamps(traitePar: 'Mère', traiteLe: 'x');
      final demande = {...b.demande, ...champs};
      expect(suiteDuVerdict(demande), SuiteDuVerdict.rebaser, reason: 'séries différentes : l\'écriture locale est rebasée');
      // Une fois rebasé, plus rien à faire (restitution posée), jamais un second rebasage.
      expect(suiteDuVerdict({...demande, 'restitution': restitutionFaite}), SuiteDuVerdict.aucune);
      expect(suiteDuVerdict({...demande, 'marquageLeve': true}), SuiteDuVerdict.aucune);
    });

    test('LE RÉSULTAT DOIT ÊTRE LE MÊME : un fileul qui a écrit d\'autres lignes que le lot tenu par la mère n\'est pas adopté (RESULTAT_DIFFERENT, il restitue)', () {
      final a = fileulEcrit('DIMF1n'), b = fileulEcrit('DIMF2n');
      final mere = MagasinMemoire(magasinInitial);
      expect(lamere(a.demande, mere).appliquee, isTrue);
      final v = lamere({...b.demande, 'rangsEcrits': [2]}, mere);
      expect([v.appliquee, v.code], [false, 'RESULTAT_DIFFERENT']);
    });
  });

  // =================================================================================================================================
  group('LA RESTITUTION REJOUÉE', () {
    test('une restitution PARTIELLE rejouée reste PARTIELLE, rend les mêmes fiches gardées, sans second mouvement inverse ni seconde ligne de journal', () {
      final e = fileulEcrit('DIMF1o');
      final l1 = e.fileul.toutes('lots').firstWhere((f) => f['numeroLot'] == 'L1');
      l1['quantiteRestante'] = 90;
      final med1 = e.fileul.toutes('produits').firstWhere((f) => f['code'] == 'MED1');
      med1['stockGros'] = 140;
      med1['stock'] = 140;
      final r1 = restituerLotDirect(jeuImportParId, e.resultat.lot!['id'], codeRefus: 'DOUBLON_MAGASIN', motifRefus: 'déjà tenu', port: e.fileul);
      expect(r1.etat, restitutionPartielle);
      final mouvements = e.fileul.toutes('mouvements').length, journal = e.fileul.journal.length;
      for (var i = 0; i < 3; i++) {
        final r = restituerLotDirect(jeuImportParId, e.resultat.lot!['id'], codeRefus: 'X', motifRefus: 'x', port: e.fileul);
        expect([r.ok, r.etat, r.archives, r.gardees.length], [true, restitutionPartielle, r1.archives, r1.gardees.length], reason: 'rejeu $i : jamais « faite »');
        expect({for (final g in r.gardees) '${g['collection']}:${g['id']}'}, {for (final g in r1.gardees) '${g['collection']}:${g['id']}'});
      }
      expect(e.fileul.toutes('mouvements').length, mouvements, reason: 'aucune seconde contre-passation');
      expect(e.fileul.journal.length, journal);
    });
  });
}
