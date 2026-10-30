import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// La caisse débloque l'aval : un paiement PARTIEL libère exactement les prestations réglées (et elles seules) ; le solde ouvre pharmacie et
/// laboratoire ; le comptable reçoit une ÉCRITURE équilibrée (RG-10) ; tout est annulable, journalisé, et refusé en le nommant.
final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 10, 30);

Magasin jeu() => Magasin({
      'factures': [
        {
          'id': 'F1',
          'numero': 'FN-2026-00001',
          'patient': 'AWA K.',
          'patientCode': 'CNT/1/26',
          'patientId': 'P1',
          'date': '2026-10-30',
          'type': 'Pharmacie',
          'montantTTC': 6000,
          'partAssurance': 0,
          'partPatient': 6000,
          'montantPaye': 0,
          'reliquat': 6000,
          'statutPaiement': 'impayee',
          'ordonnanceId': 'O1',
          'lignes': [
            {
              'id': 'L1',
              'categorie': 'analyse',
              'designation': 'NFS',
              'quantite': 1,
              'prixUnitaire': 2000,
              'partPatient': 2000,
              'demandeId': 'D1',
              'statutPaiement': 'du'
            },
            {
              'id': 'L2',
              'categorie': 'analyse',
              'designation': 'Glycémie',
              'quantite': 1,
              'prixUnitaire': 1000,
              'partPatient': 1000,
              'demandeId': 'D2',
              'statutPaiement': 'du'
            },
            {
              'id': 'L3',
              'categorie': 'medicament',
              'designation': 'Paracétamol',
              'quantite': 2,
              'prixUnitaire': 1500,
              'partPatient': 3000,
              'statutPaiement': 'du'
            },
          ],
        }
      ],
      'taches': [
        {
          'id': 'T1',
          'type': 'encaissement',
          'statut': 'en_attente',
          'factureId': 'F1',
          'reference': 'ORD-0001',
          'patient': 'AWA K.',
          'patientCode': 'CNT/1/26',
          'detail': 'Encaisser',
          'montant': 6000,
          'date': '2026-10-30'
        },
        {
          'id': 'T2',
          'type': 'dispensation',
          'statut': 'bloque',
          'factureId': 'F1',
          'reference': 'ORD-0001',
          'patient': 'AWA K.',
          'patientCode': 'CNT/1/26',
          'detail': 'Délivrer',
          'date': '2026-10-30'
        },
      ],
      'demandesAnalyses': [
        {
          'id': 'D1',
          'reference': 'LAB-00001',
          'bloqueParPaiement': true,
          'etatAnalyse': 'en_attente',
          'factureId': 'F1',
          'ordonnanceId': 'O1'
        },
        {
          'id': 'D2',
          'reference': 'LAB-00002',
          'bloqueParPaiement': true,
          'etatAnalyse': 'en_attente',
          'factureId': 'F1',
          'ordonnanceId': 'O1'
        },
      ],
      'ordonnances': [
        {'id': 'O1', 'statutPaiement': 'du'}
      ],
    });

