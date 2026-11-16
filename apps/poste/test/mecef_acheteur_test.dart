import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show adaptateurPourMode, mecefCleMode, parametreDateIso;
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/mecef_poste.dart';
import 'package:sigh_poste/donnees/normalisation_mecef.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// La fenêtre « Facture normalisée » à l'émission et la NORMALISATION de la vente soldée (E2299) : toute vente est normalisée, le numéro ne naît
/// jamais à l'émission, un refus nomme son défaut et n'écrit rien. Aucun boîtier n'est branché : le numéro est celui de l'appareil de démonstration.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> ouvrir(WidgetTester t, Magasin m, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: 'm8-facturation',
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

Future<void> choisir(WidgetTester t, String courant, String cible) async {
  await toucher(t, find.text(courant).first);
  await toucher(t, find.text(cible).last);
}

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  final f = find.descendant(
      of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField));
  await t.ensureVisible(f);
  await t.enterText(f, valeur);
  await t.pump();
}

Future<void> ajouterLibre(WidgetTester t, String libelle, String prix) async {
  await choisir(t, 'Acte / consultation', 'Ligne libre');
  await saisir(t, 'designation', libelle);
  await saisir(t, 'prix', prix);
  await saisir(t, 'quantite', '1');
  await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      // 15 s : le refus nommé de la normalisation (MECEF_NON_CONFIGURE) vit 12 s, plus que les autres messages (lot L3).
      await t.pump(const Duration(seconds: 15));
    });

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('plus de bloc « Facture normalisée » à l\'émission : ni IFU de l\'acheteur, ni nom, ni taux d\'AIB (Direction, 16/11/2026, lot FISC-2)', (t) async {
    await ouvrir(t, magasin());
    expect(find.text('FACTURE NORMALISÉE'), findsNothing);
    expect(find.text('IFU de l’acheteur'), findsNothing);
    expect(find.text('Nom de l’acheteur'), findsNothing);
    expect(find.text('Taux d’AIB'), findsNothing);
    expect(find.textContaining('Toute vente est normalisée'), findsNothing);
  });

  cas('vente soldée : aucun acheteur ni AIB dans la pièce (la facture d\'un patient ne porte aucun AIB), la vente reste EN ATTENTE de certification et ne reçoit AUCUN numéro (lot L3)', (t) async {
    final m = magasin();
    final numeros0 = numerosPris(m).length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final f = m.collection('factures').actives.first;
    expect(f['statutPaiement'], 'soldee', reason: 'l\'encaissement reste acquis');
    expect(f['ifuClient'], isNull);
    expect(f['acheteurNom'], isNull);
    expect(f['aibTaux'], 0);
    expect(f['statutMecef'], 'en_attente');
    expect(f['numeroMecef'], isNull, reason: 'aucun numéro fabriqué');
    expect(f['codeRetour'], 'MECEF_NON_CONFIGURE');
    expect(f['modeMecef'], 'boitier', reason: 'le défaut du registre');
    expect(f['mecefSimule'], isNull);
    expect(numerosPris(m).length, numeros0);
    expect(find.textContaining('MECEF_NON_CONFIGURE'), findsWidgets);
  });

  cas('règlement partiel : aucune normalisation, aucun numéro, la pièce attend le solde', (t) async {
    final m = magasin();
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '1000');
    await saisir(t, 'regle', '400');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final f = m.collection('factures').actives.first;
    expect(f['statutPaiement'], 'partielle');
    expect(f['statutMecef'], 'en_attente');
    expect(f['numeroMecef'], isNull);
  });

  group('normaliserVente', () {
    Fiche vente(Magasin m, [Map<String, Object?> sup = const {}]) =>
        m.collection('factures').inserer({
          'numero': 'FN-TEST-1',
          'montantTTC': 10000,
          'montantPaye': 10000,
          'statutPaiement': 'soldee',
          'statutMecef': 'en_attente',
          'statut': 'actif',
          'lignes': [
            {'id': 'L1', 'designation': 'Consultation', 'quantite': 1, 'prixUnitaire': 10000, 'partAssureur': 0, 'partPatient': 10000, 'statutPaiement': 'paye'}
          ],
          ...sup,
        }, prefixe: 'FAC').fiche;

    test('une vente normalisée ne se renormalise jamais, et son numéro ne change pas', () {
      final m = magasin();
      final f = vente(m, {'statutMecef': 'valide', 'numeroMecef': 'MECEF2000001'});
      final b = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(b.code, 'DEJA_NORMALISEE');
      expect(m.collection('factures').parId(f['id'])!['numeroMecef'], 'MECEF2000001');
    });

    test('sans adaptateur configuré (boîtier, mode par défaut) : refus nommé, pièce en attente, AUCUN numéro', () {
      final m = magasin();
      final f = vente(m);
      final a = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(a.ok, isFalse);
      expect(a.code, 'MECEF_NON_CONFIGURE');
      expect(a.motif, contains('Boîtier non configuré'));
      expect(a.geste, isNotEmpty);
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['numeroMecef'], isNull);
      expect(apres['codeRetour'], 'MECEF_NON_CONFIGURE');
      expect(apres['modeMecef'], 'boitier');
    });

    test('en mode e-MECeF : « non configuré, dossier d\'interface DGI requis », toujours aucun numéro', () {
      final m = magasin();
      final f = vente(m);
      final a = normaliserVente(m, '${f['id']}', maintenant: aujourdhui, adaptateur: adaptateurPourMode('emecef'));
      expect(a.code, 'MECEF_NON_CONFIGURE');
      expect(a.motif, 'e-MECeF non configuré : dossier d’interface DGI requis.');
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['numeroMecef'], isNull);
      expect(apres['modeMecef'], 'emecef');
    });

    test('le mode se lit au registre des paramètres : réglé sur e-MECeF, la normalisation suit', () {
      final m = magasin();
      final service = serviceParametres(m, auteur: () => 'Test', horloge: () => aujourdhui);
      expect(modeMecefDuPoste(m, aujourdhui), 'boitier');
      expect(service.regler(mecefCleMode, 'emecef', parametreDateIso(aujourdhui)).ok, isTrue);
      expect(modeMecefDuPoste(m, aujourdhui), 'emecef');
      final f = vente(m);
      normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(m.collection('factures').parId(f['id'])!['modeMecef'], 'emecef');
    });

    test('un numéro déjà porté par une pièce non normalisée est repris, jamais réécrit ni fabriqué', () {
      final m = magasin();
      final f = vente(m, {'numeroMecef': 'MECEF2000007'});
      final a = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(a.ok, isTrue);
      expect(a.numero, 'MECEF2000007');
    });

    test('annuler restitue la pièce en attente, sans numéro', () {
      final m = magasin();
      final f = vente(m);
      final a = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      a.annuler();
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['numeroMecef'], isNull);
    });

    test('un total incohérent écrit la pièce « refusée » en nommant le code, sans numéro', () {
      final m = magasin();
      final f = vente(m, {'montantTTC': 10001});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.code, 'TOTAL_INCOHERENT');
      expect(r.geste, isNotEmpty);
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'rejete');
      expect(apres['codeRetour'], 'TOTAL_INCOHERENT');
      expect(apres['motifRefusMecef'], contains('diffère'));
      expect(apres['numeroMecef'], isNull);
    });

    test('un refus d\'acheteur n\'écrit rien', () {
      final m = magasin();
      final f = vente(m);
      final r = normaliserVente(m, '${f['id']}',
          acheteur: {'ifu': '12', 'nom': 'X'}, maintenant: aujourdhui);
      expect(r.code, 'IFU_INVALIDE');
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['ifuClient'], isNull);
    });

    test('un taux d\'AIB demandé sur une facture de patient est refusé AIB_FACTURE_PATIENT et n\'écrit rien ; une pièce déjà émise garde son taux', () {
      final m = magasin();
      final f = vente(m);
      final r = normaliserVente(m, '${f['id']}', acheteur: {'aibTaux': 5}, maintenant: aujourdhui);
      expect(r.code, 'AIB_FACTURE_PATIENT');
      expect(r.geste, contains('Imputations'));
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['aibTaux'], isNull);
      final g = vente(m, {'aibTaux': 5, 'ifuClient': '3201642748214', 'acheteurNom': 'Ancien acheteur'});
      normaliserVente(m, '${g['id']}', maintenant: aujourdhui);
      final garde = m.collection('factures').parId(g['id'])!;
      expect(garde['aibTaux'], 5);
      expect(garde['acheteurNom'], 'Ancien acheteur');
    });

    test('une pro-forma ne se normalise pas', () {
      final m = magasin();
      final f = vente(m, {'proforma': true});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).code, 'PROFORMA');
    });
  });
}
