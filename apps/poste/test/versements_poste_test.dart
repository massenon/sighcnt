import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/donnees/versements_poste.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/m8/commun.dart' show pieceFacture, pieceRecu;
import 'package:sigh_poste/impression/piece.dart';

import 'aide_polices.dart';

/// LOT PAIE-V (Direction, 20/11/2026, section BI) : le paiement par versements successifs et modes multiples, au poste. Les règles sont celles du domaine (vecteurs tirés de l'écran
/// réel de la maquette) ; ici : l'orchestration (une écriture équilibrée et une fiche PAR versement, déblocage des seules lignes entièrement payées, refus nommés qui n'écrivent
/// rien), les gardes de collection (le moteur refuse aussi), le réglage des modalités (geste réservé, versions datées) et l'écran de caisse.
final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 10, 30, 10);

Fiche piece(String id, List<num> lignes, {String statut = 'impayee', num paye = 0}) => {
      'id': id,
      'numero': 'FN-2026-$id',
      'patient': 'AWA K.',
      'patientCode': 'CNT/1/26',
      'patientId': 'P1',
      'date': '2026-10-30',
      'type': 'Consultation',
      'montantTTC': lignes.fold<num>(0, (a, b) => a + b),
      'partAssurance': 0,
      'partPatient': lignes.fold<num>(0, (a, b) => a + b),
      'montantPaye': paye,
      'reliquat': lignes.fold<num>(0, (a, b) => a + b) - paye,
      'statutPaiement': statut,
      'lignes': [
        for (var i = 0; i < lignes.length; i++)
          {
            'id': 'L${i + 1}',
            'categorie': 'analyse',
            'designation': 'Analyse ${i + 1}',
            'quantite': 1,
            'prixUnitaire': lignes[i],
            'partPatient': lignes[i],
            'demandeId': 'D${i + 1}',
            'statutPaiement': 'du'
          }
      ],
    };

Magasin jeu() => Magasin({
      'factures': [piece('A', [15000, 8500]), piece('B', [10000, 12000, 5000])],
      'demandesAnalyses': [
        for (final i in [1, 2, 3]) {'id': 'D$i', 'reference': 'LAB-$i', 'bloqueParPaiement': true, 'etatAnalyse': 'en_attente', 'factureId': 'B'}
      ],
      'taches': const [],
      'ecritures': const [],
      'modalitesVersement': semenceModalitesVersement(),
    })..horloge = () => auj;

Map<String, Object?> mtn(num montant, [String? ref = 'M123']) =>
    {'type': 'acompte', 'modalite': 'mobile_money', 'operateur': 'mtn', 'montant': montant, if (ref != null && ref.isNotEmpty) 'referenceTransaction': ref};
Map<String, Object?> esp(num montant, [String type = 'solde']) => {'type': type, 'modalite': 'especes', 'montant': montant};

