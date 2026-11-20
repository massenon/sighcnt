import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart';

import 'aide_polices.dart';

/// E1559, E1561 : une prescription du téléphone d'un soignant (pièce `prescriptions` livrée par la mère) devient au POSTE une ordonnance, une facture de la
/// caisse et les files d'aval, par le moteur de la fiche de consultation (`csPrescrire`) ; ce qui n'est pas transcriptible est REFUSÉ en le disant.
class SourceMemoire implements SourcePiecesMobile {
  SourceMemoire(this.donnees);
  final Map<String, List<PieceSync>> donnees;
  final List<(String, Map<String, Object?>)> ecritures = [];

  @override
  Future<List<PieceSync>> liste(String collection) async => [...?donnees[collection]];

  @override
  Future<String> creer(String collection, Map<String, Object?> champs) async {
    final id = 'w${ecritures.length + 1}';
    donnees.putIfAbsent(collection, () => []).add(PieceSync(id, champs));
    ecritures.add((collection, champs));
    return id;
  }

  List<Map<String, Object?>> de(String collection) => [for (final e in ecritures) if (e.$1 == collection) e.$2];
}

final maintenant = DateTime.parse('2026-10-31T12:00:00');

Map<String, Object?> piece(String patientId, String code, List<Map<String, Object?>> lignes, {String fonction = 'medecin', String nature = 'medicament', List<String>? examens}) => {
      'nature': nature,
      'patientId': patientId,
      'patientCode': code,
      'patient': 'DOSSOU Aline',
      'date': '2026-10-31T10:00',
      'noteId': 'n1',
      if (nature == 'medicament') 'lignes': lignes,
      if (nature == 'analyse') ...{'examens': examens, 'urgence': 'Non urgent'},
      'prescripteur': 'Dr YENI M’PO Florent',
      'fonction': fonction,
      'emise': true,
      'origine': 'mobile',
    };

