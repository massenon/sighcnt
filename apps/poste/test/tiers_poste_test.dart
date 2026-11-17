import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show TranchesCreances;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tiers_poste.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LOT TIERS au poste : la facture à un tiers payeur. Les règles pures sont rejouées sur les vecteurs de la maquette (`packages/domaine/test/tiers_payeurs_test.dart`) ; ici le
/// BRANCHEMENT au magasin du poste (droits par gestes réservés, brouillon, décision de l'AIB par le comptable, émission sans numéro simulé, pièce émise figée par la garde du
/// magasin, avoir, règlement, lettrage, créance) et l'ÉCRAN (commandes ABSENTES sans le geste).
typedef M = Map<String, Object?>;

Magasin _magasin() {
  final m = Magasin({
    'utilisateurs': <M>[],
    'audit': <M>[],
    'exercices': <M>[],
    'patients': <M>[
      {'id': 'PAT1', 'statut': 'actif', 'code': 'CNT/1/26', 'nom': 'Patient Un'}
    ],
    'factures': <M>[
      {
        'id': 'FAC1',
        'statut': 'actif',
        'numero': 'FAC-2026-0001',
        'date': '2026-10-10',
        'patientId': 'PAT1',
        'patient': 'Patient Un',
        'montantTTC': 100000,
        'type': 'Facture',
        'lignes': <M>[
          {'id': 'L001', 'designation': 'Hospitalisation', 'montant': 60000, 'partAssureur': 20000, 'partPersonnel': 0},
          {'id': 'L002', 'designation': 'Bilan sanguin', 'montant': 40000, 'partAssureur': 0, 'partPersonnel': 0},
          {'id': 'L003', 'designation': 'Sans prix', 'prixManquant': {'nature': 'manquant'}},
        ],
      }
    ],
  });
  serviceParametres(m, auteur: () => 'Poste mère').semerDefauts();
  return m;
}

TiersPoste _t(Magasin m, {Set<String> gestes = const {'emettre_facture_tiers', 'corriger_facture_tiers', 'imputer_aib'}, String jour = '2026-10-30'}) =>
    TiersPoste(m, auteur: () => 'Agent de test', libelleRole: 'Rôle de test', droit: gestes.contains, horloge: () => DateTime.parse(jour));