Future<void> ouvrir(WidgetTester t, Magasin m, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: 'm8-paiements', magasin: m, horloge: () => auj));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('le moteur du poste : une écriture équilibrée et une fiche par versement', () {
    test('PRD : 23 500 en deux versements (15 000 mobile money MTN avec sa référence, 8 500 espèces) : soldée, mode mixte, deux écritures équilibrées liées à leur versement', () {
      final m = jeu();
      final r = encaisserFacture(m, 'A', versements: [mtn(15000), esp(8500)], maintenant: auj);
      final f = m.collection('factures').parId('A')!;
      expect([f['statutPaiement'], f['reliquat'], f['montantPaye'], f['modePaiement']], ['soldee', 0, 23500, 'mixte']);
      expect(r.versements.length, 2);
      final vs = versementsDePiecePoste(m, 'A');
      expect([for (final v in vs) [v['rang'], v['modalite'], v['operateur'], v['referenceTransaction'], v['montant'], v['resteApres']]],
          [[1, 'mobile_money', 'mtn', 'M123', 15000, 8500], [2, 'especes', null, null, 8500, 0]]);
      final ecr = m.collection('ecritures').actives;
      for (final v in vs) {
        final siennes = [for (final e in ecr) if ((v['ecritureIds'] as List).contains(e['id'])) e];
        expect(siennes.fold<num>(0, (a, e) => a + (e['debit'] as num)), siennes.fold<num>(0, (a, e) => a + (e['credit'] as num)), reason: 'RG-10 : équilibrée par versement');
        expect(siennes.map((e) => e['compte']).toSet(), v['modalite'] == 'mobile_money' ? {'521000', '706000'} : {'571000', '706000'});
      }
      expect(ecr.length, 4);
      expect(ecr.map((e) => e['numero']).toSet().length, 1, reason: 'une pièce de caisse par facture');
    });

    test('un versement partiel ne débloque QUE la ligne qu’il solde entièrement ; l’acompte non affecté ne débloque rien', () {
      final m = jeu();
      encaisserFacture(m, 'B', versements: [esp(10000, 'acompte')], maintenant: auj);
      expect(m.collection('demandesAnalyses').parId('D1')!['bloqueParPaiement'], false);
      expect(m.collection('demandesAnalyses').parId('D2')!['bloqueParPaiement'], true);
      expect(m.collection('demandesAnalyses').parId('D3')!['bloqueParPaiement'], true);
      encaisserFacture(m, 'B', versements: [esp(5000, 'acompte')], maintenant: auj);
      final f = m.collection('factures').parId('B')!;
      expect([for (final l in f['lignes'] as List) (l as Map)['statutPaiement']], ['paye', 'du', 'paye'], reason: 'les 5 000 couvrent la ligne de 5 000, pas celle de 12 000');
      expect([f['statutPaiement'], f['reliquat']], ['partielle', 12000]);
      expect(m.collection('demandesAnalyses').parId('D2')!['bloqueParPaiement'], true);
      encaisserFacture(m, 'B', versements: [esp(12000)], maintenant: auj);
      expect(m.collection('factures').parId('B')!['statutPaiement'], 'soldee');
      expect(m.collection('demandesAnalyses').parId('D2')!['bloqueParPaiement'], false);
    });

    test('refus nommés : rien n’est écrit (ni pièce, ni versement, ni écriture)', () {
      final m = jeu();
      void refuse(List<Map<String, Object?>> vs, String code) {
        try {
          encaisserFacture(m, 'A', versements: vs, maintenant: auj);
          fail('$code attendu');
        } on RefusCaisse catch (e) {
          expect(e.code, code);
        }
        expect(m.collection('versementsCaisse').actives, isEmpty);
        expect(m.collection('ecritures').actives, isEmpty);
        expect(m.collection('factures').parId('A')!['montantPaye'], 0);
      }

      refuse([esp(23501)], 'VERSEMENT_SUPERIEUR_AU_DU');
      refuse([mtn(1000, '')], 'VERSEMENT_REFERENCE_ABSENTE');
      refuse([esp(20000, 'acompte'), esp(4000)], 'VERSEMENT_SUPERIEUR_AU_DU');
      refuse([{...esp(1000), 'partie': 'assureur'}], 'VERSEMENT_PART_ASSUREUR');
      encaisserFacture(m, 'A', versements: [esp(23500)], maintenant: auj);
      try {
        encaisserFacture(m, 'A', versements: [esp(1)], maintenant: auj);
        fail('VERSEMENT_PIECE_SOLDEE attendu');
      } on RefusCaisse catch (e) {
        expect(e.code, 'VERSEMENT_PIECE_SOLDEE');
      }
    });

    test('LE MOTEUR REFUSE AUSSI : une insertion directe qui dépasse le dû ou sans référence est refusée par la collection, un versement enregistré ne se réécrit pas', () {
      final m = jeu();
      final base = {'factureId': 'A', 'type': 'solde', 'modalite': 'especes', 'date': '2026-10-30', 'montant': 23501};
      expect(() => m.collection('versementsCaisse').inserer(base, prefixe: 'VRS'), throwsA(isA<EcritureRefusee>().having((e) => e.motif, 'motif', contains('VERSEMENT_SUPERIEUR_AU_DU'))));
      expect(() => m.collection('versementsCaisse').inserer({...base, 'montant': 100, 'modalite': 'mobile_money', 'operateur': 'mtn'}, prefixe: 'VRS'),
          throwsA(isA<EcritureRefusee>().having((e) => e.motif, 'motif', contains('VERSEMENT_REFERENCE_ABSENTE'))));
      expect(m.collection('versementsCaisse').actives, isEmpty);
      encaisserFacture(m, 'A', versements: [esp(1000, 'acompte')], maintenant: auj);
      final v = versementsDePiecePoste(m, 'A').single;
      expect(() => m.collection('versementsCaisse').mettreAJour('${v['id']}', {'montant': 1}), throwsA(isA<EcritureRefusee>().having((e) => e.motif, 'motif', contains('VERSEMENT_FIGE'))));
    });

    test('l’encaissement par montant et mode uniques (ancien chemin) laisse AUSSI une fiche de versement', () {
      final m = jeu();
      encaisserFacture(m, 'A', montant: 15000, mode: 'mtn', maintenant: auj);
      final v = versementsDePiecePoste(m, 'A').single;
      expect([v['modalite'], v['operateur'], v['montant'], v['origine']], ['mobile_money', 'mtn', 15000, 'encaissement_direct']);
    });
  });

  group('le réglage des modalités : geste réservé, versions datées, rien ne se supprime', () {
    Fiche regler(Magasin m, {bool droit = true, bool fileul = false, String famille = 'operateur', String code = 'orange', String? dateEffet, bool actif = true, String motif = 'Test PAIE-V'}) =>
        reglerModaliteVersementPoste(m, peutRegler: droit, fileul: fileul, famille: famille, code: code, libelle: 'Orange Money', dateEffet: dateEffet, actif: actif, motif: motif);

    test('sans le droit de la fiche RBAC, le réglage est refusé nommé ; un fileul ne règle pas', () {
      final m = jeu();
      expect(() => regler(m, droit: false), throwsA(isA<RefusReglageVersement>().having((e) => e.code, 'code', 'VERSEMENT_REGLAGE_RESERVE')));
      expect(() => regler(m, fileul: true), throwsA(isA<RefusReglageVersement>().having((e) => e.code, 'code', 'FILEUL_LECTURE_SEULE')));
      expect(m.collection('modalitesVersement').actives.length, 8);
    });

    test('un opérateur ajouté est proposé à sa date, archivé il n’est plus proposé mais reste lisible, la version posée ne se réécrit pas', () {
      final m = jeu();
      regler(m, dateEffet: '2026-10-30');
      expect([for (final x in modalitesVersementActives(modalitesVersementPoste(m), 'operateur', '2026-10-30')) x['code']], ['mtn', 'moov', 'celtiis', 'orange']);
      final fiche = regler(m, dateEffet: '2026-11-10', actif: false, motif: 'Contrat résilié');
      final fiches = modalitesVersementPoste(m);
      expect([for (final x in modalitesVersementActives(fiches, 'operateur', '2026-11-10')) x['code']], ['mtn', 'moov', 'celtiis']);
      expect(modaliteVersementALaDate(fiches, 'operateur', 'orange', '2026-11-10')!['libelle'], 'Orange Money', reason: 'lisible sur les pièces passées');
      expect(() => m.collection('modalitesVersement').mettreAJour('${fiche['id']}', {'actif': true}), throwsA(isA<EcritureRefusee>()));
      expect(() => regler(m, dateEffet: '2026-10-01'), throwsA(isA<RefusReglageVersement>().having((e) => e.code, 'code', 'DATE_EFFET_ANTERIEURE')));
    });

    test('la dernière modalité proposée ne s’archive pas ; motif, code et compte sont exigés', () {
      final m = jeu();
      Fiche modalite(String code, {bool actif = true, String? compte = '521000'}) =>
          reglerModaliteVersementPoste(m, peutRegler: true, famille: 'modalite', code: code, libelle: code, compte: compte, actif: actif, dateEffet: '2026-10-30', motif: 'Test');
      modalite('mobile_money', actif: false);
      modalite('tpe', actif: false);
      expect(() => modalite('especes', actif: false), throwsA(isA<RefusReglageVersement>().having((e) => e.code, 'code', 'VERSEMENT_DERNIERE_MODALITE')));
      expect(() => modalite('virement', compte: null), throwsA(isA<RefusReglageVersement>().having((e) => e.code, 'code', 'VERSEMENT_COMPTE_INVALIDE')));
      expect(() => regler(m, motif: ''), throwsA(isA<RefusReglageVersement>().having((e) => e.code, 'code', 'VERSEMENT_MOTIF_ABSENT')));
      expect(() => regler(m, code: 'Orange 2'), throwsA(isA<RefusReglageVersement>().having((e) => e.code, 'code', 'VERSEMENT_CODE_INVALIDE')));
    });

    test('une modalité archivée est refusée à la saisie (VERSEMENT_MODALITE_ARCHIVEE) mais la pièce passée garde son versement lisible', () {
      final m = jeu();
      encaisserFacture(m, 'A', versements: [{'type': 'acompte', 'modalite': 'tpe', 'montant': 1000}], maintenant: auj);
      reglerModaliteVersementPoste(m, peutRegler: true, famille: 'modalite', code: 'tpe', libelle: 'TPE (carte bancaire)', compte: '521000', actif: false, dateEffet: '2026-10-31', motif: 'Terminal rendu');
      final demain = DateTime(2026, 10, 31, 10);
      m.horloge = () => demain;
      try {
        encaisserFacture(m, 'A', versements: [{'type': 'acompte', 'modalite': 'tpe', 'montant': 1000}], maintenant: demain);
        fail('VERSEMENT_MODALITE_ARCHIVEE attendu');
      } on RefusCaisse catch (e) {
        expect(e.code, 'VERSEMENT_MODALITE_ARCHIVEE');
      }
      expect(versementsDePiecePoste(m, 'A').single['modaliteLibelle'], 'TPE (carte bancaire)');
    });
  });

  group('les pièces imprimées', () {
    test('la facture normalisée ne porte AUCUN mode, aucun versement, ni réglé ni reste : le montant total en chiffres et en lettres', () {
      final m = jeu();
      encaisserFacture(m, 'A', versements: [mtn(15000), esp(8500)], maintenant: auj);
      final f = m.collection('factures').parId('A')!;
      final p = pieceFacture(f, utilisateur: 'T', edite: auj, reference: 'R');
      final texte = [for (final b in p.blocs) '$b'].join(' ');
      final libelles = StringBuffer();
      for (final b in p.blocs) {
        if (b is BlocTexte) libelles.writeln(b.texte);
        if (b is BlocTableau) {
          for (final l in b.tableau.lignes) {
            libelles.writeln('${l['k'] ?? ''} ${l['v'] ?? ''}');
          }
        }
      }
      final tout = libelles.toString();
      expect(tout, contains('Arrêtée la présente facture à la somme de : vingt-trois mille cinq cents francs CFA.'));
      expect(tout, isNot(contains('Mode de règlement')));
      expect(tout, isNot(contains('Mobile money')));
      expect(tout, isNot(contains('Espèces')));
      expect(tout, isNot(contains('Montant réglé')));
      expect(tout, isNot(contains('Reste à payer')));
      expect(texte, isNotEmpty);
    });

    test('le reçu DÉTAILLE les versements (type, modalité, opérateur, référence, montant) et le total versé', () {
      final m = jeu();
      encaisserFacture(m, 'A', versements: [mtn(15000), esp(8500)], maintenant: auj);
      final f = m.collection('factures').parId('A')!;
      final p = pieceRecu(f, versementsPiece: versementsDePiecePoste(m, 'A'), utilisateur: 'T', edite: auj, reference: 'R');
      final tableaux = [for (final b in p.blocs) if (b is BlocTableau && b.titre == 'Versements') b.tableau];
      expect(tableaux.length, 1);
      expect([for (final l in tableaux.single.lignes) l['modaliteLibelle']], ['Mobile money', 'Espèces']);
      expect(tableaux.single.lignes.first['operateurLibelle'], 'MTN Mobile Money');
      expect(tableaux.single.lignes.first['referenceTransaction'], 'M123');
    });
  });

  testWidgets('écran de caisse : plusieurs versements dans une seule fenêtre (reste dû en direct, retrait avant validation), pièce soldée, deux fiches, reçu détaillé', (t) async {
    final m = jeu();
    m.collection('factures').archiver('B');
    await ouvrir(t, m);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Encaisser').first);
    expect(find.text('Encaissement'), findsOneWidget);
    expect(find.byKey(const ValueKey('versement-ligne-0')), findsOneWidget);
    expect(find.textContaining('Reste dû après ces versements : ${money(0)}'), findsOneWidget, reason: 'le reste est proposé en entier');
    await toucher(t, find.byKey(const ValueKey('versement-ajouter')));
    expect(find.byKey(const ValueKey('versement-ligne-1')), findsOneWidget);
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('versement-ligne-1')), matching: find.byKey(const Key('kit:champ:montant'))).first, '1000');
    await t.pump();
    expect(find.textContaining('Dépasse le dû de ${money(1000)}'), findsOneWidget, reason: 'le dépassement se dit en direct');
    await toucher(t, find.byKey(const ValueKey('versement-retirer-1')));
    expect(find.byKey(const ValueKey('versement-ligne-1')), findsNothing);
    await toucher(t, find.byKey(const ValueKey('valider-versements')));
    final f = m.collection('factures').parId('A')!;
    expect([f['statutPaiement'], f['reliquat']], ['soldee', 0]);
    expect(versementsDePiecePoste(m, 'A').length, 1);
    expect(find.text('Reçu de paiement'), findsWidgets);
    expect(find.textContaining('VERSEMENTS'), findsWidgets, reason: 'le reçu détaille les versements');
    await t.pump(const Duration(seconds: 15));
  });

  testWidgets('RBAC : sans le droit d’éditer, la commande « Encaisser » est ABSENTE (aide comptable)', (t) async {
    await ouvrir(t, jeu(), role: 'aide_comptable');
    expect(find.widgetWithText(BoutonSigh, 'Encaisser'), findsNothing);
    await t.pump(const Duration(seconds: 15));
  });
}