void main() {
  setUpAll(chargerPolices);
  late Magasin m;
  late Map<String, Object?> produit;
  late Map<String, Object?> pasDeStock;
  late SourceMemoire src;
  late ServiceTranscriptionMobile svc;

  setUp(() {
    m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
    final meds = m.collection('produits').actives.where((p) => p['categorie'] == 'medicament' && (p['prixAchat'] as num? ?? 0) > 0).toList();
    produit = meds.first;
    // Le stock est posé : 5 en détail pour le premier médicament, 1 pour le second.
    m.collection('produits').mettreAJour(produit['id'], {'stockDetail': 5, 'stock': 5});
    pasDeStock = meds[1];
    m.collection('produits').mettreAJour(pasDeStock['id'], {'stockDetail': 1, 'stock': 1});
    src = SourceMemoire({
      'patients': [const PieceSync('s1', {'code': 'CNT/7777/26', 'nom': 'DOSSOU', 'prenom': 'Aline', 'sexe': 'F', 'dateNaissance': '1990-01-01'})],
      'notes': [const PieceSync('n1', {'diagnostic': 'Paludisme simple', 'patientId': 's1'})],
      'prescriptions': [],
    });
    svc = ServiceTranscriptionMobile(magasin: m, source: src, maintenant: () => maintenant);
  });

  PieceSync pieceSync(String id, Map<String, Object?> data) => PieceSync(id, data);

  test('une ordonnance du médecin devient ordonnance + facture + files d\'aval, au PRIX D\'ACHAT du catalogue (RG-02), et le dossier du patient entre au poste', () async {
    expect(m.collection('patients').actives.where((p) => p['code'] == 'CNT/7777/26'), isEmpty);
    final avantOrdo = m.collection('ordonnances').actives.length;
    final avantFact = m.collection('factures').actives.length;
    src.donnees['prescriptions']!.add(pieceSync('p1', piece('s1', 'CNT/7777/26', [
      {'produitId': produit['id'], 'medicament': produit['designation'], 'quantite': 2, 'posologie': '1 cp x 3/j', 'dureeJours': 5}
    ])));
    final r = await svc.traiter();
    expect((r.transcrites, r.refusees), (1, 0));
    expect(m.collection('patients').actives.where((p) => p['code'] == 'CNT/7777/26').length, 1, reason: 'le dossier vient de la synchronisation, code intact (RG-01)');
    final o = m.collection('ordonnances').actives.first;
    expect(m.collection('ordonnances').actives.length, avantOrdo + 1);
    expect(o['pieceMobileId'], 'p1');
    expect(o['origine'], 'mobile');
    expect(o['diagnostic'], 'Paludisme simple', reason: 'le diagnostic de la note rattachée part sur l\'ordonnance');
    expect(o['montant'], (produit['prixAchat'] as num) * 2, reason: 'RG-02 : le prix est celui du catalogue, jamais celui du téléphone');
    final f = m.collection('factures').parId(o['factureId'])!;
    expect(m.collection('factures').actives.length, avantFact + 1);
    expect(f['partPatient'], (produit['prixAchat'] as num) * 2);
    final taches = [for (final t in m.collection('taches').actives) if (t['ordonnanceId'] == o['id']) t['type']];
    expect(taches, containsAll(['encaissement', 'dispensation']));
    // Le compte rendu part à la mère, avec les numéros réels : c'est lui qui rend vraie la phrase « génère l'ordonnance et la facture de la caisse » au téléphone.
    final t = src.de('transcriptions').single;
    expect((t['etat'], t['prescriptionId'], t['ordonnance'], t['facture']), ('transcrite', 'p1', o['numero'], f['numero']));
    // Idempotent : un second passage ne refait rien.
    final encore = await svc.traiter();
    expect(encore.vide, isTrue);
    expect(m.collection('ordonnances').actives.length, avantOrdo + 1);
    expect(src.de('transcriptions').length, 1);
  });

  test('un refus se dit : médicament hors catalogue, stock insuffisant (RG-03), infirmier, patient inconnu ; rien n\'est transcrit à moitié, rien n\'est perdu', () async {
    final avantOrdo = m.collection('ordonnances').actives.length;
    final avantFact = m.collection('factures').actives.length;
    src.donnees['prescriptions']!.addAll([
      pieceSync('p2', piece('s1', 'CNT/7777/26', [
        {'medicament': 'Paracétamol 500 mg', 'quantite': 1, 'posologie': 'x', 'dureeJours': 1}
      ])),
      pieceSync('p3', piece('s1', 'CNT/7777/26', [
        {'produitId': pasDeStock['id'], 'medicament': pasDeStock['designation'], 'quantite': 3, 'posologie': 'x', 'dureeJours': 1}
      ])),
      pieceSync('p4', piece('s1', 'CNT/7777/26', [
        {'produitId': produit['id'], 'medicament': produit['designation'], 'quantite': 1, 'posologie': 'x', 'dureeJours': 1}
      ], fonction: 'infirmier')),
      pieceSync('p5', piece('s9', 'CNT/9999/26', [
        {'produitId': produit['id'], 'medicament': produit['designation'], 'quantite': 1, 'posologie': 'x', 'dureeJours': 1}
      ])),
    ]);
    final r = await svc.traiter();
    expect((r.transcrites, r.refusees), (0, 4));
    expect(m.collection('ordonnances').actives.length, avantOrdo);
    expect(m.collection('factures').actives.length, avantFact);
    final codes = {for (final t in src.de('transcriptions')) t['prescriptionId']: t};
    expect(codes['p2']!['code'], 'PRODUIT_INCONNU');
    expect(codes['p3']!['code'], 'STOCK_INSUFFISANT');
    expect(codes['p3']!['motif'], 'Stock insuffisant pour « ${pasDeStock['designation']} » : disponible : 1 ; demandé : 3 (RG-03).');
    expect(codes['p3']!['geste'], 'Corriger la quantité ou demander un transfert du gros.');
    expect(codes['p4']!['code'], 'FONCTION_NON_HABILITEE');
    expect(codes['p5']!['code'], 'PATIENT_INTROUVABLE');
    expect(codes.values.every((t) => t['etat'] == 'refusee' && '${t['motif']}'.isNotEmpty && '${t['geste']}'.isNotEmpty), isTrue, reason: 'code, motif et geste, jamais un refus muet');
    // Le registre du poste les garde, l'écran des ordonnances les montre.
    expect(m.collection('piecesMobile').actives.where((p) => p['etat'] == 'refusee').length, 4);
    // Un second passage ne les reprend pas (le compte rendu existe) ; les refus ne se rejouent pas tels quels.
    expect((await svc.traiter()).vide, isTrue);
  });

  test('une demande d\'analyses : les examens du mobile sont rapprochés du catalogue du laboratoire, une demande au laboratoire par examen, bloquée jusqu\'à la caisse', () async {
    src.donnees['prescriptions']!.add(pieceSync('p6', piece('s1', 'CNT/7777/26', const [], nature: 'analyse', examens: ['NFS', 'CRP'])));
    final avant = m.collection('demandesAnalyses').actives.length;
    final r = await svc.traiter();
    expect(r.transcrites, 1);
    final d = m.collection('demandesAnalyses').actives.take(2).toList();
    expect(m.collection('demandesAnalyses').actives.length, avant + 2);
    expect(d.every((x) => x['bloqueParPaiement'] == true && x['etatAnalyse'] == 'en_attente'), isTrue);
  });

  testWidgets('l\'écran des ordonnances montre l\'ordonnance transcrite et nomme les pièces refusées (code, motif, geste)', (t) async {
    src.donnees['prescriptions']!.addAll([
      pieceSync('p1', piece('s1', 'CNT/7777/26', [
        {'produitId': produit['id'], 'medicament': produit['designation'], 'quantite': 2, 'posologie': '1 cp x 3/j', 'dureeJours': 5}
      ])),
      pieceSync('p3', piece('s1', 'CNT/7777/26', [
        {'produitId': pasDeStock['id'], 'medicament': pasDeStock['designation'], 'quantite': 3, 'posologie': 'x', 'dureeJours': 1}
      ])),
    ]);
    await svc.traiter();
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(SighPoste(
        donnees: DonneesNavigation.depuisDossier(), config: ConfigPoste(mode: ModePoste.fileul, role: 'admin'), ecranInitial: 'm2-ordonnances', magasin: m, horloge: () => maintenant));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final numero = m.collection('ordonnances').actives.first['numero'];
    expect(find.textContaining('1 prescription(s) reçue(s) d’un téléphone n’ont pas pu être transcrites'), findsOneWidget);
    expect(find.textContaining('[STOCK_INSUFFISANT]'), findsOneWidget);
    expect(find.textContaining('À faire : Corriger la quantité ou demander un transfert du gros.'), findsOneWidget);
    expect(find.textContaining('$numero'), findsWidgets, reason: 'l\'ordonnance transcrite est au registre des ordonnances');
    await t.pump(const Duration(seconds: 10));
  });
}