void main() {
  test('le droit est le geste réservé de la fiche : sans lui, le moteur du poste refuse nommément et n\'écrit rien', () {
    final m = _magasin();
    final sans = _t(m, gestes: const {});
    expect(sans.creerTiers({'nom': 'X', 'type': 'entreprise'})['code'], 'TIERS_RESERVE');
    expect(sans.proposer({'tiersCode': 'TP-001', 'lignes': const []})['code'], 'FACTURE_TIERS_RESERVEE');
    expect(sans.emettre('x')['code'], 'FACTURE_TIERS_RESERVEE');
    expect(sans.reglement({'tiersCode': 'TP-001'})['code'], 'REGLEMENT_TIERS_RESERVE');
    expect(sans.avoir('x', 'm')['code'], 'AVOIR_TIERS_RESERVE');
    expect(sans.lettrer('x', const [])['code'], 'LETTRAGE_TIERS_RESERVE');
    expect(m.collection('tiersPayeurs').toutes, isEmpty);
    // Le caissier émet mais ne décide pas de l'AIB ; il ne corrige pas.
    final caissier = _t(m, gestes: const {'emettre_facture_tiers'});
    expect(caissier.deciderAib('x', {'appliquer': false, 'motif': 'm'})['code'], 'IMPUTATION_AIB_RESERVEE');
    expect(caissier.avoir('x', 'm')['code'], 'AVOIR_TIERS_RESERVE');
  });

  test('de la fiche du tiers à la facture émise : IFU et nom contrôlés, AIB décidé par le comptable, numéro de l\'année de la pièce, AUCUN numéro MECeF fabriqué, facture du patient intacte', () {
    final m = _magasin();
    final t = _t(m);
    expect(t.creerTiers({'nom': 'Soc', 'type': 'entreprise', 'ifu': '12345'})['code'], 'IFU_INVALIDE');
    final sans = t.creerTiers({'nom': 'Convention sans IFU', 'type': 'convention', 'dateEffet': '2026-01-05'});
    final a = t.creerTiers({'nom': 'Société de test', 'type': 'entreprise', 'ifu': '3201642748321', 'delaiPaiementJours': 30, 'dateEffet': '2026-01-05'});
    expect(a['ok'], isTrue);
    L(String id, num mt) => {'factureId': 'FAC1', 'ligneId': id, 'montant': mt};
    expect(t.proposer({'tiersCode': sans['code'], 'date': '2026-10-12', 'lignes': [L('L002', 100)]})['code'], 'TIERS_IFU_ABSENT');
    expect(t.proposer({'tiersCode': a['code'], 'date': '2026-10-12', 'lignes': [L('L003', 100)]})['code'], 'FACTURE_TIERS_PRIX_MANQUANT');
    expect(t.proposer({'tiersCode': a['code'], 'date': '2026-10-12', 'lignes': [L('L001', 50000)]})['code'], 'FACTURE_TIERS_MONTANT_DEPASSE', reason: 'la part de l\'assureur est exclue');
    expect(m.collection('facturesTiers').toutes, isEmpty, reason: 'un refus n\'écrit rien');
    final facAvant = m.collection('factures').parId('FAC1').toString();
    final p = t.proposer({'tiersCode': a['code'], 'date': '2026-10-12', 'lignes': [L('L001', 30000), L('L002', 40000)]});
    expect(p['ok'], isTrue, reason: '$p');
    final f = m.collection('facturesTiers').parId(p['id'])!;
    expect(f['base'], 70000);
    expect(f['partPatientRestante'], 10000, reason: '(60 000 − 20 000 − 30 000) + (40 000 − 40 000)');
    expect(f['ifuAcheteur'], '3201642748321');
    expect(t.emettre(p['id'])['code'], 'TIERS_AIB_DECISION_ABSENTE', reason: 'le logiciel n\'impose jamais l\'AIB');
    expect(t.proposer({'tiersCode': a['code'], 'date': '2026-10-12', 'lignes': [L('L002', 5000)]})['code'], 'FACTURE_TIERS_MONTANT_DEPASSE', reason: 'une prestation prise ne se reprend pas');
    expect(t.proposerAib(p['id'])['taux'], 1);
    expect(t.deciderAib(p['id'], {'appliquer': true, 'situation': 'ifu_actif', 'taux': 1})['ok'], isTrue);
    final e = t.emettre(p['id']);
    expect(e['ok'], isTrue, reason: '$e');
    expect(e['numero'], 'FT-2026-0001');
    expect([e['aib'], e['net']], [700, 70700]);
    final emise = m.collection('facturesTiers').parId(p['id'])!;
    expect(emise['statutMecef'], 'en_attente');
    expect(emise['codeRetour'], 'MECEF_NON_CONFIGURE');
    expect(emise.containsKey('numeroMecef'), isFalse, reason: 'aucun numéro MECeF simulé');
    expect(m.collection('factures').parId('FAC1').toString(), facAvant, reason: 'la facture du patient n\'est pas réécrite');
    // Une pièce émise ne se réécrit jamais : refus du moteur ET garde du magasin.
    expect(t.emettre(p['id'])['code'], 'FACTURE_TIERS_DEJA_EMISE');
    expect(t.deciderAib(p['id'], {'appliquer': false, 'motif': 'x'})['code'], 'FACTURE_TIERS_EMISE');
    expect(() => m.collection('facturesTiers').mettreAJour(p['id'], {'base': 1}), throwsA(isA<EcritureRefusee>()));
    expect(() => m.collection('facturesTiers').mettreAJour(p['id'], {'ifuAcheteur': '0000000000000'}), throwsA(isA<EcritureRefusee>()));
    expect(() => m.collection('facturesTiers').mettreAJour(p['id'], {'statutMecef': 'rejete'}), returnsNormally, reason: 'les traces MECeF évoluent');
    // L'année du numéro suit la date de la pièce.
    final f2 = t.proposer({'tiersCode': a['code'], 'date': '2026-12-20', 'lignes': [L('L001', 100)]});
    t.deciderAib(f2['id'], {'appliquer': false, 'motif': 'L\'acheteur paie son AIB'});
    expect(t.emettre(f2['id'])['numero'], 'FT-2026-0002');
    expect(m.collection('audit').toutes.any((x) => x['action'] == 'Facture tiers : émission'), isTrue, reason: 'RG-12');
  });

  test('règlement reçu, lettrage, créance (dû moins lettrages), avoir refusé après lettrage, avoir total suivi de l\'état fiscal sans numéro', () {
    final m = _magasin();
    final t = _t(m);
    final a = t.creerTiers({'nom': 'Société de test', 'type': 'entreprise', 'ifu': '3201642748321', 'delaiPaiementJours': 30, 'dateEffet': '2026-01-05'});
    String mk(String ligne, num mt, String date) {
      final p = t.proposer({'tiersCode': a['code'], 'date': date, 'lignes': [{'factureId': 'FAC1', 'ligneId': ligne, 'montant': mt}]});
      t.deciderAib(p['id'], {'appliquer': false, 'motif': 'Essai'});
      expect(t.emettre(p['id'])['ok'], isTrue);
      return '${p['id']}';
    }

    final f1 = mk('L001', 40000, '2026-10-01'), f2 = mk('L002', 40000, '2026-10-20');
    final tr = const TranchesCreances(30, 90);
    expect(t.creances('2026-10-30', tr)['total'], 80000);
    final r = t.reglement({'tiersCode': a['code'], 'date': '2026-10-28', 'montant': 50000, 'mode': 'virement', 'referencePaiement': 'VIR-1'});
    expect(r['ok'], isTrue);
    expect(t.reglement({'tiersCode': a['code'], 'date': '2026-10-28', 'montant': 50000, 'mode': 'virement', 'referencePaiement': 'vir-1'})['code'], 'REGLEMENT_TIERS_DEJA_SAISI');
    expect(t.creances('2026-10-30', tr)['total'], 80000, reason: 'non lettré : aucune créance ne diminue');
    expect(t.lettrer(r['id'], [{'factureTiersId': f1, 'montant': 40001}])['code'], 'LETTRAGE_TIERS_DEPASSE');
    expect(t.lettrer(r['id'], [{'factureTiersId': f1, 'montant': 40000}, {'factureTiersId': f2, 'montant': 10000}])['ok'], isTrue);
    final b = t.creances('2026-10-30', tr);
    expect(b['total'], 30000);
    expect(b['nonLettre'], 0);
    expect(t.avoir(f1, 'Essai')['code'], 'AVOIR_TIERS_APRES_LETTRAGE');
    final l = m.collection('lettragesTiers').actives.firstWhere((x) => x['factureTiersId'] == f1);
    expect(t.delettrer(l['id'], ' ')['code'], 'LETTRAGE_TIERS_MOTIF_ABSENT');
    expect(t.delettrer(l['id'], 'Mauvaise facture')['ok'], isTrue);
    expect(t.creances('2026-10-30', tr)['total'], 70000);
    expect(() => m.collection('lettragesTiers').mettreAJour(l['id'], {'montant': 1}), throwsA(isA<EcritureRefusee>()));
    final av = t.avoir(f1, 'Prise en charge retirée');
    expect(av['ok'], isTrue);
    final ficheAvoir = m.collection('avoirsTiers').parId(av['id'])!;
    expect(ficheAvoir['statutMecef'], 'sans_objet', reason: 'pièce jamais certifiée : sans objet ; certifiée, « en attente » de régularisation ; aucun numéro fabriqué');
    expect(ficheAvoir.containsKey('numeroMecef'), isFalse);
    expect(t.avoir(f1, 'encore')['code'], 'AVOIR_TIERS_DEJA_EMIS');
    expect(t.creances('2026-10-30', tr)['total'], 30000 + 0, reason: 'la facture annulée n\'est plus une créance');
    // Une version de tiers ne se réécrit pas.
    final v = m.collection('tiersPayeurs').toutes.first;
    expect(() => m.collection('tiersPayeurs').mettreAJour(v['id'], {'nom': 'Autre'}), throwsA(isA<EcritureRefusee>()));
  });

  group('écran', () {
    setUpAll(chargerPolices);
    final donnees = DonneesNavigation.depuisDossier();

    Future<void> ouvrir(WidgetTester t, Magasin m, String role) async {
      t.view.physicalSize = const Size(1600, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(SighPoste(key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: 'm8-factures-tiers', magasin: m, horloge: () => DateTime(2026, 10, 30)));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('avec le geste : « Nouvelle facture à un tiers payeur » est offerte ; sans le geste (Direction) elle est ABSENTE et le moteur refuse ; la liste reste lisible', (t) async {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
      final svc = TiersPoste(m, auteur: () => 'Test', libelleRole: 'Test', droit: (_) => true, horloge: () => DateTime(2026, 10, 30));
      svc.creerTiers({'nom': 'Entreprise écran', 'type': 'entreprise', 'ifu': '3201642748999', 'dateEffet': '2026-01-05'});
      await ouvrir(t, m, 'admin');
      expect(find.byKey(const Key('tiers:nouvelle')), findsOneWidget);
      expect(find.text('Factures aux tiers payeurs'), findsWidgets);
      for (final o in ['Factures', 'Tiers payeurs', 'Règlements et lettrage', 'Créances']) {
        expect(find.text(o), findsWidgets, reason: o);
      }
      await t.pump(const Duration(seconds: 10));
      await ouvrir(t, m, 'direction');
      expect(find.byKey(const Key('tiers:nouvelle')), findsNothing, reason: 'commande ABSENTE sans le geste emettre_facture_tiers');
      expect(find.text('Factures aux tiers payeurs'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });
  });
}
