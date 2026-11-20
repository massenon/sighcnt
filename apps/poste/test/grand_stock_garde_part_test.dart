import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/demandes_import_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/reservation_stock.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

import 'aide_grand_stock.dart';

/// LES GARDES DU GRAND STOCK AU FILEUL (lot IMP-E) :
///  * la garde « réglé sur la mère » laisse passer EXACTEMENT les trois cibles du jeu (produits, lots, mouvements) pendant le geste, et rien d'autre ;
///  * le STOCK d'un produit est un compteur d'activité : une modification qui ne touche que ses compteurs passe (dispensation, perte), le reste de la fiche reste réglé sur la mère ;
///  * la PART de stock d'un poste hors ligne (RG-03, E2149) : un stock importé et non confirmé n'existe que chez ce poste, sa part est le tout ; confirmé, la part est partagée.
Magasin fileulGarde() {
  final m = vide();
  ApplicateurConfiguration(m, (_) async => []).poserGardes();
  return m;
}

void main() {
  test('LA GARDE laisse passer EXACTEMENT les trois cibles du Grand Stock pendant le geste, et rien d\'autre ; hors du geste, produits, lots non confirmés et mouvements d\'un autre jeu restent gardés', () {
    final jeu = jeuImportParId('grand-stock')!;
    expect(collectionsAutoriseesAuFileul(jeu), {'produits', 'lots', 'mouvements'});
    final m = fileulGarde();
    expect(() => m.collection('produits').inserer({'code': 'HORS', 'designation': 'Saisie directe'}), throwsA(isA<EcritureRefusee>()), reason: 'hors geste : le catalogue reste réglé sur la mère');
    m.pendantImportFileul(collectionsAutoriseesAuFileul(jeu), () {
      m.collection('produits').inserer({'code': 'DANS', 'designation': 'Dans le geste'});
      m.collection('lots').inserer({'numeroLot': 'L'});
      m.collection('mouvements').inserer({'reference': 'M1'});
      expect(() => m.collection('fournisseurs').inserer({'code': 'AUTRE'}), throwsA(isA<EcritureRefusee>()), reason: 'une autre collection de configuration reste refusée pendant le geste');
      expect(() => m.collection('tarifs').inserer({'code': 'T'}), throwsA(isA<EcritureRefusee>()));
      expect(() => m.collection('actes').inserer({'code': 'A'}), throwsA(isA<EcritureRefusee>()));
    });
    expect(m.importAutorise('produits'), isFalse, reason: 'l\'autorisation est levée à la sortie du geste');
    expect(() => m.collection('produits').inserer({'code': 'APRES', 'designation': 'Après le geste'}), throwsA(isA<EcritureRefusee>()));
    // Même sur exception : le geste qui échoue ne laisse rien d'ouvert.
    expect(() => m.pendantImportFileul({'produits'}, () => throw StateError('échec')), throwsStateError);
    expect(m.importAutorise('produits'), isFalse);
  });

  test('LE STOCK EST UN COMPTEUR : une modification qui ne touche que stock, stockGros, stockDetail passe chez un fileul (sortie, perte) ; le reste de la fiche produit reste réglé sur la mère', () {
    final m = fileulGarde();
    final col = m.collection('produits');
    col.mettreAJour('PRD0002', {'stockGros': 5, 'stock': 5});
    expect(col.parId('PRD0002')!['stockGros'], 5, reason: 'la sortie d\'un fileul n\'est plus refusée « réglé sur la mère » : le stock voyage par ses variations');
    expect(() => col.mettreAJour('PRD0002', {'designation': 'AUTRE NOM'}), throwsA(isA<EcritureRefusee>()));
    expect(() => col.mettreAJour('PRD0002', {'stockGros': 4, 'prixAchat': 1}), throwsA(isA<EcritureRefusee>()), reason: 'un compteur ET un autre champ : refusé');
    expect(() => col.archiver('PRD0002'), throwsA(isA<EcritureRefusee>()));
    expect(col.parId('PRD0002')!['designation'], isNot('AUTRE NOM'));
    // Le reste du catalogue de configuration n'a pas de compteur : aucune exception.
    expect(() => m.collection('fournisseurs').mettreAJour(m.collection('fournisseurs').toutes.first['id'], {'stockGros': 1}), throwsA(isA<EcritureRefusee>()));
  });

  test('LA PART DE STOCK (RG-03, E2149) : un stock importé non confirmé est tout entier la part de ce poste ; confirmé ou ordinaire, la part est partagée entre les postes', () {
    final m = fileulGarde();
    final rs = ReservationStock.de(m)
      ..actif = true
      ..nbPostes = 3
      ..installer(m);
    expect(rs.horsLigne, isTrue, reason: 'jamais synchronisé : hors ligne');
    // Un article ORDINAIRE (10 en stock, 3 postes) : la part est de 3.
    expect(() => m.collection('produits').mettreAJour('PRD0002', {'stockGros': 6, 'stock': 6}), throwsA(isA<EcritureRefusee>()), reason: 'une sortie de 4 dépasse la part de 3');
    m.collection('produits').mettreAJour('PRD0002', {'stockGros': 7, 'stock': 7});
    // Le Grand Stock importé ICI : en attente de la mère, il n'existe que chez ce poste.
    final imp = DemandesImportPoste(m, role: 'stock', auteur: () => 'GESTIONNAIRE', matrice: donnees.matrice, aujourdhui: () => DateTime(2026, 11, 13, 9), etiquette: 'F1');
    final profil = ProfilImport(role: 'stock', libelleRole: 'stock', matrice: donnees.matrice.matriceImport);
    final jeu = jeuImportParId('grand-stock')!;
    final a = analyserLignes(jeu, lignesDuCas('gs-valide'), 'gs.xlsx', imp.portPourTests(profil))..empreinte = 'e';
    final r = imp.importerEtDemander(jeu, a);
    expect(r.resultat.ok, isTrue, reason: '${r.resultat.motif}');
    final med1 = m.collection('produits').toutes.firstWhere((f) => f['code'] == 'MED1');
    final l1 = m.collection('lots').toutes.firstWhere((f) => f['numeroLot'] == 'L1');
    expect(ficheLocaleAuPoste(med1), isTrue);
    // Un import n'est pas une sortie, et ce stock n'est vu d'aucun autre poste : tout peut en sortir.
    m.collection('lots').mettreAJour(l1['id'], {'quantiteRestante': 0});
    m.collection('produits').mettreAJour(med1['id'], {'stockGros': 50, 'stock': 50});
    expect(l1['quantiteRestante'], 0, reason: 'toute la quantité du lot en attente pouvait sortir');
    // Confirmé (marquage levé) : la fiche devient ordinaire, la part est partagée entre les trois postes.
    m.collection('produits').retirerChamp(med1['id'], champEnAttenteMere);
    rs.synchronise(m, {'produits', 'lots'}, postes: 3);
    // Le dernier tour réussi remonte à plus de 12 s : le poste est de nouveau hors ligne.
    final plusTard = DateTime.now().add(const Duration(hours: 1));
    rs.maintenant = () => plusTard;
    expect(rs.horsLigne, isTrue);
    expect(() => m.collection('produits').mettreAJour(med1['id'], {'stockGros': 20, 'stock': 20}), throwsA(isA<EcritureRefusee>()), reason: 'sortir 30 sur 50 dépasse la part (16) une fois confirmé');
    m.collection('produits').mettreAJour(med1['id'], {'stockGros': 40, 'stock': 40});
  });
  test('UN COMPTEUR REÇU N\'EST JAMAIS ADOPTÉ (course trouvée sous charge) : la fiche de configuration de la mère, qui porte le stock du jour, ne donne pas son stock à une fiche que le fileul tient déjà sans compteur ; sa valeur de départ, si elle en a une, oui', () async {
    final m = fileulGarde();
    // Le pont a déjà créé la fiche du fileul, sans compteur : la valeur de la mère arrivée ensuite par la configuration ne doit PAS s'y poser (les variations de la mère s'y additionneraient : 300 pour 150).
    m.collection('produits').appliquerDistante({'id': 'PRD-NEUF', 'code': 'NEUF', 'designation': 'ARTICLE NEUF', 'statut': 'actif', 'idSync': 'PRD-NEUF'});
    final recu = {'code': 'NEUF', 'designation': 'ARTICLE NEUF', 'statut': 'actif', 'stockGros': 150, 'stock': 150, 'stockDetail': 0};
    await ApplicateurConfiguration(m, (c) async => c == 'produits' ? [PieceSync('PRD-NEUF', recu)] : []).tirer();
    final f = m.collection('produits').parId('PRD-NEUF')!;
    expect([f.containsKey('stockGros'), f.containsKey('stock'), f.containsKey('stockDetail')], [false, false, false], reason: 'aucun compteur adopté : seules les variations en donneront un');
    // Une fiche née d'une demande d'import porte son départ : c'est son compteur.
    final recuDepart = {...recu, 'departCompteurs': {'stockGros': 150, 'stock': 150, 'stockDetail': 0}};
    await ApplicateurConfiguration(m, (c) async => c == 'produits' ? [PieceSync('PRD-IMPORT', recuDepart)] : []).tirer();
    expect(m.collection('produits').parId('PRD-IMPORT')!['stockGros'], 150);
    // Une fiche qui a déjà son compteur le garde, quelle que soit la valeur reçue.
    m.collection('produits').appliquerDistante({'id': 'PRD-GARDE', 'code': 'G', 'designation': 'G', 'stockGros': 90, 'statut': 'actif'});
    await ApplicateurConfiguration(m, (c) async => c == 'produits' ? [PieceSync('PRD-GARDE', {...recu, 'code': 'G'})] : []).tirer();
    expect(m.collection('produits').parId('PRD-GARDE')!['stockGros'], 90, reason: 'ses sorties n\'ont pas encore atteint la mère : la valeur de la mère les effacerait');
  });

}