Future<void> ouvrir(WidgetTester t, Magasin m, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: 'm8-caisse',
      magasin: m,
      horloge: () => auj));
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
  tearDown(ToastsSigh.viderPourTests);

  test(
      'moteur : règlement partiel libère SEULEMENT les analyses réglées ; le solde ouvre l’aval ; écriture équilibrée ; annulation totale',
      () {
    final m = jeu()..utilisateur = 'Caissier';
    var r = encaisserFacture(m, 'F1',
        lignes: ['L1'], mode: 'especes', maintenant: auj);
    expect(r.montantRegle, 2000);
    expect(r.restantDu, 4000);
    expect(m.collection('demandesAnalyses').parId('D1')!['bloqueParPaiement'],
        false);
    expect(m.collection('demandesAnalyses').parId('D1')!['etatAnalyse'],
        'attente_prelevement');
    expect(m.collection('demandesAnalyses').parId('D2')!['bloqueParPaiement'],
        true,
        reason: 'Glycémie non réglée : elle ne passe pas au laboratoire');
    expect(m.collection('taches').parId('T2')!['statut'], 'bloque',
        reason: 'la pharmacie n’est libérée qu’au solde');
    expect(m.collection('taches').parId('T1')!['statut'], 'en_attente');
    final ecr = r.ecritures;
    expect(ecr.fold<num>(0, (a, e) => a + (e['debit'] as num? ?? 0)),
        ecr.fold<num>(0, (a, e) => a + (e['credit'] as num? ?? 0)),
        reason: 'RG-10');
    expect(ecr.every((e) => e['statut'] == 'brouillon'), isTrue,
        reason: 'la validation comptable reste un geste humain');
    r = encaisserFacture(m, 'F1',
        lignes: ['L2', 'L3'], mode: 'tpe', maintenant: auj);
    expect(r.facture['statutPaiement'], 'soldee');
    expect(r.debloquees, ['dispensation']);
    expect(m.collection('taches').parId('T1')!['statut'], 'fait');
    expect(m.collection('taches').parId('T2')!['statut'], 'en_attente');
    expect(
        m.collection('ordonnances').parId('O1')!['statutPaiement'], 'soldee');
    expect(m.collection('demandesAnalyses').parId('D2')!['bloqueParPaiement'],
        false);
    // Annuler le DERNIER versement restitue tout ce qu'il a écrit — et rien de plus.
    r.annuler();
    expect(
        m.collection('factures').parId('F1')!['statutPaiement'], 'partielle');
    expect(m.collection('taches').parId('T2')!['statut'], 'bloque');
    expect(m.collection('taches').parId('T1')!['statut'], 'en_attente');
    expect(m.collection('demandesAnalyses').parId('D1')!['bloqueParPaiement'],
        false,
        reason: 'le premier versement tient');
    final j = m
        .collection('audit')
        .toutes
        .where((e) => e['action'] == 'Encaissement');
    expect(j, isNotEmpty);
    expect(j.first['utilisateur'], 'Caissier',
        reason: 'RG-12 : aucune action anonyme');
  });

  test('refus nommé : facture introuvable', () {
    expect(
        () => encaisserFacture(jeu(), 'ZZ', maintenant: auj),
        throwsA(isA<RefusCaisse>()
            .having((e) => e.code, 'code', 'FACTURE_INTROUVABLE')));
  });

  test(
      'journal RG-12 : toute écriture du magasin est tracée, archivage compris',
      () {
    final m = jeu()..utilisateur = 'Comptable';
    m.collection('factures').archiver('F1');
    final e = m.collection('audit').toutes.last;
    expect(e['action'], 'Archivage');
    expect(e['utilisateur'], 'Comptable');
    expect(e['reference'], 'FN-2026-00001');
    expect(e['apres'], {'statut': 'archive'});
  });

  testWidgets(
      'la file : prête avant bloquée, état « Attente encaissement », commande verrouillée pour un profil en lecture',
      (t) async {
    await ouvrir(t, jeu());
    expect(find.textContaining('Prescriptions à encaisser — 1 à traiter'),
        findsOneWidget);
    await t.pump();
    expect(find.byTooltip('Encaisser'), findsOneWidget);
    await ouvrir(t, jeu(), role: 'direction');
    expect(find.byTooltip('Votre profil consulte cette file sans l’exécuter'),
        findsOneWidget);
    expect(find.byTooltip('Encaisser'), findsNothing);
  });

  testWidgets(
      'encaisser depuis la file : le total suit la cochage ; paiement partiel annoncé ; reçu proposé ; annulation visible',
      (t) async {
    final m = jeu();
    await ouvrir(t, m);
    await toucher(t, find.byTooltip('Encaisser').first);
    expect(find.byKey(const Key('caisse:total')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('caisse:total'))).data,
        money(6000));
    expect(find.textContaining('intégralement soldée'), findsOneWidget);
    await toucher(t, find.byKey(const Key('caisse:ligne:L3')));
    expect(t.widget<Text>(find.byKey(const Key('caisse:total'))).data,
        money(3000));
    expect(find.textContaining('Reste dû après ce règlement : ${money(3000)}'),
        findsOneWidget);
    await toucher(t, find.text('Valider l’encaissement'));
    expect(m.collection('factures').parId('F1')!['reliquat'], 3000);
    expect(m.collection('demandesAnalyses').parId('D1')!['bloqueParPaiement'],
        false);
    expect(find.text('Reçu de paiement'), findsWidgets);
    expect(find.textContaining('2 examen(s) transmis au laboratoire'),
        findsOneWidget);
    await toucher(t, find.text('Fermer').last);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Annuler').last);
    expect(m.collection('factures').parId('F1')!['statutPaiement'], 'impayee');
    expect(m.collection('demandesAnalyses').parId('D1')!['bloqueParPaiement'],
        true);
    expect(find.text('Action annulée.'), findsOneWidget);
    await t.pump(const Duration(seconds: 12));
  });

  testWidgets('encaisser sans rien cocher est refusé en le disant', (t) async {
    final m = jeu();
    await ouvrir(t, m);
    await toucher(t, find.byTooltip('Encaisser').first);
    for (final id in ['L1', 'L2', 'L3']) {
      await toucher(t, find.byKey(Key('caisse:ligne:$id')));
    }
    await toucher(t, find.text('Valider l’encaissement'));
    expect(find.text('Aucune prestation cochée.'), findsOneWidget);
    expect(m.collection('factures').parId('F1')!['montantPaye'], 0);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets(
      'arrêté : KPI de la journée recomptés ; ventilation par mode ; état imprimé à totaux refaits',
      (t) async {
    final m = jeu();
    encaisserFacture(m, 'F1', lignes: ['L1'], mode: 'mtn', maintenant: auj);
    await ouvrir(t, m);
    final v = [
      for (final w
          in t.widgetList<Text>(find.byKey(const Key('kit:kpi-valeur'))))
        w.data
    ];
    expect(v, [nombre(1), money(6000), money(2000), money(4000)]);
    await toucher(t, find.text('Éditer l’arrêté de caisse'));
    await t.pumpAndSettle();
    expect(find.text('État de caisse journalier'), findsWidgets);
    expect(find.text('La Directrice Administrative'), findsOneWidget);
  });
}
