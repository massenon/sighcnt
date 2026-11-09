import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
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
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('la fenêtre « Facture normalisée » est à l\'émission : trois champs, la phrase qui dit que ce sont les seuls', (t) async {
    await ouvrir(t, magasin());
    expect(find.text('FACTURE NORMALISÉE'), findsOneWidget);
    expect(find.text('IFU de l’acheteur'), findsWidgets);
    expect(find.text('Nom de l’acheteur'), findsWidgets);
    expect(find.text('Taux d’AIB'), findsWidgets);
    expect(find.textContaining('Toute vente est normalisée'), findsOneWidget);
  });

  cas('un IFU invalide est refusé en le nommant, AVANT toute écriture', (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    final ecrAvant = m.collection('ecritures').actives.length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await saisir(t, 'acheteurIfu', '123');
    await saisir(t, 'acheteurNom', 'Clinique X');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.textContaining('IFU_INVALIDE'), findsWidgets);
    expect(find.textContaining('13 chiffres'), findsWidgets);
    expect(m.collection('factures').actives.length, avant);
    expect(m.collection('ecritures').actives.length, ecrAvant);
  });

  cas('un IFU sans nom est refusé en le nommant', (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await saisir(t, 'acheteurIfu', '3201642748214');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.textContaining('NOM_ACHETEUR_ABSENT'), findsWidgets);
    expect(m.collection('factures').actives.length, avant);
  });

  cas('vente soldée : l\'acheteur est rangé dans la pièce, le numéro vient de la normalisation et se dit non fiscal', (t) async {
    final m = magasin();
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await saisir(t, 'acheteurIfu', '3201 6427 48214');
    await saisir(t, 'acheteurNom', 'Clinique X');
    await choisir(t, '1 % (taux de la facture de référence, à confirmer)', '5 %');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final f = m.collection('factures').actives.first;
    expect(f['statutPaiement'], 'soldee');
    expect(f['ifuClient'], '3201642748214');
    expect(f['acheteurNom'], 'Clinique X');
    expect(f['aibTaux'], 5);
    expect(f['statutMecef'], 'valide');
    expect(RegExp(r'^MECEF\d{7}$').hasMatch('${f['numeroMecef']}'), isTrue);
    expect(numerosPris(m).where((x) => x == f['numeroMecef']).length, 1,
        reason: 'jamais un numéro déjà porté');
    expect(f['mecefSimule'], true);
    expect(f['aibMontant'], 25);
    expect(find.textContaining('non fiscal'), findsWidgets);
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
      final f = vente(m);
      final a = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(a.ok, isTrue);
      final numero = m.collection('factures').parId(f['id'])!['numeroMecef'];
      final b = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(b.code, 'DEJA_NORMALISEE');
      expect(m.collection('factures').parId(f['id'])!['numeroMecef'], numero);
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

    test('une pro-forma ne se normalise pas', () {
      final m = magasin();
      final f = vente(m, {'proforma': true});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).code, 'PROFORMA');
    });
  });
}
