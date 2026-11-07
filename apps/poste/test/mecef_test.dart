import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/mecef/commun.dart' show pieceFactureNormalisee, paramFiscal;

import 'aide_polices.dart';

/// MECeF en SIMULATION : les six écrans lisent la même collection que la caisse (aucune seconde vérité) ; les réponses du dispositif sont celles de la maquette
/// (tirage graine, rejouées sur vecteurs). Le boîtier physique n'est pas simulé.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);
num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

List<Fiche> norm(Magasin m, String statut) => m
    .collection('factures')
    .actives
    .where((f) => f['proforma'] != true && f['statutMecef'] == statut)
    .toList();

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

  cas('tableau de bord : les compteurs et les alertes sont recomptés sur la caisse', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'mecef-dashboard');
    final rej = norm(m, 'rejete').length, att = norm(m, 'en_attente').length;
    expect(rej, greaterThan(0));
    expect(find.textContaining('$rej facture(s) rejetée(s) par le dispositif fiscal'), findsOneWidget);
    expect(find.textContaining('$att facture(s) en attente de transmission'), findsOneWidget);
    expect(find.text('Taux de validation'), findsOneWidget);
  });

  cas('factures normalisées : le registre et l\'impression portent le code MECeF et le net à payer', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'mecef-factures');
    final tous = m.collection('factures').actives.where((f) => f['proforma'] != true).length;
    expect(find.text('Factures normalisées'), findsWidgets);
    expect(find.text(nombre(tous)), findsWidgets);
    await toucher(t, find.byTooltip('Imprimer la facture normalisée').first);
    expect(find.text('Facture de vente — normalisée'), findsWidgets);
    expect(find.textContaining('Code MECeF / DGI'), findsWidgets);
    expect(find.textContaining('NET À PAYER'), findsWidgets);
  });

  cas('synchroniser : le lot en attente est transmis selon le tirage de la maquette, et l\'annulation le restitue',
      (t) async {
    final m = magasin();
    final att = norm(m, 'en_attente');
    final attendu = synchroniser(att.length, '2026-10-30');
    await ouvrir(t, m, 'mecef-transmission');
    await toucher(t, find.text('Synchroniser maintenant'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Transmettre').last);
    for (var i = 0; i < att.length; i++) {
      final f = m.collection('factures').parId(att[i]['id'])!;
      expect(f['statutMecef'], attendu[i].statutMecef, reason: 'facture $i');
      expect(f['codeRetour'], attendu[i].codeRetour);
      expect(f['numeroMecef'], attendu[i].numeroMecef);
    }
    expect(norm(m, 'en_attente'), isEmpty);
    final acceptees = attendu.where((r) => r.statutMecef == 'valide').length;
    expect(find.textContaining('$acceptees acceptée(s), ${att.length - acceptees} rejetée(s)'), findsWidgets);
    await toucher(t, find.text('Annuler').last);
    expect(norm(m, 'en_attente').length, att.length);
  });

  cas('rejet : « Corriger et réémettre » valide la facture et le journal la compte en réémission', (t) async {
    final m = magasin();
    final avant = norm(m, 'rejete').length;
    await ouvrir(t, m, 'mecef-transmission');
    await toucher(t, find.text('Rejets'));
    await toucher(t, find.widgetWithText(BoutonSigh, 'Corriger et réémettre').first);
    expect(norm(m, 'rejete').length, avant - 1);
    final reemises = m.collection('factures').actives.where((f) => f['reemise'] == true);
    expect(reemises.length, 1);
    expect(reemises.single['statutMecef'], 'valide');
    expect(RegExp(r'^MECEF\d{7}$').hasMatch('${reemises.single['numeroMecef']}'), isTrue);
  });

  cas('RBAC : un profil en lecture voit la file sans pouvoir la transmettre', (t) async {
    await ouvrir(t, magasin(), 'mecef-transmission', role: 'direction');
    expect(find.text('Transmission & réponses'), findsWidgets);
    expect(find.text('Synchroniser maintenant'), findsNothing);
    await toucher(t, find.text('Rejets'));
    expect(find.widgetWithText(BoutonSigh, 'Corriger et réémettre'), findsNothing);
  });

  cas('avoir MECeF : supérieur à la facture → refusé nommément, rien n\'est écrit', (t) async {
    final m = magasin();
    final f = norm(m, 'valide').first;
    await ouvrir(t, m, 'mecef-avoirs');
    expect(find.text('Aucun avoir émis.'), findsOneWidget);
    await toucher(t, find.text('Émettre un avoir'));
    // Le registre de la facture choisie : on en prend la plus récente (la liste est triée par date décroissante).
    await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:factureId')), matching: find.byType(InkWell)).first);
    await t.enterText(find.byType(TextField).last, '${f['numero']}');
    await t.pump(const Duration(milliseconds: 200));
    await toucher(t, find.textContaining('${f['numero']}').last);
    await t.enterText(
        find.descendant(of: find.byKey(const Key('kit:champ:montant')), matching: find.byType(TextField)),
        '${n(f['montantTTC']) + 1}');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre l’avoir'));
    // B10 : le plafond est le CUMUL des avoirs (moteur unique), plus le seul « montant ≤ facture ».
    expect(find.textContaining('excéderait la facture'), findsWidgets);
    expect(m.collection('avoirs').actives, isEmpty);
  });

  /// Saisit la modale d'avoir MECeF sur la plus récente facture validée, avec [montant], et clique « Émettre l'avoir ».
  Future<void> emettre(WidgetTester t, Magasin m, Fiche f, String montant) async {
    await ouvrir(t, m, 'mecef-avoirs');
    await toucher(t, find.text('Émettre un avoir'));
    await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:factureId')), matching: find.byType(InkWell)).first);
    await t.enterText(find.byType(TextField).last, '${f['numero']}');
    await t.pump(const Duration(milliseconds: 200));
    await toucher(t, find.textContaining('${f['numero']}').last);
    await t.enterText(
        find.descendant(of: find.byKey(const Key('kit:champ:montant')), matching: find.byType(TextField)), montant);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre l’avoir'));
  }

  cas('E10 : un avoir MECeF de 0 FCFA est refusé en nommant le défaut, rien n\'est écrit', (t) async {
    final m = magasin();
    await emettre(t, m, norm(m, 'valide').first, '0');
    expect(find.textContaining('strictement supérieur à 0 FCFA'), findsWidgets);
    expect(m.collection('avoirs').actives, isEmpty);
  });

  cas('B10 : l\'avoir MECeF passe par le moteur unique : contre-passation en brouillon, facture qui porte son avoir, origine mecef', (t) async {
    final m = magasin();
    final f = norm(m, 'valide').first;
    await emettre(t, m, f, '500');
    final a = m.collection('avoirs').actives.single;
    expect(a['origine'], 'mecef');
    expect(a['lignesAnnulees'], isNotEmpty, reason: 'E2 : une pièce sans lignes est refusée, la ligne est nommée');
    final ecr = m.collection('ecritures').actives.where((e) => e['pieceId'] == a['id']).toList();
    expect(ecr.length, 2);
    expect(ecr.every((e) => e['statut'] == 'brouillon'), isTrue);
    expect(ecr.fold<num>(0, (x, e) => x + n(e['debit'])), 500);
    expect(ecr.fold<num>(0, (x, e) => x + n(e['credit'])), 500);
    expect(n(m.collection('factures').parId(f['id'])!['montantAvoirs']), 500);
  });

  cas('E15 : le plafond est CUMULÉ entre canaux : un avoir de caisse déjà émis borne l\'avoir MECeF', (t) async {
    final m = magasin();
    final f = norm(m, 'valide').first;
    m.collection('avoirs').inserer({
      'reference': 'AV-2026-0001', 'factureId': f['id'], 'montant': n(f['montantTTC']) - 100, 'origine': 'caisse', 'statut': 'actif',
    }, prefixe: 'AVR');
    await emettre(t, m, f, '101');
    expect(find.textContaining('cumul des avoirs'), findsWidgets);
    expect(m.collection('avoirs').actives.length, 1);
  });

  cas('E14 : la facture normalisée imprime l\'IFU du CLIENT (vide s\'il est inconnu), jamais celui de la clinique', (t) async {
    final m = magasin();
    final f = norm(m, 'valide').first;
    final p = m.collection('patients').parId(f['patientId']);
    expect(ifuClientDe(f, p), isNot(IdentiteClinique.ifu));
    expect(ifuClientDe({...f, 'ifuClient': '3201912345678'}, p), '3201912345678');
    // La pièce imprimée : la ligne « IFU client » du cartouche.
    String ifuImprime(Fiche x, Fiche? pat) => pieceFactureNormalisee(x, paramFiscal(m),
            patient: pat, utilisateur: 'TEST', edite: aujourdhui, reference: 'REF')
        .cartouche
        .firstWhere((c) => c.$1 == 'IFU client')
        .$2;
    expect(ifuImprime(f, p), '');
    expect(ifuImprime(f, p), isNot(IdentiteClinique.ifu));
    expect(ifuImprime({...f, 'ifuClient': '3201912345678'}, p), '3201912345678');
  });

  cas('avoir MECeF : transmis et validé d\'office, référence en série annuelle, annulable', (t) async {
    final m = magasin();
    final f = norm(m, 'valide').first;
    await ouvrir(t, m, 'mecef-avoirs');
    await toucher(t, find.text('Émettre un avoir'));
    await toucher(t, find.descendant(of: find.byKey(const Key('kit:champ:factureId')), matching: find.byType(InkWell)).first);
    await t.enterText(find.byType(TextField).last, '${f['numero']}');
    await t.pump(const Duration(milliseconds: 200));
    await toucher(t, find.textContaining('${f['numero']}').last);
    await t.enterText(
        find.descendant(of: find.byKey(const Key('kit:champ:montant')), matching: find.byType(TextField)), '500');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Émettre l’avoir'));
    final a = m.collection('avoirs').actives.single;
    expect(a['reference'], 'AV-2026-0001');
    expect(a['statutMecef'], 'valide');
    expect(a['factureNumero'], f['numero']);
    expect(RegExp(r'^MECEF\d{7}$').hasMatch('${a['numeroMecef']}'), isTrue);
    await toucher(t, find.text('Annuler').last);
    expect(m.collection('avoirs').actives, isEmpty);
  });

  cas('journal : lecture seule, une ligne par facture normalisée', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'mecef-journal');
    final nn = m.collection('factures').actives.where((f) => f['proforma'] != true).length;
    expect(find.text(nombre(nn)), findsWidgets);
    expect(find.byType(BoutonSigh).evaluate().where((e) => (e.widget as BoutonSigh).libelle.startsWith('Émettre') || (e.widget as BoutonSigh).libelle == 'Transmettre'), isEmpty);
  });

  cas('configuration : l\'enregistrement est journalisé (RG-12) et dit ce qu\'il ne fait pas encore', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'mecef-config');
    expect(find.text('Régime de TVA'), findsWidgets);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer les paramètres'));
    expect(m.collection('audit').toutes.any((e) => e['entite'] == 'ConfigurationFiscale'), isTrue);
    expect(find.textContaining('Le prototype simule les échanges avec le dispositif fiscal'), findsOneWidget);
  });
}
