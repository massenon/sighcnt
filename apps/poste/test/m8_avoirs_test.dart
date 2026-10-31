import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show money;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Factures d'avoir et remboursements : le moteur est rejoué sur des vecteurs de la maquette ; ici, l'ÉCRAN — ce qui est écrit, refusé, annulable.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);
num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

String money0(Object? v) => money(v);
Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

/// La facture la plus récente, réglée et détaillée par ligne : celle qu'un agent rectifie.
Fiche cible(Magasin m) => (m
        .collection('factures')
        .actives
        .where((f) =>
            (f['lignes'] as List?)?.isNotEmpty == true &&
            n(f['montantTTC']) > 0 &&
            n(f['montantPaye']) > 0)
        .toList()
      ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}')))
    .first;

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran,
    {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
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

/// Ouvre la liste du champ [champ] et y choisit [cible] (en la cherchant : le panneau ne construit que les lignes visibles).
Future<void> choisir(WidgetTester t, String champ, String cible) async {
  await toucher(
      t,
      find.descendant(
          of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  setUp(
      () => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('avoirs : le jeu n\'en contient aucun → état vide dit, KPI à zéro', (t) async {
    await ouvrir(t, magasin(), 'm8-facture-avoir');
    expect(find.text('Aucun avoir émis.'), findsOneWidget);
    expect(find.text('Émettre un avoir'), findsOneWidget);
  });

  cas('avoir : une ligne nommée contre-passée, écritures équilibrées en brouillon, facture non réécrite',
      (t) async {
    final m = magasin();
    final f = cible(m);
    final avantTTC = f['montantTTC'];
    await ouvrir(t, m, 'm8-facture-avoir');
    await toucher(t, find.text('Émettre un avoir'));
    await choisir(t, 'facture', '${f['numero']} — ${f['patient']}');
    final ligne = ((f['lignes'] as List).first as Map)['designation'];
    await toucher(t, find.text('$ligne').first);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre l’avoir'));
    final avoirs = m.collection('avoirs').actives;
    expect(avoirs.length, 1);
    final a = avoirs.single;
    expect(a['reference'], 'AV-2026-0001');
    expect(a['factureNumero'], f['numero']);
    expect((a['lignesAnnulees'] as List).single['designation'], ligne);
    final ecr = m.collection('ecritures').actives.where((e) => e['pieceId'] == a['id']).toList();
    expect(ecr.length, 2);
    expect(ecr.every((e) => e['statut'] == 'brouillon'), isTrue);
    expect(ecr.fold<num>(0, (s, e) => s + n(e['debit'])), ecr.fold<num>(0, (s, e) => s + n(e['credit'])));
    final apres = m.collection('factures').parId(f['id'])!;
    expect(apres['montantTTC'], avantTTC, reason: 'une pièce émise ne se réécrit jamais');
    expect(apres['montantAvoirs'], a['montant']);
    expect((apres['avoirIds'] as List).single, a['id']);
    expect(m.collection('audit').toutes.any((e) => e['action'] == 'Facture d’avoir émise'), isTrue);
    // Annuler retire l'avoir (archivage, RG-14) et restitue la facture.
    await toucher(t, find.text('Annuler').last);
    expect(m.collection('avoirs').actives, isEmpty);
    expect(m.collection('factures').parId(f['id'])!['montantAvoirs'], isNull);
  });

  cas('avoir sans ligne cochée : refus nommé, rien n\'est écrit', (t) async {
    final m = magasin();
    final f = cible(m);
    await ouvrir(t, m, 'm8-facture-avoir');
    await toucher(t, find.text('Émettre un avoir'));
    await choisir(t, 'facture', '${f['numero']} — ${f['patient']}');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre l’avoir'));
    expect(find.textContaining('Un avoir se rapporte à des LIGNES nommées'), findsWidgets);
    expect(m.collection('avoirs').actives, isEmpty);
    expect(m.collection('ecritures').actives.where((e) => e['origine'] == 'Facture d’avoir'), isEmpty);
  });

  cas('fille consolidée dans une mère : l\'avoir est refusé en NOMMANT la mère', (t) async {
    final m = magasin();
    final f = cible(m);
    m.collection('facturesMere').inserer({
      'id': 'FM-T',
      'numero': 'FM-2026-0042',
      'compagnie': 'NSIA',
      'piecesFilles': [f['numero']],
      'statut': 'actif'
    });
    await ouvrir(t, m, 'm8-facture-avoir');
    await toucher(t, find.text('Émettre un avoir'));
    await choisir(t, 'facture', '${f['numero']} — ${f['patient']}');
    final ligne = ((f['lignes'] as List).first as Map)['designation'];
    await toucher(t, find.text('$ligne').first);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre l’avoir'));
    expect(find.textContaining('FM-2026-0042'), findsWidgets);
    expect(m.collection('avoirs').actives, isEmpty);
  });

  cas('RBAC : un profil sans droit d\'écriture sur l\'écran consulte les avoirs sans pouvoir en émettre',
      (t) async {
    await ouvrir(t, magasin(), 'm8-facture-avoir', role: 'caissier');
    expect(find.text('Factures d’avoir'), findsWidgets);
    expect(find.text('Émettre un avoir'), findsNothing);
  });

  cas('remboursements : une annulation repasse la facture impayée, MECeF « rejeté » — jamais supprimée, et annulable',
      (t) async {
    final m = magasin();
    final f = cible(m);
    await ouvrir(t, m, 'm8-remboursements');
    expect(find.text('Aucun remboursement ni annulation enregistré.'), findsOneWidget);
    await toucher(t, find.text('Nouvelle opération'));
    await choisir(t, 'factureId', '${f['numero']} — ${f['patient']} — ${money0(f['montantTTC'])}');
    await choisir(t, 'nature', 'Annulation');
    final champ = find.descendant(of: find.byKey(const Key('kit:champ:montant')), matching: find.byType(TextField));
    await t.enterText(champ, '1000');
    await t.enterText(
        find.descendant(of: find.byKey(const Key('kit:champ:motif')), matching: find.byType(TextField)),
        'Facture émise par erreur');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final r = m.collection('remboursements').actives.single;
    expect(r['reference'], 'RB-00001');
    expect(r['nature'], 'Annulation');
    final apres = m.collection('factures').parId(f['id'])!;
    expect(apres['statutPaiement'], 'impayee');
    expect(apres['statutMecef'], 'rejete');
    expect(apres['annulee'], true);
    expect(m.collection('factures').actives.any((x) => x['id'] == f['id']), isTrue, reason: 'RG-14 : jamais supprimée');
    await toucher(t, find.text('Annuler').last);
    expect(m.collection('remboursements').actives, isEmpty);
    expect(m.collection('factures').parId(f['id'])!['statutPaiement'], f['statutPaiement']);
    expect(m.collection('factures').parId(f['id'])!['annulee'], isNull);
  });

  /// Saisit la modale « Nouvelle opération » pour la nature « Facture avoir » et clique « Enregistrer ».
  Future<void> operationAvoir(WidgetTester t, Magasin m, Fiche f, String montant) async {
    await ouvrir(t, m, 'm8-remboursements');
    await toucher(t, find.text('Nouvelle opération'));
    await choisir(t, 'factureId', '${f['numero']} — ${f['patient']} — ${money0(f['montantTTC'])}');
    await choisir(t, 'nature', 'Facture avoir');
    await t.enterText(
        find.descendant(of: find.byKey(const Key('kit:champ:montant')), matching: find.byType(TextField)), montant);
    await t.enterText(
        find.descendant(of: find.byKey(const Key('kit:champ:motif')), matching: find.byType(TextField)),
        'Tarif mal appliqué');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
  }

  cas('B10 : la nature « Facture avoir » APPELLE le moteur unique : un avoir dans `avoirs`, aucune pièce négative, annulable', (t) async {
    final m = magasin();
    final f = cible(m);
    final facturesAvant = m.collection('factures').toutes.length;
    await operationAvoir(t, m, f, '1000');
    final a = m.collection('avoirs').actives.single;
    expect(a['origine'], 'caisse');
    expect(n(a['montant']), 1000);
    expect(a['factureId'], f['id']);
    expect(a['statutMecef'], f['statutMecef'] == 'valide' ? 'en_attente' : 'sans_objet');
    final r = m.collection('remboursements').actives.single;
    expect(r['nature'], 'Facture avoir');
    expect(r['avoirId'], a['id']);
    expect(r['avoirNumero'], a['reference']);
    expect(m.collection('factures').toutes.length, facturesAvant, reason: 'plus de pièce négative dans les factures');
    final ecr = m.collection('ecritures').actives.where((e) => e['pieceId'] == a['id']).toList();
    expect(ecr.length, 2);
    expect(ecr.every((e) => e['statut'] == 'brouillon'), isTrue);
    expect(ecr.fold<num>(0, (x, e) => x + n(e['debit'])), ecr.fold<num>(0, (x, e) => x + n(e['credit'])));
    expect(n(m.collection('factures').parId(f['id'])!['montantAvoirs']), 1000);
    // L'annulation est visible : l'avoir et ses écritures sont ARCHIVÉS (RG-14), la facture rend le plafond.
    await toucher(t, find.text('Annuler').last);
    expect(m.collection('avoirs').actives, isEmpty);
    expect(m.collection('remboursements').actives, isEmpty);
    expect(m.collection('ecritures').actives.where((e) => e['pieceId'] == a['id']), isEmpty);
    expect(n(m.collection('factures').parId(f['id'])!['montantAvoirs']), n(f['montantAvoirs']));
  });

  cas('E10 : un montant à 0 FCFA est refusé en le nommant, rien n\'est écrit', (t) async {
    final m = magasin();
    final f = cible(m);
    await operationAvoir(t, m, f, '0');
    expect(find.textContaining('strictement supérieur à 0 FCFA'), findsWidgets);
    expect(m.collection('avoirs').actives, isEmpty);
    expect(m.collection('remboursements').actives, isEmpty);
  });

  cas('plafond CUMULÉ : un avoir déjà émis par un autre canal borne l\'avoir de l\'écran de facturation', (t) async {
    final m = magasin();
    final f = cible(m);
    final ttc = n(f['montantTTC']);
    // Un avoir MECeF de (TTC - 100) est déjà émis sur la facture : 101 FCFA de plus dépassent le plafond.
    m.collection('avoirs').inserer({
      'reference': 'AV-2026-0001', 'factureId': f['id'], 'montant': ttc - 100, 'origine': 'mecef', 'statut': 'actif',
    }, prefixe: 'AVR');
    await operationAvoir(t, m, f, '101');
    expect(find.textContaining('cumul des avoirs'), findsWidgets);
    expect(m.collection('avoirs').actives.length, 1);
    expect(m.collection('remboursements').actives, isEmpty);
  });

  cas('remboursements : le motif est obligatoire (RG-12), rien n\'est écrit sans lui', (t) async {
    final m = magasin();
    final f = cible(m);
    await ouvrir(t, m, 'm8-remboursements');
    await toucher(t, find.text('Nouvelle opération'));
    await choisir(t, 'factureId', '${f['numero']} — ${f['patient']} — ${money0(f['montantTTC'])}');
    await choisir(t, 'nature', 'Remboursement');
    await t.enterText(
        find.descendant(of: find.byKey(const Key('kit:champ:montant')), matching: find.byType(TextField)), '500');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.textContaining('formulaire comporte des erreurs'), findsWidgets);
    expect(m.collection('remboursements').actives, isEmpty);
  });

  cas('RBAC : un profil en lecture n\'a pas « Nouvelle opération »', (t) async {
    await ouvrir(t, magasin(), 'm8-remboursements', role: 'direction');
    expect(find.text('Nouvelle opération'), findsNothing);
  });
}
