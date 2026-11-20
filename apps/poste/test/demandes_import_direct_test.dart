import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/demandes_import_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';
import 'package:sigh_poste/sync/service_verdicts_import.dart';

/// L'IMPORT DIRECT D'UN FILEUL (lot IMP-D, décision N de la Direction du 12/11/2026), sur le magasin du poste : le fileul écrit chez lui ET dépose la demande, en UN geste ; la garde
/// « réglé sur la mère » laisse passer ce geste et rien d'autre ; la restitution sur refus archive ; le marquage « en attente de la mère » se lit ; un lot confirmé ne s'annule plus ici.
typedef M = Map<String, Object?>;
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin vide() => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });

List<List<Object?>> lignesDuCas(String id) {
  final c = (vecteurs['cas'] as List).cast<Map>().firstWhere((x) => x['id'] == id);
  return [
    for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
  ];
}

/// Un fileul rattaché : ses collections de configuration portent la garde « réglé sur la mère » (posée par `ApplicateurConfiguration.demarrer` en production).
Magasin fileulGarde() {
  final m = vide();
  ApplicateurConfiguration(m, (_) async => []).poserGardes();
  return m;
}

DemandesImportPoste poste(Magasin m, {String role = 'stock', String par = 'LE GESTIONNAIRE', String etiquette = 'F1x'}) =>
    DemandesImportPoste(m, role: role, auteur: () => par, matrice: donnees.matrice, aujourdhui: () => DateTime(2026, 11, 12, 9), etiquette: etiquette);

AnalyseImport verifier(Magasin m, String jeu, String cas, {String role = 'stock', String par = 'LE GESTIONNAIRE'}) {
  final profil = ProfilImport(role: role, libelleRole: role, matrice: donnees.matrice.matriceImport);
  final a = analyserLignes(jeuImportParId(jeu)!, lignesDuCas(cas), '$cas.xlsx', PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 12), nomAgent: par, profil: profil))..empreinte = 'e1';
  expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
  return a;
}

