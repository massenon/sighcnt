import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'aide_vecteurs.dart';
import 'import_test.dart' show MagasinMemoire, matriceReelle, profilDe;

/// LA DEMANDE D'IMPORT D'UN FILEUL À LA MÈRE (lot IMP-C, réponse Q5) : un référentiel de configuration (famille R) importé à un fileul passe par une demande vérifiée ; la mère
/// REJOUE l'analyse sous le rôle de l'auteur, applique par le chemin de l'import local ou refuse en nommant. Les fichiers sont ceux que la maquette a écrits et mesurés.
void main() {
  final V = lireVecteurs('import');
  final magasinInitial = (V['magasin'] as Map).cast<String, Object?>();
  List<List<Object?>> lignesDuCas(String id) {
    final c = liste(V['cas']).firstWhere((x) => x['id'] == id);
    return [
      for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
    ];
  }

  /// Ce que le FILEUL fait : vérifier le fichier sur SON magasin, puis composer la demande (un fichier refusé ne part jamais).
  Map<String, Object?> deposer(String cas, String role, {String par = 'GESTIONNAIRE TEST', Map<String, Object?>? magasin}) {
    final jeu = jeuImportParId('${liste(V['cas']).firstWhere((x) => x['id'] == cas)['jeu']}')!;
    final port = MagasinMemoire(magasin ?? magasinInitial, profil: profilDe(role))..utilisateurFixe = par;
    final a = analyserLignes(jeu, lignesDuCas(cas), '$cas.xlsx', port)..empreinte = 'abc';
    expect(a.accepte, isTrue, reason: 'le fileul n\'envoie que ce qu\'il a vérifié');
    return composerDemandeImport(
        id: 'DIM1', jeu: jeu, analyse: a, role: role, par: par, jour: '2026-11-01', restreint: matriceReelle.declaration(jeu.id)!.restreint);
  }

  VerdictDemandeImport lamere(Map<String, Object?> demande, MagasinMemoire mere) {
    mere
      ..profil = profilDe('${demande['demandeRole']}')
      ..utilisateurFixe = '${demande['demandePar']}';
    return traiterDemandeImport(demande, mere, jeuImportParId);
  }

  test('QUAND : un jeu passe par une demande quand une de ses collections cibles est de configuration (famille R), jamais pour l\'activité', () {
    final config = {...cfbEssentielles, 'utilisateurs'};
    for (final jeu in ['assureurs', 'plan-comptable', 'fournisseurs', 'souscripteurs', 'analyses-modele']) {
      expect(jeuExigeLaMere(matriceReelle.declaration(jeu)!, config), isTrue, reason: jeu);
    }
    for (final jeu in ['patients', 'soldes-ouverture']) {
      expect(jeuExigeLaMere(matriceReelle.declaration(jeu)!, config), isFalse, reason: '$jeu s\'écrit au fileul, par ses propres règles de fusion');
    }
    // UN JEU RESTREINT n'y passe jamais : ses lignes (identité, salaire) ne voyagent pas dans une fiche partagée ; il s'importe à la mère.
    final personnel = matriceReelle.declaration('personnel')!;
    expect(personnel.restreint && personnel.collections.any(config.contains), isTrue, reason: 'le personnel est de configuration ET restreint');
    expect(jeuExigeLaMere(personnel, config), isFalse);
    expect(jeuReserveALaMere(personnel, config), isTrue);
    expect(jeuReserveALaMere(matriceReelle.declaration('assureurs')!, config), isFalse);
  });

  test('LE FILEUL DÉPOSE une fiche vérifiée : jeu, fichier, lignes, comptes, rôle et nom de l\'auteur, état « en attente » ; elle porte les lignes que la mère rejouera', () {
    final d = deposer('as-valide', 'comptable');
    expect(d['etat'], demandeImportEnAttente);
    expect([d['jeu'], d['demandeRole'], d['demandePar'], d['aEcrire'], d['nbLignes']], ['assureurs', 'comptable', 'GESTIONNAIRE TEST', 2, 2]);
    expect((d['lignes'] as List).length, 3, reason: 'l\'en-tête et les deux lignes du fichier');
    expect(d['restreint'], isFalse);
    expect(jsonEncode(d), contains('SUNU'));
  });

  test('LA MÈRE REJOUE puis APPLIQUE par le chemin de l\'import local : le lot est signé de l\'auteur, annulable, et les lignes de la demande sont effacées', () {
    final mere = MagasinMemoire(magasinInitial);
    final d = deposer('as-valide', 'comptable');
    final v = lamere(d, mere);
    expect(v.appliquee, isTrue, reason: '${v.motif}');
    expect([v.lot, v.ecrits], ['IMP-2026-001', 2]);
    final assureurs = mere.actives('assureurs').where((a) => a['lotImport'] == 'IMP-2026-001').toList();
    expect(assureurs.map((a) => a['code']).toSet(), {'SUNU', 'OLEA'});
    expect(assureurs.every((a) => a['validePar'] == 'GESTIONNAIRE TEST'), isTrue, reason: 'RG-12 : le lot est au nom de l\'auteur de la demande, pas de la mère');
    final lot = mere.parId(collectionLots, mere.toutes(collectionLots).first['id'])!;
    expect([lot['etat'], lot['par']], ['applique', 'GESTIONNAIRE TEST']);
    final champs = v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-01');
    expect(champs['etat'], demandeImportAppliquee);
    expect(champs['lignes'], isEmpty, reason: 'aucune valeur de cellule ne reste à la demande une fois le verdict rendu');
    expect(champs['resultatLot'], 'IMP-2026-001');
  });

  test('LA MÈRE REJOUE VRAIMENT : une fiche créée par un autre poste entre-temps refuse la demande en nommant le code, le motif et le geste (rien n\'est écrit)', () {
    final d = deposer('as-valide', 'comptable');
    final mere = MagasinMemoire(magasinInitial);
    mere.inserer('assureurs', {'code': 'SUNU', 'nom': 'SUNU ASSURANCES (créé ailleurs)', 'statut': 'actif'});
    final avant = mere.toutes('assureurs').length;
    final v = lamere(d, mere);
    expect(v.appliquee, isFalse);
    expect(v.code, 'DOUBLON_MAGASIN');
    expect(v.motif, allOf(contains('rejoué à la mère'), contains('ligne 2')));
    expect(v.geste, isNotEmpty);
    expect(mere.toutes('assureurs').length, avant, reason: 'rien n\'a été écrit');
    expect(mere.toutes(collectionLots).single['etat'], 'refuse', reason: 'le fichier refusé est consigné à l\'historique de la mère');
    final champs = v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-01');
    expect([champs['etat'], champs['resultatCode']], [demandeImportRefusee, 'DOUBLON_MAGASIN']);
    expect(champs['lignes'], isEmpty);
  });

  test('LA MÈRE RELIT LE DROIT : un rôle qui ne détient pas le jeu voit sa demande refusée en nommant, même déposée par un fileul qui a contourné son bouton', () {
    // Le caissier n'a aucun droit sur les compagnies : une demande forgée (`demandeRole: caissier`) est refusée par la mère, rien n'est écrit.
    final d = {...deposer('as-valide', 'comptable'), 'demandeRole': 'caissier'};
    final mere = MagasinMemoire(magasinInitial);
    final avant = mere.toutes('assureurs').length;
    final v = lamere(d, mere);
    expect([v.appliquee, v.code], [false, 'DROIT_IMPORT_REFUSE']);
    expect(v.motif, contains('ne détient pas le droit de importer le jeu'));
    expect(mere.toutes('assureurs').length, avant);
    expect(mere.toutes(collectionLots), isEmpty, reason: 'un refus de droit ne se consigne pas');
  });

  test('UN JEU RESTREINT ne recopie aucune valeur de cellule dans le verdict de la mère (motif fixe), et un jeu inconnu est refusé en nommant', () {
    // Les patients s'écrivent au fileul (ils ne passent pas par une demande), mais le verdict d'un jeu restreint reste masqué si une demande en porte un.
    final d = deposer('pa-valide', 'reception', par: 'ACCUEIL TEST');
    final mere = MagasinMemoire(magasinInitial);
    mere.inserer('patients', {'code': 'CNT/12/24', 'nom': 'DEJA', 'prenom': 'Tenu', 'statut': 'actif'});
    final v = lamere(d, mere);
    expect(v.appliquee, isFalse);
    expect(v.code, 'DOUBLON_MAGASIN');
    expect(jsonEncode([v.motif, v.geste]), isNot(contains('CNT/12/24')));
    expect(jsonEncode([v.motif, v.geste]), isNot(contains('DEJA')));
    expect(v.motif, contains('une fiche équivalente est déjà tenue'));
    final inconnu = lamere({...d, 'jeu': 'inconnu'}, MagasinMemoire(magasinInitial));
    expect([inconnu.appliquee, inconnu.code], [false, 'JEU_INCONNU']);
  });

  // =================================================================================================================================
  // LOT IMP-D : le fileul écrit chez lui ET la mère en est avertie par une demande automatique (décision N de la Direction, 12/11/2026).
  // =================================================================================================================================
  final configuration = {...cfbEssentielles, 'utilisateurs', valCollectionValidations, parCollectionParametres, ...tarCollectionsReferentiel}
      .difference({'rolesBase', 'modulesManifeste', 'reglages', 'audit'});
  VoieImportFileul voie(String jeu) => voieImportFileul(matriceReelle.declaration(jeu)!, configuration: configuration);

  /// Ce que le FILEUL fait : vérifier, écrire chez lui sous le port de la demande (identifiants de la demande, marquage), puis composer la demande.
  ({Map<String, Object?> demande, MagasinMemoire fileul, ResultatImport resultat}) ecrireChezLeFileul(String cas, String role,
      {String par = 'GESTIONNAIRE TEST', String idDemande = 'DIMF1x1', Map<String, Object?>? magasin}) {
    final jeu = jeuImportParId('${liste(V['cas']).firstWhere((x) => x['id'] == cas)['jeu']}')!;
    final fileul = MagasinMemoire(magasin ?? magasinInitial, profil: profilDe(role))..utilisateurFixe = par;
    final a = analyserLignes(jeu, lignesDuCas(cas), '$cas.xlsx', fileul)..empreinte = 'abc';
    expect(a.accepte, isTrue, reason: 'le fileul n\'écrit que ce qu\'il a vérifié');
    final r = appliquer(jeu, a, PortDemandeImport(fileul, demandeId: idDemande, marquerEnAttente: true));
    expect(r.ok, isTrue, reason: '${r.motif}');
    final d = composerDemandeImport(
        id: idDemande, jeu: jeu, analyse: a, role: role, par: par, jour: '2026-11-01', restreint: false, lotLocal: '${r.lot!['reference']}', lotLocalId: r.lot!['id']);
    return (demande: d, fileul: fileul, resultat: r);
  }

  test('IMP-D LA VOIE (IMP-E : le Grand Stock aussi) : écriture directe ET demande dès qu\'une cible est de la configuration ; directe pour l\'activité ; la mère seule pour un jeu restreint de configuration', () {
    // LOT IMP-E (décision de la Direction du 13/11/2026) : le Grand Stock (produits, lots, mouvements) s'écrit AUSSI chez le fileul ; son double comptage, mesuré, est levé par l'identité
    // commune des fiches, leur valeur de départ et leur caractère propre au poste tant que la mère n'a pas confirmé.
    for (final jeu in ['assureurs', 'souscripteurs', 'fournisseurs', 'plan-comptable', 'analyses-modele', 'natures-facture', 'centres-couts', 'unites-labo', 'emplacements', 'grand-stock']) {
      expect(voie(jeu), VoieImportFileul.directeEtDemande, reason: jeu);
    }
    for (final jeu in ['patients', 'soldes-ouverture', 'prestataires']) {
      expect(voie(jeu), VoieImportFileul.directe, reason: '$jeu : aucune cible de configuration, écrit comme avant, sans demande');
    }
    expect(voie('personnel'), VoieImportFileul.reserveeALaMere, reason: 'restreint : ses lignes (identité, salaire) ne voyagent jamais dans une demande (RG-13)');
    expect(collectionsAutoriseesAuFileul(jeuImportParId('fournisseurs')!), {'fournisseurs'}, reason: 'le fileul n\'est autorisé à écrire que les cibles du jeu, rien d\'autre');
  });

  test('IMP-D L\'ÉCRITURE DIRECTE : fiches écrites chez le fileul sous les identifiants de la demande et marquées « en attente de la mère » ; la demande dit ce qui a été écrit', () {
    final e = ecrireChezLeFileul('fo-valide', 'stock');
    final fiches = e.fileul.actives('fournisseurs').where((f) => f['lotImport'] == e.resultat.lot!['reference']).toList();
    expect(fiches.map((f) => f['code']).toSet(), {'CAME', 'LOCAL'}, reason: 'écrit chez le fileul tout de suite');
    expect(fiches.map((f) => f['id']).toSet(), {'FOU-DIMF1x1-1', 'FOU-DIMF1x1-2'}, reason: 'identifiant de la demande, jamais le « plus un » du poste');
    expect(fiches.every((f) => f[champEnAttenteMere] == 'DIMF1x1'), isTrue, reason: 'le marquage est lisible tant que la mère n\'a pas tranché');
    expect(e.fileul.toutes(collectionLots).single.containsKey(champEnAttenteMere), isFalse, reason: 'le lot local n\'est pas une fiche de la mère : pas de marquage');
    final d = e.demande;
    expect([d['ecritureDirecte'], d['lotLocal'], d['etat']], [true, e.resultat.lot!['reference'], demandeImportEnAttente]);
    expect(d['rangsEcrits'], [2, 3], reason: 'la mère devra écrire exactement ces lignes (l\'en-tête est la ligne 1)');
    // Une demande de l'IMP-C (demande seule) ne porte rien de tout cela.
    final jeu = jeuImportParId('assureurs')!;
    final a = analyserLignes(jeu, lignesDuCas('as-valide'), 'x.xlsx', MagasinMemoire(magasinInitial, profil: profilDe('comptable')));
    final seule = composerDemandeImport(id: 'D', jeu: jeu, analyse: a, role: 'comptable', par: 'P', jour: '2026-11-01', restreint: false);
    expect(seule.containsKey('ecritureDirecte'), isFalse);
    expect(seule.containsKey('rangsEcrits'), isFalse);
  });

  test('IMP-D CAS 1, LA MÈRE APPLIQUE : même résultat, mêmes identifiants ; la fiche de la mère REMPLACE celle du fileul, aucun doublon, le marquage tombe', () {
    final e = ecrireChezLeFileul('fo-valide', 'stock');
    final mere = MagasinMemoire(magasinInitial);
    // Le pont RENOMME la demande en arrivant à la mère (`F1-` + identifiant) : la série des identifiants de fiche ne doit pas suivre ce renommage.
    final arrivee = {...e.demande, 'id': 'F1-${e.demande['id']}'};
    expect(arrivee['serieIdentifiants'], 'DIMF1x1');
    final v = lamere(arrivee, mere);
    expect(v.appliquee, isTrue, reason: '${v.motif}');
    final delaMere = mere.actives('fournisseurs').where((f) => f['lotImport'] == v.lot).toList();
    expect(delaMere.map((f) => f['id']).toSet(), {'FOU-DIMF1x1-1', 'FOU-DIMF1x1-2'}, reason: 'la mère rejoue avec la MÊME formule d\'identifiant');
    expect(delaMere.every((f) => !f.containsKey(champEnAttenteMere)), isTrue, reason: 'la fiche de la mère ne porte pas le marquage');
    expect(delaMere.every((f) => f['validePar'] == 'GESTIONNAIRE TEST'), isTrue, reason: 'RG-12 : au nom de l\'auteur de la demande');
    // La configuration de la mère arrive au fileul : elle remplace les fiches du fileul par identifiant (`appliquerDistante`).
    final chez = e.fileul.toutes('fournisseurs');
    for (final f in delaMere) {
      final i = chez.indexWhere((x) => x['id'] == f['id']);
      expect(i, greaterThanOrEqualTo(0), reason: 'la fiche existe déjà chez le fileul sous le MÊME identifiant');
      chez[i]
        ..clear()
        ..addAll(f);
    }
    final codes = [for (final f in e.fileul.actives('fournisseurs')) '${f['code']}'];
    expect(codes.where((c) => c == 'CAME').length, 1, reason: 'une identité de ligne, jamais deux versions d\'un même code');
    expect(codes.where((c) => c == 'LOCAL').length, 1);
    expect(e.fileul.actives('fournisseurs').where((f) => f.containsKey(champEnAttenteMere)), isEmpty, reason: 'confirmé par la mère : plus rien « en attente »');
  });

  test('IMP-D CAS 2, LA MÈRE REFUSE : doublon créé ailleurs entre-temps (jeu en mode « refuser »), le verdict nomme le code, rien n\'est écrit à la mère', () {
    final e = ecrireChezLeFileul('as-valide', 'comptable', idDemande: 'DIMF2y1');
    final mere = MagasinMemoire(magasinInitial);
    mere.inserer('assureurs', {'code': 'SUNU', 'nom': 'SUNU créé par un autre poste', 'statut': 'actif'});
    final avant = mere.toutes('assureurs').length;
    final v = lamere(e.demande, mere);
    expect([v.appliquee, v.code], [false, 'DOUBLON_MAGASIN']);
    expect(v.motif, contains('rejoué à la mère'));
    expect(v.geste, isNotEmpty);
    expect(mere.toutes('assureurs').length, avant);
  });

  test('IMP-D CAS 2 BIS, RÉSULTAT DIFFÉRENT : en mode « ignorer » la mère détient déjà une fiche que le fileul a écrite ; elle ne confirme pas un résultat qui n\'est pas le sien, elle nomme les lignes', () {
    final e = ecrireChezLeFileul('fo-valide', 'stock');
    final mere = MagasinMemoire(magasinInitial);
    mere.inserer('fournisseurs', {'code': 'CAME', 'nom': 'CAME (créé par un autre poste)', 'statut': 'actif'});
    final avant = mere.toutes('fournisseurs').length;
    final v = lamere(e.demande, mere);
    expect([v.appliquee, v.code], [false, 'RESULTAT_DIFFERENT']);
    expect(v.motif, allOf(contains('pas le même résultat'), contains('ligne 2'), contains('déjà tenue')));
    expect(v.geste, contains('restituée'));
    expect(mere.toutes('fournisseurs').length, avant, reason: 'rien n\'est écrit à la mère');
    // Sans l'écriture directe (lot IMP-C), la même situation écrit l'autre ligne : la règle ne s'applique qu'aux demandes dont le fileul a déjà écrit.
    final seule = {...e.demande}..remove('ecritureDirecte')..remove('rangsEcrits');
    final v2 = lamere(seule, MagasinMemoire(magasinInitial)..inserer('fournisseurs', {'code': 'CAME', 'nom': 'CAME', 'statut': 'actif'}));
    expect(v2.appliquee, isTrue, reason: 'une demande sans écriture directe écrit ce qui reste, comme avant');
  });

  test('IMP-D DEUX FILEULS IMPORTENT LE MÊME CODE : la mère applique la première demande, refuse la seconde en nommant ; le second fileul restitue, il ne reste qu\'une fiche par code', () {
    final e1 = ecrireChezLeFileul('as-valide', 'comptable', par: 'COMPTABLE UN', idDemande: 'DIMF1a1');
    final e2 = ecrireChezLeFileul('as-valide', 'comptable', par: 'COMPTABLE DEUX', idDemande: 'DIMF2b1');
    final mere = MagasinMemoire(magasinInitial);
    final v1 = lamere(e1.demande, mere);
    final v2 = lamere(e2.demande, mere);
    expect([v1.appliquee, v2.appliquee, v2.code], [true, false, 'DOUBLON_MAGASIN']);
    // Le second fileul reçoit les fiches de la première demande ET restitue la sienne : une seule fiche active par code chez lui.
    for (final f in mere.actives('assureurs').where((f) => f['lotImport'] == v1.lot)) {
      e2.fileul.toutes('assureurs').add({...f});
    }
    final r = restituerLotDirect(jeuImportParId, e2.resultat.lot!['id'], codeRefus: '${v2.code}', motifRefus: '${v2.motif}', port: e2.fileul);
    expect([r.ok, r.archives, r.gardees], [true, 2, isEmpty]);
    final codes = [for (final f in e2.fileul.actives('assureurs')) '${f['code']}'];
    expect(codes.where((c) => c == 'SUNU').length, 1);
    expect(codes.where((c) => c == 'OLEA').length, 1);
    expect(e2.fileul.actives('assureurs').where((f) => f['id'].toString().contains('DIMF2b1')), isEmpty);
  });

  test('IMP-D LA RESTITUTION archive au lieu de supprimer (RG-14), sans exiger le droit d\'annuler, une seule fois, et marque le lot', () {
    final e = ecrireChezLeFileul('fo-valide', 'stock');
    final avant = e.fileul.toutes('fournisseurs').length;
    // Le profil du fileul n'a PAS le droit d'annuler ce jeu : la restitution n'est pas son geste, c'est la suite d'une décision de la mère.
    e.fileul.profil = profilDe('caissier');
    final r = restituerLotDirect(jeuImportParId, e.resultat.lot!['id'], codeRefus: 'DOUBLON_MAGASIN', motifRefus: 'une fiche équivalente est déjà tenue', port: e.fileul);
    expect([r.ok, r.archives, r.gardees.length, r.etat], [true, 2, 0, restitutionFaite]);
    expect(e.fileul.toutes('fournisseurs').length, avant, reason: 'jamais une suppression physique : les fiches sont archivées');
    final lot = e.fileul.parId(collectionLots, e.resultat.lot!['id'])!;
    expect([lot['etat'], lot['motifRestitution']], ['restitue', contains('DOUBLON_MAGASIN')]);
    expect(e.fileul.actives('fournisseurs').where((f) => f['code'] == 'CAME' || f['code'] == 'LOCAL'), isEmpty);
    expect(e.fileul.journal.any((l) => l.startsWith('Import restitué')), isTrue, reason: 'RG-12');
    final encore = restituerLotDirect(jeuImportParId, e.resultat.lot!['id'], codeRefus: 'X', motifRefus: 'x', port: e.fileul);
    expect([encore.ok, encore.archives, encore.etat], [true, 2, restitutionFaite], reason: 'idempotent : un lot restitué ne se restitue pas deux fois, la restitution rejouée rend ce qu\'elle avait fait (lot IDEM)');
    expect(e.fileul.journal.where((l) => l.startsWith('Import restitué')), hasLength(1), reason: 'aucune seconde ligne de journal');
  });

  test('IMP-D UNE PIÈCE ÉMISE ENTRE-TEMPS : la fiche qu\'elle utilise n\'est pas archivée, elle reste marquée avec le motif de la mère ; les autres sont restituées', () {
    final e = ecrireChezLeFileul('fo-valide', 'stock');
    // Une commande est passée au fournisseur CAME avant le refus de la mère.
    e.fileul.inserer('commandes', {'numero': 'BC-1', 'fournisseurCode': 'CAME', 'statut': 'actif'});
    final r = restituerLotDirect(jeuImportParId, e.resultat.lot!['id'], codeRefus: 'RESULTAT_DIFFERENT', motifRefus: 'la mère ne produirait pas le même résultat', port: e.fileul);
    expect([r.ok, r.archives, r.etat], [true, 1, restitutionPartielle]);
    expect(r.gardees.single['code'], 'FOURNISSEUR_UTILISE');
    final came = e.fileul.toutes('fournisseurs').firstWhere((f) => f['code'] == 'CAME');
    expect(came['statut'], isNot('archive'), reason: 'une pièce émise ne se réécrit jamais : la fiche qu\'elle utilise reste en place');
    expect(came[champRefuseeParMere], allOf(contains('RESULTAT_DIFFERENT'), contains('pas le même résultat')));
    expect(e.fileul.toutes('fournisseurs').firstWhere((f) => f['code'] == 'LOCAL')['statut'], 'archive');
    expect(e.fileul.parId(collectionLots, e.resultat.lot!['id'])!['restitueGardees'], 1);
  });

  test('IMP-D L\'ANNULATION CHEZ LE FILEUL : permise tant que la mère n\'a pas statué, refusée en nommant une fois confirmée ou refusée ; le retrait d\'une demande efface ses lignes', () {
    final e = ecrireChezLeFileul('fo-valide', 'stock');
    expect(refusAnnulationLotDirect(e.demande), isNull, reason: 'en attente : le fileul peut annuler son lot');
    expect(refusAnnulationLotDirect(null), isNull, reason: 'un lot sans demande s\'annule comme avant');
    final confirmee = {...e.demande, 'etat': demandeImportAppliquee, 'resultatLot': 'IMP-2026-009'};
    final refus = refusAnnulationLotDirect(confirmee)!;
    expect(refus.code, 'LOT_CONFIRME_PAR_LA_MERE');
    expect(refus.motif, contains('IMP-2026-009'));
    expect(refus.geste, contains('mère'));
    expect(refusAnnulationLotDirect({...e.demande, 'etat': demandeImportRefusee})!.code, 'RESTITUTION_PAR_LA_MERE');
    final c = champsRetraitDemande(par: 'GESTIONNAIRE TEST', jour: '2026-11-01');
    expect([c['etat'], c['lignes']], [demandeImportRetiree, isEmpty]);
  });

  test('IMP-D LA SUITE DU VERDICT et LE LIBELLÉ : jamais « appliquée » avant la confirmation de la mère, la restitution se lit, le marquage se lève une fois', () {
    final e = ecrireChezLeFileul('fo-valide', 'stock');
    final attente = libelleEtatDemandeImport(e.demande);
    expect(attente.libelle, 'Écrit chez vous, en attente de la mère');
    expect(attente.libelle.toLowerCase(), isNot(contains('appliqu')), reason: 'jamais un « appliqué » qui n\'est pas confirmé');
    expect(attente.ton, 'attention');
    expect(libelleEtatDemandeImport({...e.demande, 'ecritureDirecte': null}).libelle, 'En attente de la mère', reason: 'demande seule : le libellé du lot IMP-C');
    expect(libelleEtatDemandeImport({...e.demande, 'etat': demandeImportAppliquee}).libelle, 'Appliquée par la mère');
    expect(libelleEtatDemandeImport({...e.demande, 'etat': demandeImportRefusee}).libelle, 'Refusée par la mère, restitution en cours');
    expect(libelleEtatDemandeImport({...e.demande, 'etat': demandeImportRefusee, 'restitution': restitutionFaite}).libelle, 'Refusée par la mère, écriture restituée');
    expect(libelleEtatDemandeImport({...e.demande, 'etat': demandeImportRefusee, 'restitution': restitutionPartielle}).libelle, 'Refusée par la mère, restitution partielle');
    expect(libelleEtatDemandeImport({...e.demande, 'etat': demandeImportRetiree}).libelle, 'Retirée par vous');

    expect(suiteDuVerdict(e.demande), SuiteDuVerdict.aucune, reason: 'la mère n\'a pas répondu : rien à faire, la demande attend (mère injoignable comprise)');
    expect(suiteDuVerdict({...e.demande, 'etat': demandeImportRefusee}), SuiteDuVerdict.restituer);
    expect(suiteDuVerdict({...e.demande, 'etat': demandeImportRefusee, 'restitution': restitutionFaite}), SuiteDuVerdict.aucune, reason: 'une seule restitution');
    expect(suiteDuVerdict({...e.demande, 'etat': demandeImportAppliquee}), SuiteDuVerdict.leverLeMarquage);
    expect(suiteDuVerdict({...e.demande, 'etat': demandeImportAppliquee, 'marquageLeve': true}), SuiteDuVerdict.aucune);
    expect(suiteDuVerdict({...e.demande, 'etat': demandeImportRetiree}), SuiteDuVerdict.aucune);
    expect(suiteDuVerdict({...e.demande, 'ecritureDirecte': null, 'etat': demandeImportRefusee}), SuiteDuVerdict.aucune, reason: 'demande seule : le fileul n\'a rien écrit, rien à restituer');
  });

  // =================================================================================================================================
  // LOT IMP-E : le Grand Stock s'écrit chez le fileul, avec idempotence prouvée (décision de la Direction du 13/11/2026).
  // =================================================================================================================================
  const compteurs = {
    'produits': {'stockGros', 'stockDetail', 'stock'},
    'lots': {'quantiteRestante'},
  };
  ({Map<String, Object?> demande, MagasinMemoire fileul, ResultatImport resultat}) stockChezLeFileul({String idDemande = 'DIMF1s1'}) {
    final jeu = jeuImportParId('grand-stock')!;
    final fileul = MagasinMemoire(magasinInitial, profil: profilDe('stock'))..utilisateurFixe = 'GESTIONNAIRE STOCK';
    final a = analyserLignes(jeu, lignesDuCas('gs-valide'), 'gs-valide.xlsx', fileul)..empreinte = 'abc';
    expect(a.accepte, isTrue);
    final r = appliquerDemande(jeu, a, PortDemandeImport(fileul, demandeId: idDemande, marquerEnAttente: true, compteurs: compteurs));
    expect(r.ok, isTrue, reason: '${r.motif}');
    final d = composerDemandeImport(
        id: idDemande, jeu: jeu, analyse: a, role: 'stock', par: 'GESTIONNAIRE STOCK', jour: '2026-11-13', restreint: false, lotLocal: '${r.lot!['reference']}', lotLocalId: r.lot!['id']);
    return (demande: d, fileul: fileul, resultat: r);
  }

  int total(MagasinMemoire m) => ['produits', 'lots', 'mouvements', collectionLots].fold<int>(0, (t, c) => t + m.toutes(c).length);
  Map<String, Object?> fiche(MagasinMemoire m, String c, bool Function(Map<String, Object?>) q) => m.toutes(c).firstWhere(q);

  test('IMP-E L\'IDENTITÉ et le DÉPART : chaque fiche du Grand Stock porte sa série, un identifiant de demande et, pour un compteur, sa valeur de départ ; la voie du jeu est « directe et demande »', () {
    final e = stockChezLeFileul();
    final med1 = fiche(e.fileul, 'produits', (f) => f['code'] == 'MED1');
    expect(med1['id'], 'PRO-DIMF1s1-1');
    expect(med1[champSerieDemande], 'DIMF1s1');
    expect(med1[champDepartCompteurs], {'stockGros': 150, 'stockDetail': 0, 'stock': 150});
    final l1 = fiche(e.fileul, 'lots', (f) => f['numeroLot'] == 'L1');
    expect([l1['id'], l1[champSerieDemande], l1[champDepartCompteurs]], ['LOT-DIMF1s1-1', 'DIMF1s1', {'quantiteRestante': 100}]);
    expect(fiche(e.fileul, 'mouvements', (f) => f['quantite'] == 50)[champSerieDemande], 'DIMF1s1');
    expect(fiche(e.fileul, 'mouvements', (f) => f['quantite'] == 50).containsKey(champDepartCompteurs), isFalse, reason: 'un mouvement n\'est pas un compteur');
    expect(e.demande['rangsEcrits'], [2, 3, 4], reason: 'les lignes du fichier (la 1 est l\'en-tête)');
    expect(ficheLocaleAuPoste(med1), isTrue, reason: 'en attente de la mère : propre à ce poste');
  });

  test('IMP-E LE REJEU NE COMPTE JAMAIS DEUX FOIS : appliquer la même demande une seconde fois n\'écrit rien (ni fiche, ni lot, ni ligne de journal) et rend le lot déjà écrit', () {
    final e = stockChezLeFileul();
    final jeu = jeuImportParId('grand-stock')!;
    final avantFiches = total(e.fileul), avantJournal = e.fileul.journal.length;
    final a = analyserLignes(jeu, lignesDuCas('gs-valide'), 'gs-valide.xlsx', MagasinMemoire(magasinInitial, profil: profilDe('stock')))..empreinte = 'abc';
    for (var i = 0; i < 3; i++) {
      final r = appliquerDemande(jeu, a, PortDemandeImport(e.fileul, demandeId: 'DIMF1s1', marquerEnAttente: true, compteurs: compteurs));
      expect(r.ok, isTrue);
      expect(r.lot!['reference'], e.resultat.lot!['reference'], reason: 'le lot déjà écrit');
      expect(r.ecrits, e.resultat.ecrits);
    }
    expect(total(e.fileul), avantFiches, reason: 'aucune fiche de plus');
    expect(e.fileul.journal.length, avantJournal, reason: 'aucune ligne de journal de plus');
    // Même sans la preuve du lot, une fiche posée à un identifiant déjà tenu par la même demande n'est jamais doublée.
    final port = PortDemandeImport(e.fileul, demandeId: 'DIMF1s1', compteurs: compteurs);
    final rendue = port.inserer('mouvements', {'reference': 'X'});
    expect(rendue['id'], 'MOU-DIMF1s1-1');
    expect(e.fileul.toutes('mouvements').where((f) => f['id'] == 'MOU-DIMF1s1-1'), hasLength(1));
  });

  test('IMP-E LA MÈRE REJOUE UNE DEMANDE DÉJÀ APPLIQUÉE : même verdict, rien de réécrit (le redémarrage entre l\'écriture et le verdict ne double pas le stock)', () {
    final e = stockChezLeFileul();
    final mere = MagasinMemoire(magasinInitial, profil: profilDe('stock'));
    final premier = (() {
      mere
        ..profil = profilDe('stock')
        ..utilisateurFixe = 'GESTIONNAIRE STOCK';
      return traiterDemandeImport(e.demande, mere, jeuImportParId, compteurs: compteurs);
    })();
    expect([premier.appliquee, premier.ecrits], [true, 7], reason: premier.motif);
    final fichesApres = total(mere), journalApres = mere.journal.length;
    final med1 = fiche(mere, 'produits', (f) => f['code'] == 'MED1');
    expect([med1['id'], med1[champDepartCompteurs], med1.containsKey(champEnAttenteMere)], ['PRO-DIMF1s1-1', {'stockGros': 150, 'stockDetail': 0, 'stock': 150}, false]);
    for (var i = 0; i < 3; i++) {
      final v = traiterDemandeImport(e.demande, mere, jeuImportParId, compteurs: compteurs);
      expect([v.appliquee, v.lot, v.ecrits], [true, premier.lot, premier.ecrits], reason: 'le même verdict');
    }
    expect(total(mere), fichesApres, reason: 'rien de réécrit à la mère');
    expect(mere.journal.length, journalApres, reason: 'aucune ligne de journal de plus');
    expect(mere.toutes('produits').where((f) => f['code'] == 'MED1'), hasLength(1), reason: 'jamais de produit doublé, la seconde analyse ne refuse pas le fichier comme un doublon de la mère elle-même');
  });

  test('IMP-E LA RESTITUTION DU GRAND STOCK : rien n\'est sorti, chaque entrée est contre-passée par un mouvement inverse nommé, les lots et articles sont archivés (RG-14), le stock ne devient pas négatif', () {
    final e = stockChezLeFileul();
    final jeu = jeuImportParId('grand-stock')!;
    expect(jeu.restituer, isNotNull);
    final produitsAvant = e.fileul.toutes('produits').length, lotsAvant = e.fileul.toutes('lots').length;
    final r = restituerLotDirect(jeuImportParId, e.resultat.lot!['id'], codeRefus: 'DOUBLON_MAGASIN', motifRefus: 'le même article est déjà tenu', port: e.fileul);
    expect([r.ok, r.etat, r.gardees], [true, restitutionFaite, isEmpty], reason: '${r.motif}');
    expect(r.archives, 4, reason: 'deux articles et deux lots');
    final tousMouvs = e.fileul.toutes('mouvements').where((f) => '${f['id']}'.startsWith('MOU-DIMF1s1') || f['restitutionDe'] != null).toList();
    final entrees = tousMouvs.where((f) => f['type'] == 'entree'), inverses = tousMouvs.where((f) => f['type'] == 'sortie');
    expect([entrees.length, inverses.length], [3, 3], reason: 'un mouvement inverse par entrée : un mouvement écrit ne se réécrit pas');
    expect(entrees.every((f) => f['statut'] != 'archive'), isTrue, reason: 'l\'historique des entrées reste');
    expect(inverses.every((f) => '${f['justificatif']}'.contains('Restitution du lot IMP-2026-001') && f[champRefuseeParMere] != null), isTrue);
    expect(entrees.fold<num>(0, (t, f) => t + (f['quantite'] as num)) - inverses.fold<num>(0, (t, f) => t + (f['quantite'] as num)), 0, reason: 'net nul : jamais de stock négatif (RG-03)');
    expect(e.fileul.actives('produits').where((f) => f['code'] == 'MED1' || f['code'] == 'GANT1'), isEmpty);
    expect(e.fileul.toutes('lots').where((f) => '${f['id']}'.startsWith('LOT-DIMF1s1')).every((f) => f['statut'] == 'archive'), isTrue);
    expect([e.fileul.toutes('produits').length, e.fileul.toutes('lots').length], [produitsAvant, lotsAvant], reason: 'rien n\'est supprimé (RG-14), tout est archivé');
    final lot = e.fileul.parId(collectionLots, e.resultat.lot!['id'])!;
    expect([lot['etat'], lot['restitueGardees']], ['restitue', 0]);
    // Idempotent : une seconde restitution n'écrit pas de mouvement inverse de plus.
    final n = e.fileul.toutes('mouvements').length;
    restituerLotDirect(jeuImportParId, e.resultat.lot!['id'], codeRefus: 'X', motifRefus: 'x', port: e.fileul);
    expect(e.fileul.toutes('mouvements').length, n);
  });

  test('IMP-E UNE SORTIE DÉJÀ FAITE SUR UN LOT EN ATTENTE : l\'article ne se restitue pas (une pièce émise ne se réécrit jamais), il reste marqué « refusé par la mère », les autres articles sont restitués', () {
    final e = stockChezLeFileul();
    // Une dispensation de 10 boîtes sur le lot L1 de MED1 avant le refus.
    final l1 = fiche(e.fileul, 'lots', (f) => f['numeroLot'] == 'L1');
    l1['quantiteRestante'] = 90;
    final med1 = fiche(e.fileul, 'produits', (f) => f['code'] == 'MED1');
    med1['stockGros'] = 140;
    med1['stock'] = 140;
    final r = restituerLotDirect(jeuImportParId, e.resultat.lot!['id'], codeRefus: 'DOUBLON_MAGASIN', motifRefus: 'le même article est déjà tenu', port: e.fileul);
    expect([r.ok, r.etat], [true, restitutionPartielle]);
    final codes = {for (final g in r.gardees) '${g['collection']}:${g['code']}'};
    expect(codes, {'produits:STOCK_DEJA_SORTI', 'lots:STOCK_DEJA_SORTI', 'mouvements:STOCK_DEJA_SORTI'});
    expect(r.gardees.where((g) => g['collection'] == 'lots'), hasLength(2));
    expect(r.gardees.where((g) => g['collection'] == 'mouvements'), hasLength(2), reason: 'les deux entrées de MED1');
    expect(r.gardees.first['motif'], allOf(contains('150 à 140'), contains('une pièce émise ne se réécrit jamais')));
    expect(med1['statut'], isNot('archive'));
    expect(med1[champRefuseeParMere], contains('DOUBLON_MAGASIN'));
    expect(l1['statut'], isNot('archive'));
    expect(l1['quantiteRestante'], 90, reason: 'la quantité n\'est pas touchée : pas de contre-passation sur un article sorti (jamais de stock négatif)');
    expect(e.fileul.toutes('mouvements').where((f) => f['restitutionDe'] != null && f['produitId'] == med1['id']), isEmpty, reason: 'aucun mouvement inverse pour l\'article gardé');
    final gant1 = fiche(e.fileul, 'produits', (f) => f['code'] == 'GANT1');
    expect(gant1['statut'], 'archive', reason: 'l\'article intact est restitué');
    expect(e.fileul.toutes('mouvements').where((f) => f['restitutionDe'] != null && f['produitId'] == gant1['id']), hasLength(1));
    expect(e.fileul.parId(collectionLots, e.resultat.lot!['id'])!['restitueGardees'], 5);
  });

  test('IMP-E UN AUTRE MOUVEMENT SUR L\'ARTICLE (une sortie dont le compteur n\'a pas bougé : une perte) suffit aussi à le garder', () {
    final e = stockChezLeFileul();
    final med1 = fiche(e.fileul, 'produits', (f) => f['code'] == 'MED1');
    e.fileul.inserer('mouvements', {'reference': 'M000999', 'produitId': med1['id'], 'produit': med1['designation'], 'type': 'perte', 'typeLabel': 'Perte', 'quantite': 1});
    final r = restituerLotDirect(jeuImportParId, e.resultat.lot!['id'], codeRefus: 'RESULTAT_DIFFERENT', motifRefus: 'x', port: e.fileul);
    expect(r.etat, restitutionPartielle);
    expect(r.gardees.first['motif'], contains('M000999'));
    expect(med1['statut'], isNot('archive'));
  });

}