void main() {
  test('LA VOIE sur le poste : les référentiels de configuration seuls s\'écrivent chez le fileul ET partent en demande ; le Grand Stock aussi (lot IMP-E) ; le personnel à la mère ; hors fileul tout est direct', () {
    VoieImportFileul voie(String jeu, {bool fileul = true}) => DemandesImportPoste.voie(fileulRattache: fileul, declaration: donnees.matrice.matriceImport.declaration(jeu));
    for (final j in ['fournisseurs', 'assureurs', 'souscripteurs', 'plan-comptable', 'analyses-modele', 'natures-facture', 'centres-couts', 'unites-labo', 'emplacements', 'grand-stock']) {
      expect(voie(j), VoieImportFileul.directeEtDemande, reason: j);
    }
    expect(voie('personnel'), VoieImportFileul.reserveeALaMere);
    for (final j in ['patients', 'soldes-ouverture', 'prestataires']) {
      expect(voie(j), VoieImportFileul.directe, reason: j);
    }
    expect(voie('fournisseurs', fileul: false), VoieImportFileul.directe, reason: 'la mère, ou un poste autonome, écrit directement');
    expect(DemandesImportPoste.voie(fileulRattache: true, declaration: null), VoieImportFileul.directe);
  });

  test('LA GARDE laisse passer EXACTEMENT le geste d\'import du fileul : ni avant, ni après, ni une autre collection, ni une écriture de référentiel hors import', () {
    final m = fileulGarde();
    final col = m.collection('fournisseurs');
    // Hors import : refusée, nommée.
    expect(() => col.inserer({'code': 'HORS', 'nom': 'Saisie directe'}), throwsA(isA<EcritureRefusee>().having((e) => e.motif, 'motif', ApplicateurConfiguration.motifGarde)));
    expect(col.toutes.where((f) => f['code'] == 'HORS'), isEmpty);
    // Dans le geste d'import de CE jeu : passe pour SES cibles seulement.
    m.pendantImportFileul({'fournisseurs'}, () {
      col.inserer({'code': 'DANS', 'nom': 'Dans le geste'});
      expect(() => m.collection('comptes').inserer({'numero': '999999', 'libelle': 'Autre collection'}), throwsA(isA<EcritureRefusee>()), reason: 'une collection qui n\'est pas une cible du jeu reste refusée');
      expect(() => m.collection('assureurs').inserer({'code': 'XX', 'nom': 'Autre'}), throwsA(isA<EcritureRefusee>()));
    });
    expect(col.toutes.where((f) => f['code'] == 'DANS'), hasLength(1));
    // Le geste terminé, l'autorisation est levée.
    expect(() => col.inserer({'code': 'APRES', 'nom': 'Après le geste'}), throwsA(isA<EcritureRefusee>()));
    // Une exception dans le geste lève aussi l'autorisation.
    expect(() => m.pendantImportFileul({'fournisseurs'}, () => throw StateError('boum')), throwsStateError);
    expect(m.importAutorise('fournisseurs'), isFalse);
    expect(() => col.inserer({'code': 'APRES2', 'nom': 'Après l\'exception'}), throwsA(isA<EcritureRefusee>()));
    // La réception de la configuration de la mère ne passe pas par les gardes (comme avant).
    expect(col.appliquerDistante({'id': 'FOU-MERE', 'code': 'MERE', 'nom': 'De la mère'}), isTrue);
  });

  test('UN GESTE : le fileul écrit chez lui (même chemin que la mère), les fiches sont marquées, le lot est consigné, la demande part ; rien n\'est écrit à côté', () {
    final m = fileulGarde();
    final p = poste(m);
    final avant = m.collection('fournisseurs').toutes.length;
    final r = p.importerEtDemander(jeuImportParId('fournisseurs')!, verifier(m, 'fournisseurs', 'fo-valide'));
    expect(r.resultat.ok, isTrue, reason: '${r.resultat.motif}');
    final fiches = m.collection('fournisseurs').actives.where((f) => f['lotImport'] == r.resultat.lot!['reference']).toList();
    expect(fiches.map((f) => f['code']).toSet(), {'CAME', 'LOCAL'});
    expect(m.collection('fournisseurs').toutes.length, avant + 2);
    expect(fiches.every((f) => f['validePar'] == 'LE GESTIONNAIRE' && f['_creePar'] == 'LE GESTIONNAIRE'), isTrue, reason: 'RG-12 : au nom de l\'agent');
    final d = r.demande!;
    expect([d['etat'], d['ecritureDirecte'], d['jeu'], d['demandeRole'], d['lotLocal']], [demandeImportEnAttente, true, 'fournisseurs', 'stock', r.resultat.lot!['reference']]);
    expect(fiches.every((f) => f[champEnAttenteMere] == d['id']), isTrue, reason: 'le marquage porte l\'identifiant de la demande');
    expect(fiches.map((f) => f['id']).toSet(), {'FOU-${d['serieIdentifiants']}-1', 'FOU-${d['serieIdentifiants']}-2'}, reason: 'la série des identifiants dérive du contenu du fichier (lot IDEM), le marquage reste celui de la demande');
    expect(d['identiteLot'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(d['serieIdentifiants'], 'IMP${(d['identiteLot'] as String).substring(0, 20)}');
    expect(m.collection(demandesImportCollection).toutes.single['id'], d['id']);
    expect(p.demandeDuLot(r.resultat.lot!['id'])!['id'], d['id']);
    expect(m.collection(collectionLots).toutes.single['etat'], 'applique');
    final miens = [for (final l in m.collection('audit').toutes) if ('${l['action']}'.startsWith('Import écrit chez le fileul')) l];
    expect(miens, hasLength(1), reason: 'RG-12 : le geste est journalisé');
    expect(jsonEncode(miens), isNot(contains('CAME')), reason: 'la ligne de journal du geste ne recopie aucune valeur de cellule');
    // Un fichier refusé par le moteur n'écrit rien ET ne dépose rien (rien n'est parti, rien n'est resté).
    final m2 = fileulGarde();
    final a = verifier(m2, 'assureurs', 'as-valide', role: 'comptable');
    m2.collection('assureurs').appliquerDistante({'id': 'ASS-X', 'code': 'SUNU', 'nom': 'Créée entre-temps', 'statut': 'actif'});
    final refus = poste(m2, role: 'comptable').importerEtDemander(jeuImportParId('assureurs')!, a);
    expect(refus.resultat.ok, isFalse, reason: 'le moteur rejoue l\'analyse au moment d\'écrire');
    expect(refus.demande, isNull);
    expect(m2.collection(demandesImportCollection).toutes, isEmpty, reason: 'une demande sans écriture n\'existe pas');
  });

  test('LES NEUF JEUX de la voie « directe et demande » s\'écrivent tous sous la garde : leurs cibles déclarées sont complètes (une collection oubliée serait refusée par la garde)', () {
    const cas = {
      'assureurs': 'as-valide',
      'fournisseurs': 'fo-valide',
      'souscripteurs': 'sc-valide',
      'plan-comptable': 'pc-valide',
      'analyses-modele': 'an-valide',
      'natures-facture': 'na-valide',
      'centres-couts': 'ce-valide',
      'unites-labo': 'un-valide',
      'emplacements': 'em-valide',
    };
    for (final e in cas.entries) {
      final m = fileulGarde();
      final jeu = jeuImportParId(e.key)!;
      final r = poste(m, role: 'admin', par: 'ADMIN').importerEtDemander(jeu, verifier(m, e.key, e.value, role: 'admin', par: 'ADMIN'));
      expect(r.resultat.ok, isTrue, reason: '${e.key} : ${r.resultat.code} ${r.resultat.motif}');
      expect(r.demande!['ecritureDirecte'], true, reason: e.key);
      final ecrits = (r.resultat.lot!['ecrits'] as List).cast<Map>();
      expect(ecrits, isNotEmpty, reason: e.key);
      expect(ecrits.every((x) => jeu.cibles.contains(x['collection'])), isTrue, reason: '${e.key} : chaque fiche écrite est dans une cible déclarée');
    }
  });

  test('UNE DEMANDE SANS ÉCRITURE N\'EXISTE PAS, ET UNE ÉCRITURE SANS DEMANDE NON PLUS : si le dépôt échoue, l\'écriture est restituée et le dit', () {
    final m = fileulGarde();
    m.collection(demandesImportCollection).garder((op, f) => 'dépôt impossible (test)');
    final r = poste(m).importerEtDemander(jeuImportParId('fournisseurs')!, verifier(m, 'fournisseurs', 'fo-valide'));
    expect([r.resultat.ok, r.resultat.code, r.demande], [false, 'DEMANDE_NON_DEPOSEE', isNull]);
    expect(r.resultat.geste, contains('restituée'));
    expect(m.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME' || f['code'] == 'LOCAL'), isEmpty, reason: 'rien ne reste écrit sans demande');
    expect(m.collection(collectionLots).toutes.single['etat'], 'restitue');
  });

  test('LE REFUS DE LA MÈRE : le fileul RESTITUE (archivage, pas de suppression), la demande dit la restitution ; un lot refusé ne s\'annule plus à la main', () {
    final m = fileulGarde();
    final p = poste(m);
    final r = p.importerEtDemander(jeuImportParId('fournisseurs')!, verifier(m, 'fournisseurs', 'fo-valide'));
    final id = '${r.demande!['id']}';
    final total = m.collection('fournisseurs').toutes.length;
    expect(p.traiterVerdicts(), 0, reason: 'la mère n\'a pas répondu (injoignable comprise) : le fileul garde son écriture et la demande attend');
    expect(m.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME'), hasLength(1));
    // Verdict de la mère, tel qu'il revient par le pont.
    m.collection(demandesImportCollection).mettreAJour(id, {
      'etat': demandeImportRefusee,
      'resultatCode': 'DOUBLON_MAGASIN',
      'resultatMotif': 'rejoué à la mère, le fichier est refusé (ligne 2, Code)',
      'resultatGeste': 'Retirez la ligne.',
      'lignes': <Object?>[],
    });
    expect(p.traiterVerdicts(), 1);
    expect(m.collection('fournisseurs').toutes.length, total, reason: 'jamais une suppression physique (RG-14)');
    expect(m.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME' || f['code'] == 'LOCAL'), isEmpty);
    final d = m.collection(demandesImportCollection).parId(id)!;
    expect([d['restitution'], d['restitutionArchives']], [restitutionFaite, 2]);
    expect(m.collection(collectionLots).toutes.single['etat'], 'restitue');
    expect(libelleEtatDemandeImport(d).libelle, 'Refusée par la mère, écriture restituée');
    expect(p.traiterVerdicts(), 0, reason: 'une seule restitution');
    final annul = p.annulerLotDuFileul(m.collection(collectionLots).toutes.single['id']);
    expect(annul.ok, isFalse);
  });

  test('UNE PIÈCE ÉMISE ENTRE-TEMPS : le refus de la mère ne réécrit pas la fiche qu\'elle utilise ; elle reste, marquée « refusée par la mère »', () {
    final m = fileulGarde();
    final p = poste(m);
    final r = p.importerEtDemander(jeuImportParId('fournisseurs')!, verifier(m, 'fournisseurs', 'fo-valide'));
    m.collection('commandes').inserer({'numero': 'BC-9', 'fournisseurCode': 'CAME', 'statut': 'actif'});
    m.collection(demandesImportCollection).mettreAJour('${r.demande!['id']}', {'etat': demandeImportRefusee, 'resultatCode': 'RESULTAT_DIFFERENT', 'resultatMotif': 'la mère ne produirait pas le même résultat', 'resultatGeste': 'Refaites l’import.'});
    expect(p.traiterVerdicts(), 1);
    final came = m.collection('fournisseurs').toutes.firstWhere((f) => f['code'] == 'CAME');
    expect(came['statut'], isNot('archive'));
    expect('${came[champRefuseeParMere]}', contains('RESULTAT_DIFFERENT'));
    expect(m.collection('fournisseurs').toutes.firstWhere((f) => f['code'] == 'LOCAL')['statut'], 'archive');
    final d = m.collection(demandesImportCollection).parId('${r.demande!['id']}')!;
    expect(d['restitution'], restitutionPartielle);
    expect((d['restitutionGardees'] as List).single['code'], 'FOURNISSEUR_UTILISE');
    expect(libelleEtatDemandeImport(d).libelle, 'Refusée par la mère, restitution partielle');
  });

  test('LA CONFIRMATION DE LA MÈRE : le marquage « en attente » est levé une fois, et la demande est lue « appliquée » seulement alors', () {
    final m = fileulGarde();
    final p = poste(m);
    final r = p.importerEtDemander(jeuImportParId('fournisseurs')!, verifier(m, 'fournisseurs', 'fo-valide'));
    final id = '${r.demande!['id']}';
    expect(m.collection('fournisseurs').actives.where((f) => f.containsKey(champEnAttenteMere)), hasLength(2));
    expect(libelleEtatDemandeImport(m.collection(demandesImportCollection).parId(id)!).libelle, isNot(contains('Appliqu')));
    m.collection(demandesImportCollection).mettreAJour(id, {'etat': demandeImportAppliquee, 'resultatLot': 'IMP-2026-004', 'resultatEcrits': 2, 'lignes': <Object?>[]});
    expect(p.traiterVerdicts(), 1);
    expect(m.collection('fournisseurs').actives.where((f) => f.containsKey(champEnAttenteMere)), isEmpty);
    expect(m.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME'), hasLength(1), reason: 'confirmé : la fiche reste');
    expect(m.collection(demandesImportCollection).parId(id)!['marquageLeve'], isTrue);
    expect(p.traiterVerdicts(), 0);
    // Confirmé par la mère : le lot ne s'annule plus ici (la mère détient les mêmes fiches).
    final annul = p.annulerLotDuFileul(r.resultat.lot!['id']);
    expect([annul.ok, annul.code], [false, 'LOT_CONFIRME_PAR_LA_MERE']);
    expect(m.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME'), hasLength(1));
  });

  test('L\'ANNULATION AVANT LA RÉPONSE : le lot est archivé et la demande est RETIRÉE ; la mère ne la traite plus', () async {
    final m = fileulGarde();
    final p = poste(m);
    final r = p.importerEtDemander(jeuImportParId('fournisseurs')!, verifier(m, 'fournisseurs', 'fo-valide'));
    final id = '${r.demande!['id']}';
    final annul = p.annulerLotDuFileul(r.resultat.lot!['id'], motif: 'erreur de fichier');
    expect(annul.ok, isTrue, reason: '${annul.motif}');
    expect(m.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME' || f['code'] == 'LOCAL'), isEmpty);
    final d = m.collection(demandesImportCollection).parId(id)!;
    expect([d['etat'], d['lignes']], [demandeImportRetiree, isEmpty]);
    // La demande retirée arrive à la mère : elle ne l'applique pas.
    final mere = vide();
    mere.collection(demandesImportCollection).appliquerDistante({...d});
    final n = await ServiceDemandesImport(mere, donnees: () async => donnees, horloge: () => DateTime(2026, 11, 12)).traiter();
    expect(n, 0);
    expect(mere.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME'), isEmpty);
    // L'agent doit détenir le droit d'annuler le jeu : le moteur le relit (le caissier n'a pas le jeu).
    final m3 = fileulGarde();
    final r3 = poste(m3).importerEtDemander(jeuImportParId('fournisseurs')!, verifier(m3, 'fournisseurs', 'fo-valide'));
    final refus = poste(m3, role: 'caissier').annulerLotDuFileul(r3.resultat.lot!['id']);
    expect(refus.ok, isFalse);
    expect(refus.code, 'DROIT_IMPORT_REFUSE');
  });

  test('LE SERVICE du fileul suit le verdict tout seul', () async {
    final m = fileulGarde();
    final r = poste(m).importerEtDemander(jeuImportParId('fournisseurs')!, verifier(m, 'fournisseurs', 'fo-valide'));
    final service = ServiceVerdictsImport(m, role: 'stock', auteur: () => 'LE GESTIONNAIRE', donnees: () async => donnees, horloge: () => DateTime(2026, 11, 12));
    expect(await service.traiter(), 0);
    m.collection(demandesImportCollection).mettreAJour('${r.demande!['id']}', {'etat': demandeImportRefusee, 'resultatCode': 'DROIT_IMPORT_REFUSE', 'resultatMotif': 'x', 'resultatGeste': 'y'});
    expect(await service.traiter(), 1);
    expect(service.derniereErreur, isNull);
    expect(m.collection('fournisseurs').actives.where((f) => f['code'] == 'CAME'), isEmpty);
  });
}
